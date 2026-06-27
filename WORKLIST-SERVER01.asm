.386
.model flat, stdcall
option casemap:none

; ==============================================================================
; INCLUDES & LIBRARIES
; ==============================================================================
include \masm32\include\windows.inc
include \masm32\include\user32.inc
include \masm32\include\kernel32.inc
include \masm32\include\ws2_32.inc
include \masm32\include\msvcrt.inc 

includelib \masm32\lib\user32.lib
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\ws2_32.lib
includelib \masm32\lib\msvcrt.lib

; ==============================================================================
; CONSTANTS
; ==============================================================================
WM_TRAYICON      equ WM_USER + 1
MAX_CLIENTS      equ 64
BUFFER_SIZE      equ 8192
MAX_PATIENTS     equ 1000
CSV_COLS         equ 18
APPEND_DELAY_MS  equ 2000
FIONBIO          equ 8004667Eh ; IOCtl to set non-blocking

; ==============================================================================
; STRUCTURES
; ==============================================================================
PatientRecord STRUCT
    cols db (CSV_COLS * 128) dup(0)
PatientRecord ENDS

TelnetClient STRUCT
    sock         dd ?
    lastActivity dd ?
    buffer       db BUFFER_SIZE dup(0)
    bufLen       dd ?
    hasPending   dd ?
    pendingEntry PatientRecord <>
    pendingSince dd ?
    timeoutLimit dd ?
TelnetClient ENDS

fd_set_struct STRUCT
    fd_count dd ?
    fd_array dd 64 dup(?)
fd_set_struct ENDS

; timeval is 8 bytes total
timeval_struct STRUCT
    tv_sec  dd ?
    tv_usec dd ?
timeval_struct ENDS

; ==============================================================================
; INITIALIZED DATA
; ==============================================================================
.data
    g_bRunning      dd 0
    g_telnetSocket  dd INVALID_SOCKET
    g_dicomSocket   dd INVALID_SOCKET
    
    g_DicomPort     dd 104
    g_TelnetPort    dd 23
    g_TelnetTimeout dd 10
    g_PatientCount  dd 0
    g_clientCount   dd 0

    ; Strings
    g_ServerAET     db "AUTOIT_SCP", 0
    CSV_HEADER      db "PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName,Status,ProcedureCode,ProcedureCodeDesc", 13, 10, 0
    
    msgServersStart db "Servers started.", 0
    msgServersStop  db "Servers stopped.", 0
    csvFileName     db "\patients.csv", 0
    
    ; Logging Formats
    szTimeFormat    db "[%02d:%02d:%02d] ", 0
    szCrLf          db 13, 10, 0
    
    ; File modes
    szModeRead      db "r", 0
    szModeWrite     db "w", 0

; ==============================================================================
; UNINITIALIZED DATA
; ==============================================================================
.data?
    hMainWnd        dd ?
    hStatusLabel    dd ?
    hClientsLabel   dd ?
    hLogEdit        dd ?
    
    g_iniFile       db MAX_PATH dup(?)
    g_csvFile       db MAX_PATH dup(?)
    
    g_Patients      PatientRecord MAX_PATIENTS dup(<>)
    g_clients       TelnetClient MAX_CLIENTS dup(<>)
    
    wsaData         WSADATA <>

; ==============================================================================
; CODE SECTION
; ==============================================================================
.code

; ------------------------------------------------------------------------------
; GetAppDir - Retrieves module path and strips filename
; ------------------------------------------------------------------------------
GetAppDir PROC outPath:DWORD, maxLen:DWORD
    LOCAL lastSlash:DWORD

    invoke GetModuleFileName, NULL, outPath, maxLen
    mov esi, outPath
    mov lastSlash, 0
@@FindSlash:
    mov al, byte ptr [esi]
    cmp al, 0
    je @@Done
    cmp al, '\'
    jne @@NextChar
    mov lastSlash, esi
@@NextChar:
    inc esi
    jmp @@FindSlash
@@Done:
    cmp lastSlash, 0
    je @@Exit
    mov edi, lastSlash
    inc edi
    mov byte ptr [edi], 0
@@Exit:
    ret
GetAppDir ENDP

; ------------------------------------------------------------------------------
; TrimString - Trims leading/trailing whitespace
; ------------------------------------------------------------------------------
TrimString PROC pStr:DWORD
    LOCAL endPtr:DWORD
    mov esi, pStr
@@SkipLeading:
    movzx eax, byte ptr [esi]
    test al, al
    jz @@Exit            
    invoke crt_isspace, eax
    test eax, eax
    jz @@LeadingDone
    inc esi
    jmp @@SkipLeading
@@LeadingDone:
    mov edi, pStr
    invoke crt_memmove, edi, esi, invoke crt_strlen, esi
    invoke crt_strlen, pStr
    test eax, eax
    jz @@Exit
    mov edi, pStr
    add edi, eax
    dec edi              
    mov endPtr, edi
@@TrimTrailing:
    mov eax, pStr
    cmp endPtr, eax
    jbe @@Terminate      
    mov edi, endPtr
    movzx eax, byte ptr [edi]
    invoke crt_isspace, eax
    test eax, eax
    jz @@Terminate
    dec endPtr           
    jmp @@TrimTrailing
@@Terminate:
    mov edi, endPtr
    inc edi
    mov byte ptr [edi], 0 
@@Exit:
    ret
TrimString ENDP

; ------------------------------------------------------------------------------
; LogMessage - Appends timestamped message to Edit Control
; ------------------------------------------------------------------------------
LogMessage PROC msg:DWORD
    LOCAL t:DWORD
    LOCAL tm_ptr:DWORD
    LOCAL timeStr[32]:BYTE
    LOCAL len:DWORD

    cmp hLogEdit, 0
    je @@Exit

    invoke crt_time, 0
    mov t, eax
    lea eax, t
    invoke crt_localtime, eax
    mov tm_ptr, eax
    
    mov edx, tm_ptr
    mov ecx, [edx+8]  ; tm_hour
    mov eax, [edx+4]  ; tm_min
    mov ebx, [edx+0]  ; tm_sec
    invoke crt_sprintf, addr timeStr, addr szTimeFormat, ecx, eax, ebx

    invoke GetWindowTextLength, hLogEdit
    mov len, eax
    invoke SendMessage, hLogEdit, EM_SETSEL, len, len
    invoke SendMessage, hLogEdit, EM_REPLACESEL, 0, addr timeStr
    
    invoke GetWindowTextLength, hLogEdit
    mov len, eax
    invoke SendMessage, hLogEdit, EM_SETSEL, len, len
    invoke SendMessage, hLogEdit, EM_REPLACESEL, 0, msg
    
    invoke GetWindowTextLength, hLogEdit
    mov len, eax
    invoke SendMessage, hLogEdit, EM_SETSEL, len, len
    invoke SendMessage, hLogEdit, EM_REPLACESEL, 0, addr szCrLf
@@Exit:
    ret
LogMessage ENDP

; ------------------------------------------------------------------------------
; appendBytes - Helper for DICOM encoding
; ------------------------------------------------------------------------------
appendBytes PROC pBufPtr:DWORD, pOffset:DWORD, pData:DWORD, dataLen:DWORD
    mov esi, pBufPtr
    mov edi, [esi]       
    mov ebx, pOffset
    mov eax, [ebx]       
    add edi, eax         
    invoke crt_memcpy, edi, pData, dataLen
    mov ebx, pOffset
    mov eax, [ebx]
    add eax, dataLen
    mov [ebx], eax
    ret
appendBytes ENDP

; ------------------------------------------------------------------------------
; DICOM encoders (Endianness handlers)
; ------------------------------------------------------------------------------
DICOM_UInt32LE PROC outPtr:DWORD, val:DWORD
    mov edi, outPtr
    mov eax, val
    mov dword ptr [edi], eax 
    ret
DICOM_UInt32LE ENDP

DICOM_UInt32BE PROC outPtr:DWORD, val:DWORD
    mov edi, outPtr
    mov eax, val
    bswap eax   
    mov dword ptr [edi], eax
    ret
DICOM_UInt32BE ENDP

DICOM_ElemImplicit PROC pBufPtr:DWORD, pOffset:DWORD, group:WORD, elem:WORD, valPtr:DWORD
    LOCAL tag[4]:BYTE
    LOCAL lenBytes[4]:BYTE
    LOCAL valLen:DWORD
    LOCAL pad:DWORD

    mov ax, group
    mov word ptr tag[0], ax
    mov ax, elem
    mov word ptr tag[2], ax
    invoke appendBytes, pBufPtr, pOffset, addr tag, 4

    invoke crt_strlen, valPtr
    mov valLen, eax
    mov pad, 0
    test eax, 1         
    jz @@Even
    mov pad, 1
@@Even:
    mov eax, valLen
    add eax, pad
    invoke DICOM_UInt32LE, addr lenBytes, eax
    invoke appendBytes, pBufPtr, pOffset, addr lenBytes, 4
    
    invoke appendBytes, pBufPtr, pOffset, valPtr, valLen
    
    cmp pad, 1
    jne @@Done
    mov tag[0], 20h 
    invoke appendBytes, pBufPtr, pOffset, addr tag, 1
@@Done:
    ret
DICOM_ElemImplicit ENDP

; ------------------------------------------------------------------------------
; ParseCSVLine - Parses a single line into a PatientRecord struct
; ------------------------------------------------------------------------------
ParseCSVLine PROC pLine:DWORD, pRec:DWORD
    LOCAL col:DWORD
    LOCAL inQuotes:DWORD
    LOCAL charIdx:DWORD
    LOCAL temp[256]:BYTE
    
    mov col, 0
    mov inQuotes, 0
    mov charIdx, 0
    invoke crt_memset, addr temp, 0, 256
    
    mov esi, pLine
@@LoopStart:
    movzx eax, byte ptr [esi]
    test al, al
    jz @@LoopEnd
    cmp al, 10
    je @@LoopEnd
    cmp al, 13
    je @@LoopEnd
    
    cmp al, '"'
    jne @@CheckComma
    xor inQuotes, 1      
    jmp @@NextChar
@@CheckComma:
    cmp al, ','
    jne @@DefaultChar
    cmp inQuotes, 0
    jne @@DefaultChar
    
    mov ecx, charIdx
    lea edi, temp
    mov byte ptr [edi + ecx], 0
    
    mov ebx, col
    imul ebx, ebx, 128
    mov edi, pRec
    add edi, ebx
    invoke crt_strncpy, edi, addr temp, 127
    invoke TrimString, edi
    
    inc col
    mov charIdx, 0
    cmp col, CSV_COLS
    jge @@LoopEnd
    jmp @@NextChar
@@DefaultChar:
    cmp charIdx, 255
    jge @@NextChar
    mov ecx, charIdx
    lea edi, temp
    mov [edi + ecx], al
    inc charIdx
@@NextChar:
    inc esi
    jmp @@LoopStart
@@LoopEnd:
    cmp col, CSV_COLS
    jge @@Exit
    mov ecx, charIdx
    lea edi, temp
    mov byte ptr [edi + ecx], 0
    
    mov ebx, col
    imul ebx, ebx, 128
    mov edi, pRec
    add edi, ebx
    invoke crt_strncpy, edi, addr temp, 127
    invoke TrimString, edi
@@Exit:
    ret
ParseCSVLine ENDP

; ------------------------------------------------------------------------------
; LoadPatientsCSV
; ------------------------------------------------------------------------------
LoadPatientsCSV PROC
    LOCAL pFile:DWORD
    LOCAL lineBuf[1024]:BYTE
    
    mov g_PatientCount, 0
    invoke crt_fopen, addr g_csvFile, addr szModeRead
    mov pFile, eax
    
    test eax, eax
    jnz @@ReadLoopStart
    
    ; If file doesn't exist, create and write header
    invoke crt_fopen, addr g_csvFile, addr szModeWrite
    mov pFile, eax
    test eax, eax
    jz @@Exit
    invoke crt_fputs, addr CSV_HEADER, pFile
    invoke crt_fclose, pFile
    jmp @@Exit

@@ReadLoopStart:
    ; Skip header
    invoke crt_fgets, addr lineBuf, 1024, pFile
    
@@ReadLoop:
    ; Ensure we don't exceed MAX_PATIENTS
    cmp g_PatientCount, MAX_PATIENTS
    jge @@DoneReading

    invoke crt_fgets, addr lineBuf, 1024, pFile
    test eax, eax
    jz @@DoneReading  ; EOF or error
    
    invoke TrimString, addr lineBuf
    invoke crt_strlen, addr lineBuf
    test eax, eax
    jz @@ReadLoop     ; Skip empty lines
    
    ; Parse into g_Patients[g_PatientCount]
    mov ebx, g_PatientCount
    imul ebx, ebx, sizeof PatientRecord
    lea edi, g_Patients
    add edi, ebx
    
    invoke ParseCSVLine, addr lineBuf, edi
    inc g_PatientCount
    jmp @@ReadLoop

@@DoneReading:
    invoke crt_fclose, pFile
@@Exit:
    ret
LoadPatientsCSV ENDP

; ------------------------------------------------------------------------------
; ProcessServerLoop (Structural Skeleton)
; ------------------------------------------------------------------------------
ProcessServerLoop PROC
    LOCAL readSet:fd_set_struct
    LOCAL timeout:timeval_struct
    LOCAL maxSock:DWORD
    LOCAL i:DWORD

    cmp g_bRunning, 0
    je @@Exit

    mov readSet.fd_count, 0
    
    mov eax, readSet.fd_count
    mov ecx, g_telnetSocket
    mov readSet.fd_array[eax*4], ecx
    inc readSet.fd_count
    
    mov eax, readSet.fd_count
    mov ecx, g_dicomSocket
    mov readSet.fd_array[eax*4], ecx
    inc readSet.fd_count

    mov eax, g_telnetSocket
    cmp eax, g_dicomSocket
    jge @@SetMax1
    mov eax, g_dicomSocket
@@SetMax1:
    mov maxSock, eax

    ; (Client loop aggregation goes here)
    
    mov timeout.tv_sec, 0
    mov timeout.tv_usec, 0
    
    mov eax, maxSock
    inc eax
    invoke select, eax, addr readSet, NULL, NULL, addr timeout
    test eax, eax
    jle @@Exit 

    ; (FD_ISSET / Accept / Recv logic would be handled here based on readSet)

@@Exit:
    ret
ProcessServerLoop ENDP

; ------------------------------------------------------------------------------
; StartServer
; ------------------------------------------------------------------------------
StartServer PROC
    LOCAL sAddr:sockaddr_in
    LOCAL mode:DWORD

    cmp g_bRunning, 1
    je @@Exit

    invoke LoadPatientsCSV

    invoke RtlZeroMemory, addr sAddr, sizeof sockaddr_in
    mov sAddr.sin_family, AF_INET
    invoke htons, g_TelnetPort
    mov sAddr.sin_port, ax
    mov sAddr.sin_addr.S_un.S_addr, INADDR_ANY

    invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
    mov g_telnetSocket, eax
    
    invoke bind, g_telnetSocket, addr sAddr, sizeof sockaddr_in
    invoke listen, g_telnetSocket, SOMAXCONN
    
    mov mode, 1
    invoke ioctlsocket, g_telnetSocket, FIONBIO, addr mode

    invoke htons, g_DicomPort
    mov sAddr.sin_port, ax
    invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
    mov g_dicomSocket, eax
    
    invoke bind, g_dicomSocket, addr sAddr, sizeof sockaddr_in
    invoke listen, g_dicomSocket, SOMAXCONN
    invoke ioctlsocket, g_dicomSocket, FIONBIO, addr mode

    mov g_bRunning, 1
    invoke LogMessage, addr msgServersStart
@@Exit:
    ret
StartServer ENDP

; ------------------------------------------------------------------------------
; StopServer
; ------------------------------------------------------------------------------
StopServer PROC
    cmp g_bRunning, 0
    je @@Exit
    
    invoke closesocket, g_telnetSocket
    invoke closesocket, g_dicomSocket
    
    mov g_bRunning, 0
    mov g_clientCount, 0
    invoke LogMessage, addr msgServersStop
@@Exit:
    ret
StopServer ENDP

; ==============================================================================
; ENTRY POINT (WinMain Stub)
; ==============================================================================
start:
    invoke WSAStartup, 202h, addr wsaData
    
    invoke GetAppDir, addr g_csvFile, MAX_PATH
    invoke lstrcat, addr g_csvFile, addr csvFileName
    
    invoke StartServer
    
    ; --------------------------------------------------------------------------
    ; This is where your Win32 Message Pump / ProcessServerLoop cycle belongs.
    ; Without a registered window class and GetMessage/DispatchMessage loop, 
    ; the program will immediately start and then exit.
    ; --------------------------------------------------------------------------
    
    invoke StopServer
    invoke WSACleanup
    invoke ExitProcess, 0

end start