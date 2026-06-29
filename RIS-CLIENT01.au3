#NoTrayIcon
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <ComboConstants.au3>
#include <ListViewConstants.au3>
#include <GuiListView.au3>
#include <GuiMenu.au3>
#include <File.au3>
#include <Array.au3>
#include <Date.au3>
#include <Misc.au3>
#include <StaticConstants.au3>

Opt("GUIOnEventMode", 0)
Opt("MustDeclareVars", 1)

; ===================================================================
; DYNAMIC INI & CONFIG
; ===================================================================
Global $INI_FILE = @ScriptDir & "\" & StringRegExpReplace(@ScriptName, "\.[^.]*$", "") & ".ini"
Global $CACHE_CSV = @ScriptDir & "\cache.csv"

Global $RIS_HOST       = "127.0.0.1"
Global $RIS_PORT       = 23
Global $RIS_TIMEOUT_MS = 5000
Global $CLIENT_AET     = "RIS_CLIENT"

; 22-column CSV header (must match worklist server)
Global $CSV_HEADER = "PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName,Status,ProcedureCode,ProcedureCodeDesc,CodingScheme,PerformingPhysician,StationName,Location"
Global $CSV_FIELDS[22] = ["PatientID","PatientName","Accession","BirthDate","Sex","SPSID","SPSDescription","RequestedProcedureID","StationAET","Modality","ScheduledDate","ScheduledTime","RequestedProcDesc","StudyInstanceUID","ReferringPhysicianName","Status","ProcedureCode","ProcedureCodeDesc","CodingScheme","PerformingPhysician","StationName","Location"]

; Fields shown in main filter row
Global $FILTER_FIELDS[7] = ["Accession","Modality","PatientName","BirthDate","PatientID","ScheduledDate","Status"]

; Status enum from server: 1..4
Global $STATUS_LIST = "|1 - SCHEDULED|2 - ARRIVED|3 - READY|4 - COMPLETED"

; Custom-search candidate columns
Global $CUSTOM_FIELDS = "Sex|SPSID|SPSDescription|RequestedProcedureID|StationAET|ScheduledTime|RequestedProcDesc|StudyInstanceUID|ReferringPhysicianName|ProcedureCode|ProcedureCodeDesc|CodingScheme|PerformingPhysician|StationName|Location"

; ===================================================================
; GLOBAL HANDLES
; ===================================================================
Global $g_hMain          = 0
Global $g_hFilterEdits[7] ; 6 edits + 1 combo
Global $g_hList          = 0
Global $g_hStatusBar     = 0
Global $g_iCols          = 22

Global $g_aRows[1][22]   ; loaded patient data (excluding header)
Global $g_iRowCount      = 0

; Menu item ids
Global $g_idFView, $g_idFSearch, $g_idFDaily, $g_idFMonth, $g_idFExit
Global $g_idEPCodes, $g_idESettings
Global $g_idHAbout

; Toolbar buttons
Global $g_btnRefresh, $g_btnNewEnc, $g_btnNewPat, $g_btnSearch, $g_btnCustom

; ===================================================================
; CONFIG MANAGEMENT
; ===================================================================
Func EnsureIni()
    If Not FileExists($INI_FILE) Then
        IniWrite($INI_FILE, "RIS", "Host",       "127.0.0.1")
        IniWrite($INI_FILE, "RIS", "Port",       "23")
        IniWrite($INI_FILE, "RIS", "TimeoutMs",  "5000")
        IniWrite($INI_FILE, "RIS", "ClientAET",  "RIS_CLIENT")
    EndIf
EndFunc

Func LoadConfig()
    EnsureIni()
    $RIS_HOST       = IniRead($INI_FILE, "RIS", "Host",      "127.0.0.1")
    $RIS_PORT       = Number(IniRead($INI_FILE, "RIS", "Port", "23"))
    $RIS_TIMEOUT_MS = Number(IniRead($INI_FILE, "RIS", "TimeoutMs", "5000"))
    $CLIENT_AET     = IniRead($INI_FILE, "RIS", "ClientAET", "RIS_CLIENT")
EndFunc

Func SaveConfig()
    IniWrite($INI_FILE, "RIS", "Host",      $RIS_HOST)
    IniWrite($INI_FILE, "RIS", "Port",      $RIS_PORT)
    IniWrite($INI_FILE, "RIS", "TimeoutMs", $RIS_TIMEOUT_MS)
    IniWrite($INI_FILE, "RIS", "ClientAET", $CLIENT_AET)
EndFunc

; ===================================================================
; CSV HELPERS
; ===================================================================
Func CSV_SplitLine($sLine, $iExpected)
    Local $aOut[$iExpected]
    Local $sCur = "", $idx = 0, $bQ = False
    For $i = 1 To StringLen($sLine)
        Local $c = StringMid($sLine, $i, 1)
        If $c = '"' Then
            $bQ = Not $bQ
            ContinueLoop
        EndIf
        If $c = "," And Not $bQ Then
            If $idx < $iExpected Then $aOut[$idx] = $sCur
            $idx += 1
            $sCur = ""
            If $idx >= $iExpected Then ExitLoop
        Else
            $sCur &= $c
        EndIf
    Next
    If $idx < $iExpected Then $aOut[$idx] = $sCur
    For $j = $idx + 1 To $iExpected - 1
        $aOut[$j] = ""
    Next
    Return $aOut
EndFunc

Func CSV_BuildLine(ByRef $aFields)
    Local $s = ""
    For $i = 0 To UBound($aFields) - 1
        Local $f = $aFields[$i]
        If StringInStr($f, ",") Or StringInStr($f, '"') Then
            $f = '"' & StringReplace($f, '"', '""') & '"'
        EndIf
        If $i > 0 Then $s &= ","
        $s &= $f
    Next
    Return $s
EndFunc

Func WriteCacheFromArray()
    Local $h = FileOpen($CACHE_CSV, 2)
    If $h = -1 Then Return False
    FileWriteLine($h, $CSV_HEADER)
    For $r = 0 To $g_iRowCount - 1
        Local $aRow[22]
        For $c = 0 To 21
            $aRow[$c] = $g_aRows[$r][$c]
        Next
        FileWriteLine($h, CSV_BuildLine($aRow))
    Next
    FileClose($h)
    Return True
EndFunc

Func LoadCacheToArray()
    $g_iRowCount = 0
    ReDim $g_aRows[1][22]
    If Not FileExists($CACHE_CSV) Then Return False
    Local $h = FileOpen($CACHE_CSV, 0)
    If $h = -1 Then Return False
    FileReadLine($h) ; skip header
    While 1
        Local $line = FileReadLine($h)
        If @error Then ExitLoop
        $line = StringStripWS($line, 3)
        If $line = "" Then ContinueLoop
        Local $aCols = CSV_SplitLine($line, 22)
        ReDim $g_aRows[$g_iRowCount + 1][22]
        For $c = 0 To 21
            $g_aRows[$g_iRowCount][$c] = $aCols[$c]
        Next
        $g_iRowCount += 1
    WEnd
    FileClose($h)
    Return True
EndFunc

; ===================================================================
; TELNET DISP
; ===================================================================
Func RIS_RunDisp($sParam = "")
    TCPStartup()
    Local $sock = TCPConnect($RIS_HOST, $RIS_PORT)
    If $sock = -1 Then
        TCPShutdown()
        MsgBox(16, "RIS Error", "Cannot connect to " & $RIS_HOST & ":" & $RIS_PORT)
        Return False
    EndIf

    Local $cmd = "DISP"
    If $sParam <> "" Then $cmd &= " " & $sParam
    TCPSend($sock, $cmd & @CRLF)

    Local $buffer = "", $timer = TimerInit()
    While TimerDiff($timer) < $RIS_TIMEOUT_MS
        Local $data = TCPRecv($sock, 65536)
        If @error Then ExitLoop
        If $data <> "" Then
            $buffer &= $data
            $timer = TimerInit()
        Else
            Sleep(50)
        EndIf
        If StringInStr($buffer, "END_OF_DISP") Then ExitLoop
    WEnd

    TCPCloseSocket($sock)
    TCPShutdown()

    Local $h = FileOpen($CACHE_CSV, 2)
    If $h = -1 Then Return False
    FileWriteLine($h, $CSV_HEADER)
    Local $aLines = StringRegExp($buffer, "[^\r\n]+", 3)
    If IsArray($aLines) Then
        For $i = 0 To UBound($aLines) - 1
            Local $ln = StringStripWS($aLines[$i], 3)
            If $ln <> "" And StringLeft($ln, 11) <> "Connected to" And $ln <> "END_OF_DISP" Then
                FileWriteLine($h, $ln)
            EndIf
        Next
    EndIf
    FileClose($h)

    LoadCacheToArray()
    Return True
EndFunc

Func RIS_SendEntry(ByRef $aFields)
    TCPStartup()
    Local $sock = TCPConnect($RIS_HOST, $RIS_PORT)
    If $sock = -1 Then
        TCPShutdown()
        MsgBox(16, "RIS Error", "Cannot connect to " & $RIS_HOST & ":" & $RIS_PORT)
        Return False
    EndIf
    Local $line = CSV_BuildLine($aFields)
    TCPSend($sock, $line & @CRLF)
    Sleep(500)

    Local $buffer = "", $timer = TimerInit()
    While TimerDiff($timer) < $RIS_TIMEOUT_MS
        Local $data = TCPRecv($sock, 4096)
        If @error Then ExitLoop
        If $data <> "" Then
            $buffer &= $data
            If StringInStr($buffer, "INSERTED") Or StringInStr($buffer, "UPDATED") _
                Or StringInStr($buffer, "PENDING") Or StringInStr($buffer, "INVALID") Then
                Sleep(200)
            EndIf
        EndIf
        If StringInStr($buffer, "INSERTED") Or StringInStr($buffer, "UPDATED") Or StringInStr($buffer, "INVALID") Then ExitLoop
        Sleep(50)
    WEnd

    TCPCloseSocket($sock)
    TCPShutdown()

    If StringInStr($buffer, "INVALID") Then
        MsgBox(48, "RIS", "Server reported INVALID LINE." & @CRLF & "Check field values.")
        Return False
    EndIf
    Return True
EndFunc

; ===================================================================
; FILTER + LISTVIEW
; ===================================================================
Func ApplyFilters()
    _GUICtrlListView_BeginUpdate($g_hList)
    _GUICtrlListView_DeleteAllItems($g_hList)

    Local $accF  = GUICtrlRead($g_hFilterEdits[0])
    Local $modF  = GUICtrlRead($g_hFilterEdits[1])
    Local $nameF = GUICtrlRead($g_hFilterEdits[2])
    Local $bdF   = GUICtrlRead($g_hFilterEdits[3])
    Local $pidF  = GUICtrlRead($g_hFilterEdits[4])
    Local $schF  = GUICtrlRead($g_hFilterEdits[5])
    Local $stF   = GUICtrlRead($g_hFilterEdits[6])
    Local $stFirstChar = ""
    If $stF <> "" Then $stFirstChar = StringLeft($stF, 1)

    For $r = 0 To $g_iRowCount - 1
        Local $okAcc  = ($accF  = "" Or StringInStr($g_aRows[$r][2], $accF))
        Local $okMod  = ($modF  = "" Or StringInStr($g_aRows[$r][9], $modF))
        Local $okName = ($nameF = "" Or StringInStr($g_aRows[$r][1], $nameF))
        Local $okBd   = ($bdF   = "" Or StringInStr($g_aRows[$r][3], $bdF))
        Local $okPid  = ($pidF  = "" Or StringInStr($g_aRows[$r][0], $pidF))
        Local $okSch  = ($schF  = "" Or StringInStr($g_aRows[$r][10], $schF))
        Local $okSt   = ($stFirstChar = "" Or $g_aRows[$r][15] = $stFirstChar)

        If $okAcc And $okMod And $okName And $okBd And $okPid And $okSch And $okSt Then
            Local $sLine = $g_aRows[$r][0]
            For $c = 1 To 21
                $sLine &= "|" & $g_aRows[$r][$c]
            Next
            GUICtrlCreateListViewItem($sLine, $g_hList)
        EndIf
    Next
    _GUICtrlListView_EndUpdate($g_hList)
    UpdateStatus()
EndFunc




Func UpdateStatus()
    Local $shown = _GUICtrlListView_GetItemCount($g_hList)
    GUICtrlSetData($g_hStatusBar, "Rows: " & $shown & " / " & $g_iRowCount & "   Server: " & $RIS_HOST & ":" & $RIS_PORT)
EndFunc

Func InitListViewColumns()
    For $i = 0 To 21
        _GUICtrlListView_AddColumn($g_hList, $CSV_FIELDS[$i], 110)
    Next
EndFunc

; ===================================================================
; MAIN WINDOW
; ===================================================================
Func CreateMainGUI()
    $g_hMain = GUICreate("RIS Worklist Client", 1100, 650, -1, -1, _
        BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS))
    GUISetIcon("shell32.dll", 14)

    ; File menu
    Local $mFile = GUICtrlCreateMenu("&File")
    $g_idFView   = GUICtrlCreateMenuItem("View Patient", $mFile)
    $g_idFSearch = GUICtrlCreateMenuItem("Search for Patient", $mFile)
    $g_idFDaily  = GUICtrlCreateMenuItem("Daily Calendar", $mFile)
    $g_idFMonth  = GUICtrlCreateMenuItem("Monthly Calendar", $mFile)
    GUICtrlCreateMenuItem("", $mFile)
    $g_idFExit   = GUICtrlCreateMenuItem("Exit", $mFile)

    ; Edit menu
    Local $mEdit = GUICtrlCreateMenu("&Edit")
    $g_idEPCodes   = GUICtrlCreateMenuItem("View Procedure Codes", $mEdit)
    $g_idESettings = GUICtrlCreateMenuItem("Edit RIS Server Settings", $mEdit)

    ; View menu (placeholder)
    Local $mView = GUICtrlCreateMenu("&View")
    GUICtrlCreateMenuItem("Refresh (F5)", $mView)

    ; Help menu
    Local $mHelp = GUICtrlCreateMenu("&Help")
    $g_idHAbout = GUICtrlCreateMenuItem("About", $mHelp)

    ; Toolbar buttons
    $g_btnRefresh = GUICtrlCreateButton("Refresh", 10, 5, 90, 25)
    $g_btnNewEnc  = GUICtrlCreateButton("New Encounter", 105, 5, 100, 25)
    $g_btnNewPat  = GUICtrlCreateButton("New Patient", 210, 5, 100, 25)
    $g_btnSearch  = GUICtrlCreateButton("Search", 315, 5, 80, 25)
    $g_btnCustom  = GUICtrlCreateButton("Custom Search", 400, 5, 110, 25)

    ; Filter row
    BuildFilterRow()

    ; ListView
    $g_hList = GUICtrlCreateListView("", 5, 75, 1085, 550, _
        BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS), _
        BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER))
    InitListViewColumns()

    ; Status bar
    $g_hStatusBar = GUICtrlCreateLabel("", 5, 627, 1085, 18, $SS_SUNKEN)
    GUICtrlSetResizing($g_hStatusBar, $GUI_DOCKAUTO + $GUI_DOCKBOTTOM)

    ; Resizing rules
    GUICtrlSetResizing($g_btnRefresh, $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKSIZE)
    GUICtrlSetResizing($g_btnNewEnc,  $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKSIZE)
    GUICtrlSetResizing($g_btnNewPat,  $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKSIZE)
    GUICtrlSetResizing($g_btnSearch,  $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKSIZE)
    GUICtrlSetResizing($g_btnCustom,  $GUI_DOCKLEFT + $GUI_DOCKTOP + $GUI_DOCKSIZE)
    GUICtrlSetResizing($g_hList, $GUI_DOCKBORDERS)

    GUISetState(@SW_SHOW, $g_hMain)
    UpdateStatus()
EndFunc

Func BuildFilterRow()
    Local $iX = 5, $iY = 40, $iH = 22
    Local $iW = Int(1090 / 7)
    Local $aLabels[7] = ["Accession","Modality","PatientName","BirthDate","PatientID","ScheduledDate","Status"]
    Local $iLblY = 38, $iEditY = 50
    For $i = 0 To 6
        GUICtrlCreateLabel($aLabels[$i], $iX + $i * $iW, $iLblY, $iW - 5, 12)
        If $i = 6 Then
            $g_hFilterEdits[$i] = GUICtrlCreateCombo("", $iX + $i * $iW, $iEditY, $iW - 5, $iH, _
                BitOR($CBS_DROPDOWNLIST, $CBS_AUTOHSCROLL))
            GUICtrlSetData($g_hFilterEdits[$i], $STATUS_LIST)
        Else
            $g_hFilterEdits[$i] = GUICtrlCreateInput("", $iX + $i * $iW, $iEditY, $iW - 5, $iH)
        EndIf
        GUICtrlSetResizing($g_hFilterEdits[$i], $GUI_DOCKHEIGHT + $GUI_DOCKTOP)
    Next
EndFunc

; ===================================================================
; ACTIONS
; ===================================================================
Func DoRefresh()
    Local $modF  = GUICtrlRead($g_hFilterEdits[1])
    Local $schF  = GUICtrlRead($g_hFilterEdits[5])
    Local $param = ""
    If $schF <> "" Then
        If StringRegExp($schF, "^\d{8}(\s+\d{8})?$") Then
            $param = $schF
        ElseIf StringRegExp($schF, "^\d{8}$") Then
            $param = $schF
        EndIf
    EndIf
    If $param = "" And $modF <> "" Then $param = $modF
    GUICtrlSetData($g_hStatusBar, "Connecting to " & $RIS_HOST & ":" & $RIS_PORT & " ...")
    If RIS_RunDisp($param) Then
        ApplyFilters()
    EndIf
EndFunc

; ===================================================================
; PATIENT EDITOR (New Patient / New Encounter)
; ===================================================================
Func ShowPatientEditor($sTitle, ByRef $aDefaults)
    Local $hWnd = GUICreate($sTitle, 600, 700, -1, -1, _
        BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS), -1, $g_hMain)
    Local $aHandles[22]
    Local $iY = 10
    For $i = 0 To 21
        GUICtrlCreateLabel($CSV_FIELDS[$i] & ":", 10, $iY + 3, 160, 18)
        $aHandles[$i] = GUICtrlCreateInput($aDefaults[$i], 180, $iY, 400, 20)
        GUICtrlSetResizing($aHandles[$i], $GUI_DOCKLEFT + $GUI_DOCKRIGHT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
        $iY += 25
    Next

    Local $btnOK     = GUICtrlCreateButton("OK",     400, 660, 80, 25)
    Local $btnCancel = GUICtrlCreateButton("Cancel", 490, 660, 80, 25)
    GUICtrlSetResizing($btnOK,     $GUI_DOCKBOTTOM + $GUI_DOCKRIGHT + $GUI_DOCKSIZE)
    GUICtrlSetResizing($btnCancel, $GUI_DOCKBOTTOM + $GUI_DOCKRIGHT + $GUI_DOCKSIZE)
    GUISetState(@SW_SHOW, $hWnd)

    Local $aResult[22]
    Local $bOK = False

    While 1
        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnCancel
                ExitLoop
            Case $btnOK
                For $i = 0 To 21
                    $aResult[$i] = GUICtrlRead($aHandles[$i])
                Next
                $bOK = True
                ExitLoop
        EndSwitch
    WEnd
    GUIDelete($hWnd)
    If $bOK Then
        $aDefaults = $aResult
        Return True
    EndIf
    Return False
EndFunc

Func DoNewPatient()
    Local $aDef[22]
    For $i = 0 To 21
        $aDef[$i] = ""
    Next
    $aDef[4] = "M"        ; Sex
    $aDef[9] = "OT"       ; Modality
    $aDef[10] = StringFormat("%04d%02d%02d", @YEAR, @MON, @MDAY)  ; ScheduledDate today
    $aDef[15] = "1"       ; Status SCHEDULED
    If ShowPatientEditor("New Patient", $aDef) Then
        If RIS_SendEntry($aDef) Then
            MsgBox(64, "Patient", "Patient submitted to RIS.")
            DoRefresh()
        EndIf
    EndIf
EndFunc

Func DoNewEncounter()
    ; Same editor but pre-fill PatientID if a row is selected
    Local $aDef[22]
    For $i = 0 To 21
        $aDef[$i] = ""
    Next

    Local $sel = _GUICtrlListView_GetSelectedIndices($g_hList, True)
    If IsArray($sel) And $sel[0] >= 1 Then
        Local $iRow = $sel[1]
        For $i = 0 To 21
            $aDef[$i] = _GUICtrlListView_GetItemText($g_hList, $iRow, $i)
        Next
        ; Wipe accession and SPS-specific fields so it becomes a NEW encounter for same patient
        $aDef[2]  = ""       ; Accession
        $aDef[5]  = ""       ; SPSID
        $aDef[7]  = ""       ; RequestedProcedureID
        $aDef[13] = ""       ; StudyInstanceUID
        $aDef[10] = StringFormat("%04d%02d%02d", @YEAR, @MON, @MDAY)
        $aDef[15] = "1"
    Else
        $aDef[4] = "M"
        $aDef[9] = "OT"
        $aDef[10] = StringFormat("%04d%02d%02d", @YEAR, @MON, @MDAY)
        $aDef[15] = "1"
    EndIf

    If ShowPatientEditor("New Encounter", $aDef) Then
        If RIS_SendEntry($aDef) Then
            MsgBox(64, "Encounter", "Encounter submitted to RIS.")
            DoRefresh()
        EndIf
    EndIf
EndFunc

; ===================================================================
; CUSTOM SEARCH
; ===================================================================
Func DoCustomSearch()
    Local $hWnd = GUICreate("Custom Search", 480, 130, -1, -1, _
        BitOR($WS_CAPTION, $WS_SYSMENU), -1, $g_hMain)
    GUICtrlCreateLabel("Field:", 10, 15, 60, 18)
    Local $cmb = GUICtrlCreateCombo("", 80, 12, 200, 22, BitOR($CBS_DROPDOWNLIST, $CBS_AUTOHSCROLL))
    GUICtrlSetData($cmb, $CUSTOM_FIELDS)

    GUICtrlCreateLabel("Value:", 10, 50, 60, 18)
    Local $edt = GUICtrlCreateInput("", 80, 47, 380, 22)

    Local $btnFind  = GUICtrlCreateButton("Search", 290, 85, 80, 25)
    Local $btnClose = GUICtrlCreateButton("Close",  380, 85, 80, 25)
    GUISetState(@SW_SHOW, $hWnd)

    While 1
        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnClose
                ExitLoop
            Case $btnFind
                Local $field = GUICtrlRead($cmb)
                Local $value = GUICtrlRead($edt)
                If $field = "" Or $value = "" Then
                    MsgBox(48, "Search", "Pick a field and enter a value.")
                ElseIf Not FieldFilter($field, $value) Then
                    MsgBox(48, "Search", "Field not found.")
                EndIf
        EndSwitch
    WEnd
    GUIDelete($hWnd)
EndFunc

Func FieldFilter($sField, $sValue)
    Local $idx = -1
    For $i = 0 To 21
        If $CSV_FIELDS[$i] = $sField Then
            $idx = $i
            ExitLoop
        EndIf
    Next
    If $idx = -1 Then Return False

    _GUICtrlListView_BeginUpdate($g_hList)
    _GUICtrlListView_DeleteAllItems($g_hList)
    For $r = 0 To $g_iRowCount - 1
        If StringInStr($g_aRows[$r][$idx], $sValue) Then
            Local $aDisp[22]
            For $c = 0 To 21
                $aDisp[$c] = $g_aRows[$r][$c]
            Next
            _GUICtrlListView_AddArray($g_hList, $aDisp)
        EndIf
    Next
    _GUICtrlListView_EndUpdate($g_hList)
    UpdateStatus()
    Return True
EndFunc

; ===================================================================
; SETTINGS DIALOG
; ===================================================================
Func ShowSettings()
    Local $hWnd = GUICreate("RIS Server Settings", 360, 220, -1, -1, _
        BitOR($WS_CAPTION, $WS_SYSMENU), -1, $g_hMain)

    GUICtrlCreateLabel("Host:",        15, 18, 100, 18)
    Local $eHost = GUICtrlCreateInput($RIS_HOST, 120, 15, 220, 22)

    GUICtrlCreateLabel("Port:",        15, 48, 100, 18)
    Local $ePort = GUICtrlCreateInput($RIS_PORT, 120, 45, 220, 22)

    GUICtrlCreateLabel("Timeout (ms):",15, 78, 100, 18)
    Local $eTo = GUICtrlCreateInput($RIS_TIMEOUT_MS, 120, 75, 220, 22)

    GUICtrlCreateLabel("Client AET:",  15, 108, 100, 18)
    Local $eAet = GUICtrlCreateInput($CLIENT_AET, 120, 105, 220, 22)

    Local $btnSave   = GUICtrlCreateButton("Save",   170, 170, 80, 25)
    Local $btnCancel = GUICtrlCreateButton("Cancel", 260, 170, 80, 25)
    GUISetState(@SW_SHOW, $hWnd)

    While 1
        Local $msg = GUIGetMsg()
        Switch $msg
            Case $GUI_EVENT_CLOSE, $btnCancel
                ExitLoop
            Case $btnSave
                $RIS_HOST       = GUICtrlRead($eHost)
                $RIS_PORT       = Number(GUICtrlRead($ePort))
                $RIS_TIMEOUT_MS = Number(GUICtrlRead($eTo))
                $CLIENT_AET     = GUICtrlRead($eAet)
                SaveConfig()
                UpdateStatus()
                ExitLoop
        EndSwitch
    WEnd
    GUIDelete($hWnd)
EndFunc

; ===================================================================
; PROCEDURE CODES VIEWER
; ===================================================================
Func ShowProcedureCodes()
    Local $hWnd = GUICreate("Procedure Codes", 500, 400, -1, -1, _
        BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS), -1, $g_hMain)
    GUICtrlCreateLabel("Procedure codes seen in current dataset:", 10, 10, 480, 18)
    Local $lv = GUICtrlCreateListView("ProcedureCode|ProcedureCodeDesc|CodingScheme", _
        10, 35, 480, 310)
    GUICtrlSetResizing($lv, $GUI_DOCKBORDERS)

    Local $aSeen[1][3], $iCount = 0
    For $r = 0 To $g_iRowCount - 1
        Local $pc = $g_aRows[$r][16]
        If $pc = "" Then ContinueLoop
        Local $bDup = False
        For $k = 0 To $iCount - 1
            If $aSeen[$k][0] = $pc Then
                $bDup = True
                ExitLoop
            EndIf
        Next
        If Not $bDup Then
            ReDim $aSeen[$iCount + 1][3]
            $aSeen[$iCount][0] = $pc
            $aSeen[$iCount][1] = $g_aRows[$r][17]
            $aSeen[$iCount][2] = $g_aRows[$r][18]
            $iCount += 1
            GUICtrlCreateListViewItem($pc & "|" & $g_aRows[$r][17] & "|" & $g_aRows[$r][18], $lv)
        EndIf
    Next

    Local $btnClose = GUICtrlCreateButton("Close", 410, 360, 80, 25)
    GUICtrlSetResizing($btnClose, $GUI_DOCKBOTTOM + $GUI_DOCKRIGHT + $GUI_DOCKSIZE)
    GUISetState(@SW_SHOW, $hWnd)

    While 1
        Local $msg = GUIGetMsg()
        If $msg = $GUI_EVENT_CLOSE Or $msg = $btnClose Then ExitLoop
    WEnd
    GUIDelete($hWnd)
EndFunc

; ===================================================================
; VIEW PATIENT  (read-only detail of selected row)
; ===================================================================
Func ViewPatient()
    Local $sel = _GUICtrlListView_GetSelectedIndices($g_hList, True)
    If Not IsArray($sel) Or $sel[0] < 1 Then
        MsgBox(48, "View", "Pick a row first.")
        Return
    EndIf
    Local $iRow = $sel[1]

    Local $hWnd = GUICreate("Patient Detail", 520, 620, -1, -1, _
        BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPSIBLINGS), -1, $g_hMain)
    Local $iY = 10
    For $i = 0 To 21
        GUICtrlCreateLabel($CSV_FIELDS[$i] & ":", 10, $iY + 3, 170, 18)
        Local $val = _GUICtrlListView_GetItemText($g_hList, $iRow, $i)
        Local $h = GUICtrlCreateInput($val, 185, $iY, 320, 20, $ES_READONLY)
        GUICtrlSetResizing($h, $GUI_DOCKLEFT + $GUI_DOCKRIGHT + $GUI_DOCKTOP + $GUI_DOCKHEIGHT)
        $iY += 25
    Next

    Local $btnClose = GUICtrlCreateButton("Close", 430, 580, 80, 25)
    GUICtrlSetResizing($btnClose, $GUI_DOCKBOTTOM + $GUI_DOCKRIGHT + $GUI_DOCKSIZE)
    GUISetState(@SW_SHOW, $hWnd)

    While 1
        Local $msg = GUIGetMsg()
        If $msg = $GUI_EVENT_CLOSE Or $msg = $btnClose Then ExitLoop
    WEnd
    GUIDelete($hWnd)
EndFunc

; ===================================================================
; SEARCH FOR PATIENT  (simple)
; ===================================================================
Func SearchPatient()
    Local $sQuery = InputBox("Search", "Type PatientName, PatientID, or Accession:")
    If @error Then Return
    Local $sq = StringStripWS($sQuery, 3)
    If $sq = "" Then Return

    _GUICtrlListView_BeginUpdate($g_hList)
    _GUICtrlListView_DeleteAllItems($g_hList)
    For $r = 0 To $g_iRowCount - 1
        If StringInStr($g_aRows[$r][0], $sq) Or _
           StringInStr($g_aRows[$r][1], $sq) Or _
           StringInStr($g_aRows[$r][2], $sq) Then
            Local $sLine = $g_aRows[$r][0]
            For $c = 1 To 21
                $sLine &= "|" & $g_aRows[$r][$c]
            Next
            GUICtrlCreateListViewItem($sLine, $g_hList)
        EndIf
    Next
    _GUICtrlListView_EndUpdate($g_hList)
    UpdateStatus()
EndFunc

; ===================================================================
; DAILY / MONTHLY CALENDAR  (very simple summary windows)
; ===================================================================
Func ShowDailyCalendar()
    Local $sDay = InputBox("Daily Calendar", "Enter date YYYYMMDD:", StringFormat("%04d%02d%02d", @YEAR, @MON, @MDAY))
    If @error Or $sDay = "" Then Return
    Local $msg = "Date: " & $sDay & @CRLF & "---" & @CRLF
    Local $n = 0
    For $r = 0 To $g_iRowCount - 1
        If $g_aRows[$r][10] = $sDay Then
            $msg &= $g_aRows[$r][11] & "  " & $g_aRows[$r][1] & "  (" & $g_aRows[$r][9] & ")  " & $g_aRows[$r][6] & @CRLF
            $n += 1
        EndIf
    Next
    If $n = 0 Then $msg &= "No entries."
    MsgBox(64, "Daily Calendar", $msg)
EndFunc

Func ShowMonthlyCalendar()
    Local $sMon = InputBox("Monthly Calendar", "Enter month YYYYMM:", StringFormat("%04d%02d", @YEAR, @MON))
    If @error Or $sMon = "" Then Return
    Local $msg = "Month: " & $sMon & @CRLF & "---" & @CRLF
    Local $n = 0
    For $r = 0 To $g_iRowCount - 1
        If StringLeft($g_aRows[$r][10], 6) = $sMon Then
            $msg &= $g_aRows[$r][10] & "  " & $g_aRows[$r][1] & "  (" & $g_aRows[$r][9] & ")" & @CRLF
            $n += 1
        EndIf
    Next
    If $n = 0 Then $msg &= "No entries."
    MsgBox(64, "Monthly Calendar", $msg)
EndFunc

; ===================================================================
; MAIN LOOP
; ===================================================================
LoadConfig()
LoadCacheToArray()
CreateMainGUI()
ApplyFilters()

; Hotkeys
HotKeySet("{F5}", "DoRefresh")

While 1
    Local $msg = GUIGetMsg()
    Switch $msg
        Case $GUI_EVENT_CLOSE, $g_idFExit
            ExitLoop

        Case $g_btnRefresh
            DoRefresh()

        Case $g_btnNewEnc
            DoNewEncounter()

        Case $g_btnNewPat
            DoNewPatient()

        Case $g_btnSearch
            SearchPatient()

        Case $g_btnCustom
            DoCustomSearch()

        Case $g_idFView
            ViewPatient()

        Case $g_idFSearch
            SearchPatient()

        Case $g_idFDaily
            ShowDailyCalendar()

        Case $g_idFMonth
            ShowMonthlyCalendar()

        Case $g_idEPCodes
            ShowProcedureCodes()

        Case $g_idESettings
            ShowSettings()

        Case $g_idHAbout
            MsgBox(64, "About", "RIS Worklist Client" & @CRLF & "AutoIt - matches WORKLIST-SERVER01")

        Case $g_hFilterEdits[0], $g_hFilterEdits[1], $g_hFilterEdits[2], _
             $g_hFilterEdits[3], $g_hFilterEdits[4], $g_hFilterEdits[5], _
             $g_hFilterEdits[6]
            ApplyFilters()
    EndSwitch
    Sleep(10)
WEnd

GUIDelete($g_hMain)
HotKeySet("{F5}")
Exit