; ===================================================================
; FULL MERGED RIS MWL SCP + TELNET CSV SERVER + GUI (STABILIZED)
; Fixed: COM Object Removal, Socket Error Handling, GUI Initialization
; ===================================================================
;run telnet 127.0.0.1 23
;DISP OT YYYYDDMM YYYYDDMM ; show range of patients for modality OT
;DISP OT YYYYDDMM ;SHOW TODAYS PATIENTS
;DISP ; show whole worklist
;to add a patient to the worklist in telnet try: 
;10002,Jane Smith,ACC002,19920515,F,SPS002,CT Head w/o Contrast,RP002,AET1,CT,20260606,10:30,CT Head w/o Contrast,1.2.3.4.5.2,Dr. Brown,2,PCODE02,CT Head


;#RequireAdmin

#include <Array.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <File.au3>
#include <Date.au3>

Opt("TrayAutoPause", 0)
Opt("TrayMenuMode", 3)

; ===================================================================
; DYNAMIC INI & CONFIGURATION
; ===================================================================
Global $INI_FILE = @ScriptDir & "\" & StringRegExpReplace(@ScriptName, "\.[^.]*$", "") & ".ini"
Global Const $CSV_FILE = @ScriptDir & "\patients.csv"

; 18-Column CSV Header
Global Const $CSV_HEADER = "PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName,Status,ProcedureCode,ProcedureCodeDesc"

Global Const $APPEND_DELAY_MS = 2000

Global $SERVER_AET = "AUTOIT_SCP"
Global $DICOM_PORT = 104
Global $TELNET_PORT = 23
Global $TELNET_TIMEOUT = 10 ; Default 10 seconds
Global $TRAY_CHECKED=0
; ===================================================================
; GLOBALS
; ===================================================================
Global $g_bRunning = False
Global $g_listenSocket = -1
Global $g_dicomsock = -1

; Telnet clients array: [0=Socket, 1=ID, 2=Buffer, 3=LastActivityTimer, 4=PendingEntry(Array), 5=PendingSinceTimer, 6=CurrentTimeoutLimitMS]
Global $g_aClients[0][7]

; GUI handles
Global $g_hStatusLabel = 0
Global $g_hClientsLabel = 0
Global $g_hLogEdit = 0

; Tray menu IDs
Global $g_idToggle = 0
Global $g_idSettings = 0
Global $g_idExit = 0

; Patients cache for MWL
Global $gPatients_RIS = 0

; ===================================================================
; INITIALIZE TCP & CONFIG
; ===================================================================
TCPStartup()

If Not FileExists($INI_FILE) Then
    IniWrite($INI_FILE, "Server", "AETitle", "AUTOIT_SCP")
    IniWrite($INI_FILE, "Server", "DicomPort", "104")
    IniWrite($INI_FILE, "Server", "TelnetPort", "23")
    IniWrite($INI_FILE, "Server", "TelnetTimeout", "10")
    
    IniWrite($INI_FILE, "Lists", "Modalities", "CR;DX;CT;MR;US;OT")
    IniWrite($INI_FILE, "Lists", "AETitles", "")
    IniWrite($INI_FILE, "Lists", "ReferringPhysicians", "")
    IniWrite($INI_FILE, "Lists", "Procedures", "")
EndIf

$SERVER_AET = IniRead($INI_FILE, "Server", "AETitle", "AUTOIT_SCP")
$DICOM_PORT = Number(IniRead($INI_FILE, "Server", "DicomPort", "104"))
$TELNET_PORT = Number(IniRead($INI_FILE, "Server", "TelnetPort", "23"))
$TELNET_TIMEOUT = Number(IniRead($INI_FILE, "Server", "TelnetTimeout", "10"))

; ===================================================================
; GUI + TRAY CREATION
; ===================================================================
Func CSVTS_TrayCreate()
    $g_idToggle   = TrayCreateItem("Server Running")
    TrayItemSetState($g_idToggle, $TRAY_CHECKED)
    $g_idSettings = TrayCreateItem("Settings")
    TrayCreateItem("")
    $g_idExit     = TrayCreateItem("Exit")
    TraySetToolTip("AutoIt RIS MWL SCP + Telnet")
    TraySetState()
EndFunc

Func CSVTS_CreateMainGUI()
    GUICreate("AutoIt RIS MWL SCP + Telnet Server", 700, 380, -1, -1, BitOR($WS_SIZEBOX, $WS_SYSMENU))
    GUISetOnEvent($GUI_EVENT_CLOSE, "CSVTS_HideMainGUI")

    $g_hStatusLabel = GUICtrlCreateLabel("Server status: Stopped", 10, 10, 500, 20)
    $g_hClientsLabel = GUICtrlCreateLabel("Active clients: 0", 10, 35, 200, 20)

    GUICtrlCreateLabel("Log:", 10, 60, 50, 20)
    $g_hLogEdit = GUICtrlCreateEdit("", 10, 85, 680, 280, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL))

    GUISetState(@SW_HIDE)
EndFunc

Func CSVTS_HideMainGUI()
    GUISetState(@SW_HIDE)
EndFunc

Func CSVTS_ShowSettings()
    Local $h = GUICreate("Settings", 420, 300)
    
    GUICtrlCreateLabel("INI file: " & StringRegExpReplace($INI_FILE, "^.*\\", ""), 10, 10, 400, 20)
    GUICtrlCreateLabel("Server AET: " & $SERVER_AET, 10, 40, 200)
    GUICtrlCreateLabel("DICOM Port: " & $DICOM_PORT, 180, 40, 100)
    GUICtrlCreateLabel("Telnet Port: " & $TELNET_PORT, 300, 40, 100)

    GUICtrlCreateLabel("Modalities:", 10, 80)
    GUICtrlCreateLabel(IniRead($INI_FILE, "Lists", "Modalities", ""), 120, 80, 280)
    GUICtrlCreateLabel("AETitles:", 10, 110)
    GUICtrlCreateLabel(IniRead($INI_FILE, "Lists", "AETitles", ""), 120, 110, 280)
    GUICtrlCreateLabel("Referring Physicians:", 10, 140)
    GUICtrlCreateLabel(IniRead($INI_FILE, "Lists", "ReferringPhysicians", ""), 160, 140, 240)
    GUICtrlCreateLabel("Procedures:", 10, 170)
    GUICtrlCreateLabel(IniRead($INI_FILE, "Lists", "Procedures", ""), 120, 170, 280)

    Local $btnClose = GUICtrlCreateButton("Close", 170, 230, 80, 30)
    GUISetState(@SW_SHOW, $h)

    While 1
        Local $m = GUIGetMsg(1)
        If $m = $GUI_EVENT_CLOSE Or $m = $btnClose Then ExitLoop
        Sleep(50)
    WEnd
    GUIDelete($h)
EndFunc

; ===================================================================
; LOGGING
; ===================================================================
Func CSVTS_Log($s)
    If $g_hLogEdit Then
        Local $text = GUICtrlRead($g_hLogEdit)
        $text &= "[" & @HOUR & ":" & @MIN & ":" & @SEC & "] " & $s & @CRLF
        GUICtrlSetData($g_hLogEdit, $text)
    EndIf
    ConsoleWrite($s & @CRLF)
EndFunc

; ===================================================================
; TELNET SERVER CONTROL
; ===================================================================
Func CSVTS_StartServer()
    If $g_bRunning Then Return

    $g_listenSocket = TCPListen("0.0.0.0", $TELNET_PORT)
    If $g_listenSocket = -1 Then
        CSVTS_Log("ERROR: Failed to listen on telnet port " & $TELNET_PORT)
        If $g_hStatusLabel Then GUICtrlSetData($g_hStatusLabel, "Server status: Failed to bind port " & $TELNET_PORT)
        $g_bRunning = False
        Return
    EndIf

    $g_bRunning = True
    CSVTS_Log("Telnet server started and listening on port " & $TELNET_PORT)
    If $g_hStatusLabel Then GUICtrlSetData($g_hStatusLabel, "Server status: Running on port " & $TELNET_PORT)
EndFunc

Func CSVTS_StopServer()
    If Not $g_bRunning Then Return

    For $i = 0 To UBound($g_aClients) - 1
        If $g_aClients[$i][0] <> 0 Then TCPCloseSocket($g_aClients[$i][0])
    Next

    If $g_listenSocket <> -1 Then
        TCPCloseSocket($g_listenSocket)
        $g_listenSocket = -1
    EndIf

    Local $empty[0][7]
    $g_aClients = $empty
    $g_bRunning = False

    CSVTS_Log("Telnet server stopped")
    If $g_hStatusLabel Then GUICtrlSetData($g_hStatusLabel, "Server status: Stopped")
    If $g_hClientsLabel Then GUICtrlSetData($g_hClientsLabel, "Active clients: 0")
EndFunc

; ===================================================================
; TELNET CLIENT MANAGEMENT
; ===================================================================
Func CSVTS_AddClient($sock)
    Local $n = UBound($g_aClients)
    ReDim $g_aClients[$n + 1][7]
    $g_aClients[$n][0] = $sock
    $g_aClients[$n][1] = $sock
    $g_aClients[$n][2] = ""
    $g_aClients[$n][3] = TimerInit()
    $g_aClients[$n][4] = 0
    $g_aClients[$n][5] = 0
    $g_aClients[$n][6] = $TELNET_TIMEOUT * 1000
    CSVTS_Log("Telnet Client connected on socket " & $sock)
EndFunc

Func CSVTS_RemoveClient($index)
    Local $n = UBound($g_aClients) - 1
    If $n < 0 Then Return
    For $j = $index To $n - 1
        For $c = 0 To 6
            $g_aClients[$j][$c] = $g_aClients[$j + 1][$c]
        Next
    Next
    If $n = 0 Then
        Local $empty[0][7]
        $g_aClients = $empty
    Else
        ReDim $g_aClients[$n][7]
    EndIf
EndFunc

; ===================================================================
; TELNET SERVER LOOP
; ===================================================================
Func CSVTS_ServerLoop()
    If $g_listenSocket = -1 Then Return

    Local $newSock = TCPAccept($g_listenSocket)
    If $newSock <> -1 Then
        CSVTS_AddClient($newSock)
        TCPSend($newSock, "Connected to RIS Telnet Server. Waiting for data..." & @CRLF)
    EndIf

    For $i = UBound($g_aClients) - 1 To 0 Step -1
        Local $sock = $g_aClients[$i][0]
        If $sock = 0 Or $sock = -1 Then ContinueLoop

        Local $data = TCPRecv($sock, 4096)
        
        ; Handle disconnect gracefully
        If @error Then
            CSVTS_Log("Client disconnected unexpectedly on socket " & $g_aClients[$i][1])
            TCPCloseSocket($sock)
            CSVTS_RemoveClient($i)
            ContinueLoop
        EndIf

        If $data <> "" Then
            $g_aClients[$i][3] = TimerInit()
            $g_aClients[$i][2] &= $data

            While StringInStr($g_aClients[$i][2], @LF)
                Local $pos = StringInStr($g_aClients[$i][2], @LF)
                Local $line = StringLeft($g_aClients[$i][2], $pos - 1)
                $g_aClients[$i][2] = StringTrimLeft($g_aClients[$i][2], $pos + StringLen(@LF) - 1)
                CSVTS_ProcessClientLine($i, $line)
            WEnd
        EndIf

        ; Check if an array is pending execution
        If IsArray($g_aClients[$i][4]) Then
            If TimerDiff($g_aClients[$i][5]) >= $APPEND_DELAY_MS Then
                CSVTS_CommitPendingEntry($i)
                $g_aClients[$i][3] = TimerInit() ; Reset timeout timer after successful entry
            EndIf
        EndIf

        ; Idle Disconnect Check
        If TimerDiff($g_aClients[$i][3]) >= $g_aClients[$i][6] Then
            CSVTS_Log("Client on socket " & $g_aClients[$i][1] & " timed out")
            TCPCloseSocket($sock)
            CSVTS_RemoveClient($i)
        EndIf
    Next
    If $g_hClientsLabel Then GUICtrlSetData($g_hClientsLabel, "Active clients: " & UBound($g_aClients))
EndFunc

; ===================================================================
; INI LIST UPDATER
; ===================================================================
Func CSVTS_UpdateIniList($key, $value)
    If $value = "" Then Return
    Local $cur = IniRead($INI_FILE, "Lists", $key, "")
    If $cur <> "" Then
        Local $arr = StringSplit($cur, ";")
        For $i = 1 To $arr[0]
            If $arr[$i] = $value Then Return
        Next
    EndIf
    If $cur = "" Then
        $cur = $value
    Else
        $cur &= ";" & $value
    EndIf
    IniWrite($INI_FILE, "Lists", $key, $cur)
EndFunc

; ===================================================================
; COMMIT PENDING ENTRY (Array Based - No COM Objects)
; ===================================================================
Func CSVTS_CommitPendingEntry($clientIndex)
    Local $entry = $g_aClients[$clientIndex][4]
    If Not IsArray($entry) Then Return

    Local $patientID = $entry[0]

    If Not FileExists($CSV_FILE) Then
        Local $hf = FileOpen($CSV_FILE, 2)
        FileWriteLine($hf, $CSV_HEADER)
        FileClose($hf)
    EndIf

    Local $lines = FileReadToArray_RIS($CSV_FILE)
    If @error Or UBound($lines) = 0 Then
        Local $arrInit[1] = [$CSV_HEADER]
        $lines = $arrInit
    EndIf

    Local $found = False
    For $i = 1 To UBound($lines) - 1
        Local $cols = CSV_Split_RIS($lines[$i], 18)
        If StringStripWS($cols[0], 3) = $patientID Then
            $lines[$i] = EntryToCSVLine_RIS($entry)
            $found = True
            ExitLoop
        EndIf
    Next

    If Not $found Then _ArrayAdd($lines, EntryToCSVLine_RIS($entry))

    Local $h = FileOpen($CSV_FILE, 2)
    If $h <> -1 Then
        For $i = 0 To UBound($lines) - 1
            FileWriteLine($h, $lines[$i])
        Next
        FileClose($h)
    EndIf

    CSVTS_UpdateIniList("Modalities", $entry[9])
    CSVTS_UpdateIniList("AETitles", $entry[8])
    CSVTS_UpdateIniList("ReferringPhysicians", $entry[14])
    CSVTS_UpdateIniList("Procedures", $entry[6])

    Local $sock = $g_aClients[$clientIndex][0]
    If $sock <> 0 And $sock <> -1 Then
        If $found Then
            TCPSend($sock, "UPDATED" & @CRLF)
            CSVTS_Log("UPDATED PatientID " & $patientID)
        Else
            TCPSend($sock, "INSERTED" & @CRLF)
            CSVTS_Log("INSERTED PatientID " & $patientID)
        EndIf
    EndIf

    $gPatients_RIS = LoadPatientsCSV_RIS()
    $g_aClients[$clientIndex][4] = 0
    $g_aClients[$clientIndex][5] = 0
EndFunc

; ===================================================================
; DICOM SERVER CONTROL
; ===================================================================
Func DICOM_StartServer()
    If $g_dicomsock <> -1 Then Return
    $g_dicomsock = TCPListen("0.0.0.0", $DICOM_PORT)
    If $g_dicomsock = -1 Then
        CSVTS_Log("ERROR: Failed to listen on DICOM port " & $DICOM_PORT)
        Return
    EndIf
    CSVTS_Log("DICOM MWL SCP listening on port " & $DICOM_PORT)
EndFunc

Func DICOM_StopServer()
    If $g_dicomsock <> -1 Then
        TCPCloseSocket($g_dicomsock)
        $g_dicomsock = -1
        CSVTS_Log("DICOM MWL SCP stopped")
    EndIf
EndFunc

; ===================================================================
; DICOM SERVER LOOP
; ===================================================================
Func DICOM_ServerLoop()
    If $g_dicomsock = -1 Then Return
    Local $hClient = TCPAccept($g_dicomsock)
    If $hClient = -1 Then Return

    CSVTS_Log("DICOM client connected (socket " & $hClient & ")")
    DICOM_HandleClient($hClient)
    TCPCloseSocket($hClient)
    CSVTS_Log("DICOM client disconnected (socket " & $hClient & ")")
EndFunc

; ===================================================================
; DICOM CLIENT ROUTER
; ===================================================================
Func DICOM_HandleClient($hSock)
    Local $assocEstablished = False
    Local $timer = TimerInit()

    While 1
        Local $data = TCPRecv($hSock, 8192, 1)

        If @error = 0 And BinaryLen($data) = 0 Then
            If TimerDiff($timer) > 10000 Then ExitLoop ; Terminate idle hanging connection to prevent blocking
            Sleep(5)
            ContinueLoop
        EndIf

        If @error <> 0 Then
            If $assocEstablished Then DICOM_SendReleaseRSP($hSock)
            ExitLoop
        EndIf

        $timer = TimerInit() ; Reset timer on valid data
        Local $pduType = BinaryMid($data, 1, 1)

        Switch $pduType
            Case Binary("0x01") ; A-ASSOCIATE-RQ
                DICOM_SendAAssociateAC($hSock)
                $assocEstablished = True

            Case Binary("0x04") ; P-DATA-TF
                Local $txt = BinaryToString($data, 4)

                If StringInStr($txt, "1.2.840.10008.1.1") Then
                    Local $msgID = DICOM_ExtractMessageID($data)
                    DICOM_SendCEchoRSP($hSock, $msgID)
                ElseIf StringInStr($txt, "1.2.840.10008.5.1.4.31") Then
                    $gPatients_RIS = LoadPatientsCSV_RIS()
                    Local $msgID = DICOM_ExtractMessageID($data)
                    Local $reqModality = DICOM_ExtractTagString($data, "08006000")
                    Local $reqDate = DICOM_ExtractTagString($data, "40000200")
                    CSVTS_Log("MWL C-FIND -> Modality: [" & ($reqModality ? $reqModality : "*") & "] | Date: [" & ($reqDate ? $reqDate : "*") & "]")
                    DICOM_SendMWLMatches($hSock, $msgID, $gPatients_RIS, $reqModality, $reqDate)
                EndIf

            Case Binary("0x05") ; A-RELEASE-RQ
                DICOM_SendReleaseRSP($hSock)
                ExitLoop
        EndSwitch
    WEnd
EndFunc

; ===================================================================
; STRING -> HEX
; ===================================================================
Func StringToHexStr($s)
    Local $hex = ""
    For $i = 1 To StringLen($s)
        $hex &= Hex(Asc(StringMid($s, $i, 1)), 2)
    Next
    Return $hex
EndFunc

; ===================================================================
; A-ASSOCIATE-AC
; ===================================================================
Func DICOM_SendAAssociateAC($hSock)
    Local $paddedAET = StringLeft($SERVER_AET & "                ", 16)
    Local $hexAET = StringToHexStr($paddedAET)
    
    Local $pdu1 = Binary("0x0200000000D400010000" & $hexAET & "414E592D534355202020202020202020" & _
        "0000000000000000000000000000000000000000000000000000000000000000")

    Local $pdu2 = Binary("0x10000015312E322E3834302E31303030382E332E312E312E31" & _
        "210000190100000040000011312E322E3834302E31303030382E312E32" & _
        "210000190300000040000011312E322E3834302E31303030382E312E32")

    Local $pdu3 = Binary("0x50000039" & _
        "5100000400004000" & _
        "5200001E312E322E3832362E302E312E333638303034332E322E313339362E393939" & _
        "5500000B43686172727561536F6674")

    TCPSend($hSock, $pdu1)
    TCPSend($hSock, $pdu2)
    TCPSend($hSock, $pdu3)
EndFunc

; ===================================================================
; C-ECHO-RSP
; ===================================================================
Func DICOM_SendCEchoRSP($hSock, $msgID)
    Local $cmd = Binary("0x")
    $cmd &= DICOM_ElemImplicit("0000", "0002", "1.2.840.10008.1.1")
    $cmd &= DICOM_ElemImplicitUS("0000", "0100", 0x8030)
    $cmd &= DICOM_ElemImplicitUS("0000", "0120", $msgID)
    $cmd &= DICOM_ElemImplicitUS("0000", "0800", 0x0101)
    $cmd &= DICOM_ElemImplicitUS("0000", "0900", 0x0000)

    Local $groupLen = BinaryLen($cmd)
    Local $cmdFull = DICOM_ElemImplicitUL("0000", "0000", $groupLen) & $cmd

    TCPSend($hSock, DICOM_WrapCommandAsSinglePDV($cmdFull, 3))
EndFunc

; ===================================================================
; MWL MATCHER LOGIC
; ===================================================================
Func MatchDateRange($valDate, $queryDate)
    $queryDate = StringStripWS($queryDate, 3)
    If $queryDate = "" Or $queryDate = "*" Then Return True

    Local $fromDate = "", $toDate = ""
    If StringInStr($queryDate, "-") Then
        Local $parts = StringSplit($queryDate, "-")
        $fromDate = $parts[1]
        $toDate = $parts[2]
    Else
        $fromDate = $queryDate
        $toDate = $queryDate
    EndIf

    If $fromDate <> "" And $valDate < $fromDate Then Return False
    If $toDate <> "" And $valDate > $toDate Then Return False
    Return True
EndFunc

Func DICOM_SendMWLMatches($hSock, $msgID, ByRef $gPatients, $reqModality = "", $reqDate = "")
    If Not IsArray($gPatients) Then Return
    $reqModality = StringStripWS($reqModality, 3)

    For $i = 0 To UBound($gPatients, 1) - 1
        Local $rowModality = $gPatients[$i][9]
        Local $rowDate = $gPatients[$i][10] 

        If $reqModality <> "" And $reqModality <> "*" Then
            If $rowModality <> $reqModality Then ContinueLoop
        EndIf

        If Not MatchDateRange($rowDate, $reqDate) Then ContinueLoop

        Local $row[18]
        For $c = 0 To 17
            $row[$c] = $gPatients[$i][$c]
        Next

        Local $dsRaw = DICOM_BuildMWLDatasetFromCSV($row)
        Local $cmdPending = DICOM_BuildCFindRspCommand($msgID, 0xFF00)
        
        TCPSend($hSock, DICOM_WrapCommandAsSinglePDV($cmdPending, 1))
        TCPSend($hSock, DICOM_WrapDatasetAsSinglePDV($dsRaw, 1))
    Next

    Local $cmdFinal = DICOM_BuildCFindRspCommand($msgID, 0x0000)
    TCPSend($hSock, DICOM_WrapCommandAsSinglePDV($cmdFinal, 1))
EndFunc

; ===================================================================
; MWL C-FIND-RSP DATASET BUILDER
; ===================================================================
Func DICOM_BuildCFindRspCommand($msgID, $status)
    Local $cmd = Binary("0x")
    $cmd &= DICOM_ElemImplicit("0000", "0002", "1.2.840.10008.5.1.4.31")
    $cmd &= DICOM_ElemImplicitUS("0000", "0100", 0x8020)
    $cmd &= DICOM_ElemImplicitUS("0000", "0120", $msgID)
    Local $dsType = ($status = 0xFF00) ? 0x0102 : 0x0101
    $cmd &= DICOM_ElemImplicitUS("0000", "0800", $dsType)
    $cmd &= DICOM_ElemImplicitUS("0000", "0900", $status)
    Local $groupLen = BinaryLen($cmd)
    Return DICOM_ElemImplicitUL("0000", "0000", $groupLen) & $cmd
EndFunc

Func DICOM_BuildMWLDatasetFromCSV($row)
    Local $PatientID        = $row[0]
    Local $PatientName      = $row[1]
    Local $Accession        = $row[2]
    Local $BirthDate        = $row[3]
    Local $Sex              = $row[4]
    Local $SPSID            = $row[5]
    Local $SPSDescription   = $row[6]
    Local $RequestedProcID  = $row[7]
    Local $StationAET       = $row[8]
    Local $Modality         = $row[9]
    Local $ScheduledDate    = $row[10]
    Local $ScheduledTime    = StringReplace($row[11], ":", "")
    Local $ReqProcDesc      = $row[12]
    Local $StudyUID         = $row[13]
    Local $RefPhysician     = $row[14]
    Local $Status           = $row[15]
    Local $ProcedureCode    = $row[16]
    Local $ProcedureCodeDesc= $row[17]

    Local $ds = Binary("0x")
    $ds &= DICOM_ElemImplicit("0008","0005","ISO_IR 100") 
    $ds &= DICOM_ElemImplicit("0008","0050",$Accession)
    $ds &= DICOM_ElemImplicit("0008","0090",$RefPhysician)
    $ds &= DICOM_ElemImplicit("0010","0010",$PatientName)
    $ds &= DICOM_ElemImplicit("0010","0020",$PatientID)
    $ds &= DICOM_ElemImplicit("0010","0030",$BirthDate)
    $ds &= DICOM_ElemImplicit("0010","0040",$Sex)
    $ds &= DICOM_ElemImplicit("0020","000D",$StudyUID)
    $ds &= DICOM_ElemImplicit("0032","1060",$ReqProcDesc)

    Local $item = Binary("0x")
    $item &= DICOM_ElemImplicit("0008","0060",$Modality)
    $item &= DICOM_ElemImplicit("0040","0001",$StationAET)
    $item &= DICOM_ElemImplicit("0040","0002",$ScheduledDate)
    $item &= DICOM_ElemImplicit("0040","0003",$ScheduledTime)
    $item &= DICOM_ElemImplicit("0040","0007",$SPSDescription)
    $item &= DICOM_ElemImplicit("0040","0009",$SPSID)
    
    If $ProcedureCode <> "" Then
        Local $codeItem = Binary("0x")
        $codeItem &= DICOM_ElemImplicit("0008","0100", $ProcedureCode)
        $codeItem &= DICOM_ElemImplicit("0008","0104", $ProcedureCodeDesc)
        $item &= DICOM_SequenceOneItem_Implicit("0040","0008", $codeItem)
    EndIf

    $ds &= DICOM_SequenceOneItem_Implicit("0040","0100",$item)
    $ds &= DICOM_ElemImplicit("0040","1001",$RequestedProcID)
    Return $ds
EndFunc

; ===================================================================
; PDV / PDU WRAPPERS
; ===================================================================
Func DICOM_WrapCommandAsSinglePDV($cmdBytes, $pcid)
    Local $pdvLenBE = DICOM_UInt32BE(BinaryLen($cmdBytes) + 2)
    Local $ctxID = Binary("0x" & StringFormat("%02X", $pcid))
    Local $pdv = $pdvLenBE & $ctxID & Binary("0x03") & $cmdBytes
    Return Binary("0x0400") & DICOM_UInt32BE(BinaryLen($pdv)) & $pdv
EndFunc

Func DICOM_WrapDatasetAsSinglePDV($ds, $pcid)
    Local $pdvLenBE = DICOM_UInt32BE(BinaryLen($ds) + 2)
    Local $ctxID = Binary("0x" & StringFormat("%02X", $pcid))
    Local $pdv = $pdvLenBE & $ctxID & Binary("0x02") & $ds
    Return Binary("0x0400") & DICOM_UInt32BE(BinaryLen($pdv)) & $pdv
EndFunc

; ===================================================================
; SEQUENCE BUILDER
; ===================================================================
Func DICOM_SequenceOneItem_Implicit($tagGroup, $tagElem, $itemData)
    Local $g = Number("0x" & $tagGroup), $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)
    Local $item = Binary("0xFEFF00E0") & DICOM_UInt32LE(BinaryLen($itemData)) & $itemData
    Return $tag & DICOM_UInt32LE(BinaryLen($item)) & $item
EndFunc

; ===================================================================
; ELEMENT BUILDERS
; ===================================================================
Func DICOM_ElemImplicit($tagGroup, $tagElem, $value)
    Local $g = Number("0x" & $tagGroup), $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)
    Local $bVal = StringToBinary($value,4)
    If Mod(BinaryLen($bVal),2) <> 0 Then $bVal &= Binary("0x20")
    Return $tag & DICOM_UInt32LE(BinaryLen($bVal)) & $bVal
EndFunc

Func DICOM_ElemImplicitUS($tagGroup, $tagElem, $val)
    Local $g = Number("0x" & $tagGroup), $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)
    Local $bVal = Binary("0x" & StringFormat("%04X",$val))
    $bVal = BinaryMid($bVal,2,1) & BinaryMid($bVal,1,1)
    Return $tag & DICOM_UInt32LE(2) & $bVal
EndFunc

Func DICOM_ElemImplicitUL($tagGroup, $tagElem, $val)
    Local $g = Number("0x" & $tagGroup), $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)
    Return $tag & DICOM_UInt32LE(4) & DICOM_UInt32LE($val)
EndFunc

; ===================================================================
; UINT HELPERS
; ===================================================================
Func DICOM_UInt32LE($iVal)
    Local $b = Binary("0x" & StringFormat("%08X",$iVal))
    Return BinaryMid($b,4,1) & BinaryMid($b,3,1) & BinaryMid($b,2,1) & BinaryMid($b,1,1)
EndFunc

Func DICOM_UInt32BE($iVal)
    Return Binary("0x" & StringFormat("%08X",$iVal))
EndFunc

; ===================================================================
; MESSAGE EXTRACTORS
; ===================================================================
Func DICOM_ExtractMessageID($bin)
    Local $pos = 13
    Local $len = BinaryLen($bin)

    While $pos + 8 <= $len
        Local $g = Hex(BinaryMid($bin, $pos+1, 1)) & Hex(BinaryMid($bin, $pos, 1))
        Local $e = Hex(BinaryMid($bin, $pos+3, 1)) & Hex(BinaryMid($bin, $pos+2, 1))
        Local $vlInt = Dec(Hex(BinaryMid($bin, $pos+7, 1)) & Hex(BinaryMid($bin, $pos+6, 1)) & Hex(BinaryMid($bin, $pos+5, 1)) & Hex(BinaryMid($bin, $pos+4, 1)))

        Local $valPos = $pos + 8

        If $g = "0000" And $e = "0110" And $vlInt = 2 Then
            Return Dec(Hex(BinaryMid($bin, $valPos+1, 1)) & Hex(BinaryMid($bin, $valPos, 1)))
        EndIf
        $pos = $valPos + $vlInt
    WEnd
    Return 1
EndFunc

Func DICOM_ExtractTagString($bin, $hexTagLE)
    Local $hex = Hex($bin)
    Local $pos = StringInStr($hex, $hexTagLE)
    If $pos = 0 Then Return ""
    
    Local $lenHex = StringMid($hex, $pos + 8, 8) 
    Local $length = Dec(StringMid($lenHex, 7, 2) & StringMid($lenHex, 5, 2) & StringMid($lenHex, 3, 2) & StringMid($lenHex, 1, 2))

    If $length > 0 And $length < 10000 Then
        Return StringStripWS(StringReplace(BinaryToString(Binary("0x" & StringMid($hex, $pos + 16, $length * 2))), Chr(0), ""), 3)
    EndIf
    Return ""
EndFunc

; ===================================================================
; CSV LOADER (Expanded to 18 columns)
; ===================================================================
Func LoadPatientsCSV_RIS()
    If Not FileExists($CSV_FILE) Then
        Local $h = FileOpen($CSV_FILE, 2)
        FileWriteLine($h, $CSV_HEADER)
        FileClose($h)
    EndIf

    Local $fh = FileOpen($CSV_FILE, 0)
    If $fh = -1 Then Return SetError(1,0,0)

    Local $header = FileReadLine($fh)
    Local $rows[0][18]

    While 1
        Local $line = FileReadLine($fh)
        If @error Then ExitLoop

        $line = StringStripWS($line, 3)
        If $line = "" Then ContinueLoop

        Local $cols = CSV_Split_RIS($line, 18)
        
        Local $count = UBound($rows)
        ReDim $rows[$count + 1][18]

        For $i = 0 To 17
            $rows[$count][$i] = $cols[$i]
        Next
    WEnd

    FileClose($fh)
    Return $rows
EndFunc

; ===================================================================
; SAFE CSV SPLITTER
; ===================================================================
Func CSV_Split_RIS($line, $expected)
    Local $out[$expected]
    Local $cur = "", $idx = 0, $inQuotes = False

    For $i = 1 To StringLen($line)
        Local $ch = StringMid($line, $i, 1)
        If $ch = '"' Then
            $inQuotes = Not $inQuotes
            ContinueLoop
        EndIf

        If $ch = "," And Not $inQuotes Then
            $out[$idx] = $cur
            $cur = ""
            $idx += 1
            If $idx >= $expected Then ExitLoop
        Else
            $cur &= $ch
        EndIf
    Next

    If $idx < $expected Then
        $out[$idx] = $cur
        $idx += 1
    EndIf

    While $idx < $expected
        $out[$idx] = ""
        $idx += 1
    WEnd

    Return $out
EndFunc

; ===================================================================
; CSV ARRAY TO LINE
; ===================================================================
Func EntryToCSVLine_RIS($arr)
    Local $s = ""
    For $i = 0 To 17
        Local $f = $arr[$i]
        If StringInStr($f, ",") Or StringInStr($f, '"') Then
            $f = '"' & StringReplace($f, '"', '""') & '"'
        EndIf
        If $i > 0 Then $s &= ","
        $s &= $f
    Next
    Return $s
EndFunc

; ===================================================================
; FILE → ARRAY
; ===================================================================
Func FileReadToArray_RIS($file)
    Local $arr[0]
    Local $h = FileOpen($file, 0)
    If $h = -1 Then Return SetError(1,0,$arr)
    While 1
        Local $line = FileReadLine($h)
        If @error Then ExitLoop
        _ArrayAdd($arr, $line)
    WEnd
    FileClose($h)
    Return $arr
EndFunc

; ===================================================================
; TELNET DISP COMMAND HANDLER
; ===================================================================
Func CSVTS_ProcessDispCommand($clientIndex, $line)
    Local $param = StringStripWS(StringMid($line, 5), 3)
    Local $lines = FileReadToArray_RIS($CSV_FILE)
    If @error Or UBound($lines) <= 1 Then Return

    Local $sock = $g_aClients[$clientIndex][0]
    Local $bMatchAll = ($param = "")
    Local $bIsDate = StringRegExp($param, "^\d{8}$")
    Local $bIsDateRange = StringRegExp($param, "^\d{8}\s+\d{8}$")
    Local $bIsModality = (Not $bMatchAll And Not $bIsDate And Not $bIsDateRange)

    Local $d1 = "", $d2 = ""
    If $bIsDateRange Then
        Local $pts = StringSplit($param, " ", 2)
        $d1 = $pts[0]
        $d2 = $pts[1]
    EndIf

    For $i = 1 To UBound($lines) - 1
        Local $cols = CSV_Split_RIS($lines[$i], 18)
        If UBound($cols) < 18 Then ContinueLoop
        
        Local $match = False
        If $bMatchAll Then
            $match = True
        ElseIf $bIsModality And StringUpper($cols[9]) = StringUpper($param) Then
            $match = True
        ElseIf $bIsDate And $cols[10] = $param Then
            $match = True
        ElseIf $bIsDateRange And $cols[10] >= $d1 And $cols[10] <= $d2 Then
            $match = True
        EndIf
        
        If $match Then TCPSend($sock, $lines[$i] & @CRLF)
    Next
EndFunc

; ===================================================================
; TELNET CSV INGESTION
; ===================================================================
Func CSVTS_ProcessClientLine($clientIndex, $line)
    $line = StringStripWS($line, 3)
    If $line = "" Then Return

    $line = StringReplace($line, "~", '"')

    If StringLeft(StringUpper($line), 4) = "DISP" Then
        CSVTS_ProcessDispCommand($clientIndex, $line)
        Return
    EndIf

    Local $fields = CSV_Split_RIS($line, 18)
    If Not IsArray($fields) Then Return

    Local $PatientID       = StringStripWS($fields[0], 3)
    Local $PatientName     = StringStripWS($fields[1], 3)
    Local $Accession       = StringStripWS($fields[2], 3)
    Local $BirthDate       = StringStripWS($fields[3], 3)
    Local $Sex             = StringUpper(StringStripWS($fields[4], 3))
    Local $SPSID           = StringStripWS($fields[5], 3)
    Local $SPSDescription  = StringStripWS($fields[6], 3)
    Local $ReqProcID       = StringStripWS($fields[7], 3)
    Local $StationAET      = StringStripWS($fields[8], 3)
    Local $Modality        = StringUpper(StringStripWS($fields[9], 3))
    Local $SchedDate       = StringStripWS($fields[10], 3)
    Local $SchedTime       = StringStripWS($fields[11], 3)
    Local $ReqProcDesc     = StringStripWS($fields[12], 3)
    Local $StudyUID        = StringStripWS($fields[13], 3)
    Local $RefPhys         = StringStripWS($fields[14], 3)
    Local $Status          = StringStripWS($fields[15], 3)
    Local $ProcCode        = StringStripWS($fields[16], 3)
    Local $ProcCodeDesc    = StringStripWS($fields[17], 3)

    ; Validate constraints
    If $PatientID = "" Or $PatientName = "" Or $Modality = "" Or $SPSDescription = "" Then Return
    If Not StringRegExp($BirthDate, "^\d{8}$") Then Return
    If Not StringRegExp($Sex, "^[MFO]$") Then Return
    If Not StringRegExp($SchedDate, "^\d{8}$") Then Return
    If Not StringRegExp($Status, "^[1-4]$") Then Return
    If $SchedTime <> "" And Not StringRegExp($SchedTime, "^\d{2}:\d{2}$") Then Return

    Local $entry[18]
    $entry[0] = $PatientID
    $entry[1] = $PatientName
    $entry[2] = $Accession
    $entry[3] = $BirthDate
    $entry[4] = $Sex
    $entry[5] = $SPSID
    $entry[6] = $SPSDescription
    $entry[7] = $ReqProcID
    $entry[8] = $StationAET
    $entry[9] = $Modality
    $entry[10] = $SchedDate
    $entry[11] = $SchedTime
    $entry[12] = $ReqProcDesc
    $entry[13] = $StudyUID
    $entry[14] = $RefPhys
    $entry[15] = $Status
    $entry[16] = $ProcCode
    $entry[17] = $ProcCodeDesc

    $g_aClients[$clientIndex][4] = $entry
    $g_aClients[$clientIndex][5] = TimerInit()
    $g_aClients[$clientIndex][6] += 1000 ; Extended disconnect timeout
    
    TCPSend($g_aClients[$clientIndex][0], "PENDING" & @CRLF)
    CSVTS_Log("PENDING PatientID " & $PatientID)
EndFunc

; ===================================================================
; RELEASE-RSP
; ===================================================================
Func DICOM_SendReleaseRSP($hSock)
    Local $pdu = Binary("0x0600000000040000")
    TCPSend($hSock, $pdu)
EndFunc

; ===================================================================
; MAIN LOOP (Fixed Initialization)
; ===================================================================
CSVTS_TrayCreate()
CSVTS_CreateMainGUI()

$gPatients_RIS = LoadPatientsCSV_RIS()
CSVTS_StartServer()
DICOM_StartServer()

While 1
    Local $msg = TrayGetMsg()
    Switch $msg
        Case $g_idToggle
            If BitAND(TrayItemGetState($g_idToggle), $TRAY_CHECKED) Then
                CSVTS_StartServer()
                DICOM_StartServer()
            Else
                CSVTS_StopServer()
                DICOM_StopServer()
            EndIf
        Case $g_idSettings
            CSVTS_ShowSettings()
        Case $g_idExit
            ExitLoop
    EndSwitch

    CSVTS_ServerLoop()
    DICOM_ServerLoop()
    Sleep(10)
WEnd

CSVTS_StopServer()
DICOM_StopServer()
TCPShutdown()