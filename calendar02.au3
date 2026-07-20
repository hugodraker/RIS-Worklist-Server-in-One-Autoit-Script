#include-once
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <ComboConstants.au3>
#include <GUIScrollBars.au3>
#include <ScrollBarConstants.au3>
#include <WinAPI.au3>
#include <Array.au3>

; ==============================================================================
; MODERN CALENDAR PALETTE & CONSTANTS
; ==============================================================================
Global Const $CAL_COL_BG_EVEN   = 0xFFFFFF ; Pure White
Global Const $CAL_COL_BG_ODD    = 0xF8FAFC ; Soft Slate Zebra Stripe
Global Const $CAL_COL_GRID      = 0xE2E8F0 ; Subtle Horizontal Gridline
Global Const $CAL_COL_GRID_VERT = 0xCBD5E1 ; Distinct Vertical Axis Divider
Global Const $CAL_COL_HEADER_BG = 0xF1F5F9 ; Header Background
Global Const $CAL_COL_HEADER_TX = 0x1E293B ; Header Text Dark Slate
Global Const $CAL_COL_TIME_TX   = 0x475569 ; Muted Time Label Text
Global Const $CAL_COL_TEXT_W    = 0xFFFFFF ; Crisp White Event Text

; Tailwind-Inspired Medical Vibrant Palette
Global Const $CAL_COL_GREEN  = 0x10B981 ; Emerald (Day Routine)
Global Const $CAL_COL_BLUE   = 0x3B82F6 ; Royal Blue (Standard MRI/CT)
Global Const $CAL_COL_AMBER  = 0xF59E0B ; Amber (On-Call / Standby)
Global Const $CAL_COL_PURPLE = 0x8B5CF6 ; Violet (Oncology / PET/CT)
Global Const $CAL_COL_ROSE   = 0xF43F5E ; Rose (ER / Urgent Trauma)
Global Const $CAL_COL_GREY   = 0x64748B ; Slate (Setup / QC / Lunch)

; ==============================================================================
; EMBEDDED CSV SCHEDULE DATA
; ==============================================================================
Global $sCalCSVData = _
    "Section,Col1,Col2,Col3,Col4,Col5,Col6,Col7,Col8" & @CRLF & _
    "SCHEDULE,20241205,08:00,08:30,Setup / QC Calibration,System Warmup & Diagnostics,Tech Team,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE,20241205,08:30,09:30,Jane Doe,ID:883491 - CT Chest w/ Contrast,Mike B. - Day,Scan Rm 1,CT,0x10B981" & @CRLF & _
    "SCHEDULE,20241205,09:30,10:00,Room Sterile Prep,Sanitization Protocol,Support Staff,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE,20241205,10:00,11:00,Emily White,ID:445666 - CT Abdomen/Pelvis,Mike B. - Day,Scan Rm 1,CT,0x10B981" & @CRLF & _
    "SCHEDULE,20241205,10:30,11:30,Robert Johnson,ID:991234 - MRI Brain Sport Protocol,Sarah J. - Day,MRI Suite A,MRI,0x3B82F6" & @CRLF & _
    "SCHEDULE,20241205,11:00,12:00,MRI Emergency Backup,Trauma Standby Slot,Sarah J. - Day,Scan Rm 1,CT,0xF59E0B" & @CRLF & _
    "SCHEDULE,20241205,12:00,13:00,Department Lunch Break,Shift Handoff & Review,All Techs,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE,20241205,13:00,15:00,John Smith,ID:112233 - CT Head Advanced 3D,Mike B. - Day,Scan Rm 1,CT,0x10B981" & @CRLF & _
    "SCHEDULE,20241205,14:00,15:30,Alice Williams,ID:774829 - PET/CT Oncology Scan,Dr. Patel / Mike B.,Scan Rm 2,PET/CT,0x8B5CF6" & @CRLF & _
    "SCHEDULE,20241205,15:00,16:00,Mike B. / Sarah J.,Shift Overlap & Joint QC,Mike B. / Sarah J.,Scan Rm 1,CT,0x10B981" & @CRLF & _
    "SCHEDULE,20241205,16:00,16:30,John Davis,ID:332111 - ER Trauma CT Spine,Mike B. - On Call,Scan Rm 1,CT,0xF43F5E" & @CRLF & _
    "SCHEDULE,20241205,16:30,17:00,Night Coverage Transition,Equipment Warmup,Sarah L. - Night,Scan Rm 1,CT,0x3B82F6" & @CRLF & _
    "SCHEDULE,20241205,17:00,18:00,Evening Emergency Block,ICU Priority Scanning,Sarah L. - Night,Scan Rm 1,CT,0xF43F5E" & @CRLF & _
    "SCHEDULE,20241205,18:00,19:00,Continuous System Cycle,Automated Diagnostics,Unattended,Scan Rm 1,CT,0x64748B"

; Array Schema: [0]Date, [1]Start, [2]End, [3]Patient/Event, [4]Details, [5]Tech, [6]Room, [7]Modality, [8]ColorHex, [9]ControlID
Global $aCalSchedule[150][10], $iCalScheduleCount = 0
Global $aCalGridLines[500], $iCalGridCount = 0
Global $iCalLastClickedRow = -1, $hCalLastClickTimer = 0
Global $iCalScrollY = 0, $iCalScrollX = 0, $iCalTotalGridHeight = 800

Global $g_hCalGUI = 0, $g_hMainParentGUI = 0, $g_lblOverviewTarget = 0

; ==============================================================================
; INITIALIZATION & PARSING
; ==============================================================================
Func _Calendar_Init($hWndCalendar, $hWndParent, $lblOverview = 0)
    $g_hCalGUI = $hWndCalendar
    $g_hMainParentGUI = $hWndParent
    $g_lblOverviewTarget = $lblOverview

    ; Parse CSV Data
    Local $aRows = StringSplit(StringStripCR($sCalCSVData), @LF)
    For $i = 1 To $aRows[0]
        If StringStripWS($aRows[$i], 8) = "" Or StringLeft($aRows[$i], 7) = "Section" Then ContinueLoop
        Local $aCols = StringSplit($aRows[$i], ",")
        If $aCols[1] = "SCHEDULE" And $iCalScheduleCount < 150 Then
            $aCalSchedule[$iCalScheduleCount][0] = ($aCols[0] >= 2) ? $aCols[2] : ""
            $aCalSchedule[$iCalScheduleCount][1] = ($aCols[0] >= 3) ? $aCols[3] : ""
            $aCalSchedule[$iCalScheduleCount][2] = ($aCols[0] >= 4) ? $aCols[4] : ""
            $aCalSchedule[$iCalScheduleCount][3] = ($aCols[0] >= 5) ? $aCols[5] : ""
            $aCalSchedule[$iCalScheduleCount][4] = ($aCols[0] >= 6) ? $aCols[6] : ""
            $aCalSchedule[$iCalScheduleCount][5] = ($aCols[0] >= 7) ? $aCols[7] : ""
            $aCalSchedule[$iCalScheduleCount][6] = ($aCols[0] >= 8) ? $aCols[8] : "Scan Rm 1"
            $aCalSchedule[$iCalScheduleCount][7] = ($aCols[0] >= 9) ? $aCols[9] : "CT"
            $aCalSchedule[$iCalScheduleCount][8] = ($aCols[0] >= 10) ? $aCols[10] : "0x10B981"
            $iCalScheduleCount += 1
        EndIf
    Next

    GUISwitch($g_hCalGUI)

    ; Sleek Sticky Header
    GUICtrlCreateLabel("TIME", 0, 0, 75, 34, BitOR($SS_CENTER, $SS_CENTERIMAGE))
    GUICtrlSetBkColor(-1, $CAL_COL_HEADER_BG)
    GUICtrlSetColor(-1, $CAL_COL_HEADER_TX)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")

    GUICtrlCreateLabel("  SCHEDULE TIMELINE & ASSIGNED TECHNICAL COVERAGE", 76, 0, 1500, 34, $SS_CENTERIMAGE)
    GUICtrlSetBkColor(-1, $CAL_COL_HEADER_BG)
    GUICtrlSetColor(-1, $CAL_COL_HEADER_TX)
    GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")

    ; Header Horizontal Border
    GUICtrlCreateLabel("", 0, 34, 1500, 1)
    GUICtrlSetBkColor(-1, $CAL_COL_GRID_VERT)

    _Calendar_Render()

    ; Initialize Native Auto-Scrollbars
    _GUIScrollBars_Init($g_hCalGUI)
    _GUIScrollBars_SetScrollInfoMax($g_hCalGUI, $SB_VERT, $iCalTotalGridHeight)
    _GUIScrollBars_SetScrollInfoMax($g_hCalGUI, $SB_HORZ, 1100)
    _GUIScrollBars_ShowScrollBar($g_hCalGUI, $SB_VERT, True)
    _GUIScrollBars_ShowScrollBar($g_hCalGUI, $SB_HORZ, True)

    GUIRegisterMsg($WM_VSCROLL, "_Calendar_WM_VSCROLL")
    GUIRegisterMsg($WM_HSCROLL, "_Calendar_WM_HSCROLL")
    GUIRegisterMsg($WM_MOUSEWHEEL, "_Calendar_WM_MOUSEWHEEL")
EndFunc

; ==============================================================================
; RENDERING THE SCHEDULE GRID & GRIDLINES
; ==============================================================================
Func _Calendar_Render()
    GUISwitch($g_hCalGUI)
    
    ; 1. Clean up existing event blocks and grid controls to prevent GDI leaks
    For $i = 0 To $iCalScheduleCount - 1
        If $aCalSchedule[$i][9] <> 0 Then
            GUICtrlDelete($aCalSchedule[$i][9])
            $aCalSchedule[$i][9] = 0
        EndIf
    Next
    For $i = 0 To $iCalGridCount - 1
        If $aCalGridLines[$i] <> 0 Then GUICtrlDelete($aCalGridLines[$i])
    Next
    $iCalGridCount = 0
    
    Local $iRowH = 54 ; Taller rows for better breathing room
    Local $iStartY = 35
    
    ; 2. Render Row Backgrounds, Zebra Striping, Gridlines & Time Labels
    For $i = 0 To $iCalScheduleCount - 1
        Local $iY = $iStartY + ($i * $iRowH)
        Local $iRowBg = (Mod($i, 2) == 0) ? $CAL_COL_BG_EVEN : $CAL_COL_BG_ODD
        
        ; Time Slot Label (Left Column)
        Local $hTime = GUICtrlCreateLabel($aCalSchedule[$i][1], 0, $iY, 75, $iRowH, BitOR($SS_CENTER, $SS_CENTERIMAGE))
        GUICtrlSetBkColor($hTime, $iRowBg)
        GUICtrlSetColor($hTime, $CAL_COL_TIME_TX)
        GUICtrlSetFont($hTime, 9.5, 600, 0, "Segoe UI")
        _AddGridCtrl($hTime)
        
        ; Row Background Track (Right Column)
        Local $hTrack = GUICtrlCreateLabel("", 76, $iY, 1424, $iRowH)
        GUICtrlSetBkColor($hTrack, $iRowBg)
        GUICtrlSetState($hTrack, $GUI_DISABLE) ; Disabled so clicks pass through to child events if needed
        _AddGridCtrl($hTrack)
        
        ; Horizontal Bottom Gridline
        Local $hGridH = GUICtrlCreateLabel("", 0, $iY + $iRowH - 1, 1500, 1)
        GUICtrlSetBkColor($hGridH, $CAL_COL_GRID)
        _AddGridCtrl($hGridH)
    Next
    
    $iCalTotalGridHeight = $iStartY + ($iCalScheduleCount * $iRowH) + 60
    
    ; 3. Render Continuous Vertical Axis Gridline
    Local $hGridV = GUICtrlCreateLabel("", 75, $iStartY, 1, $iCalTotalGridHeight)
    GUICtrlSetBkColor($hGridV, $CAL_COL_GRID_VERT)
    _AddGridCtrl($hGridV)
    
    ; 4. Render Inset "Card Style" Event Blocks ON TOP of Gridlines
    For $i = 0 To $iCalScheduleCount - 1
        Local $iY = $iStartY + ($i * $iRowH)
        
        ; Modern Two-Line Layout with Bullet/Status indicator
        Local $sText = "   " & $aCalSchedule[$i][3] & "   |   " & $aCalSchedule[$i][7] & " (" & $aCalSchedule[$i][6] & ")"
        If $aCalSchedule[$i][4] <> "" Then $sText &= @CRLF & "   " & $aCalSchedule[$i][4]
        If $aCalSchedule[$i][5] <> "" Then $sText &= "  •  Lead: " & $aCalSchedule[$i][5]
        
        ; Inset by 5px top/bottom and left/right for a modern floating card look
        Local $hBlock = GUICtrlCreateLabel($sText, 85, $iY + 5, 960, $iRowH - 11)
        GUICtrlSetBkColor($hBlock, Execute($aCalSchedule[$i][8]))
        GUICtrlSetColor($hBlock, $CAL_COL_TEXT_W)
        GUICtrlSetFont($hBlock, 9, 600, 0, "Segoe UI")
        
        $aCalSchedule[$i][9] = $hBlock
    Next
    
    If $g_hCalGUI Then _GUIScrollBars_SetScrollInfoMax($g_hCalGUI, $SB_VERT, $iCalTotalGridHeight)
EndFunc

Func _AddGridCtrl($hCtrl)
    If $iCalGridCount < 500 Then
        $aCalGridLines[$iCalGridCount] = $hCtrl
        $iCalGridCount += 1
    EndIf
EndFunc

; ==============================================================================
; RESIZE & EVENT HANDLING
; ==============================================================================
Func _Calendar_Resize($iW, $iH)
    If Not $g_hCalGUI Then Return
    _GUIScrollBars_SetScrollInfoPage($g_hCalGUI, $SB_VERT, $iH)
    _GUIScrollBars_SetScrollInfoPage($g_hCalGUI, $SB_HORZ, $iW)
EndFunc

Func _Calendar_HandleClick($iMsg)
    If $iMsg <= 0 Then Return False
    For $i = 0 To $iCalScheduleCount - 1
        If $iMsg == $aCalSchedule[$i][9] Then
            If TimerDiff($hCalLastClickTimer) < 400 And $iCalLastClickedRow == $i Then
                $hCalLastClickTimer = 0
                _Calendar_EditDialog($i)
            Else
                $iCalLastClickedRow = $i
                $hCalLastClickTimer = TimerInit()
                _Calendar_UpdateOverview($i)
            EndIf
            Return True
        EndIf
    Next
    Return False
EndFunc

Func _Calendar_UpdateOverview($iRow)
    If Not $g_lblOverviewTarget Then Return
    Local $sInfo = "PATIENT / EVENT:" & @CRLF & "? " & $aCalSchedule[$iRow][3] & @CRLF & @CRLF & _
                   "EXAM DETAILS:" & @CRLF & "• " & ($aCalSchedule[$iRow][4] = "" ? "N/A" : $aCalSchedule[$iRow][4]) & @CRLF & @CRLF & _
                   "ASSIGNED TECH:" & @CRLF & "• " & $aCalSchedule[$iRow][5] & @CRLF & @CRLF & _
                   "LOCATION:" & @CRLF & "• " & $aCalSchedule[$iRow][6] & " (" & $aCalSchedule[$iRow][7] & ")" & @CRLF & @CRLF & _
                   "SCHEDULED TIME:" & @CRLF & "• " & $aCalSchedule[$iRow][1] & " - " & $aCalSchedule[$iRow][2] & @CRLF & @CRLF & _
                   "-----------------------------------" & @CRLF & _
                   "[Double-Click card to edit event]"
    GUICtrlSetData($g_lblOverviewTarget, $sInfo)
EndFunc

; ==============================================================================
; MODERN EDIT EVENT DIALOG
; ==============================================================================
Func _Calendar_EditDialog($iRow)
    GUISetState(@SW_DISABLE, $g_hMainParentGUI)
    Local $hEditGUI = GUICreate("Edit Schedule Event - " & $aCalSchedule[$iRow][3], 460, 440, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), -1, $g_hMainParentGUI)
    GUISetBkColor(0xF8FAFC, $hEditGUI)
    
    GUICtrlCreateLabel("PATIENT / EVENT NAME", 25, 20, 200, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInPatient = GUICtrlCreateInput($aCalSchedule[$iRow][3], 25, 40, 410, 28)
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("CLINICAL DETAILS / ID", 25, 80, 200, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInDetails = GUICtrlCreateInput($aCalSchedule[$iRow][4], 25, 100, 410, 28)
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("ASSIGNED TECHNICIAN / ROLE", 25, 140, 250, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInTech = GUICtrlCreateInput($aCalSchedule[$iRow][5], 25, 160, 410, 28)
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("START TIME", 25, 200, 80, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInStart = GUICtrlCreateInput($aCalSchedule[$iRow][1], 25, 220, 95, 28)
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("END TIME", 135, 200, 80, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInEnd   = GUICtrlCreateInput($aCalSchedule[$iRow][2], 135, 220, 95, 28)
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("ROOM / SUITE", 250, 200, 100, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInRoom  = GUICtrlCreateCombo($aCalSchedule[$iRow][6], 250, 220, 185, 28, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hInRoom, "Scan Rm 1|Scan Rm 2|MRI Suite A|MRI Suite B|X-Ray Room 1", $aCalSchedule[$iRow][6])
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("MODALITY", 25, 265, 80, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInModal = GUICtrlCreateCombo($aCalSchedule[$iRow][7], 25, 285, 160, 28, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hInModal, "CT|MRI|PET/CT|X-Ray|Ultrasound", $aCalSchedule[$iRow][7])
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    GUICtrlCreateLabel("COLOR THEME", 200, 265, 120, 18)
    GUICtrlSetFont(-1, 8.5, 700, 0, "Segoe UI")
    GUICtrlSetColor(-1, 0x475569)
    Local $hInColor = GUICtrlCreateCombo("", 200, 285, 235, 28, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hInColor, "Emerald (Day Routine)|Royal Blue (MRI/CT)|Amber (Standby/Call)|Violet (Oncology/PET)|Rose (ER/Urgent)|Slate (Setup/Break)", "Emerald (Day Routine)")
    GUICtrlSetFont(-1, 9.5, 400, 0, "Segoe UI")
    
    Local $hBtnSave   = GUICtrlCreateButton("Save Changes", 45, 360, 140, 36)
    GUICtrlSetFont($hBtnSave, 9.5, 700, 0, "Segoe UI")
    GUICtrlSetBkColor($hBtnSave, 0x10B981)
    
    Local $hBtnDelete = GUICtrlCreateButton("Delete", 200, 360, 110, 36)
    GUICtrlSetFont($hBtnDelete, 9.5, 600, 0, "Segoe UI")
    
    Local $hBtnCancel = GUICtrlCreateButton("Cancel", 325, 360, 90, 36)
    GUICtrlSetFont($hBtnCancel, 9.5, 400, 0, "Segoe UI")
    
    GUISetState(@SW_SHOW, $hEditGUI)
    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE, $hBtnCancel
                ExitLoop
            Case $hBtnDelete
                If MsgBox(36, "Confirm Delete", "Permanently remove this scheduled event?") == 6 Then
                    For $j = $iRow To $iCalScheduleCount - 2
                        For $c = 0 To 8
                            $aCalSchedule[$j][$c] = $aCalSchedule[$j + 1][$c]
                        Next
                    Next
                    $iCalScheduleCount -= 1
                    ExitLoop
                EndIf
            Case $hBtnSave
                $aCalSchedule[$iRow][3] = GUICtrlRead($hInPatient)
                $aCalSchedule[$iRow][4] = GUICtrlRead($hInDetails)
                $aCalSchedule[$iRow][5] = GUICtrlRead($hInTech)
                $aCalSchedule[$iRow][1] = GUICtrlRead($hInStart)
                $aCalSchedule[$iRow][2] = GUICtrlRead($hInEnd)
                $aCalSchedule[$iRow][6] = GUICtrlRead($hInRoom)
                $aCalSchedule[$iRow][7] = GUICtrlRead($hInModal)
                
                Local $sColChoice = GUICtrlRead($hInColor)
                If StringInStr($sColChoice, "Emerald") Then $aCalSchedule[$iRow][8] = "0x10B981"
                If StringInStr($sColChoice, "Blue")    Then $aCalSchedule[$iRow][8] = "0x3B82F6"
                If StringInStr($sColChoice, "Amber")   Then $aCalSchedule[$iRow][8] = "0xF59E0B"
                If StringInStr($sColChoice, "Violet")  Then $aCalSchedule[$iRow][8] = "0x8B5CF6"
                If StringInStr($sColChoice, "Rose")    Then $aCalSchedule[$iRow][8] = "0xF43F5E"
                If StringInStr($sColChoice, "Slate")   Then $aCalSchedule[$iRow][8] = "0x64748B"
                ExitLoop
        EndSwitch
    WEnd
    
    GUIDelete($hEditGUI)
    GUISetState(@SW_ENABLE, $g_hMainParentGUI)
    WinActivate($g_hMainParentGUI)
    _Calendar_Render()
    _Calendar_UpdateOverview($iRow)
EndFunc

; ==============================================================================
; NATIVE SCROLLBAR HANDLERS
; ==============================================================================
Func _Calendar_WM_VSCROLL($hWnd, $iMsg, $wParam, $lParam)
    If $hWnd <> $g_hCalGUI Then Return $GUI_RUNDEFMSG
    Local $iOldY = $iCalScrollY
    Switch BitAND($wParam, 0x0000FFFF)
        Case $SB_LINEUP
            $iCalScrollY -= 30
        Case $SB_LINEDOWN
            $iCalScrollY += 30
        Case $SB_PAGEUP
            $iCalScrollY -= 150
        Case $SB_PAGEDOWN
            $iCalScrollY += 150
        Case $SB_THUMBTRACK
            $iCalScrollY = BitShift($wParam, 16)
    EndSwitch
    If $iCalScrollY < 0 Then $iCalScrollY = 0
    If $iCalScrollY > ($iCalTotalGridHeight - 200) Then $iCalScrollY = $iCalTotalGridHeight - 200
    If $iCalScrollY <> $iOldY Then
        DllCall("user32.dll", "int", "ScrollWindow", "hwnd", $g_hCalGUI, "int", 0, "int", $iOldY - $iCalScrollY, "ptr", 0, "ptr", 0)
        _GUIScrollBars_SetScrollInfoPos($g_hCalGUI, $SB_VERT, $iCalScrollY)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func _Calendar_WM_HSCROLL($hWnd, $iMsg, $wParam, $lParam)
    If $hWnd <> $g_hCalGUI Then Return $GUI_RUNDEFMSG
    Local $iOldX = $iCalScrollX
    Switch BitAND($wParam, 0x0000FFFF)
        Case $SB_LINELEFT
            $iCalScrollX -= 30
        Case $SB_LINERIGHT
            $iCalScrollX += 30
        Case $SB_THUMBTRACK
            $iCalScrollX = BitShift($wParam, 16)
    EndSwitch
    If $iCalScrollX < 0 Then $iCalScrollX = 0
    If $iCalScrollX > 400 Then $iCalScrollX = 400
    If $iCalScrollX <> $iOldX Then
        DllCall("user32.dll", "int", "ScrollWindow", "hwnd", $g_hCalGUI, "int", $iOldX - $iCalScrollX, "int", 0, "ptr", 0, "ptr", 0)
        _GUIScrollBars_SetScrollInfoPos($g_hCalGUI, $SB_HORZ, $iCalScrollX)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func _Calendar_WM_MOUSEWHEEL($hWnd, $iMsg, $wParam, $lParam)
    If BitShift($wParam, 16) > 0 Then
        _Calendar_WM_VSCROLL($g_hCalGUI, $WM_VSCROLL, $SB_LINEUP, 0)
    Else
        _Calendar_WM_VSCROLL($g_hCalGUI, $WM_VSCROLL, $SB_LINEDOWN, 0)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc