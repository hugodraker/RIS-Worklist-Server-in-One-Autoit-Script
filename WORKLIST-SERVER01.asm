;c:\masm32\bin\ml /c /coff /Cp worklist-server01.asm
;c:\masm32\bin\link /subsystem:console worklist-server01.obj
.586
.model flat, stdcall
option casemap:none
include \masm32\include\windows.inc
include \masm32\include\kernel32.inc
include \masm32\include\user32.inc
include \masm32\include\shell32.inc
include \masm32\include\ws2_32.inc
include \masm32\include\msvcrt.inc
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\user32.lib
includelib \masm32\lib\shell32.lib
includelib \masm32\lib\ws2_32.lib
includelib \masm32\lib\msvcrt.lib

MAX_CLIENTS        equ 16
RECV_SIZE          equ 2048
CLIENT_BUF_SIZE    equ 4096
FIELD_COUNT        equ 22
FIELD_SIZE         equ 128
ENTRY_SIZE         equ FIELD_COUNT * FIELD_SIZE
LINE_SIZE          equ 8192
APPEND_DELAY_MS    equ 2000
DEFAULT_TIMEOUT_MS equ 10000
FIONBIO            equ 8004667Eh
WSAEWOULDBLOCK     equ 10035

WM_TRAYICON        equ WM_USER + 1
ID_TRAY_TOGGLE     equ 1000
ID_TRAY_SHOW       equ 1001
ID_TRAY_EXIT       equ 1002

.data
g_TelnetPort        dd 23
g_DicomPort         dd 104
g_TelnetTimeout     dd 10
g_DebugLog          dd 1
g_bRunning          dd 0
g_listenSocket      dd INVALID_SOCKET
g_dicomListenSocket dd INVALID_SOCKET

g_hInstance         dd 0
g_hMainWnd          dd 0
g_hMenu             dd 0

g_aeCalled          db "AUTOIT_SCP      ", 0

szIniFile          db "worklist-server01.ini",0
szIniServer        db "Server",0
szIniLists         db "Lists",0
szIniAET           db "AETitle",0
szIniDicomPort     db "DicomPort",0
szIniTelnetPort    db "TelnetPort",0
szIniTelnetTimeout db "TelnetTimeout",0
szIniDebugLog      db "DebugLog",0

szIniModalities    db "Modalities",0
szIniAETitles      db "AETitles",0
szIniRefPhys       db "ReferringPhysicians",0
szIniProcedures    db "Procedures",0
szIniProcCodes     db "ProcedureCodes",0

szDefAET           db "AUTOIT_SCP",0
szDefMods          db "CR;DX;CT;MR;US;OT",0
szDefAETs          db "AET1;AET2",0
szDefRefPhys       db "Dr. Smith;Dr. Brown",0
szDefProcedures    db "Chest X-Ray;CT Head",0
szDefProcCodes     db "PCODE01;PCODE02",0
szDefDebug         db "1",0
szDefDicomPort     db "104",0
szDefTelnetPort    db "23",0
szDefTelnetTimeout db "10",0

szWndClass         db "WorklistTrayClass",0
szTrayTip          db "RIS Telnet + DICOM MWL SCP",0
szMenuStart        db "Start Server",0
szMenuStop         db "Stop Server",0
szMenuShow         db "Show Console",0
szMenuExit         db "Exit",0

szStartup          db "RIS Telnet + DICOM MWL SCP starting...",13,10,0
szConfigFmt        db "Config: AET=%s TelnetPort=%u DicomPort=%u DebugLog=%u",13,10,0
szListenFmt        db "Telnet listening on port %u",13,10,0
szListenFailFmt    db "ERROR: Failed to listen on telnet port %u",13,10,0
szClientConnFmt    db "Telnet Client connected on socket %u",13,10,0
szClientDiscFmt    db "Client disconnected on socket %u",13,10,0
szTimeoutFmt       db "Client on socket %u timed out",13,10,0
szPendingFmt       db "PENDING PatientID %s",13,10,0
szInsertedFmt      db "INSERTED PatientID %s",13,10,0
szUpdatedFmt       db "UPDATED PatientID %s",13,10,0
szConnected        db "Connected to RIS Telnet Server. Waiting for data...",13,10,0
szPendingResp      db "PENDING",13,10,0
szInsertedResp     db "INSERTED",13,10,0
szUpdatedResp      db "UPDATED",13,10,0
szInvalidResp      db "INVALID LINE",13,10,0
szDicomListenFmt   db "DICOM listening on port %u",13,10,0
szDicomListenFail  db "ERROR: Failed to listen on DICOM port %u",13,10,0
szDicomConnFmt     db "DICOM Client connected on socket %u",13,10,0
szDicomDiscFmt     db "DICOM Client disconnected on socket %u",13,10,0
szDicomEchoFmt     db "C-ECHO sock=%u MsgID=%u PCID=%u",13,10,0
szDicomFindFmt     db "C-FIND sock=%u MsgID=%u PCID=%u",13,10,0
szMatchFmt         db "  MWL match: PatientID=%s",13,10,0
szDicomAssocFmt    db "A-ASSOCIATE-AC sent on socket %u",13,10,0
szServerStarted    db "Server STARTED",13,10,0
szServerStopped    db "Server STOPPED",13,10,0

szEchoSOPClass     db "1.2.840.10008.1.1",0
szMwlSOPClass      db "1.2.840.10008.5.1.4.31",0
szCSVFile          db "patients.csv",0
szCSVTempFile      db "patients.tmp",0
szModeRead         db "r",0
szModeWrite        db "w",0
szFmtLine          db "%s",13,10,0
szCSVHeader        db "PatientID,PatientName,Accession,BirthDate,Sex,"
                   db "SPSID,SPSDescription,RequestedProcedureID,"
                   db "StationAET,Modality,ScheduledDate,ScheduledTime,"
                   db "RequestedProcDesc,StudyInstanceUID,"
                   db "ReferringPhysicianName,Status,ProcedureCode,"
                   db "ProcedureCodeDesc,CodingScheme,"
                   db "PerformingPhysician,StationName,Location",0

pdu1_prefix        db 02h,00h,00h,00h,00h,0D4h,00h,01h,00h,00h
pdu1_ae_calling    db "ANY-SCU         "
pdu_appctx         db 10h,00h,00h,15h,"1.2.840.10008.3.1.1.1"
pdu2_static        db 21h,00h,00h,19h,01h,00h,00h,00h,40h,00h,00h,11h,"1.2.840.10008.1.2"
                   db 21h,00h,00h,19h,03h,00h,00h,00h,40h,00h,00h,11h,"1.2.840.10008.1.2"
pdu3_static        db 50h,00h,00h,39h,51h,00h,00h,04h,00h,00h,40h,00h
                   db 52h,00h,00h,1Eh,"1.2.826.0.1.3680043.2.1396.999"
                   db 55h,00h,00h,0Bh,"AutoitPACS1"

.data?
wsaData            WSADATA <>
nid                NOTIFYICONDATA <>
g_clients          dd MAX_CLIENTS dup(?)
g_clientIDs        dd MAX_CLIENTS dup(?)
g_clientLastTick   dd MAX_CLIENTS dup(?)
g_clientTimeout    dd MAX_CLIENTS dup(?)
g_clientBufLen     dd MAX_CLIENTS dup(?)
g_clientBuffers    db MAX_CLIENTS * CLIENT_BUF_SIZE dup(?)
g_pendingFlag      dd MAX_CLIENTS dup(?)
g_pendingSince     dd MAX_CLIENTS dup(?)
g_pendingEntries   db MAX_CLIENTS * ENTRY_SIZE dup(?)
g_recvBuf          db RECV_SIZE dup(?)
g_fileLine         db LINE_SIZE dup(?)
g_lineOut          db LINE_SIZE dup(?)
g_tmpEntry         db ENTRY_SIZE dup(?)
g_dispParam        db 256 dup(?)
g_dicomRecvBuf     db 16384 dup(?)
g_dicomSendBuf     db 16384 dup(?)
g_mwlDsBuf         db 8192 dup(?)
g_spsBuf           db 2048 dup(?)
g_iniBuf           db 256 dup(?)

.code

; --------------------------------------------------------------------
; INI / CONFIG
; --------------------------------------------------------------------
SetAETitle PROC pSrc:DWORD
    LOCAL nLen:DWORD
    push edi
    mov edi, OFFSET g_aeCalled
    mov al, ' '
    mov ecx, 16
    rep stosb
    mov BYTE PTR [edi], 0
    pop edi
    invoke crt_strlen, pSrc
    mov nLen, eax
    cmp nLen, 16
    jbe SAT_OK
    mov nLen, 16
SAT_OK:
    invoke crt_memcpy, OFFSET g_aeCalled, pSrc, nLen
    ret
SetAETitle ENDP

LoadConfig PROC
    invoke GetPrivateProfileString, OFFSET szIniServer, OFFSET szIniAET, OFFSET szDefAET, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke SetAETitle, OFFSET g_iniBuf
    invoke GetPrivateProfileInt, OFFSET szIniServer, OFFSET szIniDicomPort, 104, OFFSET szIniFile
    mov g_DicomPort, eax
    invoke GetPrivateProfileInt, OFFSET szIniServer, OFFSET szIniTelnetPort, 23, OFFSET szIniFile
    mov g_TelnetPort, eax
    invoke GetPrivateProfileInt, OFFSET szIniServer, OFFSET szIniTelnetTimeout, 10, OFFSET szIniFile
    mov g_TelnetTimeout, eax
    invoke GetPrivateProfileInt, OFFSET szIniServer, OFFSET szIniDebugLog, 1, OFFSET szIniFile
    mov g_DebugLog, eax
    invoke WritePrivateProfileString, OFFSET szIniServer, OFFSET szIniAET, OFFSET g_aeCalled, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniServer, OFFSET szIniDicomPort, OFFSET szDefDicomPort, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniServer, OFFSET szIniTelnetPort, OFFSET szDefTelnetPort, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniServer, OFFSET szIniTelnetTimeout, OFFSET szDefTelnetTimeout, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniServer, OFFSET szIniDebugLog, OFFSET szDefDebug, OFFSET szIniFile
    invoke GetPrivateProfileString, OFFSET szIniLists, OFFSET szIniModalities, OFFSET szDefMods, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniLists, OFFSET szIniModalities, OFFSET g_iniBuf, OFFSET szIniFile
    invoke GetPrivateProfileString, OFFSET szIniLists, OFFSET szIniAETitles, OFFSET szDefAETs, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniLists, OFFSET szIniAETitles, OFFSET g_iniBuf, OFFSET szIniFile
    invoke GetPrivateProfileString, OFFSET szIniLists, OFFSET szIniRefPhys, OFFSET szDefRefPhys, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniLists, OFFSET szIniRefPhys, OFFSET g_iniBuf, OFFSET szIniFile
    invoke GetPrivateProfileString, OFFSET szIniLists, OFFSET szIniProcedures, OFFSET szDefProcedures, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniLists, OFFSET szIniProcedures, OFFSET g_iniBuf, OFFSET szIniFile
    invoke GetPrivateProfileString, OFFSET szIniLists, OFFSET szIniProcCodes, OFFSET szDefProcCodes, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniLists, OFFSET szIniProcCodes, OFFSET g_iniBuf, OFFSET szIniFile
    ret
LoadConfig ENDP

; --------------------------------------------------------------------
; POINTER HELPERS
; --------------------------------------------------------------------
GetClientSockPtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_clients
    ret
GetClientSockPtr ENDP

GetClientIDPtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_clientIDs
    ret
GetClientIDPtr ENDP

GetClientLastPtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_clientLastTick
    ret
GetClientLastPtr ENDP

GetClientTimeoutPtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_clientTimeout
    ret
GetClientTimeoutPtr ENDP

GetClientBufLenPtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_clientBufLen
    ret
GetClientBufLenPtr ENDP

GetClientBufferPtr PROC idx:DWORD
    mov eax, idx
    mov ecx, CLIENT_BUF_SIZE
    mul ecx
    add eax, OFFSET g_clientBuffers
    ret
GetClientBufferPtr ENDP

GetPendingFlagPtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_pendingFlag
    ret
GetPendingFlagPtr ENDP

GetPendingSincePtr PROC idx:DWORD
    mov eax, idx
    shl eax, 2
    add eax, OFFSET g_pendingSince
    ret
GetPendingSincePtr ENDP

GetPendingEntryPtr PROC idx:DWORD
    mov eax, idx
    mov ecx, ENTRY_SIZE
    mul ecx
    add eax, OFFSET g_pendingEntries
    ret
GetPendingEntryPtr ENDP

GetFieldPtr PROC pEntry:DWORD, fieldIdx:DWORD
    mov eax, fieldIdx
    mov ecx, FIELD_SIZE
    mul ecx
    add eax, pEntry
    ret
GetFieldPtr ENDP

; --------------------------------------------------------------------
; STRING HELPERS
; --------------------------------------------------------------------
SendText PROC sock:DWORD, pText:DWORD
    LOCAL nLen:DWORD
    invoke crt_strlen, pText
    mov nLen, eax
    cmp eax, 0
    je ST_Done
    invoke send, sock, pText, nLen, 0
ST_Done:
    ret
SendText ENDP

IsWhite PROC val:DWORD
    mov eax, val
    cmp al, 20h
    je IW_Yes
    cmp al, 09h
    je IW_Yes
    cmp al, 0Dh
    je IW_Yes
    cmp al, 0Ah
    je IW_Yes
    xor eax, eax
    ret
IW_Yes:
    mov eax, 1
    ret
IsWhite ENDP

TrimInPlace PROC uses esi edi pStr:DWORD
    LOCAL nLen:DWORD
    LOCAL pEnd:DWORD
    mov esi, pStr
TIP_Lead:
    movzx eax, BYTE PTR [esi]
    cmp eax, 0
    je TIP_Done
    invoke IsWhite, eax
    cmp eax, 1
    jne TIP_ShiftStart
    inc esi
    jmp TIP_Lead
TIP_ShiftStart:
    mov edi, pStr
    cmp esi, edi
    je TIP_Trail
TIP_Shift:
    mov al, BYTE PTR [esi]
    mov BYTE PTR [edi], al
    inc esi
    inc edi
    cmp al, 0
    jne TIP_Shift
TIP_Trail:
    invoke crt_strlen, pStr
    mov nLen, eax
    cmp eax, 0
    je TIP_Done
    mov eax, pStr
    add eax, nLen
    dec eax
    mov pEnd, eax
TIP_TrailLoop:
    mov eax, pEnd
    cmp eax, pStr
    jb TIP_Done
    movzx ecx, BYTE PTR [eax]
    invoke IsWhite, ecx
    cmp eax, 1
    jne TIP_Done
    mov eax, pEnd
    mov BYTE PTR [eax], 0
    dec pEnd
    jmp TIP_TrailLoop
TIP_Done:
    ret
TrimInPlace ENDP

UpperChar PROC val:DWORD
    mov eax, val
    cmp al, 'a'
    jb UC_Done
    cmp al, 'z'
    ja UC_Done
    sub al, 20h
UC_Done:
    ret
UpperChar ENDP

StartsWithDISP PROC pLine:DWORD
    mov edx, pLine
    movzx eax, BYTE PTR [edx+0]
    invoke UpperChar, eax
    cmp al, 'D'
    jne SWD_No
    movzx eax, BYTE PTR [edx+1]
    invoke UpperChar, eax
    cmp al, 'I'
    jne SWD_No
    movzx eax, BYTE PTR [edx+2]
    invoke UpperChar, eax
    cmp al, 'S'
    jne SWD_No
    movzx eax, BYTE PTR [edx+3]
    invoke UpperChar, eax
    cmp al, 'P'
    jne SWD_No
    mov eax, 1
    ret
SWD_No:
    xor eax, eax
    ret
StartsWithDISP ENDP

StrIEquals PROC uses esi edi pA:DWORD, pB:DWORD
    LOCAL ca:DWORD
    LOCAL cb:DWORD
    mov esi, pA
    mov edi, pB
SIE_Loop:
    movzx eax, BYTE PTR [esi]
    invoke UpperChar, eax
    mov ca, eax
    movzx eax, BYTE PTR [edi]
    invoke UpperChar, eax
    mov cb, eax
    mov eax, ca
    cmp al, BYTE PTR cb
    jne SIE_No
    cmp al, 0
    je SIE_Yes
    inc esi
    inc edi
    jmp SIE_Loop
SIE_Yes:
    mov eax, 1
    ret
SIE_No:
    xor eax, eax
    ret
StrIEquals ENDP

IsEightDigits PROC uses esi pStr:DWORD
    LOCAL idx:DWORD
    mov esi, pStr
    mov idx, 0
IED_Loop:
    cmp idx, 8
    jge IED_EndCheck
    mov al, BYTE PTR [esi]
    cmp al, '0'
    jb IED_No
    cmp al, '9'
    ja IED_No
    inc esi
    inc idx
    jmp IED_Loop
IED_EndCheck:
    cmp BYTE PTR [esi], 0
    jne IED_No
    mov eax, 1
    ret
IED_No:
    xor eax, eax
    ret
IsEightDigits ENDP

IsSexValid PROC pStr:DWORD
    mov edx, pStr
    mov al, BYTE PTR [edx]
    cmp BYTE PTR [edx+1], 0
    jne ISV_No
    cmp al, 'M'
    je ISV_Yes
    cmp al, 'F'
    je ISV_Yes
    cmp al, 'O'
    je ISV_Yes
ISV_No:
    xor eax, eax
    ret
ISV_Yes:
    mov eax, 1
    ret
IsSexValid ENDP

IsStatusValid PROC pStr:DWORD
    mov edx, pStr
    mov al, BYTE PTR [edx]
    cmp BYTE PTR [edx+1], 0
    jne IST_No
    cmp al, '1'
    jb IST_No
    cmp al, '4'
    ja IST_No
    mov eax, 1
    ret
IST_No:
    xor eax, eax
    ret
IsStatusValid ENDP

IsTimeValidOrEmpty PROC pStr:DWORD
    mov edx, pStr
    cmp BYTE PTR [edx], 0
    je ITV_Yes
    mov al, BYTE PTR [edx+0]
    cmp al, '0'
    jb ITV_No
    cmp al, '9'
    ja ITV_No
    mov al, BYTE PTR [edx+1]
    cmp al, '0'
    jb ITV_No
    cmp al, '9'
    ja ITV_No
    cmp BYTE PTR [edx+2], ':'
    jne ITV_No
    mov al, BYTE PTR [edx+3]
    cmp al, '0'
    jb ITV_No
    cmp al, '9'
    ja ITV_No
    mov al, BYTE PTR [edx+4]
    cmp al, '0'
    jb ITV_No
    cmp al, '9'
    ja ITV_No
    cmp BYTE PTR [edx+5], 0
    jne ITV_No
ITV_Yes:
    mov eax, 1
    ret
ITV_No:
    xor eax, eax
    ret
IsTimeValidOrEmpty ENDP

StripColons PROC uses esi edi pSrc:DWORD, pDest:DWORD
    mov esi, pSrc
    mov edi, pDest
SC_Loop:
    mov al, BYTE PTR [esi]
    cmp al, 0
    je SC_Done
    cmp al, ':'
    je SC_Skip
    mov BYTE PTR [edi], al
    inc edi
SC_Skip:
    inc esi
    jmp SC_Loop
SC_Done:
    mov BYTE PTR [edi], 0
    ret
StripColons ENDP

; --------------------------------------------------------------------
; DICOM HELPERS
; --------------------------------------------------------------------
MemFindString PROC USES esi edi pBuffer:DWORD, bufLen:DWORD, pStr:DWORD
    LOCAL strLen:DWORD
    invoke crt_strlen, pStr
    mov strLen, eax
    mov ecx, bufLen
    sub ecx, strLen
    jle MFS_NotFound
    mov esi, pBuffer
MFS_Loop:
    push ecx
    mov edi, pStr
    mov ecx, strLen
    push esi
    repe cmpsb
    pop esi
    pop ecx
    je MFS_Found
    inc esi
    dec ecx
    jnz MFS_Loop
MFS_NotFound:
    xor eax, eax
    ret
MFS_Found:
    mov eax, esi
    ret
MemFindString ENDP

DICOM_ExtractMessageID PROC USES esi pBin:DWORD, binLen:DWORD
    mov esi, pBin
    add esi, 12
    mov ecx, binLen
    sub ecx, 20
DEM_Loop:
    cmp ecx, 8
    jl DEM_Default
    movzx eax, WORD PTR [esi]
    cmp ax, 0000h
    jne DEM_Next
    movzx eax, WORD PTR [esi+2]
    cmp ax, 0110h
    jne DEM_Next
    mov eax, DWORD PTR [esi+4]
    cmp eax, 2
    jne DEM_Next
    movzx eax, WORD PTR [esi+8]
    ret
DEM_Next:
    inc esi
    dec ecx
    jmp DEM_Loop
DEM_Default:
    mov eax, 1
    ret
DICOM_ExtractMessageID ENDP

DICOM_WriteImplicitUS PROC pDest:DWORD, grp:DWORD, elem:DWORD, val:DWORD
    mov edx, pDest
    mov eax, grp
    mov WORD PTR [edx], ax
    mov eax, elem
    mov WORD PTR [edx+2], ax
    mov DWORD PTR [edx+4], 2
    mov eax, val
    mov WORD PTR [edx+8], ax
    mov eax, 10
    ret
DICOM_WriteImplicitUS ENDP

WriteImplicitStr PROC pDest:DWORD, grp:DWORD, elem:DWORD, pStr:DWORD
    LOCAL origLen:DWORD
    LOCAL padLen:DWORD
    LOCAL pVal:DWORD
    invoke crt_strlen, pStr
    mov origLen, eax
    test eax, 1
    jz WIS_Even
    inc eax
WIS_Even:
    mov padLen, eax
    mov edx, pDest
    mov eax, grp
    mov WORD PTR [edx], ax
    mov eax, elem
    mov WORD PTR [edx+2], ax
    mov eax, padLen
    mov DWORD PTR [edx+4], eax
    lea eax, [edx+8]
    mov pVal, eax
    cmp origLen, 0
    je WIS_Pad
    invoke crt_memcpy, pVal, pStr, origLen
WIS_Pad:
    mov eax, origLen
    cmp eax, padLen
    je WIS_Done
    mov edx, pVal
    add edx, eax
    mov BYTE PTR [edx], 20h
WIS_Done:
    mov eax, padLen
    add eax, 8
    ret
WriteImplicitStr ENDP

DICOM_SendAAssociateAC PROC USES edi sock:DWORD
    LOCAL outBuf[512]:BYTE
    LOCAL totalLen:DWORD
    lea edi, outBuf
    invoke crt_memcpy, edi, OFFSET pdu1_prefix, 10
    add edi, 10
    invoke crt_memcpy, edi, OFFSET g_aeCalled, 16
    add edi, 16
    invoke crt_memcpy, edi, OFFSET pdu1_ae_calling, 16
    add edi, 16
    mov ecx, 32
    xor al, al
    rep stosb
    invoke crt_memcpy, edi, OFFSET pdu_appctx, 25
    add edi, 25
    invoke crt_memcpy, edi, OFFSET pdu2_static, 58
    add edi, 58
    invoke crt_memcpy, edi, OFFSET pdu3_static, 61
    add edi, 61
    lea eax, outBuf
    sub edi, eax
    mov totalLen, edi
    lea edx, outBuf
    invoke send, sock, edx, totalLen, 0
    invoke crt_printf, OFFSET szDicomAssocFmt, sock
    ret
DICOM_SendAAssociateAC ENDP

DICOM_BuildCommandSet PROC USES edi pOut:DWORD, sopUid:DWORD, sopLen:DWORD, cmdField:DWORD, msgID:DWORD, dsType:DWORD, status:DWORD
    LOCAL cmdLen:DWORD
    LOCAL totalCmd:DWORD
    mov edi, pOut
    add edi, 12
    mov WORD PTR [edi], 0000h
    mov WORD PTR [edi+2], 0002h
    mov eax, sopLen
    mov DWORD PTR [edi+4], eax
    lea ecx, [edi+8]
    invoke crt_memcpy, ecx, sopUid, sopLen
    add edi, 8
    add edi, sopLen
    invoke DICOM_WriteImplicitUS, edi, 0000h, 0100h, cmdField
    add edi, 10
    invoke DICOM_WriteImplicitUS, edi, 0000h, 0120h, msgID
    add edi, 10
    invoke DICOM_WriteImplicitUS, edi, 0000h, 0800h, dsType
    add edi, 10
    invoke DICOM_WriteImplicitUS, edi, 0000h, 0900h, status
    add edi, 10
    mov eax, pOut
    add eax, 12
    mov ecx, edi
    sub ecx, eax
    mov cmdLen, ecx
    mov eax, pOut
    mov WORD PTR [eax], 0000h
    mov WORD PTR [eax+2], 0000h
    mov DWORD PTR [eax+4], 4
    mov ecx, cmdLen
    mov DWORD PTR [eax+8], ecx
    mov eax, cmdLen
    add eax, 12
    mov totalCmd, eax
    mov eax, totalCmd
    ret
DICOM_BuildCommandSet ENDP

DICOM_SendPDV PROC USES edi sock:DWORD, pcid:DWORD, pData:DWORD, dataLen:DWORD, pdvFlags:DWORD
    LOCAL pdvLen:DWORD
    LOCAL pduLen:DWORD
    LOCAL totalSend:DWORD
    mov edi, OFFSET g_dicomSendBuf
    mov BYTE PTR [edi], 04h
    mov BYTE PTR [edi+1], 00h
    mov eax, dataLen
    add eax, 2
    mov pdvLen, eax
    add eax, 4
    mov pduLen, eax
    mov eax, pduLen
    bswap eax
    mov DWORD PTR [edi+2], eax
    mov eax, pdvLen
    bswap eax
    mov DWORD PTR [edi+6], eax
    mov eax, pcid
    mov BYTE PTR [edi+10], al
    mov eax, pdvFlags
    mov BYTE PTR [edi+11], al
    lea ecx, [edi+12]
    invoke crt_memcpy, ecx, pData, dataLen
    mov eax, dataLen
    add eax, 12
    mov totalSend, eax
    mov edx, OFFSET g_dicomSendBuf
    invoke send, sock, edx, totalSend, 0
    ret
DICOM_SendPDV ENDP

SendCEchoRsp PROC sock:DWORD, pcid:DWORD, msgID:DWORD
    LOCAL cmdBuf[256]:BYTE
    LOCAL cmdLen:DWORD
    invoke DICOM_BuildCommandSet, ADDR cmdBuf, OFFSET szEchoSOPClass, 18, 08030h, msgID, 0101h, 0000h
    mov cmdLen, eax
    invoke DICOM_SendPDV, sock, pcid, ADDR cmdBuf, cmdLen, 03h
    ret
SendCEchoRsp ENDP

; ==============================================================================
; CSV PARSE / BUILD / FILE
; ==============================================================================
ParseCSVLineToEntry PROC uses esi edi pLine:DWORD, pEntry:DWORD
    LOCAL fieldIdx:DWORD
    LOCAL charIdx:DWORD
    LOCAL quoteState:DWORD
    LOCAL pDest:DWORD
    LOCAL charCode:DWORD
    invoke RtlZeroMemory, pEntry, ENTRY_SIZE
    mov esi, pLine
    mov fieldIdx, 0
    mov charIdx, 0
    mov quoteState, 0
    mov eax, pEntry
    mov pDest, eax
PCL_Loop:
    movzx eax, BYTE PTR [esi]
    mov charCode, eax
    cmp eax, 0
    je PCL_End
    cmp eax, 0Dh
    je PCL_End
    cmp eax, 0Ah
    je PCL_End
    cmp al, '~'
    jne PCL_NotTilde
    mov charCode, '"'
PCL_NotTilde:
    mov eax, charCode
    cmp al, '"'
    jne PCL_CheckComma
    cmp quoteState, 0
    je PCL_QOn
    mov quoteState, 0
    inc esi
    jmp PCL_Loop
PCL_QOn:
    mov quoteState, 1
    inc esi
    jmp PCL_Loop
PCL_CheckComma:
    mov eax, charCode
    cmp al, ','
    jne PCL_Store
    cmp quoteState, 0
    jne PCL_Store
    mov edi, pDest
    add edi, charIdx
    mov BYTE PTR [edi], 0
    inc fieldIdx
    cmp fieldIdx, FIELD_COUNT
    jge PCL_End
    mov eax, pDest
    add eax, FIELD_SIZE
    mov pDest, eax
    mov charIdx, 0
    inc esi
    jmp PCL_Loop
PCL_Store:
    cmp charIdx, FIELD_SIZE - 1
    jge PCL_NextChar
    mov edi, pDest
    add edi, charIdx
    mov eax, charCode
    mov BYTE PTR [edi], al
    inc charIdx
PCL_NextChar:
    inc esi
    jmp PCL_Loop
PCL_End:
    mov edi, pDest
    add edi, charIdx
    mov BYTE PTR [edi], 0
    mov fieldIdx, 0
PCL_Trim:
    cmp fieldIdx, FIELD_COUNT
    jge PCL_Done
    invoke GetFieldPtr, pEntry, fieldIdx
    invoke TrimInPlace, eax
    inc fieldIdx
    jmp PCL_Trim
PCL_Done:
    mov eax, 1
    ret
ParseCSVLineToEntry ENDP

ValidateEntry PROC pEntry:DWORD
    invoke GetFieldPtr, pEntry, 0
    cmp BYTE PTR [eax], 0
    je VE_No
    invoke GetFieldPtr, pEntry, 1
    cmp BYTE PTR [eax], 0
    je VE_No
    invoke GetFieldPtr, pEntry, 3
    invoke IsEightDigits, eax
    cmp eax, 1
    jne VE_No
    invoke GetFieldPtr, pEntry, 4
    invoke IsSexValid, eax
    cmp eax, 1
    jne VE_No
    invoke GetFieldPtr, pEntry, 6
    cmp BYTE PTR [eax], 0
    je VE_No
    invoke GetFieldPtr, pEntry, 9
    cmp BYTE PTR [eax], 0
    je VE_No
    invoke GetFieldPtr, pEntry, 10
    invoke IsEightDigits, eax
    cmp eax, 1
    jne VE_No
    invoke GetFieldPtr, pEntry, 15
    invoke IsStatusValid, eax
    cmp eax, 1
    jne VE_No
    invoke GetFieldPtr, pEntry, 11
    invoke IsTimeValidOrEmpty, eax
    cmp eax, 1
    jne VE_No
    mov eax, 1
    ret
VE_No:
    xor eax, eax
    ret
ValidateEntry ENDP

NeedsQuote PROC uses esi pField:DWORD
    mov esi, pField
NQ_Loop:
    mov al, BYTE PTR [esi]
    cmp al, 0
    je NQ_No
    cmp al, ','
    je NQ_Yes
    cmp al, '"'
    je NQ_Yes
    inc esi
    jmp NQ_Loop
NQ_Yes:
    mov eax, 1
    ret
NQ_No:
    xor eax, eax
    ret
NeedsQuote ENDP

AppendChar PROC pOutPtr:DWORD, charVal:DWORD
    mov edx, pOutPtr
    mov eax, DWORD PTR [edx]
    mov ecx, charVal
    mov BYTE PTR [eax], cl
    inc eax
    mov DWORD PTR [edx], eax
    ret
AppendChar ENDP

BuildCSVLineFromEntry PROC uses esi pEntry:DWORD, pOut:DWORD
    LOCAL fieldIdx:DWORD
    LOCAL pField:DWORD
    LOCAL pCur:DWORD
    LOCAL quoteNeeded:DWORD
    mov eax, pOut
    mov pCur, eax
    mov fieldIdx, 0
BCL_FieldLoop:
    cmp fieldIdx, FIELD_COUNT
    jge BCL_End
    cmp fieldIdx, 0
    je BCL_NoComma
    invoke AppendChar, ADDR pCur, ','
BCL_NoComma:
    invoke GetFieldPtr, pEntry, fieldIdx
    mov pField, eax
    invoke NeedsQuote, pField
    mov quoteNeeded, eax
    cmp quoteNeeded, 1
    jne BCL_Copy
    invoke AppendChar, ADDR pCur, '"'
BCL_Copy:
    mov esi, pField
BCL_CopyLoop:
    mov al, BYTE PTR [esi]
    cmp al, 0
    je BCL_FieldDone
    cmp quoteNeeded, 1
    jne BCL_Normal
    cmp al, '"'
    jne BCL_Normal
    invoke AppendChar, ADDR pCur, '"'
    invoke AppendChar, ADDR pCur, '"'
    inc esi
    jmp BCL_CopyLoop
BCL_Normal:
    movzx eax, BYTE PTR [esi]
    invoke AppendChar, ADDR pCur, eax
    inc esi
    jmp BCL_CopyLoop
BCL_FieldDone:
    cmp quoteNeeded, 1
    jne BCL_Next
    invoke AppendChar, ADDR pCur, '"'
BCL_Next:
    inc fieldIdx
    jmp BCL_FieldLoop
BCL_End:
    mov edx, pCur
    mov BYTE PTR [edx], 0
    ret
BuildCSVLineFromEntry ENDP

CreateCSVIfMissing PROC
    LOCAL hFile:DWORD
    invoke crt_fopen, OFFSET szCSVFile, OFFSET szModeRead
    mov hFile, eax
    cmp eax, 0
    je CCIM_Create
    invoke crt_fclose, hFile
    ret
CCIM_Create:
    invoke crt_fopen, OFFSET szCSVFile, OFFSET szModeWrite
    mov hFile, eax
    cmp eax, 0
    je CCIM_Done
    invoke crt_fprintf, hFile, OFFSET szFmtLine, OFFSET szCSVHeader
    invoke crt_fclose, hFile
CCIM_Done:
    ret
CreateCSVIfMissing ENDP

FirstFieldEquals PROC uses esi edi pLine:DWORD, pPatientID:DWORD
    mov esi, pLine
    mov edi, pPatientID
FFE_Loop:
    mov al, BYTE PTR [esi]
    cmp al, ','
    je FFE_EndField
    cmp al, 0
    je FFE_EndField
    cmp al, 0Dh
    je FFE_EndField
    cmp al, 0Ah
    je FFE_EndField
    mov dl, BYTE PTR [edi]
    cmp dl, 0
    je FFE_No
    cmp al, dl
    jne FFE_No
    inc esi
    inc edi
    jmp FFE_Loop
FFE_EndField:
    cmp BYTE PTR [edi], 0
    jne FFE_No
    mov eax, 1
    ret
FFE_No:
    xor eax, eax
    ret
FirstFieldEquals ENDP

UpdateCsvByPatient PROC pEntry:DWORD, pLineOut:DWORD
    LOCAL hIn:DWORD
    LOCAL hOut:DWORD
    LOCAL found:DWORD
    LOCAL pPatientID:DWORD
    mov found, 0
    invoke CreateCSVIfMissing
    invoke GetFieldPtr, pEntry, 0
    mov pPatientID, eax
    invoke crt_fopen, OFFSET szCSVFile, OFFSET szModeRead
    mov hIn, eax
    invoke crt_fopen, OFFSET szCSVTempFile, OFFSET szModeWrite
    mov hOut, eax
    cmp hOut, 0
    je UCP_Fail
    cmp hIn, 0
    je UCP_WriteHeader
    invoke crt_fgets, OFFSET g_fileLine, LINE_SIZE, hIn
    cmp eax, 0
    je UCP_WriteHeader
    invoke crt_fputs, OFFSET g_fileLine, hOut
    jmp UCP_ReadLoop
UCP_WriteHeader:
    invoke crt_fprintf, hOut, OFFSET szFmtLine, OFFSET szCSVHeader
    jmp UCP_AfterLoop
UCP_ReadLoop:
    invoke crt_fgets, OFFSET g_fileLine, LINE_SIZE, hIn
    cmp eax, 0
    je UCP_AfterLoop
    cmp found, 1
    je UCP_CopyOriginal
    invoke FirstFieldEquals, OFFSET g_fileLine, pPatientID
    cmp eax, 1
    jne UCP_CopyOriginal
    invoke crt_fprintf, hOut, OFFSET szFmtLine, pLineOut
    mov found, 1
    jmp UCP_ReadLoop
UCP_CopyOriginal:
    invoke crt_fputs, OFFSET g_fileLine, hOut
    jmp UCP_ReadLoop
UCP_AfterLoop:
    cmp found, 1
    je UCP_Close
    invoke crt_fprintf, hOut, OFFSET szFmtLine, pLineOut
UCP_Close:
    cmp hIn, 0
    je UCP_NoCloseIn
    invoke crt_fclose, hIn
UCP_NoCloseIn:
    invoke crt_fclose, hOut
    invoke crt_remove, OFFSET szCSVFile
    invoke crt_rename, OFFSET szCSVTempFile, OFFSET szCSVFile
    mov eax, found
    ret
UCP_Fail:
    cmp hIn, 0
    je UCP_Return
    invoke crt_fclose, hIn
UCP_Return:
    xor eax, eax
    ret
UpdateCsvByPatient ENDP

; ==============================================================================
; MWL DATASET BUILDER  (fld renamed to fldPtr)
; ==============================================================================
BuildMWLDataset PROC pEntry:DWORD, pOut:DWORD
    LOCAL pCur:DWORD
    LOCAL pSps:DWORD
    LOCAL spsLen:DWORD
    LOCAL timeBuf[16]:BYTE
    LOCAL fldPtr:DWORD
    LOCAL pTimeSrc:DWORD

    mov eax, pOut
    mov pCur, eax

    invoke GetFieldPtr, pEntry, 2
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0008h, 0050h, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 14
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0008h, 0090h, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 1
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0010h, 0010h, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 0
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0010h, 0020h, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 3
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0010h, 0030h, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 4
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0010h, 0040h, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 13
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0020h, 000Dh, fldPtr
    add pCur, eax

    invoke GetFieldPtr, pEntry, 12
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0032h, 1060h, fldPtr
    add pCur, eax

    ; ---- SPS item ----
    mov eax, OFFSET g_spsBuf
    mov pSps, eax

    invoke GetFieldPtr, pEntry, 9
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0008h, 0060h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 8
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0001h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 10
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0002h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 11
    mov pTimeSrc, eax
    invoke StripColons, pTimeSrc, ADDR timeBuf
    invoke WriteImplicitStr, pSps, 0040h, 0003h, ADDR timeBuf
    add pSps, eax

    invoke GetFieldPtr, pEntry, 19
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0006h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 6
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0007h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 5
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0009h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 20
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0010h, fldPtr
    add pSps, eax

    invoke GetFieldPtr, pEntry, 21
    mov fldPtr, eax
    invoke WriteImplicitStr, pSps, 0040h, 0011h, fldPtr
    add pSps, eax

    mov eax, pSps
    sub eax, OFFSET g_spsBuf
    mov spsLen, eax

    mov edx, pCur
    mov WORD PTR [edx], 0040h
    mov WORD PTR [edx+2], 0100h
    mov eax, spsLen
    add eax, 8
    mov DWORD PTR [edx+4], eax
    add pCur, 8

    mov edx, pCur
    mov WORD PTR [edx], 0FFFEh
    mov WORD PTR [edx+2], 0E000h
    mov eax, spsLen
    mov DWORD PTR [edx+4], eax
    add pCur, 8

    invoke crt_memcpy, pCur, OFFSET g_spsBuf, spsLen
    mov eax, spsLen
    add pCur, eax

    invoke GetFieldPtr, pEntry, 7
    mov fldPtr, eax
    invoke WriteImplicitStr, pCur, 0040h, 1001h, fldPtr
    add pCur, eax

    mov eax, pCur
    sub eax, pOut
    ret
BuildMWLDataset ENDP

SendCFindPending PROC sock:DWORD, pcid:DWORD, msgID:DWORD, pDataset:DWORD, dsLen:DWORD
    LOCAL cmdBuf[256]:BYTE
    LOCAL cmdLen:DWORD
    invoke DICOM_BuildCommandSet, ADDR cmdBuf, OFFSET szMwlSOPClass, 22, 08020h, msgID, 0102h, 0FF00h
    mov cmdLen, eax
    invoke DICOM_SendPDV, sock, pcid, ADDR cmdBuf, cmdLen, 03h
    invoke DICOM_SendPDV, sock, pcid, pDataset, dsLen, 02h
    ret
SendCFindPending ENDP

SendCFindFinal PROC sock:DWORD, pcid:DWORD, msgID:DWORD
    LOCAL cmdBuf[256]:BYTE
    LOCAL cmdLen:DWORD
    invoke DICOM_BuildCommandSet, ADDR cmdBuf, OFFSET szMwlSOPClass, 22, 08020h, msgID, 0101h, 0000h
    mov cmdLen, eax
    invoke DICOM_SendPDV, sock, pcid, ADDR cmdBuf, cmdLen, 03h
    ret
SendCFindFinal ENDP

SendMWLResults PROC sock:DWORD, pcid:DWORD, msgID:DWORD
    LOCAL hFile:DWORD
    LOCAL dsLen:DWORD
    LOCAL pPID:DWORD
    invoke crt_fopen, OFFSET szCSVFile, OFFSET szModeRead
    mov hFile, eax
    cmp eax, 0
    je SMR_Final
    invoke crt_fgets, OFFSET g_fileLine, LINE_SIZE, hFile
SMR_Loop:
    invoke crt_fgets, OFFSET g_fileLine, LINE_SIZE, hFile
    cmp eax, 0
    je SMR_Close
    invoke ParseCSVLineToEntry, OFFSET g_fileLine, OFFSET g_tmpEntry
    invoke GetFieldPtr, OFFSET g_tmpEntry, 0
    mov pPID, eax
    cmp BYTE PTR [eax], 0
    je SMR_Loop
    invoke crt_printf, OFFSET szMatchFmt, pPID
    invoke BuildMWLDataset, OFFSET g_tmpEntry, OFFSET g_mwlDsBuf
    mov dsLen, eax
    invoke SendCFindPending, sock, pcid, msgID, OFFSET g_mwlDsBuf, dsLen
    jmp SMR_Loop
SMR_Close:
    invoke crt_fclose, hFile
SMR_Final:
    invoke SendCFindFinal, sock, pcid, msgID
    ret
SendMWLResults ENDP

; ==============================================================================
; DICOM CLIENT HANDLER
; ==============================================================================
ExtractPCID PROC pBuf:DWORD, cbLen:DWORD
    mov edx, pBuf
    movzx eax, BYTE PTR [edx+10]
    ret
ExtractPCID ENDP

DICOM_HandleClient PROC USES esi sock:DWORD
    LOCAL cb:DWORD
    LOCAL msgID:DWORD
    LOCAL pcid:DWORD
DHC_Loop:
    invoke recv, sock, OFFSET g_dicomRecvBuf, 16384, 0
    mov cb, eax
    cmp eax, 0
    jle DHC_Done
    movzx eax, BYTE PTR [g_dicomRecvBuf]
    cmp al, 01h
    je DHC_Associate
    cmp al, 04h
    je DHC_Data
    cmp al, 05h
    je DHC_Release
    jmp DHC_Loop
DHC_Associate:
    invoke DICOM_SendAAssociateAC, sock
    jmp DHC_Loop
DHC_Data:
    invoke ExtractPCID, OFFSET g_dicomRecvBuf, cb
    mov pcid, eax
    invoke MemFindString, OFFSET g_dicomRecvBuf, cb, OFFSET szEchoSOPClass
    cmp eax, 0
    je DHC_CheckFind
    invoke DICOM_ExtractMessageID, OFFSET g_dicomRecvBuf, cb
    mov msgID, eax
    invoke crt_printf, OFFSET szDicomEchoFmt, sock, msgID, pcid
    invoke SendCEchoRsp, sock, pcid, msgID
    jmp DHC_Loop
DHC_CheckFind:
    invoke MemFindString, OFFSET g_dicomRecvBuf, cb, OFFSET szMwlSOPClass
    cmp eax, 0
    je DHC_Loop
    invoke DICOM_ExtractMessageID, OFFSET g_dicomRecvBuf, cb
    mov msgID, eax
    invoke crt_printf, OFFSET szDicomFindFmt, sock, msgID, pcid
    invoke SendMWLResults, sock, pcid, msgID
    jmp DHC_Loop
DHC_Release:
    mov DWORD PTR [g_dicomSendBuf], 00000006h
    mov DWORD PTR [g_dicomSendBuf+4], 00000400h
    invoke send, sock, OFFSET g_dicomSendBuf, 8, 0
DHC_Done:
    ret
DICOM_HandleClient ENDP

; ==============================================================================
; SOCKET SERVER (telnet)
; ==============================================================================
InitArrays PROC
    invoke RtlZeroMemory, OFFSET g_clients, SIZEOF g_clients
    invoke RtlZeroMemory, OFFSET g_clientIDs, SIZEOF g_clientIDs
    invoke RtlZeroMemory, OFFSET g_clientLastTick, SIZEOF g_clientLastTick
    invoke RtlZeroMemory, OFFSET g_clientTimeout, SIZEOF g_clientTimeout
    invoke RtlZeroMemory, OFFSET g_clientBufLen, SIZEOF g_clientBufLen
    invoke RtlZeroMemory, OFFSET g_pendingFlag, SIZEOF g_pendingFlag
    invoke RtlZeroMemory, OFFSET g_pendingSince, SIZEOF g_pendingSince
    ret
InitArrays ENDP

InitSockets PROC
    invoke WSAStartup, 0202h, OFFSET wsaData
    ret
InitSockets ENDP

SetNonBlocking PROC sock:DWORD
    LOCAL mode:DWORD
    mov mode, 1
    invoke ioctlsocket, sock, FIONBIO, ADDR mode
    ret
SetNonBlocking ENDP

SetBlocking PROC sock:DWORD
    LOCAL mode:DWORD
    mov mode, 0
    invoke ioctlsocket, sock, FIONBIO, ADDR mode
    ret
SetBlocking ENDP

StartTelnetServer PROC
    LOCAL sinbuf[16]:BYTE
    LOCAL s:DWORD
    invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
    mov s, eax
    mov g_listenSocket, eax
    cmp eax, INVALID_SOCKET
    jne STS_SocketOK
    invoke crt_printf, OFFSET szListenFailFmt, g_TelnetPort
    xor eax, eax
    ret
STS_SocketOK:
    invoke RtlZeroMemory, ADDR sinbuf, 16
    lea edx, sinbuf
    mov WORD PTR [edx+0], AF_INET
    invoke htons, g_TelnetPort
    lea edx, sinbuf
    mov WORD PTR [edx+2], ax
    mov DWORD PTR [edx+4], INADDR_ANY
    invoke bind, g_listenSocket, ADDR sinbuf, 16
    cmp eax, SOCKET_ERROR
    jne STS_BindOK
    invoke crt_printf, OFFSET szListenFailFmt, g_TelnetPort
    invoke closesocket, g_listenSocket
    mov g_listenSocket, INVALID_SOCKET
    xor eax, eax
    ret
STS_BindOK:
    invoke listen, g_listenSocket, SOMAXCONN
    cmp eax, SOCKET_ERROR
    jne STS_ListenOK
    invoke crt_printf, OFFSET szListenFailFmt, g_TelnetPort
    invoke closesocket, g_listenSocket
    mov g_listenSocket, INVALID_SOCKET
    xor eax, eax
    ret
STS_ListenOK:
    invoke SetNonBlocking, g_listenSocket
    invoke crt_printf, OFFSET szListenFmt, g_TelnetPort
    mov eax, 1
    ret
StartTelnetServer ENDP

StartDicomServer PROC
    LOCAL sinbuf[16]:BYTE
    LOCAL s:DWORD
    invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
    mov s, eax
    mov g_dicomListenSocket, eax
    cmp eax, INVALID_SOCKET
    je SDS_Fail
    invoke RtlZeroMemory, ADDR sinbuf, 16
    lea edx, sinbuf
    mov WORD PTR [edx+0], AF_INET
    invoke htons, g_DicomPort
    lea edx, sinbuf
    mov WORD PTR [edx+2], ax
    mov DWORD PTR [edx+4], INADDR_ANY
    invoke bind, g_dicomListenSocket, ADDR sinbuf, 16
    cmp eax, SOCKET_ERROR
    je SDS_Fail
    invoke listen, g_dicomListenSocket, SOMAXCONN
    cmp eax, SOCKET_ERROR
    je SDS_Fail
    invoke SetNonBlocking, g_dicomListenSocket
    invoke crt_printf, OFFSET szDicomListenFmt, g_DicomPort
    mov eax, 1
    ret
SDS_Fail:
    invoke crt_printf, OFFSET szDicomListenFail, g_DicomPort
    xor eax, eax
    ret
StartDicomServer ENDP

FindFreeClientSlot PROC
    LOCAL idx:DWORD
    mov idx, 0
FFCS_Loop:
    cmp idx, MAX_CLIENTS
    jge FFCS_None
    invoke GetClientSockPtr, idx
    cmp DWORD PTR [eax], 0
    je FFCS_Found
    inc idx
    jmp FFCS_Loop
FFCS_Found:
    mov eax, idx
    ret
FFCS_None:
    mov eax, -1
    ret
FindFreeClientSlot ENDP

AddClient PROC sock:DWORD
    LOCAL idx:DWORD
    LOCAL pBuf:DWORD
    invoke FindFreeClientSlot
    mov idx, eax
    cmp eax, -1
    jne AC_Add
    invoke closesocket, sock
    ret
AC_Add:
    invoke SetNonBlocking, sock
    invoke GetClientSockPtr, idx
    mov edx, sock
    mov DWORD PTR [eax], edx
    invoke GetClientIDPtr, idx
    mov edx, sock
    mov DWORD PTR [eax], edx
    invoke GetClientBufLenPtr, idx
    mov DWORD PTR [eax], 0
    invoke GetClientBufferPtr, idx
    mov pBuf, eax
    invoke RtlZeroMemory, pBuf, CLIENT_BUF_SIZE
    invoke GetTickCount
    mov edx, eax
    invoke GetClientLastPtr, idx
    mov DWORD PTR [eax], edx
    invoke GetClientTimeoutPtr, idx
    mov DWORD PTR [eax], DEFAULT_TIMEOUT_MS
    invoke GetPendingFlagPtr, idx
    mov DWORD PTR [eax], 0
    invoke GetPendingSincePtr, idx
    mov DWORD PTR [eax], 0
    invoke crt_printf, OFFSET szClientConnFmt, sock
    invoke SendText, sock, OFFSET szConnected
    ret
AddClient ENDP

RemoveClient PROC idx:DWORD
    LOCAL sock:DWORD
    invoke GetClientSockPtr, idx
    mov eax, DWORD PTR [eax]
    mov sock, eax
    cmp sock, 0
    je RC_Clear
    invoke closesocket, sock
    invoke crt_printf, OFFSET szClientDiscFmt, sock
RC_Clear:
    invoke GetClientSockPtr, idx
    mov DWORD PTR [eax], 0
    invoke GetClientIDPtr, idx
    mov DWORD PTR [eax], 0
    invoke GetClientBufLenPtr, idx
    mov DWORD PTR [eax], 0
    invoke GetPendingFlagPtr, idx
    mov DWORD PTR [eax], 0
    invoke GetPendingSincePtr, idx
    mov DWORD PTR [eax], 0
    ret
RemoveClient ENDP

AcceptNewClients PROC
    LOCAL s:DWORD
ANC_Loop:
    invoke accept, g_listenSocket, NULL, NULL
    mov s, eax
    cmp eax, INVALID_SOCKET
    jne ANC_Got
    invoke WSAGetLastError
    cmp eax, WSAEWOULDBLOCK
    je ANC_Done
    jmp ANC_Done
ANC_Got:
    invoke AddClient, s
    jmp ANC_Loop
ANC_Done:
    ret
AcceptNewClients ENDP

PollDicomServer PROC
    LOCAL s:DWORD
    invoke accept, g_dicomListenSocket, NULL, NULL
    mov s, eax
    cmp eax, INVALID_SOCKET
    je PDS_Done
    invoke crt_printf, OFFSET szDicomConnFmt, s
    invoke SetBlocking, s
    invoke DICOM_HandleClient, s
    invoke closesocket, s
    invoke crt_printf, OFFSET szDicomDiscFmt, s
PDS_Done:
    ret
PollDicomServer ENDP

ExtractDispParam PROC uses esi edi pLine:DWORD, pOut:DWORD
    mov esi, pLine
    add esi, 4
EDP_Skip:
    mov al, BYTE PTR [esi]
    cmp al, ' '
    jne EDP_Copy
    inc esi
    jmp EDP_Skip
EDP_Copy:
    mov edi, pOut
EDP_Loop:
    mov al, BYTE PTR [esi]
    cmp al, 0
    je EDP_Zero
    cmp al, 0Dh
    je EDP_Zero
    cmp al, 0Ah
    je EDP_Zero
    mov BYTE PTR [edi], al
    inc esi
    inc edi
    jmp EDP_Loop
EDP_Zero:
    mov BYTE PTR [edi], 0
    invoke TrimInPlace, pOut
    ret
ExtractDispParam ENDP

IsDateRangeParam PROC pParam:DWORD
    mov edx, pParam
    cmp BYTE PTR [edx+8], ' '
    jne IDR_No
    cmp BYTE PTR [edx+17], 0
    jne IDR_No
    mov eax, 1
    ret
IDR_No:
    xor eax, eax
    ret
IsDateRangeParam ENDP

LineMatchesDisp PROC pLine:DWORD, pParam:DWORD
    LOCAL tempEntry[ENTRY_SIZE]:BYTE
    LOCAL pField:DWORD
    LOCAL pTo:DWORD
    mov edx, pParam
    cmp BYTE PTR [edx], 0
    je LMD_Yes
    invoke ParseCSVLineToEntry, pLine, ADDR tempEntry
    invoke IsEightDigits, pParam
    cmp eax, 1
    jne LMD_Range
    invoke GetFieldPtr, ADDR tempEntry, 10
    invoke crt_strcmp, eax, pParam
    cmp eax, 0
    je LMD_Yes
    jmp LMD_No
LMD_Range:
    invoke IsDateRangeParam, pParam
    cmp eax, 1
    jne LMD_Modality
    invoke GetFieldPtr, ADDR tempEntry, 10
    mov pField, eax
    invoke crt_strncmp, pField, pParam, 8
    cmp eax, 0
    jl LMD_No
    mov eax, pParam
    add eax, 9
    mov pTo, eax
    invoke crt_strncmp, pField, pTo, 8
    cmp eax, 0
    jg LMD_No
    jmp LMD_Yes
LMD_Modality:
    invoke GetFieldPtr, ADDR tempEntry, 9
    invoke StrIEquals, eax, pParam
    cmp eax, 1
    je LMD_Yes
LMD_No:
    xor eax, eax
    ret
LMD_Yes:
    mov eax, 1
    ret
LineMatchesDisp ENDP

ProcessDispCommand PROC clientIdx:DWORD, pLine:DWORD
    LOCAL hFile:DWORD
    LOCAL sock:DWORD
    invoke ExtractDispParam, pLine, OFFSET g_dispParam
    invoke GetClientSockPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov sock, eax
    invoke crt_fopen, OFFSET szCSVFile, OFFSET szModeRead
    mov hFile, eax
    cmp eax, 0
    je PDC_Done
    invoke crt_fgets, OFFSET g_fileLine, LINE_SIZE, hFile
PDC_Loop:
    invoke crt_fgets, OFFSET g_fileLine, LINE_SIZE, hFile
    cmp eax, 0
    je PDC_Close
    invoke LineMatchesDisp, OFFSET g_fileLine, OFFSET g_dispParam
    cmp eax, 1
    jne PDC_Loop
    invoke SendText, sock, OFFSET g_fileLine
    jmp PDC_Loop
PDC_Close:
    invoke crt_fclose, hFile
PDC_Done:
    ret
ProcessDispCommand ENDP

CommitPendingEntry PROC clientIdx:DWORD
    LOCAL pEntry:DWORD
    LOCAL pPatientID:DWORD
    LOCAL sock:DWORD
    LOCAL found:DWORD
    invoke GetPendingEntryPtr, clientIdx
    mov pEntry, eax
    invoke BuildCSVLineFromEntry, pEntry, OFFSET g_lineOut
    invoke UpdateCsvByPatient, pEntry, OFFSET g_lineOut
    mov found, eax
    invoke GetFieldPtr, pEntry, 0
    mov pPatientID, eax
    invoke GetClientSockPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov sock, eax
    cmp found, 1
    je CPE_Updated
    invoke SendText, sock, OFFSET szInsertedResp
    invoke crt_printf, OFFSET szInsertedFmt, pPatientID
    jmp CPE_Clear
CPE_Updated:
    invoke SendText, sock, OFFSET szUpdatedResp
    invoke crt_printf, OFFSET szUpdatedFmt, pPatientID
CPE_Clear:
    invoke GetPendingFlagPtr, clientIdx
    mov DWORD PTR [eax], 0
    invoke GetPendingSincePtr, clientIdx
    mov DWORD PTR [eax], 0
    ret
CommitPendingEntry ENDP

ProcessClientLine PROC clientIdx:DWORD, pLine:DWORD
    LOCAL entry[ENTRY_SIZE]:BYTE
    LOCAL pPending:DWORD
    LOCAL pPatientID:DWORD
    LOCAL sock:DWORD
    invoke TrimInPlace, pLine
    mov edx, pLine
    cmp BYTE PTR [edx], 0
    je PCL2_Done
    invoke StartsWithDISP, pLine
    cmp eax, 1
    jne PCL2_CSV
    invoke ProcessDispCommand, clientIdx, pLine
    jmp PCL2_Done
PCL2_CSV:
    invoke ParseCSVLineToEntry, pLine, ADDR entry
    invoke ValidateEntry, ADDR entry
    cmp eax, 1
    je PCL2_Valid
    invoke GetClientSockPtr, clientIdx
    mov eax, DWORD PTR [eax]
    invoke SendText, eax, OFFSET szInvalidResp
    jmp PCL2_Done
PCL2_Valid:
    invoke GetPendingEntryPtr, clientIdx
    mov pPending, eax
    invoke crt_memcpy, pPending, ADDR entry, ENTRY_SIZE
    invoke GetPendingFlagPtr, clientIdx
    mov DWORD PTR [eax], 1
    invoke GetTickCount
    mov edx, eax
    invoke GetPendingSincePtr, clientIdx
    mov DWORD PTR [eax], edx
    invoke GetClientTimeoutPtr, clientIdx
    add DWORD PTR [eax], 1000
    invoke GetClientSockPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov sock, eax
    invoke SendText, sock, OFFSET szPendingResp
    invoke GetFieldPtr, pPending, 0
    mov pPatientID, eax
    invoke crt_printf, OFFSET szPendingFmt, pPatientID
PCL2_Done:
    ret
ProcessClientLine ENDP

CheckPendingAndTimeout PROC clientIdx:DWORD
    LOCAL nowTick:DWORD
    LOCAL sinceTick:DWORD
    LOCAL lastTick:DWORD
    LOCAL timeoutVal:DWORD
    LOCAL sock:DWORD
    invoke GetClientSockPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov sock, eax
    cmp eax, 0
    je CPAT_Done
    invoke GetTickCount
    mov nowTick, eax
    invoke GetPendingFlagPtr, clientIdx
    cmp DWORD PTR [eax], 1
    jne CPAT_Timeout
    invoke GetPendingSincePtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov sinceTick, eax
    mov eax, nowTick
    sub eax, sinceTick
    cmp eax, APPEND_DELAY_MS
    jb CPAT_Timeout
    invoke CommitPendingEntry, clientIdx
    invoke GetTickCount
    mov edx, eax
    invoke GetClientLastPtr, clientIdx
    mov DWORD PTR [eax], edx
CPAT_Timeout:
    invoke GetClientLastPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov lastTick, eax
    invoke GetClientTimeoutPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov timeoutVal, eax
    mov eax, nowTick
    sub eax, lastTick
    cmp eax, timeoutVal
    jb CPAT_Done
    invoke crt_printf, OFFSET szTimeoutFmt, sock
    invoke RemoveClient, clientIdx
CPAT_Done:
    ret
CheckPendingAndTimeout ENDP

AppendReceivedBytes PROC clientIdx:DWORD, pBytes:DWORD, cbBytes:DWORD
    LOCAL pBuf:DWORD
    LOCAL pLen:DWORD
    LOCAL curLen:DWORD
    LOCAL idx:DWORD
    LOCAL charCode:DWORD
    invoke GetClientBufferPtr, clientIdx
    mov pBuf, eax
    invoke GetClientBufLenPtr, clientIdx
    mov pLen, eax
    mov eax, DWORD PTR [eax]
    mov curLen, eax
    mov idx, 0
ARB_Loop:
    mov eax, idx
    cmp eax, cbBytes
    jge ARB_Done
    mov edx, pBytes
    add edx, idx
    movzx eax, BYTE PTR [edx]
    mov charCode, eax
    cmp al, 0Dh
    je ARB_Next
    cmp al, 0Ah
    je ARB_LineComplete
    cmp curLen, CLIENT_BUF_SIZE - 1
    jge ARB_Next
    mov edx, pBuf
    add edx, curLen
    mov eax, charCode
    mov BYTE PTR [edx], al
    inc curLen
    jmp ARB_Next
ARB_LineComplete:
    mov edx, pBuf
    add edx, curLen
    mov BYTE PTR [edx], 0
    invoke ProcessClientLine, clientIdx, pBuf
    mov curLen, 0
    invoke RtlZeroMemory, pBuf, CLIENT_BUF_SIZE
ARB_Next:
    inc idx
    jmp ARB_Loop
ARB_Done:
    mov eax, pLen
    mov edx, curLen
    mov DWORD PTR [eax], edx
    ret
AppendReceivedBytes ENDP

PollClient PROC clientIdx:DWORD
    LOCAL sock:DWORD
    LOCAL cb:DWORD
    invoke GetClientSockPtr, clientIdx
    mov eax, DWORD PTR [eax]
    mov sock, eax
    cmp eax, 0
    je PC_Done
    invoke recv, sock, OFFSET g_recvBuf, RECV_SIZE, 0
    mov cb, eax
    cmp eax, 0
    jg PC_Data
    cmp eax, 0
    je PC_Disconnect
    invoke WSAGetLastError
    cmp eax, WSAEWOULDBLOCK
    je PC_CheckTimers
    jmp PC_Disconnect
PC_Data:
    invoke GetTickCount
    mov edx, eax
    invoke GetClientLastPtr, clientIdx
    mov DWORD PTR [eax], edx
    invoke AppendReceivedBytes, clientIdx, OFFSET g_recvBuf, cb
    jmp PC_CheckTimers
PC_Disconnect:
    invoke RemoveClient, clientIdx
    jmp PC_Done
PC_CheckTimers:
    invoke CheckPendingAndTimeout, clientIdx
PC_Done:
    ret
PollClient ENDP

ServerStart PROC
    cmp g_bRunning, 1
    je SS_Already
    invoke StartTelnetServer
    invoke StartDicomServer
    mov g_bRunning, 1
    invoke crt_printf, OFFSET szServerStarted
    invoke ModifyMenu, g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND or MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStop
SS_Already:
    ret
ServerStart ENDP

ServerStop PROC
    LOCAL idx:DWORD
    cmp g_bRunning, 0
    je SST_Already
    mov idx, 0
SST_Loop:
    cmp idx, MAX_CLIENTS
    jge SST_Listen
    invoke RemoveClient, idx
    inc idx
    jmp SST_Loop
SST_Listen:
    cmp g_listenSocket, INVALID_SOCKET
    je SST_DicomListen
    invoke closesocket, g_listenSocket
    mov g_listenSocket, INVALID_SOCKET
SST_DicomListen:
    cmp g_dicomListenSocket, INVALID_SOCKET
    je SST_Done
    invoke closesocket, g_dicomListenSocket
    mov g_dicomListenSocket, INVALID_SOCKET
SST_Done:
    mov g_bRunning, 0
    invoke crt_printf, OFFSET szServerStopped
    invoke ModifyMenu, g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND or MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStart
SST_Already:
    ret
ServerStop ENDP

ServerLoop PROC
    LOCAL idx:DWORD
    LOCAL msg:MSG
SL_PumpLoop:
    invoke PeekMessage, ADDR msg, NULL, 0, 0, PM_REMOVE
    test eax, eax
    jz SL_NoMsg
    invoke TranslateMessage, ADDR msg
    invoke DispatchMessage, ADDR msg
    jmp SL_PumpLoop
SL_NoMsg:
    cmp g_bRunning, 1
    jne SL_Done
    invoke AcceptNewClients
    invoke PollDicomServer
    mov idx, 0
SL_Loop:
    cmp idx, MAX_CLIENTS
    jge SL_Done
    invoke PollClient, idx
    inc idx
    jmp SL_Loop
SL_Done:
    ret
ServerLoop ENDP

; ==============================================================================
; TRAY / WINDOW
; ==============================================================================
WndProc PROC hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
    LOCAL pt:POINT
    LOCAL cmd:DWORD
    mov eax, uMsg
    cmp eax, WM_TRAYICON
    jne WP_NotTray
    mov eax, lParam
    cmp eax, WM_RBUTTONUP
    jne WP_NotRClick
    invoke GetCursorPos, ADDR pt
    invoke SetForegroundWindow, hWnd
    invoke TrackPopupMenu, g_hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hWnd, NULL
    xor eax, eax
    ret
WP_NotRClick:
    xor eax, eax
    ret
WP_NotTray:
    cmp eax, WM_COMMAND
    jne WP_NotCmd
    mov eax, wParam
    and eax, 0FFFFh
    mov cmd, eax
    cmp cmd, ID_TRAY_TOGGLE
    jne WP_NotToggle
    cmp g_bRunning, 1
    je WP_DoStop
    invoke ServerStart
    xor eax, eax
    ret
WP_DoStop:
    invoke ServerStop
    xor eax, eax
    ret
WP_NotToggle:
    cmp cmd, ID_TRAY_SHOW
    jne WP_NotShow
    invoke GetConsoleWindow
    test eax, eax
    jz WP_NotShow
    invoke ShowWindow, eax, SW_SHOW
    xor eax, eax
    ret
WP_NotShow:
    cmp cmd, ID_TRAY_EXIT
    jne WP_NotExit
    invoke ServerStop
    invoke Shell_NotifyIcon, NIM_DELETE, ADDR nid
    invoke PostQuitMessage, 0
    xor eax, eax
    ret
WP_NotExit:
    xor eax, eax
    ret
WP_NotCmd:
    cmp eax, WM_DESTROY
    jne WP_Def
    invoke ServerStop
    invoke Shell_NotifyIcon, NIM_DELETE, ADDR nid
    invoke PostQuitMessage, 0
    xor eax, eax
    ret
WP_Def:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret
WndProc ENDP

CreateTray PROC
    LOCAL wc:WNDCLASSEX
    invoke GetModuleHandle, NULL
    mov g_hInstance, eax
    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.style, 0
    mov wc.lpfnWndProc, OFFSET WndProc
    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0
    push g_hInstance
    pop wc.hInstance
    invoke LoadIcon, NULL, IDI_APPLICATION
    mov wc.hIcon, eax
    invoke LoadCursor, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, COLOR_WINDOW+1
    mov wc.lpszMenuName, 0
    mov wc.lpszClassName, OFFSET szWndClass
    mov wc.hIconSm, 0
    invoke RegisterClassEx, ADDR wc
    invoke CreateWindowEx, 0, OFFSET szWndClass, OFFSET szTrayTip,
        0, 0, 0, 0, 0, HWND_MESSAGE, NULL, g_hInstance, NULL
    mov g_hMainWnd, eax
    invoke CreatePopupMenu
    mov g_hMenu, eax
    cmp g_bRunning, 1
    je CT_AddStop
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStart
    jmp CT_AfterToggle
CT_AddStop:
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStop
CT_AfterToggle:
    invoke AppendMenu, g_hMenu, MF_SEPARATOR, 0, NULL
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_SHOW, OFFSET szMenuShow
    invoke AppendMenu, g_hMenu, MF_SEPARATOR, 0, NULL
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_EXIT, OFFSET szMenuExit
    mov nid.cbSize, SIZEOF NOTIFYICONDATA
    push g_hMainWnd
    pop nid.hwnd
    mov nid.uID, 1
    mov nid.uFlags, NIF_ICON or NIF_MESSAGE or NIF_TIP
    mov nid.uCallbackMessage, WM_TRAYICON
    invoke LoadIcon, NULL, IDI_APPLICATION
    mov nid.hIcon, eax
    invoke lstrcpy, ADDR nid.szTip, OFFSET szTrayTip
    invoke Shell_NotifyIcon, NIM_ADD, ADDR nid
    ret
CreateTray ENDP

; ==============================================================================
; MAIN
; ==============================================================================
Main PROC
    LOCAL qmsg:MSG
    invoke crt_printf, OFFSET szStartup
    invoke LoadConfig
    invoke crt_printf, OFFSET szConfigFmt, OFFSET g_aeCalled, g_TelnetPort, g_DicomPort, g_DebugLog
    invoke InitArrays
    invoke InitSockets
    invoke CreateCSVIfMissing
    invoke CreateTray
    invoke ServerStart
MainLoop:
    invoke ServerLoop
    invoke PeekMessage, ADDR qmsg, NULL, WM_QUIT, WM_QUIT, PM_NOREMOVE
    test eax, eax
    jnz MainExit
    invoke Sleep, 10
    jmp MainLoop
MainExit:
    ret
Main ENDP

start:
    invoke Main
    invoke WSACleanup
    invoke ExitProcess, 0
end start