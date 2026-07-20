#include-once
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <ComboConstants.au3>
#include <DateTimeConstants.au3>
#include <EditConstants.au3>
#include <GuiListView.au3>
#include <GUIScrollBars.au3>
#include <ScrollBarConstants.au3>
#include <WinAPI.au3>
#include <Misc.au3>
#include <Date.au3>
#include <Array.au3>

; ==================== CONSTANTS & COLORS ====================
Global Const $COLOR_WORKSPACE_BG = 0xECEFF1
Global Const $COLOR_PANEL_BG     = 0xFFFFFF 
Global Const $COLOR_TEXT_LIGHT   = 0xFFFFFF 
Global Const $COLOR_TEXT_DARK    = 0x212121 
Global Const $COLOR_HEADER_BG    = 0xDFE6E9 

Global Const $COL_GREEN  = 0x059669 
Global Const $COL_BLUE   = 0x2563EB 
Global Const $COL_AMBER  = 0xD97706 
Global Const $COL_PURPLE = 0x7C3AED 
Global Const $COL_ROSE   = 0xE11D48 
Global Const $COL_GREY   = 0x64748B 

Global Const $COL_NAV         = 0x1B364A ; Dark Navy Header
Global Const $COL_SIDEBAR     = 0x243647 ; Sidebar Background
Global Const $COL_PANEL       = 0xECEFF1 ; Light Panel
Global Const $COL_STATUS      = 0x2A3E52 ; Status Bar
Global Const $COL_TEXT        = 0xFFFFFF ; White Text
Global Const $COL_INDICATOR   = 0x00BFFF ; Bright Blue Sidebar Line

Global Const $COL_SIDE_INACTIVE = 0x243647 ; Blends into sidebar
Global Const $COL_SIDE_ACTIVE   = 0x005A8C ; Distinct rich ocean blue highlight
Global Const $COL_TAB_INACTIVE  = 0x24435C ; Muted blue-grey tab
Global Const $COL_TAB_ACTIVE    = 0xDDE3E8 ; Matches Filter bar
Global Const $COL_TAB_TEXT_IN   = 0xFFFFFF ; White text for inactive tab
Global Const $COL_TAB_TEXT_ACT  = 0x1B364A ; Dark navy text for active tab

Global Const $sScriptName = StringRegExpReplace(@ScriptName, "\.[^.]+$", "")
Global Const $sIniPath    = @ScriptDir & "\" & $sScriptName & ".ini"

Global Const $DEFAULT_WIDTH  = 1200
Global Const $DEFAULT_HEIGHT = 800
Global Const $HEADER_H   = 50
Global Const $STATUS_H   = 30

; --- DYNAMIC RESIZING VARIABLES ---
Global $g_iSidebarW  = Number(IniRead($sIniPath, "Layout", "SidebarW", 170))
Global $g_iOverviewW = Number(IniRead($sIniPath, "Layout", "OverviewW", 240))
Global $g_iFilterH   = Number(IniRead($sIniPath, "Layout", "FilterH", 50))
Global $g_iLegendH   = Number(IniRead($sIniPath, "Layout", "LegendH", 80))

; ==================== DYNAMIC DATES & DUMMY DATA ====================
Global $sTodayYYYYMMDD = @YEAR & @MON & @MDAY
Global $sTodaySlash    = @YEAR & "/" & @MON & "/" & @MDAY

; Calculate Tomorrow's Date
Global $sTomorrowYYYYMMDD = _DateAdd('D', 1, @YEAR & @MON & @MDAY)
Global $sTomorrowSlash = _DateAdd('D', 1, $sTodaySlash)

Global $sWorklistCSV = _
    "SCHEDULE," & $sTodayYYYYMMDD & ",08:00,08:30,Setup / QC Calibration,System Check,Tech Team,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",08:30,09:30,Jane Doe,ID:883491 - CT Chest w/ Contrast,Mike B. - Day,Scan Rm 1,CT,0x059669" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",09:30,10:00,Room Sterile Prep,Sanitization Protocol,Support Staff,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",10:00,11:00,Emily White,ID:445666 - CT Abdomen/Pelvis,Mike B. - Day,Scan Rm 1,CT,0x059669" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",10:30,11:30,Robert Johnson,ID:991234 - MRI Brain Sport Protocol,Sarah J. - Day,MRI Suite A,MRI,0x2563EB" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",11:00,12:00,MRI Emergency Backup,Trauma Standby Slot,Sarah J. - Day,Scan Rm 1,CT,0xD97706" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",12:00,13:00,Department Lunch Break,Shift Handoff & Review,All Techs,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",13:00,15:00,John Smith,ID:112233 - CT Head Advanced 3D,Mike B. - Day,Scan Rm 1,CT,0x059669" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",14:00,15:30,Alice Williams,ID:774829 - PET/CT Oncology Scan,Dr. Patel / Mike B.,Scan Rm 2,PET/CT,0x7C3AED" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",15:00,16:00,Mike B. / Sarah J.,Shift Overlap & Joint QC,Mike B. / Sarah J.,Scan Rm 1,CT,0x059669" & @CRLF & _
    "SCHEDULE," & $sTodayYYYYMMDD & ",16:00,16:30,John Davis,ID:332111 - ER Trauma CT Spine,Mike B. - On Call,Scan Rm 1,CT,0xE11D48" & @CRLF & _
    "SCHEDULE," & $sTomorrowYYYYMMDD & ",08:00,08:30,Setup / QC Calibration,Tomorrow Setup,Tech Team,Scan Rm 1,CT,0x64748B" & @CRLF & _
    "SCHEDULE," & $sTomorrowYYYYMMDD & ",08:30,09:30,Lisa Chen,Tomorrow Patient Test 1,Mike B. - Day,Scan Rm 1,CT,0x059669" & @CRLF & _
    "SCHEDULE," & $sTomorrowYYYYMMDD & ",09:30,10:30,Tomorrow Patient Test 2,X-Ray Protocol,Tomorrow Tech,Scan Rm 2,PET/CT,0x2563EB"

Global $g_iScrollY = 0, $g_iScrollX = 0
Global $g_iTotalGridHeight = 1200 
Global $g_iTotalGridWidth  = 1000 
Global $iScheduleCount = 0
Global $g_iLastClickedRow = -1
Global $g_hLastClickTimer = 0
Global $g_sCurrentDateFilter = $sTodayYYYYMMDD

; Expanded array: [ID, StartMin, EndMin, Patient, Procedure, Tech, Room, Modality, Color, ControlID, ZebraCtrlID, TimeCtrlID]
Global $aSchedule[150][12] 

Global $aWorklistDecorations[600]
Global $iDecorationCount = 0

Global $idListViewRep
Global $iRepCount = 0
Global $aRepData[150][9] ; [ID, Date, Time, Patient, Procedure, Modality, Room, Status, Radiologist]

; --- LOGIN / LOGOUT STATE ---
Global $g_bIsLoggedIn = False

; --- GUI CONTROL REFERENCES ---
Global $btnWorkPrevDay, $dtpWorkDate, $btnWorkNextDay, $cmbWorkModality, $cmbWorkRoom, $cmbWorkPatient
Global $btnWorkNewEvent, $btnWorkPrint, $btnWorkExport, $idSplitFilter, $idSplitLegend
Global $btnRepPrevDay, $dtpRepDate, $btnRepNextDay, $cmbRepModality, $cmbRepRoom, $cmbRepPatient, $cmbRepView
Global $btnRepNewEvent, $btnRepEditPatient, $btnRepPrint, $btnRepExport

; Login GUI controls
Global $hLoginGUI, $hLoginBox, $lblLoginTitle, $lblLoginPrompt, $inpLoginPass, $btnLoginSubmit, $btnLoginDemo
Global $lblLoginErrorMsg

; ==================== MAIN GUI SETUP ====================
Local $iSaveWidth  = IniRead($sIniPath, "Window", "Width",  $DEFAULT_WIDTH)
Local $iSaveHeight = IniRead($sIniPath, "Window", "Height", $DEFAULT_HEIGHT)
Local $iSaveX      = IniRead($sIniPath, "Window", "X", -1)
Local $iSaveY      = IniRead($sIniPath, "Window", "Y", -1)

Global Const $iMainStyle = BitOR($WS_OVERLAPPEDWINDOW, $WS_CLIPCHILDREN)
If $iSaveX = -1 And $iSaveY = -1 Then
    Global $hMainGUI = GUICreate("Daily Technician Schedule - MGH Medical Center", $iSaveWidth, $iSaveHeight, -1, -1, $iMainStyle)
Else
    Global $hMainGUI = GUICreate("Daily Technician Schedule - MGH Medical Center", $iSaveWidth, $iSaveHeight, $iSaveX, $iSaveY, $iMainStyle)
EndIf

Global Const $iChildStyle = BitOR($WS_CHILD, $WS_CLIPSIBLINGS)
Global Const $iScrollChildStyle = BitOR($WS_CHILD, $WS_CLIPSIBLINGS, $WS_CLIPCHILDREN, $WS_VSCROLL, $WS_HSCROLL)

Global $hHeader   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
Global $hSidebar  = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
Global $hOverview = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
Global $hStatus   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)

; Worklist Tab Panels (Nav 2)
Global $hWorkFilter = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
Global $hWorklist   = GUICreate("", 100, 100, 0, 0, $iScrollChildStyle, -1, $hMainGUI)
Global $hWorkLegend = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)

; Reporting Tab Panels (Nav 4)
Global $hRepFilter   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
Global $hRepCalendar = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
Global $hRepLegend   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)

; ==================== HEADER & FOLDER TABS ====================
GUISwitch($hHeader)
GUISetBkColor($COL_NAV, $hHeader)
GUICtrlCreateLabel("DAILY TECHNICIAN SCHEDULE - MGH", 10, 15, 300, 20)
GUICtrlSetColor(-1, $COL_TEXT)
GUICtrlSetFont(-1, 9.5, 700, 0, "Segoe UI")

Global Const $iTabStyle = BitOR($SS_CENTER, $SS_CENTERIMAGE)
Global $btnNav1 = GUICtrlCreateLabel("Patient Search",       350, 20, 100, 30, $iTabStyle)
Global $btnNav2 = GUICtrlCreateLabel("Worklist",             455, 20, 80,  30, $iTabStyle)
Global $btnNav3 = GUICtrlCreateLabel("Scheduling",           540, 20, 85,  30, $iTabStyle)
Global $btnNav4 = GUICtrlCreateLabel("Reporting",            630, 20, 80,  30, $iTabStyle)
Global $btnNav5 = GUICtrlCreateLabel("Admin",                715, 20, 65,  30, $iTabStyle)
Global $btnNav6 = GUICtrlCreateLabel("Log Out (Dr. A. Pst)", 785, 20, 140, 30, $iTabStyle)

For $i = $btnNav1 To $btnNav6
    GUICtrlSetBkColor($i, $COL_TAB_INACTIVE)
    GUICtrlSetColor($i, $COL_TAB_TEXT_IN)
    GUICtrlSetFont($i, 8.5, 600, 0, "Segoe UI")
    GUICtrlSetCursor($i, 0)
    GUICtrlSetResizing($i, $GUI_DOCKALL)
Next

; ==================== SIDEBAR BUTTONS & SPLITTER ====================
GUISwitch($hSidebar)
GUISetBkColor($COL_SIDEBAR, $hSidebar)
Global $btnSide1 = GUICtrlCreateLabel("  Notifications (2)",   15, 20,  150, 40, $SS_CENTERIMAGE)
Global $btnSide2 = GUICtrlCreateLabel("  Recent Patients",     15, 70,  150, 40, $SS_CENTERIMAGE)
Global $btnSide3 = GUICtrlCreateLabel("  Reporting Queue (9)", 15, 120, 150, 40, $SS_CENTERIMAGE)
Global $btnSide4 = GUICtrlCreateLabel("  Tech Notes",          15, 170, 150, 40, $SS_CENTERIMAGE)
Global $btnSide5 = GUICtrlCreateLabel("  System Status",       15, 220, 150, 40, $SS_CENTERIMAGE)

Global $hActiveIndicator = GUICtrlCreateLabel("", 0, 20, 4, 40)
GUICtrlSetBkColor($hActiveIndicator, $COL_INDICATOR)
GUICtrlSetResizing($hActiveIndicator, $GUI_DOCKALL)

Global $idSplitSidebar = GUICtrlCreateLabel("", 0, 0, 4, 10)
GUICtrlSetCursor(-1, 13)
GUICtrlSetBkColor(-1, $COL_NAV)

For $i = $btnSide1 To $btnSide5
    GUICtrlSetBkColor($i, $COL_SIDE_INACTIVE)
    GUICtrlSetColor($i, $COL_TEXT)
    GUICtrlSetFont($i, 9, 600, 0, "Segoe UI")
    GUICtrlSetCursor($i, 0)
    GUICtrlSetResizing($i, $GUI_DOCKALL)
Next

; ==================== OVERVIEW PANEL & SPLITTER ====================
GUISwitch($hOverview)
GUISetBkColor(0xF1F5F9, $hOverview)
GUICtrlCreateLabel("EVENT OVERVIEW", 15, 15, 200, 20)
GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x1E293B)

Global $lblOverviewData = GUICtrlCreateLabel("Select any scheduled event card on the timeline to view clinical details and assigned technical staff." & @CRLF & @CRLF & "Double-click a card to edit or remove it.", 15, 45, $g_iOverviewW - 30, 600)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x334155)

Global $idSplitOverview = GUICtrlCreateLabel("", 0, 0, 4, 10)
GUICtrlSetCursor(-1, 13)
GUICtrlSetBkColor(-1, $COL_NAV)

; ==================== STATUS BAR ====================
GUISwitch($hStatus)
GUISetBkColor($COL_STATUS, $hStatus)
GUICtrlCreateLabel("  User: Dr. Anjali Patel | Terminal: WKS-RAD-04 | Status: Connected (Database Synced)", 10, 6, 500, 20)
GUICtrlSetColor(-1, $COL_TEXT)
GUICtrlSetFont(-1, 8.5, 400, 0, "Segoe UI")

; ==================== INITIALIZE MODULES ====================
_InitWorklist()
_InitWorklistFilter()
_InitWorklistLegend()
_InitReportingFilter()
_InitReportingLegend()
_InitReportingCalendar()

GUIRegisterMsg($WM_SIZE, "WM_SIZE")
GUIRegisterMsg($WM_VSCROLL, "WM_VSCROLL")
GUIRegisterMsg($WM_HSCROLL, "WM_HSCROLL")
GUIRegisterMsg($WM_MOUSEWHEEL, "WM_MOUSEWHEEL")

_UpdateLayout($iSaveWidth, $iSaveHeight)
_SelectNav($btnSide1)
_SelectNav($btnNav2) ; Default to Worklist tab active

; Hide main GUI initially, show login screen first
GUISetState(@SW_HIDE, $hHeader)
GUISetState(@SW_HIDE, $hSidebar)
GUISetState(@SW_HIDE, $hOverview)
GUISetState(@SW_HIDE, $hStatus)
GUISetState(@SW_HIDE, $hWorkFilter)
GUISetState(@SW_HIDE, $hWorklist)
GUISetState(@SW_HIDE, $hWorkLegend)
GUISetState(@SW_HIDE, $hRepFilter)
GUISetState(@SW_HIDE, $hRepCalendar)
GUISetState(@SW_HIDE, $hRepLegend)

GUISetState(@SW_SHOW, $hMainGUI)

; Create and show login screen (always on top)
_CreateLoginScreen()
GUISetState(@SW_SHOW, $hLoginGUI)
WinSetOnTop($hLoginGUI, "", $WINDOWS_ONTOP)


; ==================== MAIN EVENT LOOP ====================
While 1
    Local $iMsg = GUIGetMsg()

    If $iMsg = $GUI_EVENT_CLOSE Then
        _SaveWindowState()
        Exit
    EndIf

    ; --- Catch Splitter Handles ---
    If $iMsg = $idSplitSidebar Or $iMsg = $idSplitOverview Or $iMsg = $idSplitFilter Or $iMsg = $idSplitLegend Then
        _HandleResizerDrag($iMsg)
    EndIf

    ; --- Navigation Clicks ---
    If ($iMsg >= $btnNav1 And $iMsg <= $btnNav6) Or ($iMsg >= $btnSide1 And $iMsg <= $btnSide5) Then
        _SelectNav($iMsg)
    EndIf

    ; --- Worklist & Reporting Controls ---
    Switch $iMsg
        Case $cmbWorkModality, $cmbWorkRoom, $cmbWorkPatient
            _ApplyWorklistFilter()
        Case $btnWorkPrevDay
            _ChangeWorkDate(-1)
        Case $btnWorkNextDay
            _ChangeWorkDate(1)
        Case $btnWorkNewEvent
            _EditWorklistEvent($iScheduleCount)

        Case $btnRepPrevDay
            _ChangeRepDate(-1)
        Case $btnRepNextDay
            _ChangeRepDate(1)
        Case $dtpRepDate, $cmbRepPatient, $cmbRepModality, $cmbRepRoom, $cmbRepView
            _RenderRepCalendar()
        Case $btnRepNewEvent
            _HandleRepNewEvent()
        Case $btnRepEditPatient
            _HandleRepEditPatient()
    EndSwitch

    ; --- Worklist Schedule Click Handler ---
    If $iMsg > 0 And BitAND(WinGetState($hWorklist), 2) Then
        _HandleWorklistClick($iMsg)
    EndIf
    
    ; --- Login Screen Controls ---
    If $iMsg = $btnLoginSubmit Or $iMsg = $btnLoginDemo Then
        _HandleLogin()
    EndIf
WEnd

; ==================== LOGIN SCREEN FUNCTIONS ====================
Func _CreateLoginScreen()
    Local $aMainPos = WinGetClientSize($hMainGUI)
    GUISwitch($hMainGUI)
    
    ; Login GUI is the blue background covering full window
    $hLoginGUI = GUICreate("", $aMainPos[0], $aMainPos[1], 0, 0, BitOR($WS_CHILD, $WS_CLIPSIBLINGS), $WS_EX_TOPMOST, $hMainGUI)
    GUISetBkColor($COL_NAV, $hLoginGUI)
    
    ; Login Box is the centered 400x300 area
    $hLoginBox = GUICreate("", 400, 300, ($aMainPos[0]-400)/2, ($aMainPos[1]-300)/2, $WS_CHILD, -1, $hLoginGUI)
    GUISetBkColor($COL_NAV, $hLoginBox)
    
    $lblLoginTitle = GUICtrlCreateLabel("MGH MEDICAL CENTER", 100, 40, 200, 25)
    GUICtrlSetColor($lblLoginTitle, $COL_TEXT)
    GUICtrlSetFont($lblLoginTitle, 14, 700, 0, "Segoe UI")
    
    $lblLoginPrompt = GUICtrlCreateLabel("Authentication Required", 120, 80, 160, 20)
    GUICtrlSetColor($lblLoginPrompt, $COL_TEXT)
    GUICtrlSetFont($lblLoginPrompt, 11, 600, 0, "Segoe UI")
    
    $inpLoginPass = GUICtrlCreateInput("", 100, 130, 200, 30, $ES_PASSWORD)
    GUICtrlSetBkColor(-1, $COLOR_PANEL_BG)
    GUICtrlSetColor(-1, 0x1B364A)
    GUICtrlSetFont(-1, 10, 400, 0, "Segoe UI")
    
    $lblLoginErrorMsg = GUICtrlCreateLabel("", 50, 170, 300, 20)
    GUICtrlSetColor($lblLoginErrorMsg, $COL_ROSE)
    GUICtrlSetFont($lblLoginErrorMsg, 9, 400, 0, "Segoe UI")
    
    $btnLoginDemo = GUICtrlCreateButton("Use Demo Access", 100, 210, 100, 30)
    GUICtrlSetBkColor($btnLoginDemo, $COL_GREEN)
    GUICtrlSetColor($btnLoginDemo, $COL_TEXT)
    GUICtrlSetFont($btnLoginDemo, 9, 600, 0, "Segoe UI")
    
    $btnLoginSubmit = GUICtrlCreateButton("Enter Password", 210, 210, 100, 30)
    GUICtrlSetBkColor($btnLoginSubmit, $COL_BLUE)
    GUICtrlSetColor($btnLoginSubmit, $COL_TEXT)
    GUICtrlSetFont($btnLoginSubmit, 9, 600, 0, "Segoe UI")
    
    GUISetState(@SW_SHOW, $hLoginBox)
EndFunc

Func _HandleLogin()
    Local $sPassword = GUICtrlRead($inpLoginPass)
    
    ; Any password works for demo purposes
    $g_bIsLoggedIn = True
    
    ; Clear error message
    GUICtrlSetData($lblLoginErrorMsg, "")
    
    ; Hide login screen
    GUISetState(@SW_HIDE, $hLoginGUI)
    
    ; Show all main GUI components
    GUISetState(@SW_SHOW, $hHeader)
    GUISetState(@SW_SHOW, $hSidebar)
    GUISetState(@SW_SHOW, $hOverview)
    GUISetState(@SW_SHOW, $hStatus)
    GUISetState(@SW_SHOW, $hWorkFilter)
    GUISetState(@SW_SHOW, $hWorklist)
    GUISetState(@SW_SHOW, $hWorkLegend)
    
    ; Refresh displays - FORCE REDRAW
    _UpdateLayout(WinGetClientSize($hMainGUI)[0], WinGetClientSize($hMainGUI)[1])
    _RenderWorklist()
    _RenderRepCalendar()
    _UpdateWorklistScrollbars()
    
    ; Bring main GUI to front
    WinActivate($hMainGUI)
EndFunc

Func _HandleLogout()
    If Not $g_bIsLoggedIn Then Return
    
    $g_bIsLoggedIn = False
    
    ; Hide all main GUI panels except header and status
    GUISetState(@SW_HIDE, $hWorkFilter)
    GUISetState(@SW_HIDE, $hWorklist)
    GUISetState(@SW_HIDE, $hWorkLegend)
    GUISetState(@SW_HIDE, $hRepFilter)
    GUISetState(@SW_HIDE, $hRepCalendar)
    GUISetState(@SW_HIDE, $hRepLegend)
    GUISetState(@SW_HIDE, $hSidebar)
    GUISetState(@SW_HIDE, $hOverview)
    
    ; Show login screen
    GUICtrlSetData($inpLoginPass, "")
    GUICtrlSetData($lblLoginErrorMsg, "")
    GUISetState(@SW_SHOW, $hLoginGUI)
    WinSetOnTop($hLoginGUI, "", $WINDOWS_ONTOP)
    
    WinActivate($hLoginGUI)
EndFunc

; ==================== WORKLIST FUNCTIONS ====================

Func _InitWorklist()
    GUISwitch($hWorklist)
    GUISetBkColor($COLOR_PANEL_BG, $hWorklist)

    Local $aRows = StringSplit(StringStripCR($sWorklistCSV), @LF)
    For $i = 1 To $aRows[0]
        If StringStripWS($aRows[$i], 8) = "" Then ContinueLoop
        Local $aCols = StringSplit($aRows[$i], ",")
        If $aCols[1] = "SCHEDULE" And $iScheduleCount < 150 Then
            $aSchedule[$iScheduleCount][0] = ($aCols[0] >= 2) ? $aCols[2] : $sTodayYYYYMMDD
            $aSchedule[$iScheduleCount][1] = ($aCols[0] >= 3) ? $aCols[3] : ""
            $aSchedule[$iScheduleCount][2] = ($aCols[0] >= 4) ? $aCols[4] : ""
            $aSchedule[$iScheduleCount][3] = ($aCols[0] >= 5) ? $aCols[5] : ""
            $aSchedule[$iScheduleCount][4] = ($aCols[0] >= 6) ? $aCols[6] : ""
            $aSchedule[$iScheduleCount][5] = ($aCols[0] >= 7) ? $aCols[7] : ""
            $aSchedule[$iScheduleCount][6] = ($aCols[0] >= 8) ? $aCols[8] : "Scan Rm 1"
            $aSchedule[$iScheduleCount][7] = ($aCols[0] >= 9) ? $aCols[9] : "CT"
            $aSchedule[$iScheduleCount][8] = ($aCols[0] >= 10) ? $aCols[10] : "0x059669"
            $iScheduleCount += 1
        EndIf
    Next

    Global $hHeaderTime = GUICtrlCreateLabel("Time", 0, 0, 60, 30, BitOR($SS_CENTER, $SS_CENTERIMAGE))
    GUICtrlSetBkColor(-1, $COLOR_HEADER_BG)
    GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")
    Global $hHeaderDesc = GUICtrlCreateLabel("  Schedule Timeline & Assigned Technical Coverage", 60, 0, 1500, 30, $SS_CENTERIMAGE)
    GUICtrlSetBkColor(-1, $COLOR_HEADER_BG)
    GUICtrlSetFont(-1, 10, 700, 0, "Segoe UI")

    _RenderWorklist()

    _GUIScrollBars_Init($hWorklist)
    _GUIScrollBars_SetScrollInfoMax($hWorklist, $SB_VERT, $g_iTotalGridHeight)
    _GUIScrollBars_SetScrollInfoMax($hWorklist, $SB_HORZ, 1200)
    _GUIScrollBars_ShowScrollBar($hWorklist, $SB_VERT, True)
    _GUIScrollBars_ShowScrollBar($hWorklist, $SB_HORZ, True)
EndFunc

Func _RenderWorklist()
    GUISwitch($hWorklist)
    
    ; Clean up existing controls
    For $i = 0 To $iScheduleCount - 1
        If $aSchedule[$i][9] <> 0 Then GUICtrlDelete($aSchedule[$i][9])
        If $aSchedule[$i][10] <> 0 Then GUICtrlDelete($aSchedule[$i][10])
        If $aSchedule[$i][11] <> 0 Then GUICtrlDelete($aSchedule[$i][11])
        $aSchedule[$i][9] = 0
        $aSchedule[$i][10] = 0
        $aSchedule[$i][11] = 0
    Next
    
    For $i = 0 To $iDecorationCount - 1
        If $aWorklistDecorations[$i] <> 0 Then
            GUICtrlDelete($aWorklistDecorations[$i])
            $aWorklistDecorations[$i] = 0
        EndIf
    Next
    $iDecorationCount = 0
    
    Local $iRowH = 48
    Local $iVisibleIndex = 0
    
    ; Get current date filter from dropdown
    Local $sDateDisplay = GUICtrlRead($dtpWorkDate)
    Local $sDateYYYYMMDD = _StringToDateYYMMDD($sDateDisplay)
    
    For $i = 0 To $iScheduleCount - 1
        ; Skip items not matching current date
        If $aSchedule[$i][0] <> $sDateYYYYMMDD Then ContinueLoop
        
        Local $iY = 32 + ($iVisibleIndex * $iRowH)
        Local $iZebraBg = (Mod($iVisibleIndex, 2) = 0) ? 0xFFFFFF : 0xF1F5F9
        
        ; Row Background (Zebra Stripe) stored in $aSchedule[$i][10] for instant active highlighting
        Local $hZebra = GUICtrlCreateLabel("", 0, $iY, 1500, $iRowH - 1)
        GUICtrlSetBkColor($hZebra, $iZebraBg)
        GUICtrlSetState($hZebra, $GUI_DISABLE)
        $aSchedule[$i][10] = $hZebra
        
        Local $hGridH = GUICtrlCreateLabel("", 0, $iY + $iRowH - 1, 1500, 1)
        GUICtrlSetBkColor($hGridH, 0xCFD8DC)
        $aWorklistDecorations[$iDecorationCount] = $hGridH
        $iDecorationCount += 1
        
        Local $hGridV = GUICtrlCreateLabel("", 60, $iY, 1, $iRowH - 1)
        GUICtrlSetBkColor($hGridV, 0xCFD8DC)
        $aWorklistDecorations[$iDecorationCount] = $hGridV
        $iDecorationCount += 1
        
        ; Time label with $SS_CENTERIMAGE so text is centered vertically
        Local $hTime = GUICtrlCreateLabel($aSchedule[$i][1], 0, $iY, 60, $iRowH - 1, BitOR($SS_CENTER, $SS_CENTERIMAGE))
        GUICtrlSetBkColor(-1, $iZebraBg)
        GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
        $aSchedule[$i][11] = $hTime
        
        Local $sText = "  " & $aSchedule[$i][3] & "  [" & $aSchedule[$i][6] & " - " & $aSchedule[$i][7] & "]"
        If $aSchedule[$i][4] <> "" Then $sText &= "  |  " & $aSchedule[$i][4]
        If $aSchedule[$i][5] <> "" Then $sText &= @CRLF & "  Assigned Technical Lead: " & $aSchedule[$i][5]
        
        ; Adjusted Y offset and height for perfect vertical balance
        Local $hBlock = GUICtrlCreateLabel($sText, 66, $iY + 3, 1000, $iRowH - 7)
        GUICtrlSetBkColor($hBlock, Execute($aSchedule[$i][8]))
        GUICtrlSetColor($hBlock, $COLOR_TEXT_LIGHT)
        GUICtrlSetFont($hBlock, 9, 600, 0, "Segoe UI")
        
        $aSchedule[$i][9] = $hBlock
        $iVisibleIndex += 1
    Next
    
    $g_iTotalGridHeight = ($iVisibleIndex * $iRowH) + 50
    _GUIScrollBars_SetScrollInfoMax($hWorklist, $SB_VERT, $g_iTotalGridHeight)
    
    ; Keep Reporting Calendar synchronized with Worklist
    _SyncReportingFromWorklist()
EndFunc

; Convert date display format to YYYYMMDD
Func _StringToDateYYMMDD($sDate)
    ; Expected format: YYYY/MM/DD
    Local $iYear = StringLeft($sDate, 4)
    Local $iMonth = StringMid($sDate, 6, 2)
    Local $iDay = StringRight($sDate, 2)
    Return $iYear & $iMonth & $iDay
EndFunc

Func _HandleWorklistClick($iMsg)
    For $i = 0 To $iScheduleCount - 1
        If $iMsg == $aSchedule[$i][9] Then
            ; 1. Highlight the active row visually
            _HighlightWorklistRow($i)
            
            ; 2. Force immediate GUI update to show highlight
            _WinAPI_InvalidateRect($hWorklist, 0, True)
            _WinAPI_UpdateWindow($hWorklist)
            
            ; 3. Populate Event Overview Panel with clicked event data
            _PopulateOverviewPanel($i)
            
            ; 4. Handle double-click timing for editing
            If TimerDiff($g_hLastClickTimer) < 400 And $g_iLastClickedRow == $i Then
                $g_hLastClickTimer = 0
                _EditWorklistEvent($i)
            Else
                $g_iLastClickedRow = $i
                $g_hLastClickTimer = TimerInit()
            EndIf
            Return True
        EndIf
    Next
    Return False
EndFunc

Func _HighlightWorklistRow($iActiveIdx)
    For $i = 0 To $iScheduleCount - 1
        If $aSchedule[$i][10] <> 0 Then
            Local $iZebraBg = (Mod($i, 2) = 0) ? 0xFFFFFF : 0xF1F5F9
            If $i == $iActiveIdx Then $iZebraBg = 0xFEF08A ; Distinct warm yellow/gold highlight for active row
            GUICtrlSetBkColor($aSchedule[$i][10], $iZebraBg)
            If $aSchedule[$i][11] <> 0 Then GUICtrlSetBkColor($aSchedule[$i][11], $iZebraBg)
        EndIf
    Next
EndFunc

Func _PopulateOverviewPanel($iRow)
    Local $sOverview = "ACTIVE EVENT OVERVIEW" & @CRLF & _
                       "========================================" & @CRLF & @CRLF & _
                       "Patient / Event:" & @CRLF & "  " & $aSchedule[$iRow][3] & @CRLF & @CRLF & _
                       "Clinical Details:" & @CRLF & "  " & $aSchedule[$iRow][4] & @CRLF & @CRLF & _
                       "Schedule Time:" & @CRLF & "  " & $aSchedule[$iRow][1] & " - " & $aSchedule[$iRow][2] & @CRLF & @CRLF & _
                       "Assigned Room:" & @CRLF & "  " & $aSchedule[$iRow][6] & @CRLF & @CRLF & _
                       "Modality:" & @CRLF & "  " & $aSchedule[$iRow][7] & @CRLF & @CRLF & _
                       "Technical Lead:" & @CRLF & "  " & $aSchedule[$iRow][5] & @CRLF & @CRLF & _
                       "----------------------------------------" & @CRLF & _
                       "Status: Confirmed & In Progress" & @CRLF & _
                       "Double-click timeline block to edit details."
    GUICtrlSetData($lblOverviewData, $sOverview)
EndFunc

Func _EditWorklistEvent($iRow)
    If $iRow < 0 Or $iRow >= $iScheduleCount Then Return
    
    GUISetState(@SW_DISABLE, $hMainGUI)
    Local $hEditGUI = GUICreate("Edit Schedule Event - " & $aSchedule[$iRow][3], 440, 420, -1, -1, BitOR($WS_CAPTION, $WS_SYSMENU), -1, $hMainGUI)
    GUISetBkColor($COLOR_WORKSPACE_BG, $hEditGUI)
    
    GUICtrlCreateLabel("Event / Patient Name:", 20, 20, 150, 20)
    Local $hInPatient = GUICtrlCreateInput($aSchedule[$iRow][3], 20, 40, 400, 26)
    
    GUICtrlCreateLabel("Exam ID & Clinical Details:", 20, 75, 200, 20)
    Local $hInDetails = GUICtrlCreateInput($aSchedule[$iRow][4], 20, 95, 400, 26)
    
    GUICtrlCreateLabel("Assigned Technician / Lead Role:", 20, 130, 200, 20)
    Local $hInTech = GUICtrlCreateInput($aSchedule[$iRow][5], 20, 150, 400, 26)
    
    GUICtrlCreateLabel("Start Time:", 20, 185, 80, 20)
    Local $hInStart = GUICtrlCreateInput($aSchedule[$iRow][1], 20, 205, 90, 26)
    GUICtrlCreateLabel("End Time:", 130, 185, 80, 20)
    Local $hInEnd   = GUICtrlCreateInput($aSchedule[$iRow][2], 130, 205, 90, 26)
    
    GUICtrlCreateLabel("Room:", 240, 185, 80, 20)
    Local $hInRoom  = GUICtrlCreateCombo($aSchedule[$iRow][6], 240, 205, 180, 26, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hInRoom, "Scan Rm 1|Scan Rm 2|MRI Suite A|MRI Suite B|X-Ray Room 1", $aSchedule[$iRow][6])
    
    GUICtrlCreateLabel("Modality:", 20, 245, 80, 20)
    Local $hInModal = GUICtrlCreateCombo($aSchedule[$iRow][7], 20, 265, 150, 26, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hInModal, "CT|MRI|PET/CT|X-Ray|Ultrasound", $aSchedule[$iRow][7])
    
    GUICtrlCreateLabel("Color Theme:", 190, 245, 100, 20)
    Local $hInColor = GUICtrlCreateCombo("", 190, 265, 230, 26, $CBS_DROPDOWNLIST)
    GUICtrlSetData($hInColor, "Green (Day Shift)|Blue (Night Shift)|Amber (On-Call)|Purple (Special)|Rose (Urgent/ER)|Grey (Setup/Leave)", "Green (Day Shift)")
    
    Local $hBtnSave   = GUICtrlCreateButton("Save Changes", 50, 340, 130, 34)
    GUICtrlSetFont($hBtnSave, 10, 700)
    Local $hBtnDelete = GUICtrlCreateButton("Delete Event", 195, 340, 110, 34)
    Local $hBtnCancel = GUICtrlCreateButton("Cancel", 320, 340, 80, 34)
    
    GUISetState(@SW_SHOW, $hEditGUI)
    
    While 1
        Switch GUIGetMsg()
            Case $GUI_EVENT_CLOSE, $hBtnCancel
                ExitLoop
            Case $hBtnDelete
                If MsgBox(36, "Confirm Delete", "Are you sure you want to delete this scheduled event?") == 6 Then
                    For $j = $iRow To $iScheduleCount - 2
                        For $c = 0 To 8
                            $aSchedule[$j][$c] = $aSchedule[$j + 1][$c]
                        Next
                    Next
                    $iScheduleCount -= 1
                    ExitLoop
                EndIf
            Case $hBtnSave
                $aSchedule[$iRow][3] = GUICtrlRead($hInPatient)
                $aSchedule[$iRow][4] = GUICtrlRead($hInDetails)
                $aSchedule[$iRow][5] = GUICtrlRead($hInTech)
                $aSchedule[$iRow][1] = GUICtrlRead($hInStart)
                $aSchedule[$iRow][2] = GUICtrlRead($hInEnd)
                $aSchedule[$iRow][6] = GUICtrlRead($hInRoom)
                $aSchedule[$iRow][7] = GUICtrlRead($hInModal)
                
                Local $sColChoice = GUICtrlRead($hInColor)
                If StringInStr($sColChoice, "Green")  Then $aSchedule[$iRow][8] = "0x059669"
                If StringInStr($sColChoice, "Blue")   Then $aSchedule[$iRow][8] = "0x2563EB"
                If StringInStr($sColChoice, "Amber")  Then $aSchedule[$iRow][8] = "0xD97706"
                If StringInStr($sColChoice, "Purple") Then $aSchedule[$iRow][8] = "0x7C3AED"
                If StringInStr($sColChoice, "Rose")   Then $aSchedule[$iRow][8] = "0xE11D48"
                If StringInStr($sColChoice, "Grey")   Then $aSchedule[$iRow][8] = "0x64748B"
                ExitLoop
        EndSwitch
    WEnd
    
    GUIDelete($hEditGUI)
    GUISetState(@SW_ENABLE, $hMainGUI)
    WinActivate($hMainGUI)
    _RenderWorklist()
EndFunc

Func _InitWorklistFilter()
    GUISwitch($hWorkFilter)
    GUISetBkColor(0xDDE3E8, $hWorkFilter)

    $btnWorkPrevDay = GUICtrlCreateButton("<", 10, 12, 30, 25)
    $dtpWorkDate    = GUICtrlCreateDate($sTodaySlash, 45, 12, 100, 25, $DTS_SHORTDATEFORMAT)
    $btnWorkNextDay = GUICtrlCreateButton(">", 150, 12, 30, 25)

    GUICtrlCreateLabel("Modality:", 190, 17, 55, 20)
    GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
    $cmbWorkModality = GUICtrlCreateCombo("All Modalities", 250, 12, 110, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($cmbWorkModality, "CT|MRI|PET/CT|X-Ray|Ultrasound", "All Modalities")

    GUICtrlCreateLabel("Room:", 375, 17, 40, 20)
    GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
    $cmbWorkRoom = GUICtrlCreateCombo("All Rooms", 420, 12, 110, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($cmbWorkRoom, "Scan Rm 1|Scan Rm 2|MRI Suite A|MRI Suite B|X-Ray Room 1", "All Rooms")

    GUICtrlCreateLabel("Patient:", 545, 17, 50, 20)
    GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
    $cmbWorkPatient = GUICtrlCreateCombo("All Patients", 600, 12, 160, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($cmbWorkPatient, "Jane Doe|Emily White|Robert Johnson|John Smith|Alice Williams|John Davis|Lisa Chen|Tomorrow Patient Test 1|Tomorrow Patient Test 2", "All Patients")

    $idSplitFilter = GUICtrlCreateLabel("", 0, 0, 10, 4)
    GUICtrlSetCursor(-1, 11)
    GUICtrlSetBkColor(-1, 0x1B364A)
EndFunc

Func _ApplyWorklistFilter()
    Local $sModFilter     = GUICtrlRead($cmbWorkModality)
    Local $sRoomFilter    = GUICtrlRead($cmbWorkRoom)
    Local $sPatientFilter = GUICtrlRead($cmbWorkPatient)

    For $i = 0 To $iScheduleCount - 1
        If $aSchedule[$i][9] = 0 Then ContinueLoop
        Local $bShow = True

        If $sModFilter <> "All Modalities" And $aSchedule[$i][7] <> $sModFilter Then $bShow = False
        If $sRoomFilter <> "All Rooms" And $aSchedule[$i][6] <> $sRoomFilter Then $bShow = False
        If $sPatientFilter <> "All Patients" And $aSchedule[$i][3] <> $sPatientFilter Then $bShow = False

        If $bShow Then
            GUICtrlSetState($aSchedule[$i][9], $GUI_SHOW)
        Else
            GUICtrlSetState($aSchedule[$i][9], $GUI_HIDE)
        EndIf
    Next

    _UpdateWorklistScrollbars()
    _WinAPI_InvalidateRect($hWorklist, 0, True)
    _WinAPI_UpdateWindow($hWorklist)
EndFunc

Func _InitWorklistLegend()
    GUISwitch($hWorkLegend)
    GUISetBkColor(0xECEFF1, $hWorkLegend)

    $btnWorkNewEvent = GUICtrlCreateButton("+ Add Schedule Event", 12, 14, 140, 30)
    GUICtrlSetFont($btnWorkNewEvent, 9, 700, 0, "Segoe UI")
    $btnWorkPrint    = GUICtrlCreateButton("Print Schedule", 160, 14, 110, 30)
    $btnWorkExport   = GUICtrlCreateButton("Export CSV", 280, 14, 100, 30)

    Local $aColors[5] = [0x059669, 0x2563EB, 0xD97706, 0x7C3AED, 0xE11D48]
    Local $aLabels[5] = ["Day Shift", "Standard / Night", "On-Call", "PET/CT Oncology", "Urgent / ER Trauma"]
    Local $iStartX = 405

    For $i = 0 To 4
        GUICtrlCreateLabel("", $iStartX, 21, 14, 14)
        GUICtrlSetBkColor(-1, $aColors[$i])
        GUICtrlCreateLabel("  " & $aLabels[$i], $iStartX + 20, 20, 115, 18)
        GUICtrlSetFont(-1, 8.5, 600, 0, "Segoe UI")
        GUICtrlSetColor(-1, 0x334155)
        $iStartX += 135
    Next

    $idSplitLegend = GUICtrlCreateLabel("", 0, 0, 10, 4)
    GUICtrlSetCursor(-1, 11)
    GUICtrlSetBkColor(-1, 0x1B364A)
EndFunc

Func _UpdateWorklistScrollbars()
    If Not WinExists($hWorklist) Then Return
    Local $aWin = WinGetClientSize($hWorklist)
    If Not IsArray($aWin) Or $aWin[1] <= 0 Then Return

    _GUIScrollBars_SetScrollInfoPage($hWorklist, $SB_VERT, $aWin[1])
    _GUIScrollBars_SetScrollInfoPage($hWorklist, $SB_HORZ, $aWin[0])
    _GUIScrollBars_SetScrollInfoMin($hWorklist, $SB_VERT, 0)
    _GUIScrollBars_SetScrollInfoMax($hWorklist, $SB_VERT, $g_iTotalGridHeight)
    _GUIScrollBars_SetScrollInfoMin($hWorklist, $SB_HORZ, 0)
    _GUIScrollBars_SetScrollInfoMax($hWorklist, $SB_HORZ, $g_iTotalGridWidth)

    Local $iMaxScrollY = $g_iTotalGridHeight - $aWin[1]
    If $iMaxScrollY < 0 Then $iMaxScrollY = 0
    If $g_iScrollY > $iMaxScrollY Then
        Local $iDiff = $g_iScrollY - $iMaxScrollY
        $g_iScrollY = $iMaxScrollY
        DllCall("user32.dll", "int", "ScrollWindow", "hwnd", $hWorklist, "int", 0, "int", $iDiff, "ptr", 0, "ptr", 0)
        _GUIScrollBars_SetScrollInfoPos($hWorklist, $SB_VERT, $g_iScrollY)
    EndIf
EndFunc

Func _ChangeWorkDate($iDays)
    Local $sCurrentDate = GUICtrlRead($dtpWorkDate)
    Local $sNewDate = _DateAdd('D', $iDays, $sCurrentDate)
    GUICtrlSetData($dtpWorkDate, $sNewDate)
    
    ; FIX: Redraw worklist when date changes
    _RenderWorklist()
    _UpdateWorklistScrollbars()
EndFunc

; ==================== REPORTING FUNCTIONS ====================

Func _InitReportingFilter()
    GUISwitch($hRepFilter)
    GUISetBkColor(0xDDE3E8, $hRepFilter)

    $btnRepPrevDay = GUICtrlCreateButton("<", 10, 12, 30, 25)
    $dtpRepDate    = GUICtrlCreateDate($sTodaySlash, 45, 12, 100, 25, $DTS_SHORTDATEFORMAT)
    $btnRepNextDay = GUICtrlCreateButton(">", 150, 12, 30, 25)

    GUICtrlCreateLabel("Modality:", 190, 17, 55, 20)
    GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
    $cmbRepModality = GUICtrlCreateCombo("All Modalities", 250, 12, 110, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($cmbRepModality, "CT|MRI|PET/CT|X-Ray|Ultrasound", "All Modalities")

    GUICtrlCreateLabel("Room:", 375, 17, 40, 20)
    GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
    $cmbRepRoom = GUICtrlCreateCombo("All Rooms", 420, 12, 110, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($cmbRepRoom, "Scan Rm 1|Scan Rm 2|MRI Suite A|MRI Suite B|X-Ray Room 1", "All Rooms")

    GUICtrlCreateLabel("Patient:", 545, 17, 50, 20)
    GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
    $cmbRepPatient = GUICtrlCreateCombo("All Patients", 600, 12, 160, 25, $CBS_DROPDOWNLIST)
    GUICtrlSetData($cmbRepPatient, "Jane Doe|Emily White|Robert Johnson|John Smith|Alice Williams|John Davis|Lisa Chen|Tomorrow Patient Test 1|Tomorrow Patient Test 2", "All Patients")
EndFunc

Func _InitReportingLegend()
    GUISwitch($hRepLegend)
    GUISetBkColor(0xECEFF1, $hRepLegend)

    $btnRepNewEvent    = GUICtrlCreateButton("+ New Report Record", 12, 14, 150, 30)
    GUICtrlSetFont($btnRepNewEvent, 9, 700, 0, "Segoe UI")
    $btnRepEditPatient = GUICtrlCreateButton("Update Status / Rad", 175, 14, 140, 30)
    $btnRepPrint       = GUICtrlCreateButton("Print Queue", 330, 14, 100, 30)
    $btnRepExport      = GUICtrlCreateButton("Export CSV", 440, 14, 100, 30)
EndFunc

Func _InitReportingCalendar()
    GUISwitch($hRepCalendar)
    GUISetBkColor(0xFFFFFF, $hRepCalendar)
    
    $idListViewRep = GUICtrlCreateListView("ID|Date|Time|Patient|Procedure|Modality|Room|Status|Assigned Tech / Rad", 10, 10, 800, 500, BitOR($LVS_REPORT, $LVS_SINGLESEL, $LVS_SHOWSELALWAYS), BitOR($WS_EX_CLIENTEDGE,0))
    _GUICtrlListView_SetExtendedListViewStyle($idListViewRep, BitOR($LVS_EX_FULLROWSELECT, $LVS_EX_GRIDLINES, $LVS_EX_DOUBLEBUFFER))
    
    _GUICtrlListView_SetColumnWidth($idListViewRep, 0, 40)  ; ID
    _GUICtrlListView_SetColumnWidth($idListViewRep, 1, 85)  ; Date
    _GUICtrlListView_SetColumnWidth($idListViewRep, 2, 60)  ; Time
    _GUICtrlListView_SetColumnWidth($idListViewRep, 3, 150) ; Patient
    _GUICtrlListView_SetColumnWidth($idListViewRep, 4, 200) ; Procedure
    _GUICtrlListView_SetColumnWidth($idListViewRep, 5, 75)  ; Modality
    _GUICtrlListView_SetColumnWidth($idListViewRep, 6, 85)  ; Room
    _GUICtrlListView_SetColumnWidth($idListViewRep, 7, 110) ; Status
    _GUICtrlListView_SetColumnWidth($idListViewRep, 8, 160) ; Assigned Tech/Rad

    _SyncReportingFromWorklist()
    _RenderRepCalendar()
EndFunc

; Synchronizes Reporting queue directly from Worklist schedule (using the same source!)
Func _SyncReportingFromWorklist()
    $iRepCount = 0
    For $i = 0 To $iScheduleCount - 1
        Local $sDate = $sTodaySlash
        If StringLen($aSchedule[$i][0]) == 8 Then
            $sDate = StringLeft($aSchedule[$i][0], 4) & "/" & StringMid($aSchedule[$i][0], 5, 2) & "/" & StringRight($aSchedule[$i][0], 2)
        EndIf
        
        Local $sStatus = "Pending Read"
        If $i < 3 Then $sStatus = "Finalized"
        If $i >= 3 And $i < 6 Then $sStatus = "In Review"
        If $i >= 8 Then $sStatus = "Stat Urgent"
        
        _AddReportingItem($sDate, $aSchedule[$i][1], $aSchedule[$i][3], $aSchedule[$i][4], $aSchedule[$i][7], $aSchedule[$i][6], $sStatus, $aSchedule[$i][5])
    Next
EndFunc

Func _AddReportingItem($sDate, $sTime, $sPatient, $sProc, $sMod, $sRoom, $sStatus, $sRad)
    If $iRepCount >= 150 Then Return
    $aRepData[$iRepCount][0] = StringFormat("%03d", $iRepCount + 101)
    $aRepData[$iRepCount][1] = $sDate
    $aRepData[$iRepCount][2] = $sTime
    $aRepData[$iRepCount][3] = $sPatient
    $aRepData[$iRepCount][4] = $sProc
    $aRepData[$iRepCount][5] = $sMod
    $aRepData[$iRepCount][6] = $sRoom
    $aRepData[$iRepCount][7] = $sStatus
    $aRepData[$iRepCount][8] = $sRad
    $iRepCount += 1
EndFunc

Func _RenderRepCalendar()
    If Not WinExists($hRepCalendar) Then Return
    
    Local $sModFilter     = "All Modalities"
    Local $sRoomFilter    = "All Rooms"
    Local $sPatientFilter = "All Patients"
    Local $sDateFilter    = ""

    If IsDeclared("cmbRepModality") And GUICtrlRead($cmbRepModality) <> "" Then $sModFilter = GUICtrlRead($cmbRepModality)
    If IsDeclared("cmbRepRoom") And GUICtrlRead($cmbRepRoom) <> "" Then $sRoomFilter = GUICtrlRead($cmbRepRoom)
    If IsDeclared("cmbRepPatient") And GUICtrlRead($cmbRepPatient) <> "" Then $sPatientFilter = GUICtrlRead($cmbRepPatient)
    If IsDeclared("dtpRepDate") And GUICtrlRead($dtpRepDate) <> "" Then $sDateFilter = GUICtrlRead($dtpRepDate)

    _GUICtrlListView_BeginUpdate($idListViewRep)
    _GUICtrlListView_DeleteAllItems(GUICtrlGetHandle($idListViewRep))
    
    For $i = 0 To $iRepCount - 1
        Local $bShow = True
        
        If $sModFilter <> "All Modalities" And $aRepData[$i][5] <> $sModFilter Then $bShow = False
        If $sRoomFilter <> "All Rooms" And $aRepData[$i][6] <> $sRoomFilter Then $bShow = False
        If $sPatientFilter <> "All Patients" And $aRepData[$i][3] <> $sPatientFilter Then $bShow = False
        If $sDateFilter <> "" And StringInStr($aRepData[$i][1], $sDateFilter) = 0 Then $bShow = False
        
        If $bShow Then
            Local $sRow = $aRepData[$i][0] & "|" & $aRepData[$i][1] & "|" & $aRepData[$i][2] & "|" & _
                          $aRepData[$i][3] & "|" & $aRepData[$i][4] & "|" & $aRepData[$i][5] & "|" & _
                          $aRepData[$i][6] & "|" & $aRepData[$i][7] & "|" & $aRepData[$i][8]
            GUICtrlCreateListViewItem($sRow, $idListViewRep)
        EndIf
    Next
    
    _GUICtrlListView_EndUpdate($idListViewRep)
EndFunc

Func _HandleRepNewEvent()
    Local $sNewPatient = InputBox("New Reporting Event", "Enter Patient Name:", "New Patient, Test")
    If @error Or StringStripWS($sNewPatient, 8) = "" Then Return
    
    _AddReportingItem($sTodaySlash, "15:00", $sNewPatient, "Diagnostic X-Ray", "X-Ray", "X-Ray Room 1", "Pending Read", "Dr. A. Patel")
    _RenderRepCalendar()
    
    ; Also add to worklist so it shows there too
    If $iScheduleCount < 150 Then
        $aSchedule[$iScheduleCount][0] = $sTodayYYYYMMDD
        $aSchedule[$iScheduleCount][1] = "15:00"
        $aSchedule[$iScheduleCount][2] = "16:00"
        $aSchedule[$iScheduleCount][3] = $sNewPatient
        $aSchedule[$iScheduleCount][4] = "Diagnostic X-Ray"
        $aSchedule[$iScheduleCount][5] = "Dr. A. Patel"
        $aSchedule[$iScheduleCount][6] = "X-Ray Room 1"
        $aSchedule[$iScheduleCount][7] = "X-Ray"
        $aSchedule[$iScheduleCount][8] = "0x64748B"
        $iScheduleCount += 1
    EndIf
    _RenderWorklist()
EndFunc

Func _HandleRepEditPatient()
    Local $iSel = _GUICtrlListView_GetSelectionMark($idListViewRep)
    If $iSel = -1 Then
        MsgBox(48, "Selection Required", "Please select a patient reporting record from the list first.")
        Return
    EndIf
    
    Local $sID = _GUICtrlListView_GetItemText($idListViewRep, $iSel, 0)
    For $i = 0 To $iRepCount - 1
        If $aRepData[$i][0] = $sID Then
            Local $sNewStatus = InputBox("Update Report Status", "Enter new status (Pending Read, In Review, Finalized, Stat Urgent):", $aRepData[$i][7])
            If Not @error And StringStripWS($sNewStatus, 8) <> "" Then
                $aRepData[$i][7] = $sNewStatus
                _RenderRepCalendar()
            EndIf
            ExitLoop
        EndIf
    Next
EndFunc

Func _ChangeRepDate($iDays)
    Local $sCurrentDate = GUICtrlRead($dtpRepDate)
    Local $sNewDate = _DateAdd('D', $iDays, $sCurrentDate)
    GUICtrlSetData($dtpRepDate, $sNewDate)
    _RenderRepCalendar()
EndFunc

; ==================== GUI MANAGEMENT & RESIZING ====================

Func _HandleResizerDrag($iSplitterID)
    While _IsPressed("01")
        Local $aCursorInfo = GUIGetCursorInfo($hMainGUI)
        If Not IsArray($aCursorInfo) Then ContinueLoop

        Local $aClient = WinGetClientSize($hMainGUI)
        Local $bChanged = False

        Switch $iSplitterID
            Case $idSplitSidebar
                Local $iNewW = $aCursorInfo[0]
                If $iNewW < 120 Then $iNewW = 120
                If $iNewW > $aClient[0] - $g_iOverviewW - 200 Then $iNewW = $aClient[0] - $g_iOverviewW - 200
                If $g_iSidebarW <> $iNewW Then
                    $g_iSidebarW = $iNewW
                    $bChanged = True
                EndIf

            Case $idSplitOverview
                Local $iNewW = $aClient[0] - $aCursorInfo[0]
                If $iNewW < 150 Then $iNewW = 150
                If $iNewW > $aClient[0] - $g_iSidebarW - 200 Then $iNewW = $aClient[0] - $g_iSidebarW - 200
                If $g_iOverviewW <> $iNewW Then
                    $g_iOverviewW = $iNewW
                    GUICtrlSetPos($lblOverviewData, 15, 45, $g_iOverviewW - 30, 600)
                    $bChanged = True
                EndIf

            Case $idSplitFilter
                Local $iNewH = $aCursorInfo[1] - $HEADER_H
                If $iNewH < 40 Then $iNewH = 40
                If $iNewH > $aClient[1] - $HEADER_H - $STATUS_H - $g_iLegendH - 150 Then $iNewH = $aClient[1] - $HEADER_H - $STATUS_H - $g_iLegendH - 150
                If $g_iFilterH <> $iNewH Then
                    $g_iFilterH = $iNewH
                    $bChanged = True
                EndIf

            Case $idSplitLegend
                Local $iNewH = ($aClient[1] - $STATUS_H) - $aCursorInfo[1]
                If $iNewH < 30 Then $iNewH = 30
                If $iNewH > $aClient[1] - $HEADER_H - $STATUS_H - $g_iFilterH - 150 Then $iNewH = $aClient[1] - $HEADER_H - $STATUS_H - $g_iFilterH - 150
                If $g_iLegendH <> $iNewH Then
                    $g_iLegendH = $iNewH
                    $bChanged = True
                EndIf
        EndSwitch

        If $bChanged Then _UpdateLayout($aClient[0], $aClient[1])
        Sleep(10)
    WEnd
EndFunc

Func _SelectNav($iClickedID)
    If $iClickedID >= $btnNav1 And $iClickedID <= $btnNav6 Then
        For $i = $btnNav1 To $btnNav6
            GUICtrlSetBkColor($i, $COL_TAB_INACTIVE)
            GUICtrlSetColor($i, $COL_TAB_TEXT_IN)
        Next
        GUICtrlSetBkColor($iClickedID, $COL_TAB_ACTIVE)
        GUICtrlSetColor($iClickedID, $COL_TAB_TEXT_ACT)

        GUISetState(@SW_HIDE, $hWorkFilter)
        GUISetState(@SW_HIDE, $hWorklist)
        GUISetState(@SW_HIDE, $hWorkLegend)
        GUISetState(@SW_HIDE, $hRepFilter)
        GUISetState(@SW_HIDE, $hRepCalendar)
        GUISetState(@SW_HIDE, $hRepLegend)

        If $iClickedID = $btnNav2 Then ; Worklist View
            GUISetState(@SW_SHOW, $hWorkFilter)
            GUISetState(@SW_SHOW, $hWorklist)
            GUISetState(@SW_SHOW, $hWorkLegend)
            _RenderWorklist()
            _UpdateWorklistScrollbars()
        ElseIf $iClickedID = $btnNav4 Then ; Reporting View
            _SyncReportingFromWorklist()
            GUISetState(@SW_SHOW, $hRepFilter)
            GUISetState(@SW_SHOW, $hRepCalendar)
            GUISetState(@SW_SHOW, $hRepLegend)
            _RenderRepCalendar()
        EndIf
        
        ; Handle Logout button click
        If $iClickedID = $btnNav6 Then
            _HandleLogout()
        EndIf
    EndIf

    If $iClickedID >= $btnSide1 And $iClickedID <= $btnSide5 Then
        For $i = $btnSide1 To $btnSide5
            GUICtrlSetBkColor($i, $COL_SIDE_INACTIVE)
        Next
        GUICtrlSetBkColor($iClickedID, $COL_SIDE_ACTIVE)

        Local $iIndex = $iClickedID - $btnSide1
        Local $iNewY = 20 + ($iIndex * 50)
        GUICtrlSetPos($hActiveIndicator, 0, $iNewY, 4, 40)
        GUICtrlSetState($hActiveIndicator, $GUI_SHOW)
    EndIf
EndFunc

Func WM_SIZE($hWnd, $iMsg, $wParam, $lParam)
    If $hWnd <> $hMainGUI Then Return $GUI_RUNDEFMSG
    Local $iNewWidth  = BitAND($lParam, 0xFFFF)
    Local $iNewHeight = BitShift($lParam, 16)
    If $iNewWidth < 100 Or $iNewHeight < 100 Then Return $GUI_RUNDEFMSG

    ; Resize Login Overlay if it exists
    If WinExists($hLoginGUI) Then
        WinMove($hLoginGUI, "", 0, 0, $iNewWidth, $iNewHeight)
        WinMove($hLoginBox, "", ($iNewWidth-400)/2, ($iNewHeight-300)/2)
    EndIf

    _UpdateLayout($iNewWidth, $iNewHeight)
    Return $GUI_RUNDEFMSG
EndFunc

Func _UpdateLayout($iW, $iH)
    WinMove($hHeader,   "", 0, 0, $iW, $HEADER_H)
    WinMove($hSidebar,  "", 0, $HEADER_H, $g_iSidebarW, $iH - $HEADER_H - $STATUS_H)
    WinMove($hOverview, "", $iW - $g_iOverviewW, $HEADER_H, $g_iOverviewW, $iH - $HEADER_H - $STATUS_H)
    WinMove($hStatus,   "", 0, $iH - $STATUS_H, $iW, $STATUS_H)

    Local $iCenterW = $iW - $g_iSidebarW - $g_iOverviewW
    Local $iCenterX = $g_iSidebarW
    Local $iCalendarH = $iH - $HEADER_H - $g_iFilterH - $g_iLegendH - $STATUS_H
    If $iCalendarH < 50 Then $iCalendarH = 50

    WinMove($hWorkFilter, "", $iCenterX, $HEADER_H, $iCenterW, $g_iFilterH)
    WinMove($hWorklist,   "", $iCenterX, $HEADER_H + $g_iFilterH, $iCenterW, $iCalendarH)
    WinMove($hWorkLegend, "", $iCenterX, $HEADER_H + $g_iFilterH + $iCalendarH, $iCenterW, $g_iLegendH)
    _UpdateWorklistScrollbars()

    WinMove($hRepFilter,   "", $iCenterX, $HEADER_H, $iCenterW, $g_iFilterH)
    WinMove($hRepCalendar, "", $iCenterX, $HEADER_H + $g_iFilterH, $iCenterW, $iCalendarH)
    WinMove($hRepLegend,   "", $iCenterX, $HEADER_H + $g_iFilterH + $iCalendarH, $iCenterW, $g_iLegendH)
    
    If WinExists($hRepCalendar) Then
        Local $aCalSize = WinGetClientSize($hRepCalendar)
        If IsArray($aCalSize) Then
            GUICtrlSetPos($idListViewRep, 10, 10, $aCalSize[0] - 20, $aCalSize[1] - 20)
        EndIf
    EndIf
    If BitAND(WinGetState($hRepCalendar), 2) Then _RenderRepCalendar()

    GUICtrlSetPos($idSplitSidebar, $g_iSidebarW - 4, 0, 4, $iH - $HEADER_H - $STATUS_H)
    GUICtrlSetPos($idSplitOverview, 0, 0, 4, $iH - $HEADER_H - $STATUS_H)
    GUICtrlSetPos($idSplitFilter, 0, $g_iFilterH - 4, $iCenterW, 4)
    GUICtrlSetPos($idSplitLegend, 0, 0, $iCenterW, 4)
EndFunc

Func _SaveWindowState()
    Local $aPos = WinGetPos($hMainGUI)
    If Not @extended Then
        IniWrite($sIniPath, "Window", "Width",  $aPos[2])
        IniWrite($sIniPath, "Window", "Height", $aPos[3])
        IniWrite($sIniPath, "Window", "X",      $aPos[0])
        IniWrite($sIniPath, "Window", "Y",      $aPos[1])
        IniWrite($sIniPath, "Layout", "SidebarW",  $g_iSidebarW)
        IniWrite($sIniPath, "Layout", "OverviewW", $g_iOverviewW)
        IniWrite($sIniPath, "Layout", "FilterH",   $g_iFilterH)
        IniWrite($sIniPath, "Layout", "LegendH",   $g_iLegendH)
    EndIf
EndFunc

; ==================== SCROLLING HANDLERS ====================
Func WM_VSCROLL($hWnd, $iMsg, $wParam, $lParam)
    If $hWnd <> $hWorklist Then Return $GUI_RUNDEFMSG
    Local $iOldY = $g_iScrollY
    Local $iAction = BitAND($wParam, 0x0000FFFF)
    
    Switch $iAction
        Case $SB_LINEUP
            $g_iScrollY -= 48
        Case $SB_LINEDOWN
            $g_iScrollY += 48
        Case $SB_PAGEUP
            $g_iScrollY -= 150
        Case $SB_PAGEDOWN
            $g_iScrollY += 150
        Case $SB_THUMBTRACK
            $g_iScrollY = BitShift($wParam, 16)
    EndSwitch

    Local $aWin = WinGetClientSize($hWorklist)
    Local $iMaxScroll = $g_iTotalGridHeight - $aWin[1]
    If $iMaxScroll < 0 Then $iMaxScroll = 0

    If $g_iScrollY < 0 Then $g_iScrollY = 0
    If $g_iScrollY > $iMaxScroll Then $g_iScrollY = $iMaxScroll

    If $g_iScrollY <> $iOldY Then
        DllCall("user32.dll", "int", "ScrollWindow", "hwnd", $hWorklist, "int", 0, "int", $iOldY - $g_iScrollY, "ptr", 0, "ptr", 0)
        _WinAPI_InvalidateRect($hWorklist)
        _GUIScrollBars_SetScrollInfoPos($hWorklist, $SB_VERT, $g_iScrollY)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func WM_HSCROLL($hWnd, $iMsg, $wParam, $lParam)
    If $hWnd <> $hWorklist Then Return $GUI_RUNDEFMSG
    Local $iOldX = $g_iScrollX
    Local $iAction = BitAND($wParam, 0x0000FFFF)
    
    Switch $iAction
        Case $SB_LINELEFT
            $g_iScrollX -= 30
        Case $SB_LINERIGHT
            $g_iScrollX += 30
        Case $SB_THUMBTRACK
            $g_iScrollX = BitShift($wParam, 16)
    EndSwitch
    
    If $g_iScrollX < 0 Then $g_iScrollX = 0
    If $g_iScrollX > $g_iTotalGridWidth Then $g_iScrollX = $g_iTotalGridWidth
    If $g_iScrollX <> $iOldX Then
        DllCall("user32.dll", "int", "ScrollWindow", "hwnd", $hWorklist, "int", $iOldX - $g_iScrollX, "int", 0, "ptr", 0, "ptr", 0)
        _WinAPI_InvalidateRect($hWorklist)
        _GUIScrollBars_SetScrollInfoPos($hWorklist, $SB_HORZ, $g_iScrollX)
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc

Func WM_MOUSEWHEEL($hWnd, $iMsg, $wParam, $lParam)
    If BitAND(WinGetState($hWorklist), 2) Then
        Local $iDelta = BitShift($wParam, 16)
        If $iDelta > 0 Then
            WM_VSCROLL($hWorklist, $WM_VSCROLL, $SB_LINEUP, 0)
        Else
            WM_VSCROLL($hWorklist, $WM_VSCROLL, $SB_LINEDOWN, 0)
        EndIf
    EndIf
    Return $GUI_RUNDEFMSG
EndFunc