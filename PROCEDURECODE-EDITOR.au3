#NoTrayIcon
;====================================================================
; ProcedureCodeEditor.au3
;
; BUILD / RUN INSTRUCTIONS:
;
; Run:
;   AutoIt3.exe ProcedureCodeEditor.au3
;
; Compile:
;   Aut2Exe.exe /in ProcedureCodeEditor.au3 /out ProcedureCodeEditor.exe
;
; Notes:
;   - INI file is saved next to script/exe using @ScriptName:
;       @ScriptDir & "\" & StringRegExpReplace(@ScriptName, "\.[^.]*$", "") & ".ini"
;   - Last opened file auto-loads.
;   - Default file is procedurecodes.csv next to script/exe.
;   - CSV first row is treated as column headers and is NOT inserted as data.
;   - Clicking a column header sorts data rows ascending; clicking same column toggles descending.
;   - Save writes current displayed order, so sorting/reordering becomes permanent in CSV.
;====================================================================

#include <GUIConstantsEx.au3>
#include <ListViewConstants.au3>
#include <WindowsConstants.au3>
#include <GuiListView.au3>
#include <Misc.au3>
#include <FileConstants.au3>
#include <StringConstants.au3>
#include <StructureConstants.au3>
#include <WinAPI.au3>

Opt("MustDeclareVars", 1)
Opt("GUICloseOnESC", 0)

;====================================================================
; Globals
;====================================================================

Global Const $APP = "Procedure Code Editor"
Global $INI = @ScriptDir & "\" & StringRegExpReplace(@ScriptName, "\.[^.]*$", "") & ".ini"
Global Const $DEFAULT_FILE = @ScriptDir & "\procedurecodes.csv"

Global Const $MAX_COLS = 64
Global Const $DEF_COLS = 4

Global Const $MIN_W = 700
Global Const $MIN_H = 380
Global Const $GAP = 10
Global Const $TOP_LABEL_H = 22
Global Const $BOTTOM_H = 42
Global Const $BTN_H = 28

; ListView insert mark message/flag for drag/drop.
;Global Const $LVM_SETINSERTMARK = 0x10A6
;Global Const $LVIM_AFTER = 1

Global $g_hGUI = 0
Global $g_idLV = 0
Global $g_hLV = 0
Global $g_idLblFile = 0

Global $btnBrowse = 0
Global $btnSave = 0
Global $btnAdd = 0
Global $btnDelete = 0
Global $btnUp = 0
Global $btnDown = 0
Global $chkDirect = 0

Global $g_cols = $DEF_COLS
Global $g_headers[$MAX_COLS]

Global $g_file = ""
Global $g_dirty = False
Global $g_directEdit = False
Global $g_columnWidthsLoaded = False

Global $editCtrl = 0
Global $editRow = -1
Global $editCol = -1

Global $g_sortCol = -1
Global $g_sortAsc = True

Global $g_dragging = False
Global $g_dragTarget = -1

;====================================================================
; Startup
;====================================================================

InitHeaders()
Main()
Exit

;====================================================================
; Main
;====================================================================

Func Main()
    Local $x = Number(IniRead($INI, "Window", "X", -1))
    Local $y = Number(IniRead($INI, "Window", "Y", -1))
    Local $w = Number(IniRead($INI, "Window", "W", 900))
    Local $h = Number(IniRead($INI, "Window", "H", 600))
    Local $maximized = IniRead($INI, "Window", "Maximized", "0")

    If $w < $MIN_W Then $w = 900
    If $h < $MIN_H Then $h = 600

    Local $posX = -1
    Local $posY = -1
    If $x >= 0 Then $posX = $x
    If $y >= 0 Then $posY = $y

    $g_directEdit = (IniRead($INI, "Settings", "DirectEdit", "0") = "1")

    $g_hGUI = GUICreate($APP, $w, $h, $posX, $posY, _
            BitOR($GUI_SS_DEFAULT_GUI, $WS_SIZEBOX, $WS_MAXIMIZEBOX, $WS_MINIMIZEBOX))

    $g_idLblFile = GUICtrlCreateLabel("", $GAP, $GAP, $w - ($GAP * 2), $TOP_LABEL_H, 0x1000)

    $g_idLV = GUICtrlCreateListView("", $GAP, $GAP + $TOP_LABEL_H + 4, _
            $w - ($GAP * 2), $h - $BOTTOM_H - $TOP_LABEL_H - ($GAP * 3), _
            BitOR($LVS_REPORT, $LVS_SHOWSELALWAYS), _
            BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES))
    $g_hLV = GUICtrlGetHandle($g_idLV)

    RebuildColumns()

    $btnBrowse = GUICtrlCreateButton("Browse", 0, 0, 80, $BTN_H)
    $btnSave = GUICtrlCreateButton("Save", 0, 0, 80, $BTN_H)
    $btnAdd = GUICtrlCreateButton("Add Row", 0, 0, 80, $BTN_H)
    $btnDelete = GUICtrlCreateButton("Delete Row", 0, 0, 80, $BTN_H)
    $btnUp = GUICtrlCreateButton("+", 0, 0, 40, $BTN_H)
    $btnDown = GUICtrlCreateButton("-", 0, 0, 40, $BTN_H)
    $chkDirect = GUICtrlCreateCheckbox("Direct Edit", 0, 0, 120, $BTN_H)

    If $g_directEdit Then
        GUICtrlSetState($chkDirect, $GUI_CHECKED)
    Else
        GUICtrlSetState($chkDirect, $GUI_UNCHECKED)
    EndIf

    GUIRegisterMsg($WM_NOTIFY, "WM_NOTIFY")
    GUIRegisterMsg($WM_SIZE, "WM_SIZE")
    GUIRegisterMsg($WM_MOUSEMOVE, "WM_MOUSEMOVE")
    GUIRegisterMsg($WM_LBUTTONUP, "WM_LBUTTONUP")

    LayoutControls()

    If $maximized = "1" Then
        GUISetState(@SW_SHOWMAXIMIZED, $g_hGUI)
    Else
        GUISetState(@SW_SHOW, $g_hGUI)
    EndIf

    LoadLastFile()

    Local $msg
    While 1
        $msg = GUIGetMsg()

        Switch $msg
            Case $GUI_EVENT_CLOSE
                EndInPlaceEdit(True)
                SaveAllSettings()
                GUIDelete($g_hGUI)
                Exit

            Case $btnBrowse
                EndInPlaceEdit(True)
                DoBrowse()

            Case $btnSave
                EndInPlaceEdit(True)
                DoSave()

            Case $btnAdd
                EndInPlaceEdit(True)
                AddRow()

            Case $btnDelete
                EndInPlaceEdit(True)
                DeleteRows()

            Case $btnUp
                EndInPlaceEdit(True)
                MoveRows(-1)

            Case $btnDown
                EndInPlaceEdit(True)
                MoveRows(1)

            Case $chkDirect
                $g_directEdit = (BitAND(GUICtrlRead($chkDirect), $GUI_CHECKED) = $GUI_CHECKED)
                IniWrite($INI, "Settings", "DirectEdit", $g_directEdit ? "1" : "0")
                If Not $g_directEdit Then EndInPlaceEdit(True)
        EndSwitch
    WEnd
EndFunc

;====================================================================
; Headers / columns
;====================================================================

Func InitHeaders()
    For $i = 0 To $MAX_COLS - 1
        $g_headers[$i] = ""
    Next

    $g_headers[0] = "Name"
    $g_headers[1] = "Desc"
    $g_headers[2] = "Cat"
    $g_headers[3] = "Notes"
EndFunc

Func RebuildColumns()
    Local $count = _GUICtrlListView_GetColumnCount($g_hLV)

    For $i = $count - 1 To 0 Step -1
        _GUICtrlListView_DeleteColumn($g_hLV, $i)
    Next

    For $i = 0 To $g_cols - 1
        If $g_headers[$i] = "" Then
            $g_headers[$i] = "Col" & ($i + 1)
        EndIf
        _GUICtrlListView_InsertColumn($g_hLV, $i, $g_headers[$i], 120)
    Next

    LoadColumnWidths()

    If Not $g_columnWidthsLoaded Then
        AutoSizeColumnsFiveToOne()
    EndIf
EndFunc

Func AutoSizeColumnsFiveToOne()
    If $g_cols <= 0 Then Return

    Local $size = WinGetClientSize($g_hLV)
    If @error Or Not IsArray($size) Then Return

    Local $width = $size[0] - 4
    If $width < 100 Then Return

    If $g_cols = 1 Then
        _GUICtrlListView_SetColumnWidth($g_hLV, 0, $width)
        Return
    EndIf

    ; First/Name column is 5x each other column.
    Local $weightTotal = 5 + ($g_cols - 1)
    Local $nameW = Int(($width * 5) / $weightTotal)
    Local $otherW = Int(($width - $nameW) / ($g_cols - 1))

    If $otherW < 40 Then $otherW = 40

    _GUICtrlListView_SetColumnWidth($g_hLV, 0, $nameW)

    For $i = 1 To $g_cols - 1
        _GUICtrlListView_SetColumnWidth($g_hLV, $i, $otherW)
    Next
EndFunc

Func SaveColumnWidths()
    IniWrite($INI, "Columns", "Count", $g_cols)

    For $i = 0 To $g_cols - 1
        IniWrite($INI, "Columns", "C" & $i, _GUICtrlListView_GetColumnWidth($g_hLV, $i))
    Next
EndFunc

Func LoadColumnWidths()
    $g_columnWidthsLoaded = False

    For $i = 0 To $g_cols - 1
        Local $cw = Number(IniRead($INI, "Columns", "C" & $i, -1))

        If $cw > 0 Then
            _GUICtrlListView_SetColumnWidth($g_hLV, $i, $cw)
            $g_columnWidthsLoaded = True
        EndIf
    Next
EndFunc

;====================================================================
; Window / INI settings
;====================================================================

Func SaveAllSettings()
    SaveColumnWidths()

    Local $isMax = 0
    If BitAND(WinGetState($g_hGUI), 32) Then $isMax = 1

    Local $pos = WinGetPos($g_hGUI)
    If IsArray($pos) Then
        IniWrite($INI, "Window", "X", $pos[0])
        IniWrite($INI, "Window", "Y", $pos[1])
        IniWrite($INI, "Window", "W", $pos[2])
        IniWrite($INI, "Window", "H", $pos[3])
    EndIf

    IniWrite($INI, "Window", "Maximized", $isMax)
    IniWrite($INI, "Settings", "DirectEdit", $g_directEdit ? "1" : "0")

    If $g_file <> "" Then
        IniWrite($INI, "Recent", "LastFile", $g_file)
    EndIf
EndFunc

;====================================================================
; File operations
;====================================================================

Func UpdateFileLabel()
    Local $label = "(no file)"

    If $g_file <> "" Then $label = $g_file
    If $g_dirty Then $label &= "  *"

    GUICtrlSetData($g_idLblFile, $label)
EndFunc

Func LoadLastFile()
    Local $last = IniRead($INI, "Recent", "LastFile", $DEFAULT_FILE)

    If FileExists($last) Then
        LoadCsv($last)
    Else
        $g_file = $last
        UpdateFileLabel()
    EndIf
EndFunc

Func DoBrowse()
    Local $file = FileOpenDialog("Open CSV", @ScriptDir, "CSV (*.csv)|All (*.*)", $FD_FILEMUSTEXIST)

    If @error Then Return

    LoadCsv($file)
EndFunc

Func DoSave()
    If $g_file = "" Then
        Local $file = FileSaveDialog("Save CSV", @ScriptDir, "CSV (*.csv)|All (*.*)", $FD_PROMPTOVERWRITE, "procedurecodes.csv")

        If @error Then Return

        If StringLower(StringRight($file, 4)) <> ".csv" Then
            $file &= ".csv"
        EndIf

        $g_file = $file
    EndIf

    SaveCsv($g_file)
EndFunc

Func LoadCsv($file)
    Local $fh = FileOpen($file, $FO_READ)
    If $fh = -1 Then Return

    Local $content = FileRead($fh)
    FileClose($fh)

    Local $normalized = StringReplace($content, @CRLF, @LF)
    $normalized = StringReplace($normalized, @CR, @LF)

    Local $lines = StringSplit($normalized, @LF, $STR_NOCOUNT)
    If Not IsArray($lines) Or UBound($lines) = 0 Then Return

    ; CSV first row is header only. It is never inserted as data.
    Local $headerFields = CSV_ParseLine($lines[0])
    Local $headerCount = UBound($headerFields)

    If $headerCount > $DEF_COLS Then
        $g_cols = $headerCount
    Else
        $g_cols = $DEF_COLS
    EndIf

    InitHeaders()

    For $i = 0 To $headerCount - 1
        If $i < $MAX_COLS Then
            If $headerFields[$i] <> "" Then $g_headers[$i] = $headerFields[$i]
        EndIf
    Next

    _GUICtrlListView_DeleteAllItems($g_hLV)
    RebuildColumns()

    For $r = 1 To UBound($lines) - 1
        If StringStripWS($lines[$r], 8) = "" Then ContinueLoop

        Local $fields = CSV_ParseLine($lines[$r])
        Local $row = _GUICtrlListView_AddItem($g_hLV, "")

        For $c = 0 To $g_cols - 1
            Local $val = ""
            If $c < UBound($fields) Then $val = $fields[$c]
            _GUICtrlListView_SetItemText($g_hLV, $row, $val, $c)
        Next
    Next

    $g_file = $file
    $g_dirty = False
    $g_sortCol = -1
    $g_sortAsc = True

    IniWrite($INI, "Recent", "LastFile", $g_file)
    UpdateFileLabel()
EndFunc

Func SaveCsv($file)
    Local $fh = FileOpen($file, $FO_OVERWRITE)
    If $fh = -1 Then Return

    ; Write header row from g_headers. Header is not overwritten by data.
    Local $line = ""
    For $c = 0 To $g_cols - 1
        If $c > 0 Then $line &= ","
        $line &= CSV_QuoteField($g_headers[$c])
    Next
    FileWriteLine($fh, $line)

    ; Write current ListView data order. Sorting/reordering becomes permanent here.
    Local $rows = _GUICtrlListView_GetItemCount($g_hLV)

    For $r = 0 To $rows - 1
        $line = ""

        For $c = 0 To $g_cols - 1
            If $c > 0 Then $line &= ","
            $line &= CSV_QuoteField(_GUICtrlListView_GetItemText($g_hLV, $r, $c))
        Next

        FileWriteLine($fh, $line)
    Next

    FileClose($fh)

    $g_file = $file
    $g_dirty = False

    IniWrite($INI, "Recent", "LastFile", $g_file)
    UpdateFileLabel()
EndFunc

;====================================================================
; CSV helpers
;====================================================================

Func CSV_ParseLine($line)
    Local $fields[0]
    Local $field = ""
    Local $inQuote = False
    Local $len = StringLen($line)
    Local $i = 1

    While $i <= $len
        Local $ch = StringMid($line, $i, 1)

        If $inQuote Then
            If $ch = '"' Then
                If $i < $len And StringMid($line, $i + 1, 1) = '"' Then
                    $field &= '"'
                    $i += 2
                    ContinueLoop
                Else
                    $inQuote = False
                    $i += 1
                    ContinueLoop
                EndIf
            Else
                $field &= $ch
                $i += 1
                ContinueLoop
            EndIf
        Else
            If $ch = '"' And $field = "" Then
                $inQuote = True
                $i += 1
                ContinueLoop
            EndIf

            If $ch = "," Then
                ReDim $fields[UBound($fields) + 1]
                $fields[UBound($fields) - 1] = $field
                $field = ""
                $i += 1
                ContinueLoop
            EndIf

            $field &= $ch
            $i += 1
        EndIf
    WEnd

    ReDim $fields[UBound($fields) + 1]
    $fields[UBound($fields) - 1] = $field

    Return $fields
EndFunc

Func CSV_QuoteField($text)
    If StringRegExp($text, '[,"\r\n]') Then
        $text = StringReplace($text, '"', '""')
        Return '"' & $text & '"'
    EndIf

    Return $text
EndFunc

;====================================================================
; Row functions
;====================================================================

Func AddRow()
    Local $row = _GUICtrlListView_AddItem($g_hLV, "")

    For $c = 1 To $g_cols - 1
        _GUICtrlListView_SetItemText($g_hLV, $row, "", $c)
    Next

    _GUICtrlListView_SetItemSelected($g_hLV, -1, False, False)
    _GUICtrlListView_SetItemSelected($g_hLV, $row, True, True)
    _GUICtrlListView_EnsureVisible($g_hLV, $row)

    $g_dirty = True
    UpdateFileLabel()
EndFunc

Func DeleteRows()
    Local $sel = _GUICtrlListView_GetSelectedIndices($g_hLV, True)
    If Not IsArray($sel) Or $sel[0] = 0 Then Return

    For $i = $sel[0] To 1 Step -1
        _GUICtrlListView_DeleteItem($g_hLV, $sel[$i])
    Next

    $g_dirty = True
    UpdateFileLabel()
EndFunc

Func MoveRows($dir)
    Local $sel = _GUICtrlListView_GetSelectedIndices($g_hLV, True)
    If Not IsArray($sel) Or $sel[0] = 0 Then Return

    If $dir < 0 Then
        If $sel[1] = 0 Then Return

        For $i = 1 To $sel[0]
            SwapRows($sel[$i], $sel[$i] - 1)
            $sel[$i] -= 1
        Next
    Else
        Local $count = _GUICtrlListView_GetItemCount($g_hLV)
        If $sel[$sel[0]] >= $count - 1 Then Return

        For $i = $sel[0] To 1 Step -1
            SwapRows($sel[$i], $sel[$i] + 1)
            $sel[$i] += 1
        Next
    EndIf

    _GUICtrlListView_SetItemSelected($g_hLV, -1, False, False)

    For $i = 1 To $sel[0]
        _GUICtrlListView_SetItemSelected($g_hLV, $sel[$i], True, ($i = 1))
    Next

    $g_dirty = True
    UpdateFileLabel()
EndFunc

Func SwapRows($r1, $r2)
    For $c = 0 To $g_cols - 1
        Local $tmp1 = _GUICtrlListView_GetItemText($g_hLV, $r1, $c)
        Local $tmp2 = _GUICtrlListView_GetItemText($g_hLV, $r2, $c)

        _GUICtrlListView_SetItemText($g_hLV, $r1, $tmp2, $c)
        _GUICtrlListView_SetItemText($g_hLV, $r2, $tmp1, $c)
    Next
EndFunc

Func GetSelectedRowsArray()
    Local $sel = _GUICtrlListView_GetSelectedIndices($g_hLV, True)
    Local $empty[0]

    If Not IsArray($sel) Or $sel[0] = 0 Then Return $empty

    Local $out[$sel[0]]

    For $i = 1 To $sel[0]
        $out[$i - 1] = $sel[$i]
    Next

    Return $out
EndFunc

Func ReorderSelectedRowsBefore($target)
    Local $count = _GUICtrlListView_GetItemCount($g_hLV)
    If $count <= 1 Then Return

    Local $selected = GetSelectedRowsArray()
    Local $n = UBound($selected)
    If $n = 0 Then Return

    If $target < 0 Then $target = 0
    If $target > $count Then $target = $count

    ; Dropping into selected block is a no-op.
    For $i = 0 To $n - 1
        If $target = $selected[$i] Or $target = ($selected[$i] + 1) Then
            Return
        EndIf
    Next

    Local $snap[$n][$g_cols]

    For $i = 0 To $n - 1
        For $c = 0 To $g_cols - 1
            $snap[$i][$c] = _GUICtrlListView_GetItemText($g_hLV, $selected[$i], $c)
        Next
    Next

    Local $adjusted = $target
    For $i = 0 To $n - 1
        If $selected[$i] < $target Then $adjusted -= 1
    Next

    If $adjusted < 0 Then $adjusted = 0

    For $i = $n - 1 To 0 Step -1
        _GUICtrlListView_DeleteItem($g_hLV, $selected[$i])
    Next

    Local $newCount = _GUICtrlListView_GetItemCount($g_hLV)
    If $adjusted > $newCount Then $adjusted = $newCount

    For $i = 0 To $n - 1
        Local $row = _GUICtrlListView_InsertItem($g_hLV, "", $adjusted + $i)

        For $c = 0 To $g_cols - 1
            _GUICtrlListView_SetItemText($g_hLV, $row, $snap[$i][$c], $c)
        Next
    Next

    _GUICtrlListView_SetItemSelected($g_hLV, -1, False, False)

    For $i = 0 To $n - 1
        _GUICtrlListView_SetItemSelected($g_hLV, $adjusted + $i, True, ($i = 0))
    Next

    _GUICtrlListView_EnsureVisible($g_hLV, $adjusted)

    $g_dirty = True
    UpdateFileLabel()
EndFunc

;====================================================================
; Sorting
;====================================================================

Func SortByColumn($col)
    If $col < 0 Or $col >= $g_cols Then Return

    If $g_sortCol = $col Then
        $g_sortAsc = Not $g_sortAsc
    Else
        $g_sortCol = $col
        $g_sortAsc = True
    EndIf

    Local $rows = _GUICtrlListView_GetItemCount($g_hLV)
    If $rows <= 1 Then Return

    Local $data[$rows][$g_cols]

    For $r = 0 To $rows - 1
        For $c = 0 To $g_cols - 1
            $data[$r][$c] = _GUICtrlListView_GetItemText($g_hLV, $r, $c)
        Next
    Next

    ; Simple stable-ish bubble sort. Fine for modest procedure-code CSVs.
    For $i = 0 To $rows - 2
        For $j = $i + 1 To $rows - 1
            Local $a = StringLower($data[$i][$col])
            Local $b = StringLower($data[$j][$col])
            Local $swap = False

            If $g_sortAsc Then
                If $a > $b Then $swap = True
            Else
                If $a < $b Then $swap = True
            EndIf

            If $swap Then
                For $c = 0 To $g_cols - 1
                    Local $tmp = $data[$i][$c]
                    $data[$i][$c] = $data[$j][$c]
                    $data[$j][$c] = $tmp
                Next
            EndIf
        Next
    Next

    _GUICtrlListView_DeleteAllItems($g_hLV)

    For $r = 0 To $rows - 1
        Local $row = _GUICtrlListView_AddItem($g_hLV, $data[$r][0])

        For $c = 1 To $g_cols - 1
            _GUICtrlListView_SetItemText($g_hLV, $row, $data[$r][$c], $c)
        Next
    Next

    $g_dirty = True
    UpdateFileLabel()
EndFunc

;====================================================================
; Layout / resize
;====================================================================

Func LayoutControls()
    Local $size = WinGetClientSize($g_hGUI)
    If @error Or Not IsArray($size) Then Return

    Local $w = $size[0]
    Local $h = $size[1]

    If $w < $MIN_W Then $w = $MIN_W
    If $h < $MIN_H Then $h = $MIN_H

    GUICtrlSetPos($g_idLblFile, $GAP, $GAP, $w - ($GAP * 2), $TOP_LABEL_H)

    Local $lvY = $GAP + $TOP_LABEL_H + 4
    Local $lvH = $h - $lvY - $BOTTOM_H - $GAP
    If $lvH < 80 Then $lvH = 80

    GUICtrlSetPos($g_idLV, $GAP, $lvY, $w - ($GAP * 2), $lvH)

    Local $btnY = $h - $BOTTOM_H + Int(($BOTTOM_H - $BTN_H) / 2)
    Local $btnCount = 6
    Local $chkW = 120
    Local $available = $w - ($GAP * 2) - $chkW - $GAP
    Local $btnW = Int(($available - (($btnCount - 1) * $GAP)) / $btnCount)

    If $btnW < 65 Then $btnW = 65

    Local $x = $GAP

    GUICtrlSetPos($btnBrowse, $x, $btnY, $btnW, $BTN_H)
    $x += $btnW + $GAP

    GUICtrlSetPos($btnSave, $x, $btnY, $btnW, $BTN_H)
    $x += $btnW + $GAP

    GUICtrlSetPos($btnAdd, $x, $btnY, $btnW, $BTN_H)
    $x += $btnW + $GAP

    GUICtrlSetPos($btnDelete, $x, $btnY, $btnW, $BTN_H)
    $x += $btnW + $GAP

    GUICtrlSetPos($btnUp, $x, $btnY, $btnW, $BTN_H)
    $x += $btnW + $GAP

    GUICtrlSetPos($btnDown, $x, $btnY, $btnW, $BTN_H)

    GUICtrlSetPos($chkDirect, $w - $GAP - $chkW, $btnY, $chkW, $BTN_H)
EndFunc

Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    If $hWnd = $g_hGUI Then LayoutControls()
    Return $GUI_RUNDEFMSG
EndFunc

;====================================================================
; Notify handling: double-click, header sort, drag start
;====================================================================

Func WM_NOTIFY($hWnd, $msg, $wParam, $lParam)
    Local $hdr = DllStructCreate($tagNMHDR, $lParam)

    If DllStructGetData($hdr, "hWndFrom") <> $g_hLV Then
        Return $GUI_RUNDEFMSG
    EndIf

    Local $code = DllStructGetData($hdr, "Code")

    Switch $code
        Case $NM_DBLCLK
            Local $info = DllStructCreate($tagNMITEMACTIVATE, $lParam)
            Local $row = DllStructGetData($info, "Index")
            Local $col = DllStructGetData($info, "SubItem")

            If $row < 0 Then Return $GUI_RUNDEFMSG
            If $col < 0 Then $col = 0

            If GUICtrlRead($chkDirect) = $GUI_CHECKED Then
                StartInPlaceEdit($row, $col)
            Else
                ShowEditDialog($row)
            EndIf

        Case $LVN_COLUMNCLICK
            Local $lv = DllStructCreate($tagNMLISTVIEW, $lParam)
            Local $colClicked = DllStructGetData($lv, "SubItem")
            SortByColumn($colClicked)

        Case $LVN_BEGINDRAG
            If _GUICtrlListView_GetSelectedCount($g_hLV) > 0 Then
                $g_dragging = True
                $g_dragTarget = -1
                _WinAPI_SetCapture($g_hGUI)
                DrawInsertMark(-1)
            EndIf
    EndSwitch

    Return $GUI_RUNDEFMSG
EndFunc

;====================================================================
; Drag/drop reorder
;====================================================================

Func WM_MOUSEMOVE($hWnd, $iMsg, $wParam, $lParam)
    If Not $g_dragging Then Return $GUI_RUNDEFMSG

    Local $mx = BitAND($lParam, 0xFFFF)
    Local $my = BitShift(BitAND($lParam, 0xFFFF0000), 16)

    Local $lvPos = ControlGetPos($g_hGUI, "", $g_idLV)
    If Not IsArray($lvPos) Then Return $GUI_RUNDEFMSG

    Local $lvX = $mx - $lvPos[0]
    Local $lvY = $my - $lvPos[1]

    $g_dragTarget = ComputeDragTarget($lvX, $lvY)
    DrawInsertMark($g_dragTarget)

    Return $GUI_RUNDEFMSG
EndFunc

Func WM_LBUTTONUP($hWnd, $iMsg, $wParam, $lParam)
    If $g_dragging Then
        $g_dragging = False
        _WinAPI_ReleaseCapture()
        DrawInsertMark(-1)

        If $g_dragTarget >= 0 Then
            ReorderSelectedRowsBefore($g_dragTarget)
        EndIf

        $g_dragTarget = -1
    EndIf

    Return $GUI_RUNDEFMSG
EndFunc

Func ComputeDragTarget($x, $y)
    Local $count = _GUICtrlListView_GetItemCount($g_hLV)
    If $count = 0 Then Return 0

    Local $hit = _GUICtrlListView_HitTest($g_hLV, $x, $y)

    If IsArray($hit) Then
        $hit = $hit[0]
    EndIf

    If $hit < 0 Then
        Local $lastRect = _GUICtrlListView_GetItemRect($g_hLV, $count - 1)

        If IsArray($lastRect) Then
            If $y >= $lastRect[3] Then Return $count
        EndIf

        Return 0
    EndIf

    Local $rect = _GUICtrlListView_GetItemRect($g_hLV, $hit)
    If Not IsArray($rect) Then Return $hit

    Local $mid = Int(($rect[1] + $rect[3]) / 2)

    If $y < $mid Then
        Return $hit
    EndIf

    Return $hit + 1
EndFunc

Func DrawInsertMark($target)
    Local $t = DllStructCreate("dword cbSize;dword dwFlags;int iItem;dword dwReserved")
    DllStructSetData($t, "cbSize", DllStructGetSize($t))

    If $target < 0 Then
        DllStructSetData($t, "iItem", -1)
        DllStructSetData($t, "dwFlags", 0)
    Else
        Local $count = _GUICtrlListView_GetItemCount($g_hLV)

        If $count <= 0 Then
            DllStructSetData($t, "iItem", -1)
            DllStructSetData($t, "dwFlags", 0)
        ElseIf $target >= $count Then
            DllStructSetData($t, "iItem", $count - 1)
            DllStructSetData($t, "dwFlags", $LVIM_AFTER)
        Else
            DllStructSetData($t, "iItem", $target)
            DllStructSetData($t, "dwFlags", 0)
        EndIf
    EndIf

    _SendMessage($g_hLV, $LVM_SETINSERTMARK, 0, DllStructGetPtr($t))
EndFunc

;====================================================================
; Direct edit / edit window
;====================================================================

Func StartInPlaceEdit($row, $col)
    EndInPlaceEdit(True)

    Local $rect = _GUICtrlListView_GetSubItemRect($g_hLV, $row, $col)
    If Not IsArray($rect) Then Return

    Local $lvPos = ControlGetPos($g_hGUI, "", $g_idLV)
    If Not IsArray($lvPos) Then Return

    Local $x = $lvPos[0] + $rect[0]
    Local $y = $lvPos[1] + $rect[1]
    Local $width = $rect[2] - $rect[0]
    Local $height = $rect[3] - $rect[1]

    If $width < 40 Then $width = 80
    If $height < 18 Then $height = 22

    Local $text = _GUICtrlListView_GetItemText($g_hLV, $row, $col)

    $editCtrl = GUICtrlCreateInput($text, $x, $y, $width, $height)
    GUICtrlSetState($editCtrl, $GUI_FOCUS)

    $editRow = $row
    $editCol = $col

    While $editCtrl <> 0
        Local $msg = GUIGetMsg()

        Switch $msg
            Case $GUI_EVENT_CLOSE
                EndInPlaceEdit(True)
                SaveAllSettings()
                Exit

            Case $btnBrowse, $btnSave, $btnAdd, $btnDelete, $btnUp, $btnDown
                EndInPlaceEdit(True)

                Switch $msg
                    Case $btnBrowse
                        DoBrowse()
                    Case $btnSave
                        DoSave()
                    Case $btnAdd
                        AddRow()
                    Case $btnDelete
                        DeleteRows()
                    Case $btnUp
                        MoveRows(-1)
                    Case $btnDown
                        MoveRows(1)
                EndSwitch

                ExitLoop
        EndSwitch

        If _IsPressed("0D") Then
            EndInPlaceEdit(True)
            ExitLoop
        EndIf

        If _IsPressed("1B") Then
            EndInPlaceEdit(False)
            ExitLoop
        EndIf

        Sleep(10)
    WEnd
EndFunc

Func EndInPlaceEdit($save)
    If $editCtrl = 0 Then Return

    If $save Then
        _GUICtrlListView_SetItemText($g_hLV, $editRow, GUICtrlRead($editCtrl), $editCol)
        $g_dirty = True
        UpdateFileLabel()
    EndIf

    GUICtrlDelete($editCtrl)
    $editCtrl = 0
    $editRow = -1
    $editCol = -1
EndFunc

Func ShowEditDialog($row)
    Local $dlgH = 90 + ($g_cols * 32)

    If $dlgH < 220 Then $dlgH = 220
    If $dlgH > 720 Then $dlgH = 720

    Local $dlg = GUICreate("Edit Row", 620, $dlgH, -1, -1, _
            BitOR($WS_CAPTION, $WS_SYSMENU, $WS_SIZEBOX), -1, $g_hGUI)

    Local $inputs[$MAX_COLS]
    For $i = 0 To $MAX_COLS - 1
        $inputs[$i] = 0
    Next

    Local $labelW = 140
    Local $inputX = 160
    Local $inputW = 430
    Local $y = 14

    For $c = 0 To $g_cols - 1
        GUICtrlCreateLabel($g_headers[$c], 12, $y + 4, $labelW, 20)
        $inputs[$c] = GUICtrlCreateInput(_GUICtrlListView_GetItemText($g_hLV, $row, $c), $inputX, $y, $inputW, 24)
        $y += 32
    Next

    Local $btnDlgSave = GUICtrlCreateButton("Save", 390, $dlgH - 42, 90, 28)
    Local $btnDlgClose = GUICtrlCreateButton("Close", 500, $dlgH - 42, 90, 28)

    GUISetState(@SW_SHOW, $dlg)

    While 1
        Local $msg = GUIGetMsg(1)
        If Not IsArray($msg) Then ContinueLoop

        If $msg[1] = $dlg Then
            Switch $msg[0]
                Case $GUI_EVENT_CLOSE, $btnDlgClose
                    GUIDelete($dlg)
                    Return

                Case $btnDlgSave
                    For $c = 0 To $g_cols - 1
                        _GUICtrlListView_SetItemText($g_hLV, $row, GUICtrlRead($inputs[$c]), $c)
                    Next

                    $g_dirty = True
                    UpdateFileLabel()
            EndSwitch
        ElseIf $msg[1] = $g_hGUI Then
            Switch $msg[0]
                Case $GUI_EVENT_CLOSE
                    GUIDelete($dlg)
                    SaveAllSettings()
                    Exit
            EndSwitch
        EndIf

        Sleep(10)
    WEnd
EndFunc