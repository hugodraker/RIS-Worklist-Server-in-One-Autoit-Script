#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <StructureConstants.au3>
#include <WinAPISysWin.au3>
#include <Misc.au3> ; Required for _IsPressed to handle drag states
#include "calendar02.au3" ; Include the upgraded modern calendar module

; ==================== CONSTANTS ====================
; --- COLORS ---
Global Const $COL_NAV         = 0x1B364A ; Dark Navy Header
Global Const $COL_SIDEBAR     = 0x243647 ; Sidebar Background
Global Const $COL_PANEL       = 0xECEFF1 ; Light Panel
Global Const $COL_STATUS      = 0x2A3E52 ; Status Bar
Global Const $COL_TEXT        = 0xFFFFFF ; White Text
Global Const $COL_INDICATOR   = 0x00BFFF ; Bright Blue Sidebar Line

; --- SIDEBAR HIGHLIGHT COLORS ---
Global Const $COL_SIDE_INACTIVE = 0x243647 ; Blends into sidebar
Global Const $COL_SIDE_ACTIVE   = 0x005A8C ; Distinct rich ocean blue highlight

; --- TOP FOLDER TAB COLORS ---
Global Const $COL_TAB_INACTIVE  = 0x24435C ; Muted blue-grey tab
Global Const $COL_TAB_ACTIVE    = 0xDDE3E8 ; Matches the Filter bar below it (Folder Tab effect!)
Global Const $COL_TAB_TEXT_IN   = 0xFFFFFF ; White text for inactive tab
Global Const $COL_TAB_TEXT_ACT  = 0x1B364A ; Dark navy text for active tab

; --- CONFIG FILE ---
Global Const $sScriptName = StringRegExpReplace(@ScriptName, "\.[^.]+$", "")
Global Const $sIniPath    = @ScriptDir & "\" & $sScriptName & ".ini"

; --- DEFAULT WINDOW SIZE & STATIC LAYOUT ---
Global Const $DEFAULT_WIDTH  = 1024
Global Const $DEFAULT_HEIGHT = 720
Global Const $HEADER_H   = 50
Global Const $STATUS_H   = 30

; --- DYNAMIC RESIZING VARIABLES ---
Global $g_iSidebarW  = Number(IniRead($sIniPath, "Layout", "SidebarW", 170))
Global $g_iOverviewW = Number(IniRead($sIniPath, "Layout", "OverviewW", 220))
Global $g_iFilterH   = Number(IniRead($sIniPath, "Layout", "FilterH", 50))
Global $g_iLegendH   = Number(IniRead($sIniPath, "Layout", "LegendH", 80))

; ==================== MAIN GUI ====================
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

; --- 1. Create Child Windows ---
Global Const $iChildStyle = BitOR($WS_CHILD, $WS_CLIPSIBLINGS)

Global $hHeader   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor($COL_NAV, $hHeader)

Global $hSidebar  = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor($COL_SIDEBAR, $hSidebar)

Global $hFilter   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor(0xDDE3E8, $hFilter) 

Global $hCalendar = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor(0xFFFFFF, $hCalendar)

Global $hLegend   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor($COL_PANEL, $hLegend)

Global $hOverview = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor(0xF1F5F9, $hOverview) ; Clean slate background matching calendar headers

Global $hStatus   = GUICreate("", 100, 100, 0, 0, $iChildStyle, -1, $hMainGUI)
GUISetBkColor($COL_STATUS, $hStatus)

GUIRegisterMsg($WM_SIZE, "WM_SIZE")

; --- 2. POPULATE CONTROLS & RESIZE SPLITTERS ---

; Header & Folder Tabs
GUISwitch($hHeader)
GUICtrlCreateLabel("DAILY TECHNICIAN SCHEDULE - MGH", 10, 15, 300, 20)
GUICtrlSetColor(-1, $COL_TEXT)
GUICtrlSetFont(-1, 9.5, 700, 0, "Segoe UI")
GUICtrlSetResizing(-1, $GUI_DOCKALL)

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

; Sidebar Buttons & Splitter
GUISwitch($hSidebar)
Global $btnSide1 = GUICtrlCreateLabel("  Notifications (2)",   15, 20,  150, 40, $SS_CENTERIMAGE)
Global $btnSide2 = GUICtrlCreateLabel("  Recent Patients",     15, 70,  150, 40, $SS_CENTERIMAGE)
Global $btnSide3 = GUICtrlCreateLabel("  Reporting Queue (9)", 15, 120, 150, 40, $SS_CENTERIMAGE)
Global $btnSide4 = GUICtrlCreateLabel("  Tech Notes",          15, 170, 150, 40, $SS_CENTERIMAGE)
Global $btnSide5 = GUICtrlCreateLabel("  System Status",       15, 220, 150, 40, $SS_CENTERIMAGE)

Global $hActiveIndicator = GUICtrlCreateLabel("", 0, 20, 4, 40)
GUICtrlSetBkColor($hActiveIndicator, $COL_INDICATOR)
GUICtrlSetResizing($hActiveIndicator, $GUI_DOCKALL)

Global $idSplitSidebar = GUICtrlCreateLabel("", 0, 0, 4, 10)
GUICtrlSetCursor(-1, 13) ; WE Split Cursor
GUICtrlSetBkColor(-1, $COL_NAV) 

For $i = $btnSide1 To $btnSide5
    GUICtrlSetBkColor($i, $COL_SIDE_INACTIVE)
    GUICtrlSetColor($i, $COL_TEXT)
    GUICtrlSetFont($i, 9, 600, 0, "Segoe UI")
    GUICtrlSetCursor($i, 0)
    GUICtrlSetResizing($i, $GUI_DOCKALL)
Next

; Overview Panel & Splitter
GUISwitch($hOverview)
GUICtrlCreateLabel("EVENT OVERVIEW", 15, 15, 200, 20)
GUICtrlSetFont(-1, 9, 700, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x1E293B)
GUICtrlSetResizing(-1, $GUI_DOCKALL)

; Hook this label ID into calendar02 for dynamic card click updates
Global $lblOverviewData = GUICtrlCreateLabel("Select any scheduled event card on the timeline to view clinical details and assigned technical staff." & @CRLF & @CRLF & "Double-click a card to edit or remove it.", 15, 45, $g_iOverviewW - 30, 500)
GUICtrlSetFont(-1, 9, 400, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x334155)
GUICtrlSetResizing(-1, $GUI_DOCKALL)

Global $idSplitOverview = GUICtrlCreateLabel("", 0, 0, 4, 10)
GUICtrlSetCursor(-1, 13) ; WE Split Cursor
GUICtrlSetBkColor(-1, $COL_NAV)

; Filter Panel Splitter & Quick Info
GUISwitch($hFilter)
GUICtrlCreateLabel("  Filter by Modality:   [ All ]    [ CT Suite ]    [ MRI Suite ]    [ PET/CT ]  |  Viewing: Thursday, Dec 5, 2024", 10, 15, 800, 20)
GUICtrlSetFont(-1, 9, 600, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x1E293B)

Global $idSplitFilter = GUICtrlCreateLabel("", 0, 0, 10, 4)
GUICtrlSetCursor(-1, 11) ; NS Split Cursor
GUICtrlSetBkColor(-1, $COL_NAV)

; Legend Panel
GUISwitch($hLegend)
GUICtrlCreateLabel("  MODALITY LEGEND:   ■ Emerald: Day Routine   ■ Royal Blue: Standard MRI/CT   ■ Amber: On-Call / Standby   ■ Violet: PET/CT Oncology   ■ Rose: Emergency / Trauma", 10, 12, 1000, 20)
GUICtrlSetFont(-1, 8.5, 600, 0, "Segoe UI")
GUICtrlSetColor(-1, 0x475569)

Global $idSplitLegend = GUICtrlCreateLabel("", 0, 0, 10, 4)
GUICtrlSetCursor(-1, 11) ; NS Split Cursor
GUICtrlSetBkColor(-1, $COL_NAV)

; Status Bar
GUISwitch($hStatus)
GUICtrlCreateLabel("  User: Dr. Anjali Patel | Terminal: WKS-RAD-04 | Status: Connected (Database Synced)", 10, 6, 500, 20)
GUICtrlSetColor(-1, $COL_TEXT)
GUICtrlSetFont(-1, 8.5, 400, 0, "Segoe UI")
GUICtrlSetResizing(-1, $GUI_DOCKALL)

; --- 3. INITIALIZATION & LAYOUT ---
_UpdateLayout($iSaveWidth, $iSaveHeight)
_SelectNav($btnSide1) 
_SelectNav($btnNav3) ; Default to "Scheduling" tab active

; Initialize calendar02 inside the $hCalendar pane and link the Overview label
_Calendar_Init($hCalendar, $hMainGUI, $lblOverviewData)
Local $aCalClient = WinGetClientSize($hCalendar)
_Calendar_Resize($aCalClient[0], $aCalClient[1])

Local $aWindows = [$hHeader, $hSidebar, $hFilter, $hCalendar, $hLegend, $hOverview, $hStatus]
For $w In $aWindows
    GUISetState(@SW_SHOW, $w)
Next
GUISetState(@SW_SHOW, $hMainGUI)

; ==================== MAIN EVENT LOOP ====================
While 1
    Local $iMsg = GUIGetMsg()

    If $iMsg = $GUI_EVENT_CLOSE Then
        _SaveWindowState()
        Exit
    EndIf

    ; Delegate clicks to Calendar02 (handles single-click overview & double-click edit dialogs)
    If _Calendar_HandleClick($iMsg) Then ContinueLoop

    ; Catch Splitter Handles
    If $iMsg = $idSplitSidebar Or $iMsg = $idSplitOverview Or $iMsg = $idSplitFilter Or $iMsg = $idSplitLegend Then
        _HandleResizerDrag($iMsg)
    EndIf

    If ($iMsg >= $btnNav1 And $iMsg <= $btnNav6) Or ($iMsg >= $btnSide1 And $iMsg <= $btnSide5) Then
        _SelectNav($iMsg)
    EndIf
WEnd

; ==================== FUNCTIONS ====================

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
                    ; Keep overview text wrapped nicely within new width
                    GUICtrlSetPos($lblOverviewData, 15, 45, $g_iOverviewW - 30, 500)
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

        If $bChanged Then
            _UpdateLayout($aClient[0], $aClient[1])
        EndIf

        Sleep(10) ; Prevents high CPU usage during drag loops
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

    _UpdateLayout($iNewWidth, $iNewHeight)
    Return $GUI_RUNDEFMSG
EndFunc

Func _UpdateLayout($iW, $iH)
    ; --- Pinned-edge panels ---
    WinMove($hHeader,   "", 0, 0, $iW, $HEADER_H)
    WinMove($hSidebar,  "", 0, $HEADER_H, $g_iSidebarW, $iH - $HEADER_H - $STATUS_H)
    WinMove($hOverview, "", $iW - $g_iOverviewW, $HEADER_H, $g_iOverviewW, $iH - $HEADER_H - $STATUS_H)
    WinMove($hStatus,   "", 0, $iH - $STATUS_H, $iW, $STATUS_H)

    ; --- Center 3 panels ---
    Local $iCenterW = $iW - $g_iSidebarW - $g_iOverviewW
    Local $iCenterX = $g_iSidebarW

    Local $iCalendarH = $iH - $HEADER_H - $g_iFilterH - $g_iLegendH - $STATUS_H
    If $iCalendarH < 50 Then $iCalendarH = 50

    WinMove($hFilter,   "", $iCenterX, $HEADER_H, $iCenterW, $g_iFilterH)
    WinMove($hCalendar, "", $iCenterX, $HEADER_H + $g_iFilterH, $iCenterW, $iCalendarH)
    WinMove($hLegend,   "", $iCenterX, $HEADER_H + $g_iFilterH + $iCalendarH, $iCenterW, $g_iLegendH)

    ; --- Inform calendar02 of new dimensions to adjust scrollbars ---
    _Calendar_Resize($iCenterW, $iCalendarH)

    ; --- Un-docked Splitter Position Updates ---
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