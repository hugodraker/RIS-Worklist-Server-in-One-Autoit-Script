;================================================================
; PACS-MANAGER.asm - Process Control GUI - MASM32
;
; Build:
;   \masm32\bin\ml /c /coff PACS-MANAGER.asm
;   \masm32\bin\link /SUBSYSTEM:WINDOWS PACS-MANAGER.obj
;================================================================

.386
.model flat, stdcall
option casemap:none

include \masm32\include\windows.inc
include \masm32\include\user32.inc
include \masm32\include\kernel32.inc
include \masm32\include\gdi32.inc
include \masm32\include\shell32.inc
include \masm32\include\comdlg32.inc
include \masm32\include\masm32.inc

includelib \masm32\lib\user32.lib
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\gdi32.lib
includelib \masm32\lib\shell32.lib
includelib \masm32\lib\comdlg32.lib
includelib \masm32\lib\masm32.lib

CreateToolhelp32Snapshot PROTO :DWORD, :DWORD

TH32CS_SNAPPROCESS  equ 00000002h
PROCESS_TERMINATE   equ 00000001h

MAX_ROWS          equ 16

ID_LBL_BASE       equ 2000
ID_BTNA_BASE      equ 3000
ID_BTNB_BASE      equ 4000
ID_MENU_BASE      equ 5000

IDM_ADDROW        equ 9001
IDM_EXIT          equ 9002

TIMER_ID          equ 1
TIMER_MS          equ 800

WAIT_TIMEOUT_MS   equ 3000
WAIT_POLL_MS      equ 100

GAP               equ 10
Y_TOP             equ 12
X_PAD             equ 40

MIN_COL_U         equ 24
COL_U_DEF         equ 80

BTN_H_DEF         equ 32
BTN_H_MIN         equ 24
BTN_H_MAX         equ 120

; --- COLORREF byte order is 0x00BBGGRR ---
CLR_RUN_RGB       equ 066CC66h     ; R=66 G=CC B=66  green
CLR_STOP_RGB      equ 07070E0h     ; R=E0 G=70 B=70  red   (was swapped)
CLR_NONE_RGB      equ 0F0F0F0h     ; gray

ST_NONE           equ 0
ST_RUN            equ 1
ST_STOP           equ 2

IDE_NAME0         equ 100
IDE_DESC0         equ 101
IDE_BROW0         equ 102
IDE_NAME1         equ 110
IDE_DESC1         equ 111
IDE_BROW1         equ 112
IDE_NAME2         equ 120
IDE_DESC2         equ 121
IDE_BROW2         equ 122
IDE_AUTO          equ 130
IDE_SAVE          equ 200
IDE_DEL           equ 201
IDE_CANCEL        equ 202

PENTRY32A struct
    dwSize              dd ?
    cntUsage            dd ?
    th32ProcessID       dd ?
    th32DefaultHeapID   dd ?
    th32ModuleID        dd ?
    cntThreads          dd ?
    th32ParentProcessID dd ?
    pcPriClassBase      dd ?
    dwFlags             dd ?
    szExeFile           db 260 dup(?)
PENTRY32A ends

ROW struct
    szName      db 128 dup(?)
    szProcess   db 260 dup(?)
    bAutoStart  dd ?
    szNameA     db 128 dup(?)
    szTargetA   db 260 dup(?)
    szNameB     db 128 dup(?)
    szTargetB   db 260 dup(?)
ROW ends

;================================================================
; Prototypes
;================================================================
WinMain               proto :DWORD, :DWORD, :DWORD, :DWORD
WndProc               proto :DWORD, :DWORD, :DWORD, :DWORD
EditWndProc           proto :DWORD, :DWORD, :DWORD, :DWORD

InitToolhelpProcs     proto

StrLower              proto :DWORD
StripQuotesTrim       proto :DWORD
GetExeBasename        proto :DWORD, :DWORD, :DWORD
ZeroMem               proto :DWORD, :DWORD

ResolveIniPath        proto
EnsureDefaultIni      proto
WriteOneRow           proto :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD, :DWORD
LoadRowsFromIni       proto
SaveRowsToIni         proto

IsProcessRunning      proto :DWORD
StopProcessByName     proto :DWORD
StartProcessByPath    proto :DWORD
WaitProcessState      proto :DWORD, :DWORD, :DWORD

LayoutButtons         proto
RefreshAllRows        proto
RefreshRow            proto :DWORD
AutoStartRows         proto

RebuildEditMenu       proto
BuildMainControls     proto
DestroyMainControls   proto

AddNewRow             proto
DeleteRowAt           proto :DWORD

DoBrowse              proto :DWORD, :DWORD
BuildEditControls     proto :DWORD
SaveEditFields        proto
OpenEditWindow        proto :DWORD

SaveWindowPlacement   proto

;================================================================
.data

szClassMain          db "PACSManagerWnd",0
szClassEdit          db "PACSManagerEditWnd",0
szAppTitle           db "Process Control",0

szEditTitleFmt       db "Edit Row %d",0
szEditMenuName       db "&Edit",0
szAddRowText         db "Add Row",0
szExitItemText       db "Exit",0
szEmptyItem          db "(empty)",0

szStartFmt           db "Start %s",0
szStopFmt            db "Stop  %s",0

szDescFmt            db "Desc%d",0
szDescAFmt           db "Desc%dA",0
szDescBFmt           db "Desc%dB",0
szRowSecFmt          db "Row%d",0

szKey_Name           db "Name",0
szKey_Process        db "Process",0
szKey_AutoStart      db "AutoStart",0
szKey_NameA          db "NameA",0
szKey_TargetA        db "TargetA",0
szKey_NameB          db "NameB",0
szKey_TargetB        db "TargetB",0

szOne                db "1",0
szZero               db "0",0
szEmpty              db 0

szOpen               db "open",0
szStatic             db "STATIC",0
szButton             db "BUTTON",0
szEditCls            db "EDIT",0
szDotIni             db ".ini",0

szLblName            db "Name",0
szLblDesc            db "Description",0
szLblAuto            db "Auto-Start at launch",0

szGrp0               db "Main button (Description = full path to .EXE)",0
szGrp1               db "Helper A (column 2 - launches any file)",0
szGrp2               db "Helper B (column 3 - launches any file)",0

szSave               db "Save",0
szDel                db "Delete",0
szCancel             db "Cancel",0
szBrowse             db "Browse",0

szFilter             db "All files (*.*)",0,"*.*",0,0

szKernel32Name        db "kernel32.dll",0
szProcess32FirstName  db "Process32First",0
szProcess32NextName   db "Process32Next",0
szProcess32FirstAName db "Process32FirstA",0
szProcess32NextAName  db "Process32NextA",0



; --- Window placement INI ---
szSecWindow          db "Window",0
szKeyX               db "X",0
szKeyY               db "Y",0
szKeyW               db "W",0
szKeyH               db "H",0
szKeyMax             db "Maximized",0
szIntFmt             db "%d",0

szDefR1N             db "Worklist",0
szDefR1P             db "WORKLIST-SERVER01.EXE",0
szDefR1NA            db "View Log",0
szDefR1TA            db "WORKLIST_Server.log",0
szDefR1NB            db "Edit Config",0
szDefR1TB            db "WORKLIST-SERVER01.ini",0

szDefR2N             db "PACS",0
szDefR2P             db "PACS-SERVER01.EXE",0
szDefR2NA            db "View Log",0
szDefR2TA            db "PACS_Server.log",0
szDefR2NB            db "Edit Config",0
szDefR2TB            db "PACS-SERVER01.ini",0

szDefR3N             db "Desc3",0
szDefR3NA            db "Desc3A",0
szDefR3NB            db "Desc3B",0

;================================================================
.data?

g_hInst         dd ?
g_hMain         dd ?
g_hEditWnd      dd ?
g_hEditMenu     dd ?
g_hFont         dd ?

g_nRows         dd ?
g_aRows         ROW MAX_ROWS dup(<>)
g_aRowState     db MAX_ROWS dup(?)

g_hBrushRun     dd ?
g_hBrushStop    dd ?
g_hBrushNone    dd ?

g_pProcess32First dd ?
g_pProcess32Next  dd ?

g_iniPath       db 512 dup(?)

g_sec           db 64 dup(?)
g_probe         db 32 dup(?)
g_dir           db 260 dup(?)
g_browseBuf     db 260 dup(?)
g_edTitle       db 64 dup(?)
g_base          db 260 dup(?)
g_pename        db 260 dup(?)
g_textBuf       db 256 dup(?)

g_pe            PENTRY32A <>

g_editRow       dd ?
g_aEdName       dd 3 dup(?)
g_aEdDesc       dd 3 dup(?)
g_aEdBrow       dd 3 dup(?)

g_hEdAuto       dd ?
g_hEdSave       dd ?
g_hEdDel        dd ?
g_hEdCancel     dd ?

;================================================================
.code

start:
    invoke GetModuleHandle, NULL
    mov g_hInst, eax
    invoke WinMain, eax, NULL, NULL, SW_SHOWNORMAL
    invoke ExitProcess, eax

;----------------------------------------------------------------
InitToolhelpProcs proc
    LOCAL hK32:DWORD

    mov g_pProcess32First, 0
    mov g_pProcess32Next, 0

    invoke GetModuleHandle, addr szKernel32Name
    test eax, eax
    jnz _ith_have
    invoke LoadLibrary, addr szKernel32Name
    test eax, eax
    jz _ith_done

_ith_have:
    mov hK32, eax

    ; Try the universal name first (works on all Windows versions)
    invoke GetProcAddress, hK32, addr szProcess32FirstName
    test eax, eax
    jnz _ith_first_ok

    ; Fall back to the "A" suffixed variant
    invoke GetProcAddress, hK32, addr szProcess32FirstAName

_ith_first_ok:
    mov g_pProcess32First, eax

    invoke GetProcAddress, hK32, addr szProcess32NextName
    test eax, eax
    jnz _ith_next_ok

    invoke GetProcAddress, hK32, addr szProcess32NextAName

_ith_next_ok:
    mov g_pProcess32Next, eax

_ith_done:
    ret
InitToolhelpProcs endp

;----------------------------------------------------------------
StrLower proc lpStr:DWORD
    mov edx, lpStr
_sl_lp:
    mov al, [edx]
    test al, al
    jz _sl_done
    cmp al, 'A'
    jl _sl_n
    cmp al, 'Z'
    jg _sl_n
    add al, 32
    mov [edx], al
_sl_n:
    inc edx
    jmp _sl_lp
_sl_done:
    ret
StrLower endp

StripQuotesTrim proc lpStr:DWORD
    LOCAL n:DWORD
    invoke lstrlen, lpStr
    mov n, eax
    test eax, eax
    jnz _sq_has
    ret
_sq_has:
_sq_trail:
    mov ecx, lpStr
    mov edx, n
    test edx, edx
    jz _sq_lead
    dec edx
    mov al, [ecx + edx]
    cmp al, ' '
    je _sq_clip
    cmp al, 9
    je _sq_clip
    cmp al, '"'
    je _sq_clip
    cmp al, 13
    je _sq_clip
    cmp al, 10
    je _sq_clip
    jmp _sq_lead
_sq_clip:
    mov byte ptr [ecx + edx], 0
    mov n, edx
    jmp _sq_trail
_sq_lead:
    mov ecx, lpStr
    mov al, [ecx]
    test al, al
    jz _sq_done
    cmp al, '"'
    je _sq_shift
    cmp al, ' '
    je _sq_shift
    cmp al, 9
    je _sq_shift
    jmp _sq_done
_sq_shift:
    push ecx
_sq_smv:
    mov al, [ecx + 1]
    mov [ecx], al
    test al, al
    jz _sq_smv_done
    inc ecx
    jmp _sq_smv
_sq_smv_done:
    pop ecx
    dec n
    jmp _sq_lead
_sq_done:
    ret
StripQuotesTrim endp

GetExeBasename proc uses esi edi lpIn:DWORD, lpOut:DWORD, cbOut:DWORD
    invoke lstrcpyn, addr g_base, lpIn, 260
    invoke StripQuotesTrim, addr g_base

    mov edx, offset g_base
_gb_slash:
    mov al, [edx]
    test al, al
    jz _gb_slash_done
    cmp al, '/'
    jne _gb_skip
    mov byte ptr [edx], '\'
_gb_skip:
    inc edx
    jmp _gb_slash
_gb_slash_done:

    invoke lstrlen, addr g_base
    mov esi, offset g_base
    mov edi, esi
    add edi, eax

_gb_scan:
    cmp edi, esi
    jbe _gb_copy
    dec edi
    mov al, [edi]
    cmp al, '\'
    je _gb_after
    jmp _gb_scan
_gb_after:
    inc edi
_gb_copy:
    invoke lstrcpyn, lpOut, edi, cbOut
    invoke StrLower, lpOut
    ret
GetExeBasename endp

ZeroMem proc lpDst:DWORD, n:DWORD
    push edi
    mov edi, lpDst
    mov ecx, n
    xor eax, eax
    rep stosb
    pop edi
    ret
ZeroMem endp

;----------------------------------------------------------------
ResolveIniPath proc
    LOCAL i:DWORD
    invoke GetModuleFileName, NULL, addr g_iniPath, 512
    mov i, eax
    dec i
_rip_find:
    cmp i, 0
    jl _rip_done
    lea ecx, g_iniPath
    mov edx, i
    mov al, [ecx + edx]
    cmp al, '.'
    je _rip_cut
    cmp al, '\'
    je _rip_done
    dec i
    jmp _rip_find
_rip_cut:
    lea ecx, g_iniPath
    mov edx, i
    mov byte ptr [ecx + edx], 0
_rip_done:
    invoke lstrcat, addr g_iniPath, addr szDotIni
    ret
ResolveIniPath endp

WriteOneRow proc lpSec:DWORD, lpN:DWORD, lpP:DWORD, asNum:DWORD, \
                 lpNA:DWORD, lpTA:DWORD, lpNB:DWORD, lpTB:DWORD
    invoke WritePrivateProfileString, lpSec, addr szKey_Name,    lpN, addr g_iniPath
    invoke WritePrivateProfileString, lpSec, addr szKey_Process, lpP, addr g_iniPath
    mov eax, asNum
    test eax, eax
    jz _wor_z
    invoke WritePrivateProfileString, lpSec, addr szKey_AutoStart, addr szOne, addr g_iniPath
    jmp _wor_rest
_wor_z:
    invoke WritePrivateProfileString, lpSec, addr szKey_AutoStart, addr szZero, addr g_iniPath
_wor_rest:
    invoke WritePrivateProfileString, lpSec, addr szKey_NameA,   lpNA, addr g_iniPath
    invoke WritePrivateProfileString, lpSec, addr szKey_TargetA, lpTA, addr g_iniPath
    invoke WritePrivateProfileString, lpSec, addr szKey_NameB,   lpNB, addr g_iniPath
    invoke WritePrivateProfileString, lpSec, addr szKey_TargetB, lpTB, addr g_iniPath
    ret
WriteOneRow endp

EnsureDefaultIni proc
    invoke GetFileAttributes, addr g_iniPath
    cmp eax, -1
    jne _edi_done

    invoke wsprintf, addr g_sec, addr szRowSecFmt, 1
    invoke WriteOneRow, addr g_sec, addr szDefR1N, addr szDefR1P, 1, \
        addr szDefR1NA, addr szDefR1TA, addr szDefR1NB, addr szDefR1TB

    invoke wsprintf, addr g_sec, addr szRowSecFmt, 2
    invoke WriteOneRow, addr g_sec, addr szDefR2N, addr szDefR2P, 1, \
        addr szDefR2NA, addr szDefR2TA, addr szDefR2NB, addr szDefR2TB

    invoke wsprintf, addr g_sec, addr szRowSecFmt, 3
    invoke WriteOneRow, addr g_sec, addr szDefR3N, addr szEmpty, 0, \
        addr szDefR3NA, addr szEmpty, addr szDefR3NB, addr szEmpty
_edi_done:
    ret
EnsureDefaultIni endp

LoadRowsFromIni proc uses esi edi
    LOCAL i:DWORD
    LOCAL pName:DWORD
    LOCAL pProc:DWORD
    LOCAL pNA:DWORD
    LOCAL pTA:DWORD
    LOCAL pNB:DWORD
    LOCAL pTB:DWORD
    LOCAL hasName:DWORD
    LOCAL hasProc:DWORD

    invoke ZeroMem, addr g_aRows, sizeof g_aRows
    mov g_nRows, 0
    mov i, 1

_lr_loop:
    mov eax, i
    cmp eax, MAX_ROWS
    jg _lr_pad

    invoke wsprintf, addr g_sec, addr szRowSecFmt, i

    invoke GetPrivateProfileString, addr g_sec, addr szKey_Name, addr szEmpty, \
        addr g_probe, 32, addr g_iniPath
    mov hasName, eax

    invoke GetPrivateProfileString, addr g_sec, addr szKey_Process, addr szEmpty, \
        addr g_probe, 32, addr g_iniPath
    mov hasProc, eax

    mov eax, hasName
    test eax, eax
    jnz _lr_use
    mov eax, hasProc
    test eax, eax
    jz _lr_pad

_lr_use:
    mov esi, g_nRows
    cmp esi, MAX_ROWS
    jge _lr_pad

    mov edi, esi
    imul edi, sizeof ROW
    add edi, offset g_aRows

    lea eax, [edi].ROW.szName
    mov pName, eax
    lea eax, [edi].ROW.szProcess
    mov pProc, eax
    lea eax, [edi].ROW.szNameA
    mov pNA, eax
    lea eax, [edi].ROW.szTargetA
    mov pTA, eax
    lea eax, [edi].ROW.szNameB
    mov pNB, eax
    lea eax, [edi].ROW.szTargetB
    mov pTB, eax

    invoke GetPrivateProfileString, addr g_sec, addr szKey_Name, addr szEmpty, \
        pName, 128, addr g_iniPath
    invoke GetPrivateProfileString, addr g_sec, addr szKey_Process, addr szEmpty, \
        pProc, 260, addr g_iniPath
    invoke GetPrivateProfileInt, addr g_sec, addr szKey_AutoStart, 0, addr g_iniPath
    mov [edi].ROW.bAutoStart, eax
    invoke GetPrivateProfileString, addr g_sec, addr szKey_NameA, addr szEmpty, \
        pNA, 128, addr g_iniPath
    invoke GetPrivateProfileString, addr g_sec, addr szKey_TargetA, addr szEmpty, \
        pTA, 260, addr g_iniPath
    invoke GetPrivateProfileString, addr g_sec, addr szKey_NameB, addr szEmpty, \
        pNB, 128, addr g_iniPath
    invoke GetPrivateProfileString, addr g_sec, addr szKey_TargetB, addr szEmpty, \
        pTB, 260, addr g_iniPath

    inc g_nRows
    inc i
    jmp _lr_loop

_lr_pad:
    mov eax, g_nRows
    cmp eax, 2
    jge _lr_done

    mov esi, eax
    mov edi, esi
    imul edi, sizeof ROW
    add edi, offset g_aRows

    invoke ZeroMem, edi, sizeof ROW

    lea eax, [edi].ROW.szName
    mov pName, eax
    lea eax, [edi].ROW.szNameA
    mov pNA, eax
    lea eax, [edi].ROW.szNameB
    mov pNB, eax

    mov eax, esi
    inc eax
    invoke wsprintf, pName, addr szDescFmt, eax
    mov eax, esi
    inc eax
    invoke wsprintf, pNA, addr szDescAFmt, eax
    mov eax, esi
    inc eax
    invoke wsprintf, pNB, addr szDescBFmt, eax

    mov [edi].ROW.bAutoStart, 0
    inc g_nRows
    jmp _lr_pad

_lr_done:
    ret
LoadRowsFromIni endp

SaveRowsToIni proc uses esi edi
    LOCAL i:DWORD
    LOCAL pName:DWORD
    LOCAL pProc:DWORD
    LOCAL pNA:DWORD
    LOCAL pTA:DWORD
    LOCAL pNB:DWORD
    LOCAL pTB:DWORD

    mov i, 1
_sr_del:
    mov eax, i
    cmp eax, MAX_ROWS
    jg _sr_writes
    invoke wsprintf, addr g_sec, addr szRowSecFmt, i
    invoke WritePrivateProfileString, addr g_sec, NULL, NULL, addr g_iniPath
    inc i
    jmp _sr_del

_sr_writes:
    xor esi, esi
_sr_loop:
    cmp esi, g_nRows
    jge _sr_done

    mov eax, esi
    inc eax
    invoke wsprintf, addr g_sec, addr szRowSecFmt, eax

    mov edi, esi
    imul edi, sizeof ROW
    add edi, offset g_aRows

    lea eax, [edi].ROW.szName
    mov pName, eax
    lea eax, [edi].ROW.szProcess
    mov pProc, eax
    lea eax, [edi].ROW.szNameA
    mov pNA, eax
    lea eax, [edi].ROW.szTargetA
    mov pTA, eax
    lea eax, [edi].ROW.szNameB
    mov pNB, eax
    lea eax, [edi].ROW.szTargetB
    mov pTB, eax

    mov eax, [edi].ROW.bAutoStart
    invoke WriteOneRow, addr g_sec, pName, pProc, eax, pNA, pTA, pNB, pTB

    inc esi
    jmp _sr_loop
_sr_done:
    ret
SaveRowsToIni endp

;----------------------------------------------------------------
; Save window position/size/maximized state to [Window] in INI
;----------------------------------------------------------------
SaveWindowPlacement proc
    LOCAL wp:WINDOWPLACEMENT
    LOCAL w:DWORD
    LOCAL h:DWORD

    cmp g_hMain, 0
    je _swp_done

    ; "length" is a MASM reserved word - write the first DWORD directly
    mov dword ptr [wp], sizeof WINDOWPLACEMENT

    invoke GetWindowPlacement, g_hMain, addr wp
    test eax, eax
    jz _swp_done

    ; X
    mov eax, wp.rcNormalPosition.left
    invoke wsprintf, addr g_textBuf, addr szIntFmt, eax
    invoke WritePrivateProfileString, addr szSecWindow, addr szKeyX, addr g_textBuf, addr g_iniPath

    ; Y
    mov eax, wp.rcNormalPosition.top
    invoke wsprintf, addr g_textBuf, addr szIntFmt, eax
    invoke WritePrivateProfileString, addr szSecWindow, addr szKeyY, addr g_textBuf, addr g_iniPath

    ; W = right - left
    mov eax, wp.rcNormalPosition.right
    sub eax, wp.rcNormalPosition.left
    mov w, eax
    invoke wsprintf, addr g_textBuf, addr szIntFmt, w
    invoke WritePrivateProfileString, addr szSecWindow, addr szKeyW, addr g_textBuf, addr g_iniPath

    ; H = bottom - top
    mov eax, wp.rcNormalPosition.bottom
    sub eax, wp.rcNormalPosition.top
    mov h, eax
    invoke wsprintf, addr g_textBuf, addr szIntFmt, h
    invoke WritePrivateProfileString, addr szSecWindow, addr szKeyH, addr g_textBuf, addr g_iniPath

    ; Maximized?
    mov eax, wp.showCmd
    cmp eax, SW_SHOWMAXIMIZED
    jne _swp_not_max
    invoke WritePrivateProfileString, addr szSecWindow, addr szKeyMax, addr szOne, addr g_iniPath
    jmp _swp_done
_swp_not_max:
    invoke WritePrivateProfileString, addr szSecWindow, addr szKeyMax, addr szZero, addr g_iniPath

_swp_done:
    ret
SaveWindowPlacement endp

;----------------------------------------------------------------
IsProcessRunning proc lpExeLower:DWORD
    LOCAL hSnap:DWORD

    cmp g_pProcess32First, 0
    je _ipr_no
    cmp g_pProcess32Next, 0
    je _ipr_no

    mov eax, lpExeLower
    movzx ecx, byte ptr [eax]
    test cl, cl
    jz _ipr_no

    invoke CreateToolhelp32Snapshot, TH32CS_SNAPPROCESS, 0
    cmp eax, -1
    je _ipr_no
    mov hSnap, eax

    mov g_pe.dwSize, sizeof PENTRY32A

    push offset g_pe
    push hSnap
    call dword ptr [g_pProcess32First]
    test eax, eax
    jz _ipr_close_no

_ipr_loop:
    invoke lstrcpyn, addr g_pename, addr g_pe.szExeFile, 260
    invoke StrLower, addr g_pename
    invoke lstrcmp, addr g_pename, lpExeLower
    test eax, eax
    jz _ipr_close_yes

    push offset g_pe
    push hSnap
    call dword ptr [g_pProcess32Next]
    test eax, eax
    jnz _ipr_loop

_ipr_close_no:
    invoke CloseHandle, hSnap
_ipr_no:
    xor eax, eax
    ret
_ipr_close_yes:
    invoke CloseHandle, hSnap
    mov eax, 1
    ret
IsProcessRunning endp

StopProcessByName proc lpExeLower:DWORD
    LOCAL hSnap:DWORD
    LOCAL hProc:DWORD

    cmp g_pProcess32First, 0
    je _spbn_done
    cmp g_pProcess32Next, 0
    je _spbn_done

    mov eax, lpExeLower
    movzx ecx, byte ptr [eax]
    test cl, cl
    jz _spbn_done

    invoke CreateToolhelp32Snapshot, TH32CS_SNAPPROCESS, 0
    cmp eax, -1
    je _spbn_done
    mov hSnap, eax

    mov g_pe.dwSize, sizeof PENTRY32A

    push offset g_pe
    push hSnap
    call dword ptr [g_pProcess32First]
    test eax, eax
    jz _spbn_close

_spbn_loop:
    invoke lstrcpyn, addr g_pename, addr g_pe.szExeFile, 260
    invoke StrLower, addr g_pename
    invoke lstrcmp, addr g_pename, lpExeLower
    test eax, eax
    jnz _spbn_next

    invoke OpenProcess, PROCESS_TERMINATE, FALSE, g_pe.th32ProcessID
    test eax, eax
    jz _spbn_next
    mov hProc, eax
    invoke TerminateProcess, hProc, 0
    invoke CloseHandle, hProc

_spbn_next:
    push offset g_pe
    push hSnap
    call dword ptr [g_pProcess32Next]
    test eax, eax
    jnz _spbn_loop

_spbn_close:
    invoke CloseHandle, hSnap
_spbn_done:
    ret
StopProcessByName endp

StartProcessByPath proc lpPath:DWORD
    LOCAL i:DWORD

    mov eax, lpPath
    movzx ecx, byte ptr [eax]
    test cl, cl
    jz _sp_done

    invoke lstrcpyn, addr g_dir, lpPath, 260
    invoke StripQuotesTrim, addr g_dir

    invoke GetFileAttributes, addr g_dir
    cmp eax, INVALID_FILE_ATTRIBUTES
    je _sp_done

    invoke lstrcpyn, addr g_pename, addr g_dir, 260
    invoke lstrlen, addr g_pename
    mov i, eax

_sp_find:
    cmp i, 0
    jle _sp_no_dir
    dec i
    lea ecx, g_pename
    mov edx, i
    mov al, [ecx + edx]
    cmp al, '\'
    jne _sp_find

    mov edx, i
    lea ecx, g_pename
    mov byte ptr [ecx + edx], 0

    invoke ShellExecute, g_hMain, offset szOpen, addr g_dir, NULL, addr g_pename, SW_SHOWNORMAL
    ret

_sp_no_dir:
    invoke ShellExecute, g_hMain, offset szOpen, addr g_dir, NULL, NULL, SW_SHOWNORMAL

_sp_done:
    ret
StartProcessByPath endp

WaitProcessState proc lpExe:DWORD, bAppear:DWORD, nTimeoutMs:DWORD
    LOCAL t0:DWORD
    LOCAL m:MSG
    invoke GetTickCount
    mov t0, eax
_wps_lp:
    invoke IsProcessRunning, lpExe
    mov ecx, bAppear
    test ecx, ecx
    jz _wps_want_gone
    test eax, eax
    jnz _wps_done
    jmp _wps_pump
_wps_want_gone:
    test eax, eax
    jz _wps_done
_wps_pump:
    invoke GetTickCount
    sub eax, t0
    cmp eax, nTimeoutMs
    jge _wps_done
_wps_pmsg:
    invoke PeekMessage, addr m, NULL, 0, 0, PM_REMOVE
    test eax, eax
    jz _wps_sleep
    invoke TranslateMessage, addr m
    invoke DispatchMessage, addr m
    jmp _wps_pmsg
_wps_sleep:
    invoke Sleep, WAIT_POLL_MS
    jmp _wps_lp
_wps_done:
    ret
WaitProcessState endp

;----------------------------------------------------------------
LayoutButtons proc uses ebx esi edi
    LOCAL rc:RECT
    LOCAL W:DWORD, H:DWORD
    LOCAL colU:DWORD, col1:DWORD, col2:DWORD, col3:DWORD
    LOCAL gridW:DWORD, xStart:DWORD, yStart:DWORD
    LOCAL btnH:DWORD, contentH:DWORD, usableW:DWORD, usableH:DWORD
    LOCAL hCtl:DWORD

    cmp g_hMain, 0
    je _lb_done
    cmp g_nRows, 0
    je _lb_done

    invoke GetClientRect, g_hMain, addr rc
    mov eax, rc.right
    mov W, eax
    mov eax, rc.bottom
    mov H, eax

    mov eax, W
    sub eax, GAP*4
    mov edx, MIN_COL_U*6
    cmp eax, edx
    jge _lb_uw_ok
    mov eax, edx
_lb_uw_ok:
    mov usableW, eax
    xor edx, edx
    mov ecx, 6
    div ecx
    cmp eax, MIN_COL_U
    jge _lb_cu_ok
    mov eax, MIN_COL_U
_lb_cu_ok:
    mov colU, eax

    shl eax, 2
    mov col1, eax
    mov eax, colU
    mov col2, eax
    mov col3, eax

    mov eax, col1
    add eax, col2
    add eax, col3
    add eax, GAP*2
    mov gridW, eax

    mov eax, W
    sub eax, gridW
    sar eax, 1
    cmp eax, GAP
    jge _lb_x_ok
    mov eax, GAP
_lb_x_ok:
    mov xStart, eax

    mov eax, H
    sub eax, Y_TOP + GAP
    mov ebx, g_nRows
    dec ebx
    imul ebx, GAP
    sub eax, ebx
    mov ebx, g_nRows
    imul ebx, BTN_H_MIN
    cmp eax, ebx
    jge _lb_uh_ok
    mov eax, ebx
_lb_uh_ok:
    mov usableH, eax
    xor edx, edx
    mov ecx, g_nRows
    div ecx
    cmp eax, BTN_H_MIN
    jge _lb_bmin
    mov eax, BTN_H_MIN
_lb_bmin:
    cmp eax, BTN_H_MAX
    jle _lb_bmax
    mov eax, BTN_H_MAX
_lb_bmax:
    mov btnH, eax

    mov eax, g_nRows
    imul eax, btnH
    mov ebx, g_nRows
    dec ebx
    imul ebx, GAP
    add eax, ebx
    mov contentH, eax

    mov eax, H
    sub eax, contentH
    sar eax, 1
    cmp eax, Y_TOP
    jge _lb_y_ok
    mov eax, Y_TOP
_lb_y_ok:
    mov yStart, eax

    xor esi, esi
_lb_loop:
    cmp esi, g_nRows
    jge _lb_invalidate

    mov eax, btnH
    add eax, GAP
    imul eax, esi
    add eax, yStart
    mov edi, eax

    mov eax, ID_LBL_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    mov hCtl, eax
    test eax, eax
    jz _lb_skip1
    invoke MoveWindow, hCtl, xStart, edi, col1, btnH, TRUE
_lb_skip1:

    mov ebx, xStart
    add ebx, col1
    add ebx, GAP

    mov eax, ID_BTNA_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    mov hCtl, eax
    test eax, eax
    jz _lb_skip2
    invoke MoveWindow, hCtl, ebx, edi, col2, btnH, TRUE
_lb_skip2:

    add ebx, col2
    add ebx, GAP

    mov eax, ID_BTNB_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    mov hCtl, eax
    test eax, eax
    jz _lb_skip3
    invoke MoveWindow, hCtl, ebx, edi, col3, btnH, TRUE
_lb_skip3:

    inc esi
    jmp _lb_loop

_lb_invalidate:
    invoke InvalidateRect, g_hMain, NULL, TRUE
_lb_done:
    ret
LayoutButtons endp

;----------------------------------------------------------------
RefreshRow proc uses ebx esi edi i:DWORD
    LOCAL hLbl:DWORD
    LOCAL pNameStr:DWORD
    LOCAL pProcStr:DWORD

    mov eax, i
    cmp eax, 0
    jl _rr_done
    cmp eax, g_nRows
    jge _rr_done

    mov esi, eax
    mov eax, ID_LBL_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    test eax, eax
    jz _rr_done
    mov hLbl, eax

    mov edi, esi
    imul edi, sizeof ROW
    add edi, offset g_aRows

    lea eax, [edi].ROW.szProcess
    mov pProcStr, eax
    lea eax, [edi].ROW.szName
    mov pNameStr, eax

    mov ecx, pProcStr
    movzx eax, byte ptr [ecx]
    test al, al
    jnz _rr_has

    mov byte ptr [g_aRowState + esi], ST_NONE
    invoke SetWindowText, hLbl, pNameStr
    invoke InvalidateRect, hLbl, NULL, TRUE
    invoke UpdateWindow, hLbl
    ret

_rr_has:
    invoke GetExeBasename, pProcStr, addr g_base, 260
    invoke IsProcessRunning, addr g_base
    test eax, eax
    jnz _rr_running

    mov byte ptr [g_aRowState + esi], ST_STOP
    invoke wsprintf, addr g_textBuf, addr szStartFmt, pNameStr
    invoke SetWindowText, hLbl, addr g_textBuf
    invoke InvalidateRect, hLbl, NULL, TRUE
    invoke UpdateWindow, hLbl
    ret

_rr_running:
    mov byte ptr [g_aRowState + esi], ST_RUN
    invoke wsprintf, addr g_textBuf, addr szStopFmt, pNameStr
    invoke SetWindowText, hLbl, addr g_textBuf
    invoke InvalidateRect, hLbl, NULL, TRUE
    invoke UpdateWindow, hLbl
_rr_done:
    ret
RefreshRow endp

RefreshAllRows proc uses esi
    xor esi, esi
_rar_loop:
    cmp esi, g_nRows
    jge _rar_done
    invoke RefreshRow, esi
    inc esi
    jmp _rar_loop
_rar_done:
    ret
RefreshAllRows endp

;----------------------------------------------------------------
AutoStartRows proc uses esi edi
    LOCAL pProcStr:DWORD
    xor esi, esi
_asr_loop:
    cmp esi, g_nRows
    jge _asr_done

    mov eax, esi
    imul eax, sizeof ROW
    lea edi, [g_aRows + eax]

    cmp [edi].ROW.bAutoStart, 1
    jne _asr_next

    lea eax, [edi].ROW.szProcess
    mov pProcStr, eax
    movzx ecx, byte ptr [eax]
    test cl, cl
    jz _asr_next

    invoke GetExeBasename, pProcStr, addr g_base, 260
    invoke IsProcessRunning, addr g_base
    test eax, eax
    jnz _asr_next

    invoke StartProcessByPath, pProcStr

_asr_next:
    inc esi
    jmp _asr_loop
_asr_done:
    ret
AutoStartRows endp

;----------------------------------------------------------------
RebuildEditMenu proc uses esi
    LOCAL n:DWORD
    cmp g_hEditMenu, 0
    je _rem_done

    invoke GetMenuItemCount, g_hEditMenu
    mov n, eax
_rem_wipe:
    cmp n, 0
    jle _rem_wipe_done
    dec n
    invoke DeleteMenu, g_hEditMenu, n, MF_BYPOSITION
    jmp _rem_wipe
_rem_wipe_done:

    xor esi, esi
_rem_loop:
    cmp esi, g_nRows
    jge _rem_tail

    mov eax, esi
    imul eax, sizeof ROW
    lea eax, [g_aRows + eax].ROW.szName
    movzx ecx, byte ptr [eax]
    test cl, cl
    jnz _rem_label
    mov eax, offset szEmptyItem
_rem_label:
    mov edx, ID_MENU_BASE
    add edx, esi
    invoke AppendMenu, g_hEditMenu, MF_STRING, edx, eax
    inc esi
    jmp _rem_loop

_rem_tail:
    invoke AppendMenu, g_hEditMenu, MF_SEPARATOR, 0, NULL
    invoke AppendMenu, g_hEditMenu, MF_STRING, IDM_ADDROW, offset szAddRowText
    invoke AppendMenu, g_hEditMenu, MF_SEPARATOR, 0, NULL
    invoke AppendMenu, g_hEditMenu, MF_STRING, IDM_EXIT,   offset szExitItemText
    invoke DrawMenuBar, g_hMain
_rem_done:
    ret
RebuildEditMenu endp

;----------------------------------------------------------------
BuildMainControls proc uses ebx esi edi
    LOCAL ctlId:DWORD
    LOCAL h:DWORD

    xor esi, esi
_bmc_loop:
    cmp esi, g_nRows
    jge _bmc_done

    mov eax, ID_LBL_BASE
    add eax, esi
    mov ctlId, eax
    invoke CreateWindowEx, 0, offset szStatic, NULL, \
        WS_CHILD or WS_VISIBLE or SS_NOTIFY or SS_CENTER or SS_CENTERIMAGE or SS_SUNKEN, \
        0, 0, 10, 10, g_hMain, ctlId, g_hInst, NULL
    mov h, eax
    test eax, eax
    jz _bmc_n2
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE
_bmc_n2:

    mov eax, ID_BTNA_BASE
    add eax, esi
    mov ctlId, eax
    mov edi, esi
    imul edi, sizeof ROW
    lea edi, [g_aRows + edi]
    lea ebx, [edi].ROW.szNameA
    invoke CreateWindowEx, 0, offset szButton, ebx, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        0, 0, 10, 10, g_hMain, ctlId, g_hInst, NULL
    mov h, eax
    test eax, eax
    jz _bmc_n3
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE
_bmc_n3:

    mov eax, ID_BTNB_BASE
    add eax, esi
    mov ctlId, eax
    mov edi, esi
    imul edi, sizeof ROW
    lea edi, [g_aRows + edi]
    lea ebx, [edi].ROW.szNameB
    invoke CreateWindowEx, 0, offset szButton, ebx, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        0, 0, 10, 10, g_hMain, ctlId, g_hInst, NULL
    mov h, eax
    test eax, eax
    jz _bmc_n4
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE
_bmc_n4:

    inc esi
    jmp _bmc_loop
_bmc_done:
    ret
BuildMainControls endp

DestroyMainControls proc uses esi
    LOCAL h:DWORD
    xor esi, esi
_dmc_loop:
    cmp esi, MAX_ROWS
    jge _dmc_done

    mov eax, ID_LBL_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    mov h, eax
    test eax, eax
    jz _dmc_a
    invoke DestroyWindow, h
_dmc_a:
    mov eax, ID_BTNA_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    mov h, eax
    test eax, eax
    jz _dmc_b
    invoke DestroyWindow, h
_dmc_b:
    mov eax, ID_BTNB_BASE
    add eax, esi
    invoke GetDlgItem, g_hMain, eax
    mov h, eax
    test eax, eax
    jz _dmc_next
    invoke DestroyWindow, h
_dmc_next:
    inc esi
    jmp _dmc_loop
_dmc_done:
    ret
DestroyMainControls endp

;----------------------------------------------------------------
AddNewRow proc uses edi
    LOCAL pName:DWORD
    LOCAL pNA:DWORD
    LOCAL pNB:DWORD

    mov eax, g_nRows
    cmp eax, MAX_ROWS
    jl _anr_ok
    ret
_anr_ok:
    mov edi, eax
    imul edi, sizeof ROW
    add edi, offset g_aRows
    invoke ZeroMem, edi, sizeof ROW

    lea eax, [edi].ROW.szName
    mov pName, eax
    lea eax, [edi].ROW.szNameA
    mov pNA, eax
    lea eax, [edi].ROW.szNameB
    mov pNB, eax

    mov eax, g_nRows
    inc eax
    invoke wsprintf, pName, addr szDescFmt, eax
    mov eax, g_nRows
    inc eax
    invoke wsprintf, pNA, addr szDescAFmt, eax
    mov eax, g_nRows
    inc eax
    invoke wsprintf, pNB, addr szDescBFmt, eax

    mov [edi].ROW.bAutoStart, 0
    inc g_nRows

    invoke SaveRowsToIni
    invoke DestroyMainControls
    invoke BuildMainControls
    invoke LayoutButtons
    invoke RebuildEditMenu
    invoke RefreshAllRows
    ret
AddNewRow endp

DeleteRowAt proc uses esi edi iRow:DWORD
    LOCAL src:DWORD
    LOCAL dst:DWORD

    mov eax, iRow
    cmp eax, 2
    jge _dra_ok
    ret
_dra_ok:
    mov esi, eax

_dra_loop:
    mov eax, esi
    inc eax
    cmp eax, g_nRows
    jge _dra_clear

    mov eax, esi
    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov dst, eax

    mov eax, esi
    inc eax
    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov src, eax

    push esi
    push edi
    mov esi, src
    mov edi, dst
    mov ecx, sizeof ROW
    cld
    rep movsb
    pop edi
    pop esi

    inc esi
    jmp _dra_loop

_dra_clear:
    mov eax, g_nRows
    dec eax
    imul eax, sizeof ROW
    add eax, offset g_aRows
    invoke ZeroMem, eax, sizeof ROW
    dec g_nRows

    invoke SaveRowsToIni
    invoke DestroyMainControls
    invoke BuildMainControls
    invoke LayoutButtons
    invoke RebuildEditMenu
    invoke RefreshAllRows
    ret
DeleteRowAt endp

;----------------------------------------------------------------
DoBrowse proc hParent:DWORD, hEdit:DWORD
    LOCAL ofn:OPENFILENAME
    invoke ZeroMem, addr ofn, sizeof ofn
    invoke ZeroMem, addr g_browseBuf, 260
    mov ofn.lStructSize, sizeof ofn
    mov eax, hParent
    mov ofn.hwndOwner, eax
    mov eax, offset szFilter
    mov ofn.lpstrFilter, eax
    mov eax, offset g_browseBuf
    mov ofn.lpstrFile, eax
    mov ofn.nMaxFile, 260
    mov ofn.Flags, OFN_FILEMUSTEXIST or OFN_HIDEREADONLY
    invoke GetOpenFileName, addr ofn
    test eax, eax
    jz _db_done
    invoke SetWindowText, hEdit, addr g_browseBuf
_db_done:
    ret
DoBrowse endp

BuildEditControls proc uses ebx esi edi hWnd:DWORD
    LOCAL h:DWORD
    LOCAL pName:DWORD
    LOCAL pProc:DWORD
    LOCAL pNA:DWORD
    LOCAL pTA:DWORD
    LOCAL pNB:DWORD
    LOCAL pTB:DWORD

    invoke CreateWindowEx, 0, offset szStatic, offset szGrp0, \
        WS_CHILD or WS_VISIBLE, 15, 12, 580, 16, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblName, \
        WS_CHILD or WS_VISIBLE, 15, 36, 90, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, WS_EX_CLIENTEDGE, offset szEditCls, NULL, \
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, \
        110, 34, 480, 22, hWnd, IDE_NAME0, g_hInst, NULL
    mov g_aEdName[0*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblDesc, \
        WS_CHILD or WS_VISIBLE, 15, 64, 90, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, WS_EX_CLIENTEDGE, offset szEditCls, NULL, \
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, \
        110, 62, 380, 22, hWnd, IDE_DESC0, g_hInst, NULL
    mov g_aEdDesc[0*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szButton, offset szBrowse, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        500, 60, 90, 24, hWnd, IDE_BROW0, g_hInst, NULL
    mov g_aEdBrow[0*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szGrp1, \
        WS_CHILD or WS_VISIBLE, 15, 100, 580, 16, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblName, \
        WS_CHILD or WS_VISIBLE, 15, 124, 90, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, WS_EX_CLIENTEDGE, offset szEditCls, NULL, \
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, \
        110, 122, 480, 22, hWnd, IDE_NAME1, g_hInst, NULL
    mov g_aEdName[1*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblDesc, \
        WS_CHILD or WS_VISIBLE, 15, 152, 90, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, WS_EX_CLIENTEDGE, offset szEditCls, NULL, \
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, \
        110, 150, 380, 22, hWnd, IDE_DESC1, g_hInst, NULL
    mov g_aEdDesc[1*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szButton, offset szBrowse, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        500, 148, 90, 24, hWnd, IDE_BROW1, g_hInst, NULL
    mov g_aEdBrow[1*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szGrp2, \
        WS_CHILD or WS_VISIBLE, 15, 188, 580, 16, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblName, \
        WS_CHILD or WS_VISIBLE, 15, 212, 90, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, WS_EX_CLIENTEDGE, offset szEditCls, NULL, \
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, \
        110, 210, 480, 22, hWnd, IDE_NAME2, g_hInst, NULL
    mov g_aEdName[2*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblDesc, \
        WS_CHILD or WS_VISIBLE, 15, 240, 90, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, WS_EX_CLIENTEDGE, offset szEditCls, NULL, \
        WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL, \
        110, 238, 380, 22, hWnd, IDE_DESC2, g_hInst, NULL
    mov g_aEdDesc[2*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szButton, offset szBrowse, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        500, 236, 90, 24, hWnd, IDE_BROW2, g_hInst, NULL
    mov g_aEdBrow[2*4], eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szStatic, offset szLblAuto, \
        WS_CHILD or WS_VISIBLE, 15, 276, 130, 18, hWnd, 0, g_hInst, NULL
    mov h, eax
    invoke SendMessage, h, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szButton, NULL, \
        WS_CHILD or WS_VISIBLE or BS_AUTOCHECKBOX, \
        150, 274, 20, 20, hWnd, IDE_AUTO, g_hInst, NULL
    mov g_hEdAuto, eax

    invoke CreateWindowEx, 0, offset szButton, offset szSave, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        110, 320, 90, 28, hWnd, IDE_SAVE, g_hInst, NULL
    mov g_hEdSave, eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szButton, offset szDel, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        260, 320, 90, 28, hWnd, IDE_DEL, g_hInst, NULL
    mov g_hEdDel, eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    invoke CreateWindowEx, 0, offset szButton, offset szCancel, \
        WS_CHILD or WS_VISIBLE or BS_PUSHBUTTON, \
        410, 320, 90, 28, hWnd, IDE_CANCEL, g_hInst, NULL
    mov g_hEdCancel, eax
    invoke SendMessage, eax, WM_SETFONT, g_hFont, TRUE

    mov eax, g_editRow
    cmp eax, 0
    jl _bec_done
    cmp eax, g_nRows
    jge _bec_done

    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov edi, eax

    lea eax, [edi].ROW.szName
    mov pName, eax
    lea eax, [edi].ROW.szProcess
    mov pProc, eax
    lea eax, [edi].ROW.szNameA
    mov pNA, eax
    lea eax, [edi].ROW.szTargetA
    mov pTA, eax
    lea eax, [edi].ROW.szNameB
    mov pNB, eax
    lea eax, [edi].ROW.szTargetB
    mov pTB, eax

    invoke SetWindowText, g_aEdName[0*4], pName
    invoke SetWindowText, g_aEdDesc[0*4], pProc
    invoke SetWindowText, g_aEdName[1*4], pNA
    invoke SetWindowText, g_aEdDesc[1*4], pTA
    invoke SetWindowText, g_aEdName[2*4], pNB
    invoke SetWindowText, g_aEdDesc[2*4], pTB

    cmp [edi].ROW.bAutoStart, 0
    je _bec_uncheck
    invoke SendMessage, g_hEdAuto, BM_SETCHECK, BST_CHECKED, 0
    jmp _bec_del_state
_bec_uncheck:
    invoke SendMessage, g_hEdAuto, BM_SETCHECK, BST_UNCHECKED, 0
_bec_del_state:
    cmp g_editRow, 2
    jge _bec_done
    invoke EnableWindow, g_hEdDel, FALSE
_bec_done:
    ret
BuildEditControls endp

SaveEditFields proc uses edi
    LOCAL pName:DWORD
    LOCAL pProc:DWORD
    LOCAL pNA:DWORD
    LOCAL pTA:DWORD
    LOCAL pNB:DWORD
    LOCAL pTB:DWORD

    mov eax, g_editRow
    cmp eax, 0
    jl _sef_done
    cmp eax, g_nRows
    jge _sef_done

    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov edi, eax

    lea eax, [edi].ROW.szName
    mov pName, eax
    lea eax, [edi].ROW.szProcess
    mov pProc, eax
    lea eax, [edi].ROW.szNameA
    mov pNA, eax
    lea eax, [edi].ROW.szTargetA
    mov pTA, eax
    lea eax, [edi].ROW.szNameB
    mov pNB, eax
    lea eax, [edi].ROW.szTargetB
    mov pTB, eax

    invoke GetWindowText, g_aEdName[0*4], pName, 128
    invoke GetWindowText, g_aEdDesc[0*4], pProc, 260
    invoke GetWindowText, g_aEdName[1*4], pNA,   128
    invoke GetWindowText, g_aEdDesc[1*4], pTA,   260
    invoke GetWindowText, g_aEdName[2*4], pNB,   128
    invoke GetWindowText, g_aEdDesc[2*4], pTB,   260

    invoke SendMessage, g_hEdAuto, BM_GETCHECK, 0, 0
    cmp eax, BST_CHECKED
    je _sef_on
    mov [edi].ROW.bAutoStart, 0
    jmp _sef_save
_sef_on:
    mov [edi].ROW.bAutoStart, 1
_sef_save:
    invoke SaveRowsToIni
_sef_done:
    ret
SaveEditFields endp

OpenEditWindow proc iRow:DWORD
    mov eax, iRow
    mov g_editRow, eax
    inc eax
    invoke wsprintf, addr g_edTitle, addr szEditTitleFmt, eax
    invoke EnableWindow, g_hMain, FALSE
    invoke CreateWindowEx, WS_EX_DLGMODALFRAME, offset szClassEdit, addr g_edTitle, \
        WS_CAPTION or WS_SYSMENU or WS_SIZEBOX or WS_VISIBLE or WS_POPUP, \
        CW_USEDEFAULT, CW_USEDEFAULT, 620, 410, \
        g_hMain, NULL, g_hInst, NULL
    mov g_hEditWnd, eax
    ret
OpenEditWindow endp

;================================================================
; EditWndProc
;================================================================
EditWndProc proc uses ebx esi edi hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL id:DWORD
    LOCAL row:DWORD

    mov eax, uMsg
    cmp eax, WM_CREATE
    je _ewp_create
    cmp eax, WM_COMMAND
    je _ewp_cmd
    cmp eax, WM_CLOSE
    je _ewp_close
    cmp eax, WM_DESTROY
    je _ewp_destroy

    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret

_ewp_create:
    mov eax, hWnd
    mov g_hEditWnd, eax
    invoke BuildEditControls, hWnd
    xor eax, eax
    ret

_ewp_cmd:
    mov eax, wParam
    and eax, 0FFFFh
    mov id, eax

    cmp eax, IDE_CANCEL
    je _ewp_close

    cmp eax, IDE_SAVE
    jne _ewp_n1
    invoke SaveEditFields
    invoke DestroyWindow, hWnd
    xor eax, eax
    ret
_ewp_n1:
    cmp eax, IDE_DEL
    jne _ewp_n2
    mov eax, g_editRow
    cmp eax, 2
    jl _ewp_def
    mov row, eax
    invoke DestroyWindow, hWnd
    invoke DeleteRowAt, row
    xor eax, eax
    ret
_ewp_n2:
    cmp eax, IDE_BROW0
    jne _ewp_n3
    invoke DoBrowse, hWnd, g_aEdDesc[0*4]
    xor eax, eax
    ret
_ewp_n3:
    cmp eax, IDE_BROW1
    jne _ewp_n4
    invoke DoBrowse, hWnd, g_aEdDesc[1*4]
    xor eax, eax
    ret
_ewp_n4:
    cmp eax, IDE_BROW2
    jne _ewp_def
    invoke DoBrowse, hWnd, g_aEdDesc[2*4]
    xor eax, eax
    ret
_ewp_def:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret

_ewp_close:
    invoke DestroyWindow, hWnd
    xor eax, eax
    ret

_ewp_destroy:
    invoke EnableWindow, g_hMain, TRUE
    invoke SetForegroundWindow, g_hMain
    mov g_hEditWnd, 0
    mov g_editRow, -1
    invoke RebuildEditMenu
    invoke RefreshAllRows
    xor eax, eax
    ret
EditWndProc endp

;================================================================
; WndProc
;================================================================
WndProc proc uses ebx esi edi hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    LOCAL id:DWORD
    LOCAL code:DWORD
    LOCAL idx:DWORD
    LOCAL hbar:DWORD
    LOCAL pRow:DWORD
    LOCAL pProcStr:DWORD
    LOCAL pTgtStr:DWORD
    LOCAL colorIdx:DWORD
    LOCAL stateByte:DWORD

    mov eax, uMsg
    cmp eax, WM_CREATE
    je _wp_create
    cmp eax, WM_SIZE
    je _wp_size
    cmp eax, WM_TIMER
    je _wp_timer
    cmp eax, WM_CTLCOLORSTATIC
    je _wp_color
    cmp eax, WM_COMMAND
    je _wp_command
    cmp eax, WM_DESTROY
    je _wp_destroy
    cmp eax, WM_CLOSE
    je _wp_close

    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret

_wp_create:
    mov eax, hWnd
    mov g_hMain, eax
    invoke CreateMenu
    mov hbar, eax
    invoke CreatePopupMenu
    mov g_hEditMenu, eax
    invoke AppendMenu, hbar, MF_POPUP, g_hEditMenu, offset szEditMenuName
    invoke SetMenu, hWnd, hbar
    invoke RebuildEditMenu
    invoke BuildMainControls
    invoke LayoutButtons
    invoke RefreshAllRows
    invoke SetTimer, hWnd, TIMER_ID, TIMER_MS, NULL
    xor eax, eax
    ret

_wp_size:
    invoke LayoutButtons
    xor eax, eax
    ret

_wp_timer:
    mov eax, wParam
    cmp eax, TIMER_ID
    jne _wp_timer_done
    invoke RefreshAllRows
_wp_timer_done:
    xor eax, eax
    ret

_wp_color:
    invoke GetDlgCtrlID, lParam
    sub eax, ID_LBL_BASE
    js _wp_color_def
    cmp eax, g_nRows
    jge _wp_color_def

    mov colorIdx, eax

    invoke SetBkMode, wParam, TRANSPARENT

    mov eax, colorIdx
    movzx eax, byte ptr [g_aRowState + eax]
    mov stateByte, eax

    cmp stateByte, ST_RUN
    je _wp_color_run
    cmp stateByte, ST_STOP
    je _wp_color_stop

    mov eax, g_hBrushNone
    ret
_wp_color_run:
    mov eax, g_hBrushRun
    ret
_wp_color_stop:
    mov eax, g_hBrushStop
    ret
_wp_color_def:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret

_wp_command:
    mov eax, wParam
    and eax, 0FFFFh
    mov id, eax

    mov eax, wParam
    shr eax, 16
    mov code, eax

    mov eax, id
    cmp eax, IDM_EXIT
    jne _wp_n_exit
    invoke DestroyWindow, hWnd
    xor eax, eax
    ret

_wp_n_exit:
    cmp eax, IDM_ADDROW
    jne _wp_n_add
    invoke AddNewRow
    xor eax, eax
    ret

_wp_n_add:
    mov edx, id
    sub edx, ID_MENU_BASE
    js _wp_n_menu
    cmp edx, g_nRows
    jge _wp_n_menu
    mov idx, edx
    invoke OpenEditWindow, idx
    xor eax, eax
    ret

_wp_n_menu:
    mov eax, code
    cmp eax, STN_CLICKED
    jne _wp_check_a

    mov edx, id
    sub edx, ID_LBL_BASE
    js _wp_check_a
    cmp edx, g_nRows
    jge _wp_check_a
    mov idx, edx

    mov eax, idx
    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov pRow, eax

    mov eax, pRow
    add eax, ROW.szProcess
    mov pProcStr, eax

    mov ecx, pProcStr
    movzx eax, byte ptr [ecx]
    test al, al
    jz _wp_lbl_refresh

    invoke GetExeBasename, pProcStr, addr g_base, 260

    invoke IsProcessRunning, addr g_base
    test eax, eax
    jz _wp_lbl_start

    invoke StopProcessByName, addr g_base
    invoke WaitProcessState, addr g_base, 0, WAIT_TIMEOUT_MS
    jmp _wp_lbl_refresh

_wp_lbl_start:
    invoke StartProcessByPath, pProcStr
    invoke WaitProcessState, addr g_base, 1, WAIT_TIMEOUT_MS

_wp_lbl_refresh:
    invoke RefreshRow, idx
    xor eax, eax
    ret

_wp_check_a:
    mov edx, id
    sub edx, ID_BTNA_BASE
    js _wp_check_b
    cmp edx, g_nRows
    jge _wp_check_b
    mov idx, edx

    mov eax, idx
    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov pRow, eax

    mov eax, pRow
    add eax, ROW.szTargetA
    mov pTgtStr, eax

    mov ecx, pTgtStr
    movzx eax, byte ptr [ecx]
    test al, al
    jz _wp_cmd_def

    invoke ShellExecute, hWnd, offset szOpen, pTgtStr, NULL, NULL, SW_SHOW
    xor eax, eax
    ret

_wp_check_b:
    mov edx, id
    sub edx, ID_BTNB_BASE
    js _wp_cmd_def
    cmp edx, g_nRows
    jge _wp_cmd_def
    mov idx, edx

    mov eax, idx
    imul eax, sizeof ROW
    add eax, offset g_aRows
    mov pRow, eax

    mov eax, pRow
    add eax, ROW.szTargetB
    mov pTgtStr, eax

    mov ecx, pTgtStr
    movzx eax, byte ptr [ecx]
    test al, al
    jz _wp_cmd_def

    invoke ShellExecute, hWnd, offset szOpen, pTgtStr, NULL, NULL, SW_SHOW
    xor eax, eax
    ret

_wp_cmd_def:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret

_wp_close:
    invoke SaveWindowPlacement
    invoke DestroyWindow, hWnd
    xor eax, eax
    ret

_wp_destroy:
    invoke SaveWindowPlacement
    invoke KillTimer, hWnd, TIMER_ID
    invoke PostQuitMessage, 0
    xor eax, eax
    ret
WndProc endp

;================================================================
; WinMain
;================================================================
WinMain proc hInst:DWORD, hPrev:DWORD, lpCmd:DWORD, nShow:DWORD
    LOCAL wc:WNDCLASSEX
    LOCAL we:WNDCLASSEX
    LOCAL msg:MSG
    LOCAL winW:DWORD
    LOCAL winH:DWORD
    LOCAL winX:DWORD
    LOCAL winY:DWORD
    LOCAL bMax:DWORD
    LOCAL defW:DWORD
    LOCAL defH:DWORD

    invoke CreateSolidBrush, CLR_RUN_RGB
    mov g_hBrushRun, eax
    invoke CreateSolidBrush, CLR_STOP_RGB
    mov g_hBrushStop, eax
    invoke CreateSolidBrush, CLR_NONE_RGB
    mov g_hBrushNone, eax

    invoke GetStockObject, DEFAULT_GUI_FONT
    mov g_hFont, eax

    mov g_editRow, -1

    invoke InitToolhelpProcs

    mov wc.cbSize, sizeof WNDCLASSEX
    mov wc.style, CS_HREDRAW or CS_VREDRAW
    mov wc.lpfnWndProc, offset WndProc
    mov wc.cbClsExtra, 0
    mov wc.cbWndExtra, 0
    mov eax, hInst
    mov wc.hInstance, eax
    invoke LoadIcon, NULL, IDI_APPLICATION
    mov wc.hIcon, eax
    mov wc.hIconSm, eax
    invoke LoadCursor, NULL, IDC_ARROW
    mov wc.hCursor, eax
    mov wc.hbrBackground, COLOR_BTNFACE + 1
    mov wc.lpszMenuName, NULL
    mov wc.lpszClassName, offset szClassMain
    invoke RegisterClassEx, addr wc

    mov we.cbSize, sizeof WNDCLASSEX
    mov we.style, CS_HREDRAW or CS_VREDRAW
    mov we.lpfnWndProc, offset EditWndProc
    mov we.cbClsExtra, 0
    mov we.cbWndExtra, 0
    mov eax, hInst
    mov we.hInstance, eax
    invoke LoadIcon, NULL, IDI_APPLICATION
    mov we.hIcon, eax
    mov we.hIconSm, eax
    invoke LoadCursor, NULL, IDC_ARROW
    mov we.hCursor, eax
    mov we.hbrBackground, COLOR_BTNFACE + 1
    mov we.lpszMenuName, NULL
    mov we.lpszClassName, offset szClassEdit
    invoke RegisterClassEx, addr we

    invoke ResolveIniPath
    invoke EnsureDefaultIni
    invoke LoadRowsFromIni

    ; Compute default size
    mov eax, COL_U_DEF * 6 + GAP * 2 + X_PAD * 2
    mov defW, eax

    mov eax, g_nRows
    imul eax, BTN_H_DEF + GAP
    add eax, Y_TOP + GAP + 60
    mov defH, eax

    ; Load saved window placement from [Window]
    invoke GetPrivateProfileInt, addr szSecWindow, addr szKeyX, CW_USEDEFAULT, addr g_iniPath
    mov winX, eax
    invoke GetPrivateProfileInt, addr szSecWindow, addr szKeyY, CW_USEDEFAULT, addr g_iniPath
    mov winY, eax
    invoke GetPrivateProfileInt, addr szSecWindow, addr szKeyW, defW, addr g_iniPath
    mov winW, eax
    invoke GetPrivateProfileInt, addr szSecWindow, addr szKeyH, defH, addr g_iniPath
    mov winH, eax
    invoke GetPrivateProfileInt, addr szSecWindow, addr szKeyMax, 0, addr g_iniPath
    mov bMax, eax

    invoke CreateWindowEx, 0, offset szClassMain, offset szAppTitle, \
        WS_OVERLAPPEDWINDOW, winX, winY, winW, winH, \
        NULL, NULL, hInst, NULL
    mov g_hMain, eax

    ; Show maximized if requested, else use the supplied nShow
    mov eax, bMax
    test eax, eax
    jz _wm_show_normal
    invoke ShowWindow, g_hMain, SW_SHOWMAXIMIZED
    jmp _wm_show_done
_wm_show_normal:
    invoke ShowWindow, g_hMain, nShow
_wm_show_done:
    invoke UpdateWindow, g_hMain

    invoke AutoStartRows

_wmlp:
    invoke GetMessage, addr msg, NULL, 0, 0
    test eax, eax
    jz _wmdone
    invoke TranslateMessage, addr msg
    invoke DispatchMessage, addr msg
    jmp _wmlp

_wmdone:
    mov eax, msg.wParam
    ret
WinMain endp

end start
