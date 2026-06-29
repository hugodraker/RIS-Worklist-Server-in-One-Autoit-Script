;c:\masm32\bin\ml /c /coff /Cp pacs-server01.asm
;c:\masm32\bin\link /subsystem:console pacs-server01.obj

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

DICOM_RECV_BUF_SIZE     equ 1048576
DICOM_SEND_BUF_SIZE     equ 16384
MAX_IMAGES_PER_FOLDER   equ 16000
MAX_PRES_CONTEXTS       equ 32

FIONBIO                 equ 8004667Eh
WSAEWOULDBLOCK          equ 10035

WM_TRAYICON             equ WM_USER + 1
ID_TRAY_TOGGLE          equ 1000
ID_TRAY_SETTINGS        equ 1001
ID_TRAY_SHOW            equ 1002
ID_TRAY_EXIT            equ 1003

ID_BTN_STARTSTOP        equ 2001
ID_BTN_SAVE             equ 2002
ID_BTN_CLOSE            equ 2003
ID_EDIT_AET             equ 2010
ID_EDIT_PORT            equ 2011
ID_CHK_DEBUG            equ 2012

.data
g_DicomPort         dd 777
g_DebugLog          dd 1
g_bRunning          dd 0
g_dicomListenSock   dd INVALID_SOCKET
g_scuMaxPduLen      dd 16384

g_CurrentFolderIndex dd 0
g_CurrentFileIndex   dd 0

g_hInstance         dd 0
g_hMainWnd          dd 0
g_hSettingsWnd      dd 0
g_hMenu             dd 0
g_hLogEdit          dd 0
g_hStatusLabel      dd 0

g_aeCalled          db "PACS_SCP        ", 0
g_aeCalling         db "ANY-SCU         ", 0

szIniFile           db "pacs-server01.ini",0
szIniServer         db "Server",0
szIniStorage        db "Storage",0
szIniAET            db "AETitle",0
szIniDicomPort      db "DicomPort",0
szIniDebugLog       db "DebugLog",0
szIniLastFolder     db "LastFolderIndex",0
szIniLastFile       db "LastFileIndex",0

szDefAET            db "PACS_SCP",0
szDefDicomPort      db "777",0
szDefDebugLog       db "1",0
szDefZero           db "0",0

szWndClass          db "PACSTrayClass",0
szSettingsClass     db "PACSSettingsClass",0
szTrayTip           db "PACS SCP Storage Server",0
szMenuStart         db "Start Server",0
szMenuStop          db "Stop Server",0
szMenuSettings      db "Settings",0
szMenuShow          db "Show Console",0
szMenuExit          db "Exit",0

szMainTitle         db "PACS SCP Storage Server",0
szSettingsTitle     db "Settings",0
szLblAET            db "Server AET:",0
szLblPort           db "DICOM Port:",0
szLblDebug          db "Debug Logging:",0
szLblEnabled        db "Enabled",0
szLblStatusStop     db "Server status: Stopped",0
szLblStatusRunFmt   db "Server status: Running on port %u",0
szLblStatusFailFmt  db "Server status: Failed to bind port %u",0
szLblLog            db "Log:",0

szClsStatic         db "STATIC",0
szClsEdit           db "EDIT",0
szClsButton         db "BUTTON",0

szStartup           db "PACS SCP Storage Server starting...",13,10,0
szConfigFmt         db "Config: AET=%s DicomPort=%u DebugLog=%u Folder=%u File=%u",13,10,0
szListenFmt         db "DICOM SCP listening on port %u",13,10,0
szListenFailFmt     db "ERROR: Failed to listen on DICOM port %u",13,10,0
szClientConnFmt     db "DICOM client connected (socket %u)",13,10,0
szClientDiscFmt     db "DICOM client disconnected (socket %u)",13,10,0
szEchoLog           db "C-ECHO Request received. Replying with C-ECHO-RSP.",13,10,0
szStoreRqLog        db "C-STORE-RQ received. SOP Class=%s",13,10,0
szStoreRspLog       db "C-STORE-RSP sent.",13,10,0
szAssocAcptLog      db "A-ASSOCIATE-AC sent on socket %u (PDU len %u, %u PCs)",13,10,0
szSavedFmt          db "Image saved to: %s",13,10,0
szServerStarted     db "Server STARTED",13,10,0
szServerStopped     db "Server STOPPED",13,10,0

szLogTimeFmt        db "[%02d:%02d:%02d] %s",13,10,0
szLogFileMode       db "a",0
szLogFile           db "PACS_Server.log",0

szEchoSOPClass      db "1.2.840.10008.1.1",0
szDefaultSOPClass   db "1.2.840.10008.5.1.4.1.1.7",0
szDefaultSOPInst    db "1.2.3.4.5.6.7.8.9.0",0
szImplicitVRLE      db "1.2.840.10008.1.2",0
szExplicitVRLE      db "1.2.840.10008.1.2.1",0
szAppCtxUID         db "1.2.840.10008.3.1.1.1",0
szImplClassUID      db "1.2.276.0.7230010.3.0.3.6.4",0
szImplVersionName   db "PACS_SCP_MASM32",0

; Foldered layout: SR000000\000001.DCM
szFolderFmt         db "SR%06u",0
szStoragePathFmt    db "SR%06u\%06u.DCM",0
szUIntFmt           db "%u",0

releaseRsp          db 06h,00h,00h,00h,00h,04h,00h,00h
abortPdu            db 07h,00h,00h,00h,00h,04h,00h,00h,00h,00h

.data?
wsaData            WSADATA <>
nid                NOTIFYICONDATA <>
g_dicomRecvBuf     db DICOM_RECV_BUF_SIZE dup(?)
g_dicomSendBuf     db DICOM_SEND_BUF_SIZE dup(?)
g_assocAcBuf       db 4096 dup(?)
g_tmpPath          db 260 dup(?)
g_iniBuf           db 256 dup(?)
g_iniValBuf        db 64 dup(?)
g_logBuf           db 1024 dup(?)
g_logScratch       db 1024 dup(?)

g_currentSOPClass  db 128 dup(?)
g_currentSOPInst   db 128 dup(?)
g_pendingMsgID     dd ?
g_pendingPCID      dd ?
g_bReceivingImage  dd ?
g_hTempFile        dd ?

g_proposedPCIDs    db MAX_PRES_CONTEXTS dup(?)
g_proposedPCCount  dd ?

g_pcidToTsUid      dd MAX_PRES_CONTEXTS dup(?)

.code

; ==============================================================================
; LOGGING
; ==============================================================================
LogText PROC pText:DWORD
    LOCAL hFile:DWORD
    LOCAL sysTime:SYSTEMTIME
    LOCAL hourV:DWORD
    LOCAL minV:DWORD
    LOCAL secV:DWORD

    invoke GetLocalTime, ADDR sysTime
    movzx eax, sysTime.wHour
    mov hourV, eax
    movzx eax, sysTime.wMinute
    mov minV, eax
    movzx eax, sysTime.wSecond
    mov secV, eax

    invoke crt_sprintf, OFFSET g_logBuf, OFFSET szLogTimeFmt, hourV, minV, secV, pText
    invoke crt_printf, OFFSET g_logBuf

    invoke crt_fopen, OFFSET szLogFile, OFFSET szLogFileMode
    mov hFile, eax
    test eax, eax
    je LT_NoFile
    invoke crt_fputs, OFFSET g_logBuf, hFile
    invoke crt_fclose, hFile
LT_NoFile:
    cmp g_hLogEdit, 0
    je LT_NoEdit
    invoke SendMessage, g_hLogEdit, EM_SETSEL, -1, -1
    invoke SendMessage, g_hLogEdit, EM_REPLACESEL, FALSE, OFFSET g_logBuf
LT_NoEdit:
    ret
LogText ENDP

; ==============================================================================
; INI / CONFIG
; First-run only: write defaults if INI doesn't exist.
; Subsequent runs: only READ — never overwrite the persisted folder/file counters.
; ==============================================================================
SetAETitle PROC pDest:DWORD, pSrc:DWORD
    LOCAL nLen:DWORD
    push edi
    mov edi, pDest
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
    invoke crt_memcpy, pDest, pSrc, nLen
    ret
SetAETitle ENDP

LoadConfig PROC
    LOCAL fAttr:DWORD

    invoke GetFileAttributes, OFFSET szIniFile
    mov fAttr, eax
    cmp eax, INVALID_FILE_ATTRIBUTES
    jne LC_HaveIni

    ; First run: seed defaults
    invoke WritePrivateProfileString, OFFSET szIniServer,  OFFSET szIniAET,        OFFSET szDefAET,       OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniServer,  OFFSET szIniDicomPort,  OFFSET szDefDicomPort, OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniServer,  OFFSET szIniDebugLog,   OFFSET szDefDebugLog,  OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniStorage, OFFSET szIniLastFolder, OFFSET szDefZero,      OFFSET szIniFile
    invoke WritePrivateProfileString, OFFSET szIniStorage, OFFSET szIniLastFile,   OFFSET szDefZero,      OFFSET szIniFile

LC_HaveIni:
    invoke GetPrivateProfileString, OFFSET szIniServer, OFFSET szIniAET, OFFSET szDefAET, OFFSET g_iniBuf, 256, OFFSET szIniFile
    invoke SetAETitle, OFFSET g_aeCalled, OFFSET g_iniBuf

    invoke GetPrivateProfileInt, OFFSET szIniServer, OFFSET szIniDicomPort, 777, OFFSET szIniFile
    mov g_DicomPort, eax

    invoke GetPrivateProfileInt, OFFSET szIniServer, OFFSET szIniDebugLog, 1, OFFSET szIniFile
    mov g_DebugLog, eax

    invoke GetPrivateProfileInt, OFFSET szIniStorage, OFFSET szIniLastFolder, 0, OFFSET szIniFile
    mov g_CurrentFolderIndex, eax

    invoke GetPrivateProfileInt, OFFSET szIniStorage, OFFSET szIniLastFile, 0, OFFSET szIniFile
    mov g_CurrentFileIndex, eax
    ret
LoadConfig ENDP

SaveConfigStr PROC pKey:DWORD, pVal:DWORD
    invoke WritePrivateProfileString, OFFSET szIniServer, pKey, pVal, OFFSET szIniFile
    ret
SaveConfigStr ENDP

; ==============================================================================
; STORAGE PATH — foldered layout, rolls every MAX_IMAGES_PER_FOLDER
; Path: SR000000\000001.DCM, SR000000\000002.DCM, ... SR000001\000001.DCM, etc.
; Creates the SR folder if it doesn't already exist.
; Persists both indices to the INI on every image.
; ==============================================================================
GetNextStoragePath PROC pOut:DWORD
    LOCAL folder[64]:BYTE

    inc g_CurrentFileIndex
    mov eax, g_CurrentFileIndex
    cmp eax, MAX_IMAGES_PER_FOLDER
    jbe GNSP_NoRoll
    inc g_CurrentFolderIndex
    mov g_CurrentFileIndex, 1
GNSP_NoRoll:
    ; Persist both indices
    invoke crt_sprintf, OFFSET g_iniValBuf, OFFSET szUIntFmt, g_CurrentFolderIndex
    invoke WritePrivateProfileString, OFFSET szIniStorage, OFFSET szIniLastFolder, OFFSET g_iniValBuf, OFFSET szIniFile
    invoke crt_sprintf, OFFSET g_iniValBuf, OFFSET szUIntFmt, g_CurrentFileIndex
    invoke WritePrivateProfileString, OFFSET szIniStorage, OFFSET szIniLastFile, OFFSET g_iniValBuf, OFFSET szIniFile

    ; Build folder name and ensure it exists
    invoke crt_sprintf, ADDR folder, OFFSET szFolderFmt, g_CurrentFolderIndex
    invoke CreateDirectory, ADDR folder, NULL

    ; Build the full file path: SRxxxxxx\nnnnnn.DCM
    invoke crt_sprintf, pOut, OFFSET szStoragePathFmt, g_CurrentFolderIndex, g_CurrentFileIndex
    ret
GetNextStoragePath ENDP

; ==============================================================================
; DICOM HELPERS  (unchanged)
; ==============================================================================
ReadBE32 PROC pBuf:DWORD, offv:DWORD
    mov edx, pBuf
    add edx, offv
    movzx eax, BYTE PTR [edx+0]
    shl eax, 24
    movzx ecx, BYTE PTR [edx+1]
    shl ecx, 16
    or eax, ecx
    movzx ecx, BYTE PTR [edx+2]
    shl ecx, 8
    or eax, ecx
    movzx ecx, BYTE PTR [edx+3]
    or eax, ecx
    ret
ReadBE32 ENDP

ReadBE16 PROC pBuf:DWORD, offv:DWORD
    mov edx, pBuf
    add edx, offv
    movzx eax, BYTE PTR [edx+0]
    shl eax, 8
    movzx ecx, BYTE PTR [edx+1]
    or eax, ecx
    ret
ReadBE16 ENDP

FindCmdElement PROC USES esi pCmd:DWORD, cmdLen:DWORD, tagGE:DWORD, pValLen:DWORD
    LOCAL pos:DWORD
    mov pos, 0
FCE_Loop:
    mov eax, pos
    add eax, 8
    cmp eax, cmdLen
    ja FCE_NotFound

    mov esi, pCmd
    add esi, pos
    mov eax, DWORD PTR [esi]
    cmp eax, tagGE
    jne FCE_Next

    mov eax, DWORD PTR [esi+4]
    mov edx, pValLen
    mov DWORD PTR [edx], eax
    lea eax, [esi+8]
    ret

FCE_Next:
    mov eax, DWORD PTR [esi+4]
    add eax, 8
    add pos, eax
    jmp FCE_Loop

FCE_NotFound:
    xor eax, eax
    ret
FindCmdElement ENDP

ExtractCmdString PROC pCmd:DWORD, cmdLen:DWORD, tagGE:DWORD, pOut:DWORD, outSize:DWORD
    LOCAL pVal:DWORD
    LOCAL valLen:DWORD
    LOCAL copyLen:DWORD
    invoke FindCmdElement, pCmd, cmdLen, tagGE, ADDR valLen
    test eax, eax
    je ECS_NotFound
    mov pVal, eax

    mov eax, valLen
    mov ecx, outSize
    dec ecx
    cmp eax, ecx
    jbe ECS_OK
    mov eax, ecx
ECS_OK:
    mov copyLen, eax
    invoke crt_memcpy, pOut, pVal, copyLen
    mov edx, pOut
    mov eax, copyLen
    mov BYTE PTR [edx+eax], 0

    mov eax, copyLen
ECS_Trim:
    test eax, eax
    jz ECS_TrimDone
    dec eax
    mov dl, BYTE PTR [edx+eax]
    cmp dl, ' '
    je ECS_TrimZero
    cmp dl, 0
    jne ECS_TrimDone
ECS_TrimZero:
    mov BYTE PTR [edx+eax], 0
    jmp ECS_Trim
ECS_TrimDone:
    mov eax, 1
    ret

ECS_NotFound:
    xor eax, eax
    ret
ExtractCmdString ENDP

ExtractCmdUS PROC pCmd:DWORD, cmdLen:DWORD, tagGE:DWORD
    LOCAL pVal:DWORD
    LOCAL valLen:DWORD
    invoke FindCmdElement, pCmd, cmdLen, tagGE, ADDR valLen
    test eax, eax
    je ECU_NotFound
    mov pVal, eax
    cmp valLen, 2
    jne ECU_NotFound
    mov edx, pVal
    movzx eax, WORD PTR [edx]
    ret
ECU_NotFound:
    xor eax, eax
    ret
ExtractCmdUS ENDP

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

DICOM_BuildCommandSet PROC USES edi pOut:DWORD, sopUid:DWORD, sopLen:DWORD, cmdField:DWORD, msgID:DWORD, dsType:DWORD, status:DWORD
    LOCAL cmdLen:DWORD
    LOCAL totalCmd:DWORD
    LOCAL paddedSopLen:DWORD

    mov eax, sopLen
    test eax, 1
    jz BCS_SopEven
    inc eax
BCS_SopEven:
    mov paddedSopLen, eax

    mov edi, pOut
    add edi, 12

    mov WORD PTR [edi], 0000h
    mov WORD PTR [edi+2], 0002h
    mov eax, paddedSopLen
    mov DWORD PTR [edi+4], eax

    lea ecx, [edi+8]
    invoke crt_memcpy, ecx, sopUid, sopLen

    mov eax, sopLen
    cmp eax, paddedSopLen
    je BCS_NoPad
    mov edx, edi
    add edx, 8
    add edx, eax
    mov BYTE PTR [edx], 0
BCS_NoPad:

    add edi, 8
    add edi, paddedSopLen

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
    LOCAL sopLen:DWORD
    invoke crt_strlen, OFFSET szEchoSOPClass
    mov sopLen, eax
    invoke DICOM_BuildCommandSet, ADDR cmdBuf, OFFSET szEchoSOPClass, sopLen, 08030h, msgID, 0101h, 0000h
    mov cmdLen, eax
    invoke DICOM_SendPDV, sock, pcid, ADDR cmdBuf, cmdLen, 03h
    invoke LogText, OFFSET szEchoLog
    ret
SendCEchoRsp ENDP

SendCStoreRsp PROC sock:DWORD, pcid:DWORD, msgID:DWORD
    LOCAL cmdBuf[512]:BYTE
    LOCAL cmdLen:DWORD
    LOCAL sopLen:DWORD
    invoke crt_strlen, OFFSET g_currentSOPClass
    mov sopLen, eax
    invoke DICOM_BuildCommandSet, ADDR cmdBuf, OFFSET g_currentSOPClass, sopLen, 08001h, msgID, 0101h, 0000h
    mov cmdLen, eax
    invoke DICOM_SendPDV, sock, pcid, ADDR cmdBuf, cmdLen, 03h
    invoke LogText, OFFSET szStoreRspLog
    ret
SendCStoreRsp ENDP

; ==============================================================================
; A-ASSOCIATE-AC BUILDER HELPERS
; ==============================================================================
AppendPCAC PROC pDest:DWORD, pcid:DWORD, result:DWORD, pTsUid:DWORD
    LOCAL tsLen:DWORD
    LOCAL tsLenPad:DWORD
    LOCAL itemLen:DWORD
    LOCAL totalLen:DWORD

    mov edx, pDest
    mov BYTE PTR [edx], 21h
    mov BYTE PTR [edx+1], 00h

    mov eax, result
    cmp eax, 0
    jne APCA_Rejected

    invoke crt_strlen, pTsUid
    mov tsLen, eax
    mov ebx, eax
    test eax, 1
    jz APCA_TsEven
    inc ebx
APCA_TsEven:
    mov tsLenPad, ebx

    mov eax, tsLenPad
    add eax, 8
    mov itemLen, eax

    mov edx, pDest
    mov eax, itemLen
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], al

    mov eax, pcid
    mov BYTE PTR [edx+4], al
    mov BYTE PTR [edx+5], 0
    mov eax, result
    mov BYTE PTR [edx+6], al
    mov BYTE PTR [edx+7], 0

    mov BYTE PTR [edx+8], 40h
    mov BYTE PTR [edx+9], 00h
    mov eax, tsLenPad
    mov BYTE PTR [edx+10], 0
    mov BYTE PTR [edx+11], al

    lea ecx, [edx+12]
    invoke crt_memcpy, ecx, pTsUid, tsLen

    mov eax, tsLen
    cmp eax, tsLenPad
    je APCA_NoPad
    mov edx, pDest
    add edx, 12
    add edx, eax
    mov BYTE PTR [edx], 0
APCA_NoPad:
    mov eax, itemLen
    add eax, 4
    mov totalLen, eax
    mov eax, totalLen
    ret

APCA_Rejected:
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], 4
    mov eax, pcid
    mov BYTE PTR [edx+4], al
    mov BYTE PTR [edx+5], 0
    mov eax, result
    mov BYTE PTR [edx+6], al
    mov BYTE PTR [edx+7], 0
    mov eax, 8
    ret
AppendPCAC ENDP

AppendAppCtx PROC pDest:DWORD
    LOCAL uidLen:DWORD
    LOCAL uidLenPad:DWORD
    invoke crt_strlen, OFFSET szAppCtxUID
    mov uidLen, eax
    mov ebx, eax
    test eax, 1
    jz AAC_Even
    inc ebx
AAC_Even:
    mov uidLenPad, ebx

    mov edx, pDest
    mov BYTE PTR [edx], 10h
    mov BYTE PTR [edx+1], 00h
    mov eax, uidLenPad
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], al
    lea ecx, [edx+4]
    invoke crt_memcpy, ecx, OFFSET szAppCtxUID, uidLen

    mov eax, uidLen
    cmp eax, uidLenPad
    je AAC_NoPad
    mov edx, pDest
    add edx, 4
    add edx, eax
    mov BYTE PTR [edx], 0
AAC_NoPad:
    mov eax, uidLenPad
    add eax, 4
    ret
AppendAppCtx ENDP

AppendUserInfo PROC pDest:DWORD
    LOCAL icuLen:DWORD
    LOCAL icuLenPad:DWORD
    LOCAL vnLen:DWORD
    LOCAL vnLenPad:DWORD
    LOCAL totalInner:DWORD
    LOCAL pCur:DWORD

    invoke crt_strlen, OFFSET szImplClassUID
    mov icuLen, eax
    mov ebx, eax
    test eax, 1
    jz AUI_IcuEven
    inc ebx
AUI_IcuEven:
    mov icuLenPad, ebx

    invoke crt_strlen, OFFSET szImplVersionName
    mov vnLen, eax
    mov ebx, eax
    test eax, 1
    jz AUI_VnEven
    inc ebx
AUI_VnEven:
    mov vnLenPad, ebx

    mov eax, icuLenPad
    add eax, vnLenPad
    add eax, 16
    mov totalInner, eax

    mov edx, pDest
    mov BYTE PTR [edx], 50h
    mov BYTE PTR [edx+1], 00h
    mov eax, totalInner
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], al

    mov pCur, edx
    add pCur, 4

    mov edx, pCur
    mov BYTE PTR [edx], 51h
    mov BYTE PTR [edx+1], 00h
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], 4
    mov DWORD PTR [edx+4], 00400000h
    add pCur, 8

    mov edx, pCur
    mov BYTE PTR [edx], 52h
    mov BYTE PTR [edx+1], 00h
    mov eax, icuLenPad
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], al
    lea ecx, [edx+4]
    invoke crt_memcpy, ecx, OFFSET szImplClassUID, icuLen
    mov eax, icuLen
    cmp eax, icuLenPad
    je AUI_NoIcuPad
    mov edx, pCur
    add edx, 4
    add edx, eax
    mov BYTE PTR [edx], 0
AUI_NoIcuPad:
    mov eax, icuLenPad
    add eax, 4
    add pCur, eax

    mov edx, pCur
    mov BYTE PTR [edx], 55h
    mov BYTE PTR [edx+1], 00h
    mov eax, vnLenPad
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], al
    lea ecx, [edx+4]
    invoke crt_memcpy, ecx, OFFSET szImplVersionName, vnLen
    mov eax, vnLen
    cmp eax, vnLenPad
    je AUI_NoVnPad
    mov edx, pCur
    add edx, 4
    add edx, eax
    mov BYTE PTR [edx], 0
AUI_NoVnPad:

    mov eax, totalInner
    add eax, 4
    ret
AppendUserInfo ENDP


; ==============================================================================
; PARSE A-ASSOCIATE-RQ AND BUILD A-ASSOCIATE-AC
; ==============================================================================
ParseAndBuildAC PROC USES esi edi pRqPayload:DWORD, rqLen:DWORD, pAcOut:DWORD, pAcLen:DWORD
    LOCAL pos:DWORD
    LOCAL itemType:DWORD
    LOCAL itemLen:DWORD
    LOCAL pcid:DWORD
    LOCAL subPos:DWORD
    LOCAL subType:DWORD
    LOCAL subLen:DWORD
    LOCAL hasImplicit:DWORD
    LOCAL hasExplicit:DWORD
    LOCAL pAcCur:DWORD
    LOCAL pcCount:DWORD
    LOCAL acceptedTs:DWORD
    LOCAL acceptResult:DWORD
    LOCAL pSubData:DWORD
    LOCAL ubuf[64]:BYTE

    mov pcCount, 0
    mov g_proposedPCCount, 0

    push edi
    mov edi, OFFSET g_pcidToTsUid
    xor eax, eax
    mov ecx, MAX_PRES_CONTEXTS
    rep stosd
    pop edi

    mov eax, pAcOut
    mov pAcCur, eax

    mov edx, pAcCur
    mov BYTE PTR [edx], 02h
    mov BYTE PTR [edx+1], 00h
    mov DWORD PTR [edx+2], 0
    add pAcCur, 6

    mov edx, pAcCur
    mov BYTE PTR [edx], 0
    mov BYTE PTR [edx+1], 1
    mov BYTE PTR [edx+2], 0
    mov BYTE PTR [edx+3], 0
    add pAcCur, 4

    mov esi, pRqPayload
    add esi, 4
    mov edi, pAcCur
    mov ecx, 16
    rep movsb
    add pAcCur, 16

    mov esi, pRqPayload
    add esi, 20
    mov edi, pAcCur
    mov ecx, 16
    rep movsb

    mov esi, pRqPayload
    add esi, 20
    invoke crt_memcpy, OFFSET g_aeCalling, esi, 16
    add pAcCur, 16

    mov edi, pAcCur
    xor al, al
    mov ecx, 32
    rep stosb
    add pAcCur, 32

    invoke AppendAppCtx, pAcCur
    add pAcCur, eax

    mov pos, 68

PRB_ItemLoop:
    mov eax, pos
    add eax, 4
    cmp eax, rqLen
    ja PRB_ItemDone

    mov esi, pRqPayload
    add esi, pos
    movzx eax, BYTE PTR [esi]
    mov itemType, eax
    movzx eax, BYTE PTR [esi+2]
    shl eax, 8
    movzx ecx, BYTE PTR [esi+3]
    or eax, ecx
    mov itemLen, eax

    mov eax, pos
    add eax, 4
    add eax, itemLen
    cmp eax, rqLen
    ja PRB_ItemDone

    cmp itemType, 20h
    je PRB_PresContext
    cmp itemType, 50h
    je PRB_UserInfo
    jmp PRB_NextItem

PRB_PresContext:
    mov esi, pRqPayload
    add esi, pos
    movzx eax, BYTE PTR [esi+4]
    mov pcid, eax

    mov ebx, g_proposedPCCount
    cmp ebx, MAX_PRES_CONTEXTS
    jae PRB_SkipTrack
    mov edx, OFFSET g_proposedPCIDs
    add edx, ebx
    mov al, BYTE PTR pcid
    mov [edx], al
    inc g_proposedPCCount
PRB_SkipTrack:

    mov hasImplicit, 0
    mov hasExplicit, 0

    mov eax, pos
    add eax, 8
    mov subPos, eax

PRB_SubLoop:
    mov eax, pos
    add eax, 4
    add eax, itemLen
    cmp subPos, eax
    jae PRB_SubDone

    mov esi, pRqPayload
    add esi, subPos
    movzx eax, BYTE PTR [esi]
    mov subType, eax
    movzx eax, BYTE PTR [esi+2]
    shl eax, 8
    movzx ecx, BYTE PTR [esi+3]
    or eax, ecx
    mov subLen, eax

    lea eax, [esi+4]
    mov pSubData, eax

    cmp subType, 40h
    jne PRB_NextSub

    mov eax, subLen
    cmp eax, 17
    jne PRB_CheckExp
    invoke crt_memcpy, ADDR ubuf, pSubData, subLen
    mov eax, subLen
    mov BYTE PTR ubuf[eax], 0
    invoke crt_strcmp, ADDR ubuf, OFFSET szImplicitVRLE
    test eax, eax
    jne PRB_NextSub
    mov hasImplicit, 1
    jmp PRB_NextSub

PRB_CheckExp:
    cmp eax, 19
    jne PRB_NextSub
    invoke crt_memcpy, ADDR ubuf, pSubData, subLen
    mov eax, subLen
    mov BYTE PTR ubuf[eax], 0
    invoke crt_strcmp, ADDR ubuf, OFFSET szExplicitVRLE
    test eax, eax
    jne PRB_NextSub
    mov hasExplicit, 1

PRB_NextSub:
    mov eax, subLen
    add eax, 4
    add subPos, eax
    jmp PRB_SubLoop

PRB_SubDone:
    cmp hasImplicit, 1
    jne PRB_TryExplicit
    mov acceptedTs, OFFSET szImplicitVRLE
    mov acceptResult, 0
    jmp PRB_AppendPC

PRB_TryExplicit:
    cmp hasExplicit, 1
    jne PRB_RejectTs
    mov acceptedTs, OFFSET szExplicitVRLE
    mov acceptResult, 0
    jmp PRB_AppendPC

PRB_RejectTs:
    mov acceptedTs, 0
    mov acceptResult, 4

PRB_AppendPC:
    cmp acceptResult, 0
    jne PRB_NoTsRecord
    mov eax, pcid
    cmp eax, MAX_PRES_CONTEXTS
    jae PRB_NoTsRecord
    mov edx, OFFSET g_pcidToTsUid
    mov ecx, acceptedTs
    mov DWORD PTR [edx + eax*4], ecx
PRB_NoTsRecord:

    cmp acceptResult, 0
    jne PRB_AppendRejected
    invoke AppendPCAC, pAcCur, pcid, 0, acceptedTs
    jmp PRB_AppendDone
PRB_AppendRejected:
    invoke AppendPCAC, pAcCur, pcid, acceptResult, 0
PRB_AppendDone:
    add pAcCur, eax
    inc pcCount
    jmp PRB_NextItem

PRB_UserInfo:
    mov eax, pos
    add eax, 4
    mov subPos, eax
PRB_UiLoop:
    mov eax, pos
    add eax, 4
    add eax, itemLen
    cmp subPos, eax
    jae PRB_NextItem

    mov esi, pRqPayload
    add esi, subPos
    movzx eax, BYTE PTR [esi]
    mov subType, eax
    movzx eax, BYTE PTR [esi+2]
    shl eax, 8
    movzx ecx, BYTE PTR [esi+3]
    or eax, ecx
    mov subLen, eax

    cmp subType, 51h
    jne PRB_UiNextSub
    cmp subLen, 4
    jne PRB_UiNextSub

    mov esi, pRqPayload
    add esi, subPos
    movzx eax, BYTE PTR [esi+4]
    shl eax, 24
    movzx ecx, BYTE PTR [esi+5]
    shl ecx, 16
    or eax, ecx
    movzx ecx, BYTE PTR [esi+6]
    shl ecx, 8
    or eax, ecx
    movzx ecx, BYTE PTR [esi+7]
    or eax, ecx
    mov g_scuMaxPduLen, eax

PRB_UiNextSub:
    mov eax, subLen
    add eax, 4
    add subPos, eax
    jmp PRB_UiLoop

PRB_NextItem:
    mov eax, itemLen
    add eax, 4
    add pos, eax
    jmp PRB_ItemLoop

PRB_ItemDone:
    invoke AppendUserInfo, pAcCur
    add pAcCur, eax

    mov eax, pAcCur
    sub eax, pAcOut
    mov edx, eax
    sub edx, 6
    mov eax, pAcOut
    bswap edx
    mov DWORD PTR [eax+2], edx

    mov eax, pAcCur
    sub eax, pAcOut
    mov edx, pAcLen
    mov DWORD PTR [edx], eax

    mov eax, pcCount
    ret
ParseAndBuildAC ENDP

DICOM_SendAssociateAC PROC sock:DWORD, pRqPayload:DWORD, rqLen:DWORD
    LOCAL acLen:DWORD
    LOCAL pcCount:DWORD
    invoke ParseAndBuildAC, pRqPayload, rqLen, OFFSET g_assocAcBuf, ADDR acLen
    mov pcCount, eax
    invoke send, sock, OFFSET g_assocAcBuf, acLen, 0
    invoke crt_sprintf, OFFSET g_logScratch, OFFSET szAssocAcptLog, sock, acLen, pcCount
    invoke LogText, OFFSET g_logScratch
    ret
DICOM_SendAssociateAC ENDP

; ==============================================================================
; FILE I/O — direct raw write, no Part 10 wrap
; ==============================================================================
WriteFileBytes PROC hFile:DWORD, pBuf:DWORD, nBytes:DWORD
    LOCAL wrote:DWORD
    invoke WriteFile, hFile, pBuf, nBytes, ADDR wrote, NULL
    ret
WriteFileBytes ENDP

OpenStorageFile PROC pPath:DWORD
    invoke CreateFile, pPath, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL
    ret
OpenStorageFile ENDP

CloseStorageFile PROC
    cmp g_hTempFile, INVALID_HANDLE_VALUE
    je CSF_None
    invoke CloseHandle, g_hTempFile
    mov g_hTempFile, INVALID_HANDLE_VALUE
CSF_None:
    ret
CloseStorageFile ENDP

; ==============================================================================
; DICOM CLIENT HANDLER
; ==============================================================================
ExtractPCID PROC pBuf:DWORD, offv:DWORD
    mov edx, pBuf
    add edx, offv
    movzx eax, BYTE PTR [edx+4]
    ret
ExtractPCID ENDP

ExtractFlags PROC pBuf:DWORD, offv:DWORD
    mov edx, pBuf
    add edx, offv
    movzx eax, BYTE PTR [edx+5]
    ret
ExtractFlags ENDP

InitClientState PROC sock:DWORD
    mov g_bReceivingImage, 0
    mov g_pendingMsgID, 1
    mov g_pendingPCID, 1
    mov g_hTempFile, INVALID_HANDLE_VALUE
    mov g_scuMaxPduLen, 16384
    invoke lstrcpy, OFFSET g_currentSOPClass, OFFSET szDefaultSOPClass
    invoke lstrcpy, OFFSET g_currentSOPInst,  OFFSET szDefaultSOPInst
    ret
InitClientState ENDP

ProcessPDataPDU PROC sock:DWORD, pPayload:DWORD, pduLen:DWORD
    LOCAL pos:DWORD
    LOCAL pdvLen:DWORD
    LOCAL pcid:DWORD
    LOCAL flagsByte:DWORD
    LOCAL fragLen:DWORD
    LOCAL pFrag:DWORD
    LOCAL cmdField:DWORD
    LOCAL msgID:DWORD

    mov pos, 0

PD_Loop:
    mov eax, pos
    add eax, 6
    cmp eax, pduLen
    ja PD_Done

    invoke ReadBE32, pPayload, pos
    mov pdvLen, eax
    cmp pdvLen, 2
    jb PD_Done

    invoke ExtractPCID, pPayload, pos
    mov pcid, eax
    invoke ExtractFlags, pPayload, pos
    mov flagsByte, eax

    mov eax, pPayload
    add eax, pos
    add eax, 6
    mov pFrag, eax

    mov eax, pdvLen
    sub eax, 2
    mov fragLen, eax

    mov eax, flagsByte
    test eax, 1
    jz PD_DataPdv

    ; ====== Command PDV ======
    invoke ExtractCmdUS, pFrag, fragLen, 01000000h
    mov cmdField, eax

    invoke ExtractCmdUS, pFrag, fragLen, 01100000h
    mov msgID, eax
    test eax, eax
    jnz PD_HaveMsgId
    mov msgID, 1
PD_HaveMsgId:

    ; C-ECHO-RQ
    cmp cmdField, 0030h
    jne PD_NotEcho
    invoke SendCEchoRsp, sock, pcid, msgID
    jmp PD_NextPdv

PD_NotEcho:
    ; C-STORE-RQ
    cmp cmdField, 0001h
    jne PD_NextPdv

    invoke ExtractCmdString, pFrag, fragLen, 00020000h, OFFSET g_currentSOPClass, 128
    invoke ExtractCmdString, pFrag, fragLen, 10000000h, OFFSET g_currentSOPInst, 128

    invoke crt_sprintf, OFFSET g_logScratch, OFFSET szStoreRqLog, OFFSET g_currentSOPClass
    invoke LogText, OFFSET g_logScratch

    mov eax, msgID
    mov g_pendingMsgID, eax
    mov eax, pcid
    mov g_pendingPCID, eax
    jmp PD_NextPdv

PD_DataPdv:
    ; ====== Image data PDV ======
    cmp g_bReceivingImage, 1
    je PD_HaveFile

    ; First data fragment for this image: allocate next NNNNNN.DCM, open it
    invoke GetNextStoragePath, OFFSET g_tmpPath
    invoke OpenStorageFile, OFFSET g_tmpPath
    mov g_hTempFile, eax
    cmp eax, INVALID_HANDLE_VALUE
    je PD_NextPdv
    mov g_bReceivingImage, 1

PD_HaveFile:
    invoke WriteFileBytes, g_hTempFile, pFrag, fragLen

    mov eax, flagsByte
    test eax, 2
    jz PD_NextPdv

    ; Last data fragment: close, log, C-STORE-RSP, reset state for next image
    invoke CloseStorageFile

    invoke crt_sprintf, OFFSET g_logScratch, OFFSET szSavedFmt, OFFSET g_tmpPath
    invoke LogText, OFFSET g_logScratch

    mov g_bReceivingImage, 0
    invoke SendCStoreRsp, sock, g_pendingPCID, g_pendingMsgID

PD_NextPdv:
    mov eax, pos
    add eax, pdvLen
    add eax, 4
    mov pos, eax
    jmp PD_Loop

PD_Done:
    ret
ProcessPDataPDU ENDP

RecvExact PROC sock:DWORD, pBuf:DWORD, nBytes:DWORD
    LOCAL got:DWORD
    mov got, 0
RE_Loop:
    mov eax, got
    cmp eax, nBytes
    jae RE_Done
    mov eax, pBuf
    add eax, got
    mov ecx, nBytes
    sub ecx, got
    invoke recv, sock, eax, ecx, 0
    cmp eax, 0
    jle RE_Fail
    add got, eax
    jmp RE_Loop
RE_Done:
    mov eax, got
    ret
RE_Fail:
    mov eax, -1
    ret
RecvExact ENDP

DICOM_HandleClient PROC sock:DWORD
    LOCAL pduType:DWORD
    LOCAL pduLen:DWORD
    LOCAL pPayload:DWORD

    invoke InitClientState, sock

DH_Loop:
    invoke RecvExact, sock, OFFSET g_dicomRecvBuf, 6
    cmp eax, 6
    jne DH_End

    movzx eax, BYTE PTR [g_dicomRecvBuf]
    mov pduType, eax

    invoke ReadBE32, OFFSET g_dicomRecvBuf, 2
    mov pduLen, eax

    cmp eax, DICOM_RECV_BUF_SIZE - 6
    ja DH_End

    cmp eax, 0
    je DH_NoPayload
    mov edx, OFFSET g_dicomRecvBuf
    add edx, 6
    invoke RecvExact, sock, edx, pduLen
    cmp eax, pduLen
    jne DH_End
DH_NoPayload:

    mov eax, OFFSET g_dicomRecvBuf
    add eax, 6
    mov pPayload, eax

    cmp pduType, 01h
    jne DH_NotAssoc
    invoke DICOM_SendAssociateAC, sock, pPayload, pduLen
    jmp DH_Loop

DH_NotAssoc:
    cmp pduType, 04h
    jne DH_NotData
    invoke ProcessPDataPDU, sock, pPayload, pduLen
    jmp DH_Loop

DH_NotData:
    cmp pduType, 05h
    jne DH_Loop
    invoke send, sock, OFFSET releaseRsp, SIZEOF releaseRsp, 0
    jmp DH_End

DH_End:
    invoke CloseStorageFile
    ret
DICOM_HandleClient ENDP

; ==============================================================================
; SOCKET SERVER
; ==============================================================================
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

StartDicomServer PROC
    LOCAL sinbuf[16]:BYTE
    LOCAL msgBuf[128]:BYTE

    invoke socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
    cmp eax, INVALID_SOCKET
    jne SDS_HasSock
    invoke crt_sprintf, ADDR msgBuf, OFFSET szListenFailFmt, g_DicomPort
    invoke LogText, ADDR msgBuf
    xor eax, eax
    ret
SDS_HasSock:
    mov g_dicomListenSock, eax
    invoke RtlZeroMemory, ADDR sinbuf, 16
    lea edx, sinbuf
    mov WORD PTR [edx], AF_INET
    invoke htons, g_DicomPort
    lea edx, sinbuf
    mov WORD PTR [edx+2], ax
    mov DWORD PTR [edx+4], INADDR_ANY
    invoke bind, g_dicomListenSock, ADDR sinbuf, 16
    cmp eax, SOCKET_ERROR
    je SDS_Fail
    invoke listen, g_dicomListenSock, SOMAXCONN
    cmp eax, SOCKET_ERROR
    je SDS_Fail
    invoke SetNonBlocking, g_dicomListenSock
    invoke crt_sprintf, ADDR msgBuf, OFFSET szListenFmt, g_DicomPort
    invoke LogText, ADDR msgBuf
    cmp g_hStatusLabel, 0
    je SDS_NoStatus
    invoke crt_sprintf, ADDR msgBuf, OFFSET szLblStatusRunFmt, g_DicomPort
    invoke SetWindowText, g_hStatusLabel, ADDR msgBuf
SDS_NoStatus:
    mov eax, 1
    ret
SDS_Fail:
    invoke crt_sprintf, ADDR msgBuf, OFFSET szListenFailFmt, g_DicomPort
    invoke LogText, ADDR msgBuf
    cmp g_hStatusLabel, 0
    je SDS_NoStatus2
    invoke crt_sprintf, ADDR msgBuf, OFFSET szLblStatusFailFmt, g_DicomPort
    invoke SetWindowText, g_hStatusLabel, ADDR msgBuf
SDS_NoStatus2:
    invoke closesocket, g_dicomListenSock
    mov g_dicomListenSock, INVALID_SOCKET
    xor eax, eax
    ret
StartDicomServer ENDP

PollDicomServer PROC
    LOCAL s:DWORD
    LOCAL msgBuf[96]:BYTE
    cmp g_dicomListenSock, INVALID_SOCKET
    je PDS_Done
    invoke accept, g_dicomListenSock, NULL, NULL
    mov s, eax
    cmp eax, INVALID_SOCKET
    je PDS_Done
    invoke crt_sprintf, ADDR msgBuf, OFFSET szClientConnFmt, s
    invoke LogText, ADDR msgBuf
    invoke SetBlocking, s
    invoke DICOM_HandleClient, s
    invoke closesocket, s
    invoke crt_sprintf, ADDR msgBuf, OFFSET szClientDiscFmt, s
    invoke LogText, ADDR msgBuf
PDS_Done:
    ret
PollDicomServer ENDP

ServerStart PROC
    cmp g_bRunning, 1
    je SS_Already
    invoke StartDicomServer
    cmp eax, 1
    jne SS_Already
    mov g_bRunning, 1
    invoke LogText, OFFSET szServerStarted
    invoke ModifyMenu, g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND or MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStop
SS_Already:
    ret
ServerStart ENDP

ServerStop PROC
    cmp g_bRunning, 0
    je SS2_Done
    cmp g_dicomListenSock, INVALID_SOCKET
    je SS2_NoSock
    invoke closesocket, g_dicomListenSock
    mov g_dicomListenSock, INVALID_SOCKET
SS2_NoSock:
    mov g_bRunning, 0
    invoke LogText, OFFSET szServerStopped
    cmp g_hStatusLabel, 0
    je SS2_NoStatus
    invoke SetWindowText, g_hStatusLabel, OFFSET szLblStatusStop
SS2_NoStatus:
    invoke ModifyMenu, g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND or MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStart
SS2_Done:
    ret
ServerStop ENDP

ServerLoop PROC
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
    invoke PollDicomServer
SL_Done:
    ret
ServerLoop ENDP

; ==============================================================================
; SETTINGS DIALOG / MAIN WINDOW / TRAY / MAIN
; ==============================================================================
SettingsProc PROC hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
    LOCAL buf[64]:BYTE
    LOCAL cmd:DWORD
    LOCAL newPort:DWORD
    LOCAL newDebug:DWORD

    mov eax, uMsg
    cmp eax, WM_COMMAND
    jne SP_NotCmd

    mov eax, wParam
    and eax, 0FFFFh
    mov cmd, eax

    cmp cmd, ID_BTN_CLOSE
    jne SP_NotClose
    invoke DestroyWindow, hWnd
    mov g_hSettingsWnd, 0
    xor eax, eax
    ret

SP_NotClose:
    cmp cmd, ID_BTN_STARTSTOP
    jne SP_NotToggle
    cmp g_bRunning, 1
    je SP_Stop
    invoke ServerStart
    invoke SetDlgItemText, hWnd, ID_BTN_STARTSTOP, OFFSET szMenuStop
    xor eax, eax
    ret
SP_Stop:
    invoke ServerStop
    invoke SetDlgItemText, hWnd, ID_BTN_STARTSTOP, OFFSET szMenuStart
    xor eax, eax
    ret

SP_NotToggle:
    cmp cmd, ID_BTN_SAVE
    jne SP_NotSave

    invoke GetDlgItemText, hWnd, ID_EDIT_AET, ADDR buf, 64
    invoke SetAETitle, OFFSET g_aeCalled, ADDR buf
    invoke SaveConfigStr, OFFSET szIniAET, ADDR buf

    invoke GetDlgItemInt, hWnd, ID_EDIT_PORT, NULL, FALSE
    mov newPort, eax
    invoke crt_sprintf, ADDR buf, OFFSET szUIntFmt, newPort
    invoke SaveConfigStr, OFFSET szIniDicomPort, ADDR buf
    mov eax, newPort
    mov g_DicomPort, eax

    invoke IsDlgButtonChecked, hWnd, ID_CHK_DEBUG
    mov newDebug, eax
    mov eax, newDebug
    mov g_DebugLog, eax
    invoke crt_sprintf, ADDR buf, OFFSET szUIntFmt, newDebug
    invoke SaveConfigStr, OFFSET szIniDebugLog, ADDR buf
    xor eax, eax
    ret

SP_NotSave:
SP_NotCmd:
    cmp eax, WM_CLOSE
    jne SP_NotCloseMsg
    invoke DestroyWindow, hWnd
    mov g_hSettingsWnd, 0
    xor eax, eax
    ret
SP_NotCloseMsg:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret
SettingsProc ENDP

CreateSettingsClass PROC
    LOCAL wc:WNDCLASSEX
    invoke RtlZeroMemory, ADDR wc, SIZEOF WNDCLASSEX
    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.lpfnWndProc, OFFSET SettingsProc
    mov eax, g_hInstance
    mov wc.hInstance, eax
    invoke LoadCursor, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, COLOR_BTNFACE+1
    mov wc.lpszClassName, OFFSET szSettingsClass
    invoke RegisterClassEx, ADDR wc
    ret
CreateSettingsClass ENDP

ShowSettings PROC
    LOCAL portStr[16]:BYTE
    LOCAL h:DWORD
    LOCAL btnText:DWORD
    cmp g_hSettingsWnd, 0
    je SS3_Create
    invoke SetForegroundWindow, g_hSettingsWnd
    ret
SS3_Create:
    invoke CreateWindowEx, 0, OFFSET szSettingsClass, OFFSET szSettingsTitle,
        WS_OVERLAPPED or WS_SYSMENU or WS_CAPTION or WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 460, 200, NULL, NULL, g_hInstance, NULL
    mov h, eax
    mov g_hSettingsWnd, eax

    invoke CreateWindowEx, 0, OFFSET szClsStatic, OFFSET szLblAET,
        WS_CHILD or WS_VISIBLE, 10, 10, 100, 20, h, 0, g_hInstance, NULL
    invoke CreateWindowEx, WS_EX_CLIENTEDGE, OFFSET szClsEdit, OFFSET g_aeCalled,
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, 120, 10, 120, 22, h,
        ID_EDIT_AET, g_hInstance, NULL

    invoke CreateWindowEx, 0, OFFSET szClsStatic, OFFSET szLblPort,
        WS_CHILD or WS_VISIBLE, 260, 10, 80, 20, h, 0, g_hInstance, NULL
    invoke crt_sprintf, ADDR portStr, OFFSET szUIntFmt, g_DicomPort
    invoke CreateWindowEx, WS_EX_CLIENTEDGE, OFFSET szClsEdit, ADDR portStr,
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL or ES_NUMBER, 340, 10, 80, 22, h,
        ID_EDIT_PORT, g_hInstance, NULL

    invoke CreateWindowEx, 0, OFFSET szClsStatic, OFFSET szLblDebug,
        WS_CHILD or WS_VISIBLE, 10, 40, 100, 20, h, 0, g_hInstance, NULL
    invoke CreateWindowEx, 0, OFFSET szClsButton, OFFSET szLblEnabled,
        WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX, 120, 40, 80, 20, h,
        ID_CHK_DEBUG, g_hInstance, NULL
    cmp g_DebugLog, 0
    je SS3_NoCheck
    invoke CheckDlgButton, h, ID_CHK_DEBUG, BST_CHECKED
SS3_NoCheck:
    cmp g_bRunning, 1
    je SS3_BtnStop
    mov btnText, OFFSET szMenuStart
    jmp SS3_BtnReady
SS3_BtnStop:
    mov btnText, OFFSET szMenuStop
SS3_BtnReady:
    invoke CreateWindowEx, 0, OFFSET szClsButton, btnText,
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, 10, 100, 100, 30, h,
        ID_BTN_STARTSTOP, g_hInstance, NULL
    invoke CreateWindowEx, 0, OFFSET szClsButton, OFFSET szMenuSettings,
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, 200, 100, 100, 30, h,
        ID_BTN_SAVE, g_hInstance, NULL
    invoke CreateWindowEx, 0, OFFSET szClsButton, OFFSET szMenuExit,
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, 320, 100, 100, 30, h,
        ID_BTN_CLOSE, g_hInstance, NULL
    ret
ShowSettings ENDP

MainProc PROC hWnd:HWND, uMsg:UINT, wParam:WPARAM, lParam:LPARAM
    LOCAL pt:POINT
    LOCAL cmd:DWORD

    mov eax, uMsg
    cmp eax, WM_CREATE
    jne MP_NotCreate
    invoke CreateWindowEx, 0, OFFSET szClsStatic, OFFSET szLblStatusStop,
        WS_CHILD or WS_VISIBLE or SS_LEFT, 10, 10, 500, 20, hWnd, 0, g_hInstance, NULL
    mov g_hStatusLabel, eax
    invoke CreateWindowEx, 0, OFFSET szClsStatic, OFFSET szLblLog,
        WS_CHILD or WS_VISIBLE or SS_LEFT, 10, 60, 50, 20, hWnd, 0, g_hInstance, NULL
    invoke CreateWindowEx, WS_EX_CLIENTEDGE, OFFSET szClsEdit, NULL,
        WS_CHILD or WS_VISIBLE or WS_VSCROLL or ES_MULTILINE or ES_READONLY or ES_AUTOVSCROLL,
        10, 85, 680, 280, hWnd, 0, g_hInstance, NULL
    mov g_hLogEdit, eax
    xor eax, eax
    ret

MP_NotCreate:
    cmp eax, WM_TRAYICON
    jne MP_NotTray
    mov eax, lParam
    cmp eax, WM_RBUTTONUP
    jne MP_NotRClick
    invoke GetCursorPos, ADDR pt
    invoke SetForegroundWindow, hWnd
    invoke TrackPopupMenu, g_hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hWnd, NULL
    xor eax, eax
    ret
MP_NotRClick:
    xor eax, eax
    ret
MP_NotTray:
    cmp eax, WM_COMMAND
    jne MP_NotCmd
    mov eax, wParam
    and eax, 0FFFFh
    mov cmd, eax
    cmp cmd, ID_TRAY_TOGGLE
    jne MP_NotToggle
    cmp g_bRunning, 1
    je MP_DoStop
    invoke ServerStart
    xor eax, eax
    ret
MP_DoStop:
    invoke ServerStop
    xor eax, eax
    ret
MP_NotToggle:
    cmp cmd, ID_TRAY_SETTINGS
    jne MP_NotSettings
    invoke ShowSettings
    xor eax, eax
    ret
MP_NotSettings:
    cmp cmd, ID_TRAY_SHOW
    jne MP_NotShowConsole
    invoke ShowWindow, hWnd, SW_SHOW
    invoke SetForegroundWindow, hWnd
    xor eax, eax
    ret
MP_NotShowConsole:
    cmp cmd, ID_TRAY_EXIT
    jne MP_NotExit
    invoke ServerStop
    invoke Shell_NotifyIcon, NIM_DELETE, ADDR nid
    invoke PostQuitMessage, 0
    xor eax, eax
    ret
MP_NotExit:
    xor eax, eax
    ret
MP_NotCmd:
    cmp eax, WM_CLOSE
    jne MP_NotCloseMsg
    invoke ShowWindow, hWnd, SW_HIDE
    xor eax, eax
    ret
MP_NotCloseMsg:
    cmp eax, WM_DESTROY
    jne MP_Def
    invoke ServerStop
    invoke Shell_NotifyIcon, NIM_DELETE, ADDR nid
    invoke PostQuitMessage, 0
    xor eax, eax
    ret
MP_Def:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret
MainProc ENDP

CreateTray PROC
    LOCAL wc:WNDCLASSEX
    invoke GetModuleHandle, NULL
    mov g_hInstance, eax

    invoke RtlZeroMemory, ADDR wc, SIZEOF WNDCLASSEX
    mov wc.cbSize, SIZEOF WNDCLASSEX
    mov wc.lpfnWndProc, OFFSET MainProc
    mov eax, g_hInstance
    mov wc.hInstance, eax
    invoke LoadIcon, NULL, IDI_APPLICATION
    mov wc.hIcon, eax
    invoke LoadCursor, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, COLOR_BTNFACE+1
    mov wc.lpszClassName, OFFSET szWndClass
    invoke RegisterClassEx, ADDR wc

    invoke CreateSettingsClass

    invoke CreateWindowEx, 0, OFFSET szWndClass, OFFSET szMainTitle,
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 720, 420,
        NULL, NULL, g_hInstance, NULL
    mov g_hMainWnd, eax
    invoke ShowWindow, g_hMainWnd, SW_HIDE

    invoke CreatePopupMenu
    mov g_hMenu, eax
    cmp g_bRunning, 1
    je CT_AddStop
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStart
    jmp CT_AfterToggle
CT_AddStop:
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_TOGGLE, OFFSET szMenuStop
CT_AfterToggle:
    invoke AppendMenu, g_hMenu, MF_STRING, ID_TRAY_SETTINGS, OFFSET szMenuSettings
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

Main PROC
    LOCAL qmsg:MSG
    invoke LogText, OFFSET szStartup
    invoke LoadConfig
    invoke crt_sprintf, OFFSET g_logScratch, OFFSET szConfigFmt,
        OFFSET g_aeCalled, g_DicomPort, g_DebugLog, g_CurrentFileIndex
    invoke LogText, OFFSET g_logScratch

    invoke WSAStartup, 0202h, ADDR wsaData
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
    invoke ServerStop
    invoke WSACleanup
    ret
Main ENDP

start:
    invoke Main
    invoke ExitProcess, 0

end start