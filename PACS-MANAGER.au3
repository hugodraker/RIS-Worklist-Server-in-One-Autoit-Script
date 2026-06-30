#NoTrayIcon
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <EditConstants.au3>
#include <ButtonConstants.au3>
#include <WinAPITheme.au3>
#include <Misc.au3>

Opt("MustDeclareVars", 1)
Opt("GUIResizeMode", $GUI_DOCKALL)

; ---------------- Layout constants (initial / minimums) ----------------
Global Const $BTN_H_MIN = 24
Global Const $BTN_H_MAX = 120
Global Const $BTN_H_DEF = 32                ; default startup row height
Global Const $GAP       = 10
Global Const $COL_U     = 80                ; default column unit (used only for initial window size)
Global Const $COL1_W    = $COL_U * 4
Global Const $COL2_W    = $COL_U
Global Const $COL3_W    = $COL_U
Global Const $Y_TOP     = 12
Global Const $X_PAD     = 40
Global Const $GRID_W    = $COL1_W + $GAP + $COL2_W + $GAP + $COL3_W
Global Const $MIN_COL_U = 24                ; smallest allowed column unit when shrinking
Global Const $CLR_RUN   = 0x66CC66
Global Const $CLR_STOP  = 0xE07070
Global Const $CLR_NONE  = 0xF0F0F0

; ---------------- Win32 constants ----------------
Global Const $TH32CS_SNAPPROCESS = 0x00000002
Global Const $PROCESS_TERMINATE  = 0x0001

Global Const $WAIT_START_MS = 3000
Global Const $WAIT_STOP_MS  = 3000
Global Const $WAIT_POLL_MS  = 100

; ---------------- Globals ----------------
Global $g_sIni = @ScriptDir & "\" & StringRegExpReplace(@ScriptName, "\.[^.]+$", "") & ".ini"
Global $g_aRows[0][7]
Global $g_aBtnMain[0], $g_aBtnA[0], $g_aBtnB[0]
Global $g_idEditMenu
Global $g_aMenuItems[0][2]
Global $g_idAddRow = 0, $g_idExit = 0
Global $g_hMain
Global $g_iLastW = -1, $g_iLastH = -1

EnsureDefaultIni()
LoadRowsFromIni()
BuildMainGui()
AutoStartRows()

Local $tmr = TimerInit()
While 1
    Local $msg = GUIGetMsg()
    If $msg = $GUI_EVENT_CLOSE Then ExitLoop
    HandleMsg($msg)

    Local $aCS = WinGetClientSize($g_hMain)
    If Not @error And UBound($aCS) >= 2 Then
        If $aCS[0] <> $g_iLastW Or $aCS[1] <> $g_iLastH Then
            $g_iLastW = $aCS[0]
            $g_iLastH = $aCS[1]
            LayoutButtons()
        EndIf
    EndIf

    If TimerDiff($tmr) > 800 Then
        UpdateRowVisualState()
        $tmr = TimerInit()
    EndIf
    Sleep(30)
WEnd
Exit

; ====================================================================
;                            PATH HELPERS
; ====================================================================
Func GetExeBasename($sPath)
    If $sPath = "" Then Return ""
    Local $s = StringStripWS($sPath, 3)
    If StringLeft($s, 1) = '"' And StringRight($s, 1) = '"' And StringLen($s) >= 2 Then _
            $s = StringMid($s, 2, StringLen($s) - 2)
    $s = StringReplace($s, "/", "\")
    Local $iPos = StringInStr($s, "\", 0, -1)
    If $iPos > 0 Then $s = StringMid($s, $iPos + 1)
    Return $s
EndFunc

; ====================================================================
;                              INI I/O
; ====================================================================
Func EnsureDefaultIni()
    If FileExists($g_sIni) Then Return
    WriteDefaultRow("Row1", "Worklist", "WORKLIST-SERVER01.EXE", "1", _
            "View Log",    "WORKLIST_Server.log", _
            "Edit Config", "WORKLIST-SERVER01.ini")
    WriteDefaultRow("Row2", "PACS", "PACS-SERVER01.EXE", "1", _
            "View Log",    "PACS_Server.log", _
            "Edit Config", "PACS-SERVER01.ini")
    WriteDefaultRow("Row3", "Desc3", "", "0", "Desc3A", "", "Desc3B", "")
EndFunc

Func WriteDefaultRow($sec, $n, $p, $as, $na, $ta, $nb, $tb)
    IniWrite($g_sIni, $sec, "Name",      $n)
    IniWrite($g_sIni, $sec, "Process",   $p)
    IniWrite($g_sIni, $sec, "AutoStart", $as)
    IniWrite($g_sIni, $sec, "NameA",     $na)
    IniWrite($g_sIni, $sec, "TargetA",   $ta)
    IniWrite($g_sIni, $sec, "NameB",     $nb)
    IniWrite($g_sIni, $sec, "TargetB",   $tb)
EndFunc

Func LoadRowsFromIni()
    ReDim $g_aRows[0][7]
    Local $aSec = IniReadSectionNames($g_sIni)
    If @error Then Return

    Local $aPairs[0][2]
    For $i = 1 To $aSec[0]
        If StringRegExp($aSec[$i], "^(?i)Row\d+$") Then
            Local $num = Number(StringRegExpReplace($aSec[$i], "(?i)^Row", ""))
            Local $n = UBound($aPairs)
            ReDim $aPairs[$n + 1][2]
            $aPairs[$n][0] = $num
            $aPairs[$n][1] = $aSec[$i]
        EndIf
    Next

    Local $cnt = UBound($aPairs)
    For $i = 0 To $cnt - 2
        For $j = $i + 1 To $cnt - 1
            If $aPairs[$j][0] < $aPairs[$i][0] Then
                Local $a = $aPairs[$i][0], $b = $aPairs[$i][1]
                $aPairs[$i][0] = $aPairs[$j][0]
                $aPairs[$i][1] = $aPairs[$j][1]
                $aPairs[$j][0] = $a
                $aPairs[$j][1] = $b
            EndIf
        Next
    Next

    For $i = 0 To $cnt - 1
        Local $s = $aPairs[$i][1]
        Local $n = UBound($g_aRows)
        ReDim $g_aRows[$n + 1][7]
        $g_aRows[$n][0] = IniRead($g_sIni, $s, "Name",      "")
        $g_aRows[$n][1] = StringStripWS(IniRead($g_sIni, $s, "Process", ""), 3)
        $g_aRows[$n][2] = IniRead($g_sIni, $s, "AutoStart", "0")
        $g_aRows[$n][3] = IniRead($g_sIni, $s, "NameA",     "")
        $g_aRows[$n][4] = IniRead($g_sIni, $s, "TargetA",   "")
        $g_aRows[$n][5] = IniRead($g_sIni, $s, "NameB",     "")
        $g_aRows[$n][6] = IniRead($g_sIni, $s, "TargetB",   "")
    Next

    While UBound($g_aRows) < 2
        Local $m = UBound($g_aRows)
        ReDim $g_aRows[$m + 1][7]
        $g_aRows[$m][0] = "Desc" & ($m + 1)
        $g_aRows[$m][1] = ""
        $g_aRows[$m][2] = "0"
        $g_aRows[$m][3] = "Desc" & ($m + 1) & "A"
        $g_aRows[$m][4] = ""
        $g_aRows[$m][5] = "Desc" & ($m + 1) & "B"
        $g_aRows[$m][6] = ""
    WEnd
EndFunc

Func SaveRowsToIni()
    Local $aSec = IniReadSectionNames($g_sIni)
    If Not @error Then
        For $i = 1 To $aSec[0]
            If StringRegExp($aSec[$i], "^(?i)Row\d+$") Then IniDelete($g_sIni, $aSec[$i])
        Next
    EndIf
    For $i = 0 To UBound($g_aRows) - 1
        Local $s = "Row" & ($i + 1)
        IniWrite($g_sIni, $s, "Name",      $g_aRows[$i][0])
        IniWrite($g_sIni, $s, "Process",   StringStripWS($g_aRows[$i][1], 3))
        IniWrite($g_sIni, $s, "AutoStart", $g_aRows[$i][2])
        IniWrite($g_sIni, $s, "NameA",     $g_aRows[$i][3])
        IniWrite($g_sIni, $s, "TargetA",   $g_aRows[$i][4])
        IniWrite($g_sIni, $s, "NameB",     $g_aRows[$i][5])
        IniWrite($g_sIni, $s, "TargetB",   $g_aRows[$i][6])
    Next
EndFunc

; ====================================================================
;                              MAIN GUI
; ====================================================================
Func BuildMainGui()
    ReDim $g_aMenuItems[0][2]
    $g_idAddRow = 0
    $g_idExit   = 0

    Local $rows = UBound($g_aRows)
    Local $winW = $GRID_W + $X_PAD * 2
    Local $winH = $Y_TOP + $rows * ($BTN_H_DEF + $GAP) + $GAP + 30

    $g_hMain = GUICreate("Process Control", $winW, $winH, -1, -1, _
            BitOR($GUI_SS_DEFAULT_GUI, $WS_SIZEBOX, $WS_MAXIMIZEBOX))

    $g_idEditMenu = GUICtrlCreateMenu("&Edit")
    RebuildEditMenu()

    ReDim $g_aBtnMain[$rows]
    ReDim $g_aBtnA[$rows]
    ReDim $g_aBtnB[$rows]

    For $i = 0 To $rows - 1
        $g_aBtnMain[$i] = GUICtrlCreateLabel(MainBtnLabel($i), 0, 0, 10, 10, _
                BitOR($SS_NOTIFY, $SS_CENTER, $SS_CENTERIMAGE, $SS_SUNKEN))
        GUICtrlSetFont($g_aBtnMain[$i], 9, 600)
        $g_aBtnA[$i] = GUICtrlCreateButton($g_aRows[$i][3], 0, 0, 10, 10)
        $g_aBtnB[$i] = GUICtrlCreateButton($g_aRows[$i][5], 0, 0, 10, 10)
    Next

    LayoutButtons()
    UpdateRowVisualState()
    GUISetState(@SW_SHOW, $g_hMain)

    Local $aCS = WinGetClientSize($g_hMain)
    If Not @error And UBound($aCS) >= 2 Then
        $g_iLastW = $aCS[0]
        $g_iLastH = $aCS[1]
    EndIf
EndFunc

Func RebuildMainGui()
    GUIDelete($g_hMain)
    BuildMainGui()
EndFunc

Func RebuildEditMenu()
    ReDim $g_aMenuItems[0][2]
    For $i = 0 To UBound($g_aRows) - 1
        Local $sLabel = ($g_aRows[$i][0] = "") ? "(empty)" : $g_aRows[$i][0]
        Local $id = GUICtrlCreateMenuItem($sLabel, $g_idEditMenu)
        Local $n = UBound($g_aMenuItems)
        ReDim $g_aMenuItems[$n + 1][2]
        $g_aMenuItems[$n][0] = $id
        $g_aMenuItems[$n][1] = $i
    Next
    GUICtrlCreateMenuItem("", $g_idEditMenu)
    $g_idAddRow = GUICtrlCreateMenuItem("Add Row", $g_idEditMenu)
    GUICtrlCreateMenuItem("", $g_idEditMenu)
    $g_idExit = GUICtrlCreateMenuItem("Exit", $g_idEditMenu)
EndFunc

; ----- Fully responsive layout: column widths follow window width
;       (4:1:1 ratio preserved) and row height follows window height -----
Func LayoutButtons()
    Local $aCS = WinGetClientSize($g_hMain)
    If @error Or UBound($aCS) < 2 Then Return
    Local $W = $aCS[0]
    Local $H = $aCS[1]

    Local $rows = UBound($g_aBtnMain)
    If $rows = 0 Then Return

    ; ---- Horizontal scaling: keep 4:1:1 (= 6 units) ----
    Local $sideMargin = $GAP
    Local $usableW = $W - 2 * $sideMargin - 2 * $GAP    ; 2 inter-column gaps
    If $usableW < 6 * $MIN_COL_U Then $usableW = 6 * $MIN_COL_U
    Local $colU = Int($usableW / 6)
    If $colU < $MIN_COL_U Then $colU = $MIN_COL_U
    Local $col1W = $colU * 4
    Local $col2W = $colU
    Local $col3W = $colU
    Local $gridW = $col1W + $col2W + $col3W + 2 * $GAP

    ; Center the grid horizontally (handles both shrunk and oversized windows)
    Local $xStart = Int(($W - $gridW) / 2)
    If $xStart < $sideMargin Then $xStart = $sideMargin

    ; ---- Vertical scaling: rows share the available height ----
    Local $topMargin = $Y_TOP
    Local $botMargin = $GAP
    Local $usableH = $H - $topMargin - $botMargin - ($rows - 1) * $GAP
    If $usableH < $rows * $BTN_H_MIN Then $usableH = $rows * $BTN_H_MIN
    Local $btnH = Int($usableH / $rows)
    If $btnH < $BTN_H_MIN Then $btnH = $BTN_H_MIN
    If $btnH > $BTN_H_MAX Then $btnH = $BTN_H_MAX

    Local $contentH = $rows * $btnH + ($rows - 1) * $GAP
    Local $yStart = $topMargin
    If $H > $contentH + $topMargin + $botMargin Then
        $yStart = Int(($H - $contentH) / 2)
    EndIf
    If $yStart < $topMargin Then $yStart = $topMargin

    For $i = 0 To $rows - 1
        Local $y  = $yStart + $i * ($btnH + $GAP)
        Local $x1 = $xStart
        Local $x2 = $x1 + $col1W + $GAP
        Local $x3 = $x2 + $col2W + $GAP
        GUICtrlSetPos($g_aBtnMain[$i], $x1, $y, $col1W, $btnH)
        GUICtrlSetPos($g_aBtnA[$i],    $x2, $y, $col2W, $btnH)
        GUICtrlSetPos($g_aBtnB[$i],    $x3, $y, $col3W, $btnH)
    Next
EndFunc

Func MainBtnLabel($i, $bRunning = Default)
    Local $proc = $g_aRows[$i][1]
    Local $name = $g_aRows[$i][0]
    If $proc = "" Then Return $name
    If $bRunning = Default Then $bRunning = IsProcessRunningByName(GetExeBasename($proc))
    Return ($bRunning ? "Stop  " : "Start ") & $name
EndFunc

Func UpdateRowVisualState()
    Local $aRunning = GetRunningProcessNames()
    For $i = 0 To UBound($g_aRows) - 1
        If $i > UBound($g_aBtnMain) - 1 Then ExitLoop
        Local $proc = $g_aRows[$i][1]
        If $proc = "" Then
            GUICtrlSetData($g_aBtnMain[$i], $g_aRows[$i][0])
            GUICtrlSetBkColor($g_aBtnMain[$i], $CLR_NONE)
        Else
            Local $sExe = GetExeBasename($proc)
            Local $bRun = ProcessNameInList($sExe, $aRunning)
            GUICtrlSetData($g_aBtnMain[$i], MainBtnLabel($i, $bRun))
            GUICtrlSetBkColor($g_aBtnMain[$i], $bRun ? $CLR_RUN : $CLR_STOP)
        EndIf
    Next
EndFunc

Func RefreshRow($i)
    If $i < 0 Or $i > UBound($g_aBtnMain) - 1 Then Return
    Local $proc = $g_aRows[$i][1]
    If $proc = "" Then
        GUICtrlSetData($g_aBtnMain[$i], $g_aRows[$i][0])
        GUICtrlSetBkColor($g_aBtnMain[$i], $CLR_NONE)
        Return
    EndIf
    Local $sExe = GetExeBasename($proc)
    Local $bRun = IsProcessRunningByName($sExe)
    GUICtrlSetData($g_aBtnMain[$i], MainBtnLabel($i, $bRun))
    GUICtrlSetBkColor($g_aBtnMain[$i], $bRun ? $CLR_RUN : $CLR_STOP)
EndFunc

; ====================================================================
;                       PROCESS DETECTION (API)
; ====================================================================
Func GetRunningProcessNames()
    Local $aOut[0]
    Local $aSnap = DllCall("kernel32.dll", "handle", "CreateToolhelp32Snapshot", _
            "dword", $TH32CS_SNAPPROCESS, "dword", 0)
    If @error Or Not IsArray($aSnap) Then Return $aOut
    Local $hSnap = $aSnap[0]
    If $hSnap = Ptr(-1) Or $hSnap = 0 Then Return $aOut

    Local $tPE = DllStructCreate( _
            "dword dwSize;" & _
            "dword cntUsage;" & _
            "dword th32ProcessID;" & _
            "ulong_ptr th32DefaultHeapID;" & _
            "dword th32ModuleID;" & _
            "dword cntThreads;" & _
            "dword th32ParentProcessID;" & _
            "long  pcPriClassBase;" & _
            "dword dwFlags;" & _
            "wchar szExeFile[260]")
    DllStructSetData($tPE, "dwSize", DllStructGetSize($tPE))

    Local $aRet = DllCall("kernel32.dll", "bool", "Process32FirstW", _
            "handle", $hSnap, "struct*", $tPE)
    While IsArray($aRet) And $aRet[0]
        Local $sName = DllStructGetData($tPE, "szExeFile")
        Local $n = UBound($aOut)
        ReDim $aOut[$n + 1]
        $aOut[$n] = StringLower($sName)
        $aRet = DllCall("kernel32.dll", "bool", "Process32NextW", _
                "handle", $hSnap, "struct*", $tPE)
    WEnd

    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $hSnap)
    Return $aOut
EndFunc

Func ProcessNameInList($sExeBasename, ByRef $aRunning)
    If $sExeBasename = "" Then Return False
    Local $sTarget = StringLower($sExeBasename)
    For $i = 0 To UBound($aRunning) - 1
        If $aRunning[$i] = $sTarget Then Return True
    Next
    Return False
EndFunc

Func IsProcessRunningByName($sExeBasename)
    If $sExeBasename = "" Then Return False
    Local $aRunning = GetRunningProcessNames()
    Return ProcessNameInList($sExeBasename, $aRunning)
EndFunc

Func WaitProcessState($sExeBasename, $bAppear, $iTimeoutMs)
    If $sExeBasename = "" Then Return False
    Local $tmr = TimerInit()
    While TimerDiff($tmr) < $iTimeoutMs
        Local $bRun = IsProcessRunningByName($sExeBasename)
        If ($bAppear And $bRun) Or (Not $bAppear And Not $bRun) Then Return $bRun
        GUIGetMsg()
        Sleep($WAIT_POLL_MS)
    WEnd
    Return IsProcessRunningByName($sExeBasename)
EndFunc

; ====================================================================
;                           PROCESS ACTIONS
; ====================================================================
Func AutoStartRows()
    For $i = 0 To UBound($g_aRows) - 1
        If $g_aRows[$i][2] = "1" And $g_aRows[$i][1] <> "" _
                And Not IsProcessRunningByName(GetExeBasename($g_aRows[$i][1])) Then
            StartProcess($g_aRows[$i][1])
        EndIf
    Next
EndFunc

Func StartProcess($sFullPath)
    If $sFullPath = "" Then Return
    If StringLeft($sFullPath, 1) = '"' And StringRight($sFullPath, 1) = '"' _
            And StringLen($sFullPath) >= 2 Then
        $sFullPath = StringMid($sFullPath, 2, StringLen($sFullPath) - 2)
    EndIf
    If Not FileExists($sFullPath) Then Return

    Local $sDir = ""
    Local $iPos = StringInStr($sFullPath, "\", 0, -1)
    If $iPos > 0 Then $sDir = StringLeft($sFullPath, $iPos - 1)
    ShellExecute($sFullPath, "", ($sDir <> "") ? $sDir : @ScriptDir)
EndFunc

Func StopProcess($sFullPathOrName)
    If $sFullPathOrName = "" Then Return
    Local $sTarget = StringLower(GetExeBasename($sFullPathOrName))
    If $sTarget = "" Then Return

    Local $aSnap = DllCall("kernel32.dll", "handle", "CreateToolhelp32Snapshot", _
            "dword", $TH32CS_SNAPPROCESS, "dword", 0)
    If @error Or Not IsArray($aSnap) Then Return
    Local $hSnap = $aSnap[0]
    If $hSnap = Ptr(-1) Or $hSnap = 0 Then Return

    Local $tPE = DllStructCreate( _
            "dword dwSize;" & _
            "dword cntUsage;" & _
            "dword th32ProcessID;" & _
            "ulong_ptr th32DefaultHeapID;" & _
            "dword th32ModuleID;" & _
            "dword cntThreads;" & _
            "dword th32ParentProcessID;" & _
            "long  pcPriClassBase;" & _
            "dword dwFlags;" & _
            "wchar szExeFile[260]")
    DllStructSetData($tPE, "dwSize", DllStructGetSize($tPE))

    Local $aRet = DllCall("kernel32.dll", "bool", "Process32FirstW", _
            "handle", $hSnap, "struct*", $tPE)

    While IsArray($aRet) And $aRet[0]
        Local $sName = DllStructGetData($tPE, "szExeFile")
        If StringLower($sName) = $sTarget Then
            Local $iPid = DllStructGetData($tPE, "th32ProcessID")
            If $iPid <> 0 Then TerminatePid($iPid)
        EndIf
        $aRet = DllCall("kernel32.dll", "bool", "Process32NextW", _
                "handle", $hSnap, "struct*", $tPE)
    WEnd

    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $hSnap)
EndFunc

Func TerminatePid($iPid)
    Local $aOpen = DllCall("kernel32.dll", "handle", "OpenProcess", _
            "dword", $PROCESS_TERMINATE, "bool", 0, "dword", $iPid)
    If @error Or Not IsArray($aOpen) Then Return
    Local $hProc = $aOpen[0]
    If $hProc = 0 Then Return
    DllCall("kernel32.dll", "bool", "TerminateProcess", _
            "handle", $hProc, "uint", 0)
    DllCall("kernel32.dll", "bool", "CloseHandle", "handle", $hProc)
EndFunc

Func LaunchTarget($sTarget)
    If $sTarget = "" Then Return
    Local $sPath = $sTarget
    If Not FileExists($sPath) Then
        Local $c = @ScriptDir & "\" & $sTarget
        If FileExists($c) Then $sPath = $c
    EndIf
    ShellExecute($sPath, "", @ScriptDir)
EndFunc

; ====================================================================
;                         MESSAGE DISPATCH
; ====================================================================
Func HandleMsg($msg)
    If $msg = 0 Then Return

    If $msg = $g_idAddRow Then
        AddRow()
        Return
    EndIf
    If $msg = $g_idExit Then
        GUIDelete($g_hMain)
        Exit
    EndIf

    For $i = 0 To UBound($g_aMenuItems) - 1
        If $msg = $g_aMenuItems[$i][0] Then
            ShowEditWindow($g_aMenuItems[$i][1])
            Return
        EndIf
    Next

    For $i = 0 To UBound($g_aRows) - 1
        If $i > UBound($g_aBtnMain) - 1 Then ExitLoop
        If $msg = $g_aBtnMain[$i] Then
            Local $proc = $g_aRows[$i][1]
            If $proc <> "" Then
                Local $sExe = GetExeBasename($proc)
                If IsProcessRunningByName($sExe) Then
                    StopProcess($proc)
                    WaitProcessState($sExe, False, $WAIT_STOP_MS)
                Else
                    StartProcess($proc)
                    WaitProcessState($sExe, True, $WAIT_START_MS)
                EndIf
            EndIf
            RefreshRow($i)
            Return
        ElseIf $msg = $g_aBtnA[$i] Then
            LaunchTarget($g_aRows[$i][4])
            Return
        ElseIf $msg = $g_aBtnB[$i] Then
            LaunchTarget($g_aRows[$i][6])
            Return
        EndIf
    Next
EndFunc

Func AddRow()
    Local $n = UBound($g_aRows)
    ReDim $g_aRows[$n + 1][7]
    $g_aRows[$n][0] = "Desc" & ($n + 1)
    $g_aRows[$n][1] = ""
    $g_aRows[$n][2] = "0"
    $g_aRows[$n][3] = "Desc" & ($n + 1) & "A"
    $g_aRows[$n][4] = ""
    $g_aRows[$n][5] = "Desc" & ($n + 1) & "B"
    $g_aRows[$n][6] = ""
    SaveRowsToIni()
    RebuildMainGui()
EndFunc

; ====================================================================
;                            EDIT WINDOW
; ====================================================================
Func ShowEditWindow($iRow)
    GUISetState(@SW_DISABLE, $g_hMain)
    Local $w = 600, $h = 400
    Local $hEdit = GUICreate("Edit Row " & ($iRow + 1), $w, $h, -1, -1, _
            BitOR($WS_CAPTION, $WS_SYSMENU, $WS_POPUP, $WS_SIZEBOX, $WS_MINIMIZEBOX, $WS_MAXIMIZEBOX), _
            0, $g_hMain)
    GUISwitch($hEdit)

    Local $y = 15
    Local $xLbl = 15, $lblW = 95, $xEdit = $xLbl + $lblW
    Local $btnBrowseW = 90
    Local $editW = $w - $xEdit - $btnBrowseW - 10 - 15

    Local $aNameEdit[3], $aDescEdit[3], $aBrowse[3]
    Local $aGroups[3] = ["Main button  (Description = full path to .EXE)", _
                        "Helper A  (column 2 - launches any file)", _
                        "Helper B  (column 3 - launches any file)"]

    For $k = 0 To 2
        Local $idGrpLbl = GUICtrlCreateLabel($aGroups[$k], $xLbl, $y, $w - 30, 14)
        GUICtrlSetFont(-1, 8, 800)
        GUICtrlSetResizing($idGrpLbl, BitOR($GUI_DOCKLEFT, $GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))
        $y += 18

        Local $idNL = GUICtrlCreateLabel("Name", $xLbl, $y + 4, $lblW, 18)
        GUICtrlSetResizing($idNL, BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))

        Local $sName
        Switch $k
            Case 0
                $sName = $g_aRows[$iRow][0]
            Case 1
                $sName = $g_aRows[$iRow][3]
            Case 2
                $sName = $g_aRows[$iRow][5]
        EndSwitch
        $aNameEdit[$k] = GUICtrlCreateInput($sName, $xEdit, $y, $editW + $btnBrowseW + 10, 22)
        GUICtrlSetResizing($aNameEdit[$k], BitOR($GUI_DOCKLEFT, $GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))
        $y += 28

        Local $idDL = GUICtrlCreateLabel("Description", $xLbl, $y + 4, $lblW, 18)
        GUICtrlSetResizing($idDL, BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))

        Local $sDesc
        Switch $k
            Case 0
                $sDesc = $g_aRows[$iRow][1]
            Case 1
                $sDesc = $g_aRows[$iRow][4]
            Case 2
                $sDesc = $g_aRows[$iRow][6]
        EndSwitch
        $aDescEdit[$k] = GUICtrlCreateInput($sDesc, $xEdit, $y, $editW, 22)
        GUICtrlSetResizing($aDescEdit[$k], BitOR($GUI_DOCKLEFT, $GUI_DOCKRIGHT, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))

        $aBrowse[$k] = GUICtrlCreateButton("Browse", $xEdit + $editW + 10, $y - 1, $btnBrowseW, 24)
        GUICtrlSetResizing($aBrowse[$k], BitOR($GUI_DOCKRIGHT, $GUI_DOCKWIDTH, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))
        $y += 34
    Next

    Local $idAutoLbl = GUICtrlCreateLabel("Auto-Start at launch", $xLbl, $y + 4, $lblW + 30, 18)
    GUICtrlSetResizing($idAutoLbl, BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))
    Local $idAuto = GUICtrlCreateCheckbox("", $xEdit + 30, $y + 2, 20, 22)
    GUICtrlSetResizing($idAuto, BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKTOP, $GUI_DOCKHEIGHT))
    If $g_aRows[$iRow][2] = "1" Then GUICtrlSetState($idAuto, $GUI_CHECKED)
    $y += 36

    Local $idSave   = GUICtrlCreateButton("Save",   100, $y, 90, 28)
    Local $idDel    = GUICtrlCreateButton("Delete", 255, $y, 90, 28)
    Local $idCancel = GUICtrlCreateButton("Cancel", 410, $y, 90, 28)
    GUICtrlSetResizing($idSave,   BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKBOTTOM, $GUI_DOCKHEIGHT))
    GUICtrlSetResizing($idDel,    BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKBOTTOM, $GUI_DOCKHEIGHT))
    GUICtrlSetResizing($idCancel, BitOR($GUI_DOCKLEFT, $GUI_DOCKWIDTH, $GUI_DOCKBOTTOM, $GUI_DOCKHEIGHT))
    If $iRow < 2 Then GUICtrlSetState($idDel, $GUI_DISABLE)

    GUISetState(@SW_SHOW, $hEdit)

    While 1
        Local $em = GUIGetMsg()
        Switch $em
            Case $GUI_EVENT_CLOSE, $idCancel
                ExitLoop
            Case $idSave
                $g_aRows[$iRow][0] = GUICtrlRead($aNameEdit[0])
                $g_aRows[$iRow][1] = StringStripWS(GUICtrlRead($aDescEdit[0]), 3)
                $g_aRows[$iRow][3] = GUICtrlRead($aNameEdit[1])
                $g_aRows[$iRow][4] = GUICtrlRead($aDescEdit[1])
                $g_aRows[$iRow][5] = GUICtrlRead($aNameEdit[2])
                $g_aRows[$iRow][6] = GUICtrlRead($aDescEdit[2])
                $g_aRows[$iRow][2] = ((BitAND(GUICtrlRead($idAuto), $GUI_CHECKED) = $GUI_CHECKED) ? "1" : "0")
                SaveRowsToIni()
                GUIDelete($hEdit)
                GUISetState(@SW_ENABLE, $g_hMain)
                WinActivate($g_hMain)
                RebuildMainGui()
                Return
            Case $idDel
                If $iRow >= 2 Then
                    DeleteRow($iRow)
                    GUIDelete($hEdit)
                    GUISetState(@SW_ENABLE, $g_hMain)
                    WinActivate($g_hMain)
                    Return
                EndIf
            Case $aBrowse[0]
                BrowseInto($aDescEdit[0], $hEdit)
            Case $aBrowse[1]
                BrowseInto($aDescEdit[1], $hEdit)
            Case $aBrowse[2]
                BrowseInto($aDescEdit[2], $hEdit)
        EndSwitch
        Sleep(20)
    WEnd

    GUIDelete($hEdit)
    GUISetState(@SW_ENABLE, $g_hMain)
    WinActivate($g_hMain)
EndFunc

Func BrowseInto($idCtrl, $hParent)
    Local $sFile = FileOpenDialog("Browse", @ScriptDir, "All files (*.*)", 0, "", $hParent)
    If @error Then Return
    GUICtrlSetData($idCtrl, $sFile)
EndFunc

Func DeleteRow($iRow)
    If $iRow < 2 Then Return
    Local $n = UBound($g_aRows)
    For $i = $iRow To $n - 2
        For $j = 0 To 6
            $g_aRows[$i][$j] = $g_aRows[$i + 1][$j]
        Next
    Next
    ReDim $g_aRows[$n - 1][7]
    SaveRowsToIni()
    RebuildMainGui()
EndFunc
;GUICtrlSetResizing(-1,$GUI_DOCKHCENTER+$GUI_DOCKVCENTER)