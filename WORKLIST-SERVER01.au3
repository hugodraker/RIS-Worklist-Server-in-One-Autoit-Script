; ===================================================================
; FULL MERGED RIS MWL SCP + TELNET CSV SERVER + GUI
; Added: 15-Column CSV (Time, ReqProcDesc, StudyUID, RefPhysician)
; ===================================================================

#RequireAdmin

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

; 15-Column CSV Header
Global Const $CSV_HEADER = "PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName"

Global Const $INACTIVITY_MS = 15000
Global Const $APPEND_DELAY_MS = 2000

Global $SERVER_AET = "AUTOIT_SCP"
Global $DICOM_PORT = 104
Global $TELNET_PORT = 23

; ===================================================================
; GLOBALS
; ===================================================================
Global $g_bRunning = False
Global $g_listenSocket = -1
Global $g_dicomsock = -1

; Telnet clients array: [Socket, ID, Buffer, LastActivityTimer, PendingEntry, PendingSinceTimer]
Dim $g_aClients[0][6]

; GUI handles
Global $g_hStatusLabel = 0
Global $g_hClientsLabel = 0
Global $g_hLogEdit = 0

; Tray menu IDs
Global $g_idStart = 0
Global $g_idStop = 0
Global $g_idSettings = 0
Global $g_idExit = 0

; Patients cache for MWL
Global $gPatients_RIS = 0

; ===================================================================
; INITIALIZE TCP & CONFIG
; ===================================================================
TCPStartup()

; Ensure INI and default configurations exist
If Not FileExists($INI_FILE) Then
    IniWrite($INI_FILE, "Server", "AETitle", "AUTOIT_SCP")
    IniWrite($INI_FILE, "Server", "DicomPort", "104")
    IniWrite($INI_FILE, "Server", "TelnetPort", "23")
    
    IniWrite($INI_FILE, "Lists", "Modalities", "CR;DX;CT;MR;US;OT")
    IniWrite($INI_FILE, "Lists", "AETitles", "")
    IniWrite($INI_FILE, "Lists", "ReferringPhysicians", "")
    IniWrite($INI_FILE, "Lists", "Procedures", "")
EndIf

; Load configurations on startup
$SERVER_AET = IniRead($INI_FILE, "Server", "AETitle", "AUTOIT_SCP")
$DICOM_PORT = Number(IniRead($INI_FILE, "Server", "DicomPort", "104"))
$TELNET_PORT = Number(IniRead($INI_FILE, "Server", "TelnetPort", "23"))

; ===================================================================
; GUI + TRAY CREATION
; ===================================================================
Func CSVTS_TrayCreate()
    $g_idStart    = TrayCreateItem("Start Server")
    $g_idStop     = TrayCreateItem("Stop Server")
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

Func CSVTS_ShowMainGUI()
    GUISetState(@SW_SHOW)
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
; STARTUP GUI + TRAY
; ===================================================================
CSVTS_TrayCreate()
CSVTS_CreateMainGUI()

ConsoleWrite("SCRIPT STARTED" & @CRLF)

; ===================================================================
; TELNET SERVER CONTROL
; ===================================================================
Func CSVTS_StartServer()
    If $g_bRunning Then Return

    $g_listenSocket = TCPListen("0.0.0.0", $TELNET_PORT)
    If $g_listenSocket = -1 Then
        CSVTS_Log("ERROR: Failed to listen on telnet port " & $TELNET_PORT)
        GUICtrlSetData($g_hStatusLabel, "Server status: Failed to bind port " & $TELNET_PORT)
        $g_bRunning = False
        Return
    EndIf

    $g_bRunning = True
    CSVTS_Log("Telnet server started and listening on port " & $TELNET_PORT)
    GUICtrlSetData($g_hStatusLabel, "Server status: Running on port " & $TELNET_PORT)
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

    ReDim $g_aClients[0][6]
    $g_bRunning = False

    CSVTS_Log("Telnet server stopped")
    GUICtrlSetData($g_hStatusLabel, "Server status: Stopped")
    GUICtrlSetData($g_hClientsLabel, "Active clients: 0")
EndFunc

; ===================================================================
; TELNET CLIENT MANAGEMENT
; ===================================================================
Func CSVTS_AddClient($sock)
    Local $n = UBound($g_aClients)
    ReDim $g_aClients[$n + 1][6]
    $g_aClients[$n][0] = $sock
    $g_aClients[$n][1] = $sock
    $g_aClients[$n][2] = ""
    $g_aClients[$n][3] = TimerInit()
    $g_aClients[$n][4] = 0
    $g_aClients[$n][5] = 0
    CSVTS_Log("Telnet Client connected on socket " & $sock)
EndFunc

Func CSVTS_RemoveClient($index)
    Local $n = UBound($g_aClients) - 1
    For $j = $index To $n - 1
        For $c = 0 To 5
            $g_aClients[$j][$c] = $g_aClients[$j + 1][$c]
        Next
    Next
    ReDim $g_aClients[$n][6]
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
        If @error = 0 And $data <> "" Then
            $g_aClients[$i][3] = TimerInit()
            $g_aClients[$i][2] &= $data

            While StringInStr($g_aClients[$i][2], @CRLF)
                Local $pos = StringInStr($g_aClients[$i][2], @CRLF)
                Local $line = StringLeft($g_aClients[$i][2], $pos - 1)
                $g_aClients[$i][2] = StringTrimLeft($g_aClients[$i][2], $pos + StringLen(@CRLF) - 1)
                CSVTS_ProcessClientLine($i, $line)
            WEnd
        EndIf

        If IsObj($g_aClients[$i][4]) Then
            If TimerDiff($g_aClients[$i][5]) >= $APPEND_DELAY_MS Then
                CSVTS_CommitPendingEntry($i)
                $g_aClients[$i][3] = TimerInit()
            EndIf
        EndIf

        If TimerDiff($g_aClients[$i][3]) >= $INACTIVITY_MS Then
            CSVTS_Log("Client on socket " & $g_aClients[$i][1] & " timed out")
            TCPCloseSocket($g_aClients[$i][0])
            CSVTS_RemoveClient($i)
        EndIf
    Next
    GUICtrlSetData($g_hClientsLabel, "Active clients: " & UBound($g_aClients))
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
; COMMIT PENDING ENTRY
; ===================================================================
Func CSVTS_CommitPendingEntry($clientIndex)
    Local $entry = $g_aClients[$clientIndex][4]
    If Not IsObj($entry) Then Return

    Local $patientID = $entry.Item("PatientID")

    If Not FileExists($CSV_FILE) Then
        Local $h = FileOpen($CSV_FILE, 2)
        FileWriteLine($h, $CSV_HEADER)
        FileClose($h)
    EndIf

    Local $lines = FileReadToArray_RIS($CSV_FILE)
    If @error Or UBound($lines) = 0 Then
        Local $arrInit[1] = [$CSV_HEADER]
        $lines = $arrInit
    EndIf

    Local $found = False
    For $i = 1 To UBound($lines) - 1
        Local $cols = CSV_Split_RIS($lines[$i], 15)
        If StringStripWS($cols[0], 3) = $patientID Then
            $lines[$i] = EntryToCSVLine_RIS($entry)
            $found = True
            ExitLoop
        EndIf
    Next

    If Not $found Then _ArrayAdd($lines, EntryToCSVLine_RIS($entry))

    Local $h = FileOpen($CSV_FILE, 2)
    For $i = 0 To UBound($lines) - 1
        FileWriteLine($h, $lines[$i])
    Next
    FileClose($h)

    CSVTS_UpdateIniList("Modalities", $entry.Item("Modality"))
    CSVTS_UpdateIniList("AETitles", $entry.Item("StationAET"))
    CSVTS_UpdateIniList("ReferringPhysicians", $entry.Item("ReferringPhysicianName"))
    CSVTS_UpdateIniList("Procedures", $entry.Item("SPSDescription"))

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

    While 1
        Local $data = TCPRecv($hSock, 8192, 1)

        If @error = 0 And BinaryLen($data) = 0 Then
            Sleep(5)
            ContinueLoop
        EndIf

        If @error <> 0 Then
            If $assocEstablished Then DICOM_SendReleaseRSP($hSock)
            ExitLoop
        EndIf

        Local $pduType = BinaryMid($data, 1, 1)

        Switch $pduType
            Case Binary("0x01") ; A-ASSOCIATE-RQ
                DICOM_SendAAssociateAC($hSock)
                $assocEstablished = True

            Case Binary("0x04") ; P-DATA-TF
                Local $txt = BinaryToString($data, 4)

                If StringInStr($txt, "1.2.840.10008.1.1") Then
                    ; C-ECHO
                    Local $msgID = DICOM_ExtractMessageID($data)
                    DICOM_SendCEchoRSP($hSock, $msgID)

                ElseIf StringInStr($txt, "1.2.840.10008.5.1.4.31") Then
                    ; MWL C-FIND
                    $gPatients_RIS = LoadPatientsCSV_RIS()
                    Local $msgID = DICOM_ExtractMessageID($data)
                    
                    ; Extract Modality & Date Filters dynamically
                    Local $reqModality = DICOM_ExtractTagString($data, "08006000")
                    Local $reqDate = DICOM_ExtractTagString($data, "40000200")
                    CSVTS_Log("MWL C-FIND -> Modality Requested: [" & ($reqModality ? $reqModality : "*") & "] | Date Requested: [" & ($reqDate ? $reqDate : "*") & "]")

                    DICOM_SendMWLMatches($hSock, $msgID, $gPatients_RIS, $reqModality, $reqDate)
                EndIf

            Case Binary("0x05") ; A-RELEASE-RQ
                DICOM_SendReleaseRSP($hSock)
                ExitLoop
        EndSwitch
    WEnd
EndFunc

; ===================================================================
; STRING -> HEX (Helpers for Association Setup)
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
; MWL DATE MATCHER (Handles Ranges)
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

; ===================================================================
; SEND MWL MATCHES (With Filters)
; ===================================================================
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

        Local $row[15]
        For $c = 0 To 14
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
; BUILD C-FIND-RSP COMMAND
; ===================================================================
Func DICOM_BuildCFindRspCommand($msgID, $status)
    Local $cmd = Binary("0x")
    $cmd &= DICOM_ElemImplicit("0000", "0002", "1.2.840.10008.5.1.4.31")
    $cmd &= DICOM_ElemImplicitUS("0000", "0100", 0x8020)
    $cmd &= DICOM_ElemImplicitUS("0000", "0120", $msgID)

    Local $dsType = 0x0101
    If $status = 0xFF00 Then $dsType = 0x0102

    $cmd &= DICOM_ElemImplicitUS("0000", "0800", $dsType)
    $cmd &= DICOM_ElemImplicitUS("0000", "0900", $status)

    Local $groupLen = BinaryLen($cmd)
    Return DICOM_ElemImplicitUL("0000", "0000", $groupLen) & $cmd
EndFunc

; ===================================================================
; BUILD MWL DATASET FROM CSV (Expanded to 15 columns)
; ===================================================================
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
    Local $ScheduledTime    = $row[11]
    Local $ReqProcDesc      = $row[12]
    Local $StudyUID         = $row[13]
    Local $RefPhysician     = $row[14]

    Local $ds = Binary("0x")
    
    ; Note: (0008,0005) SpecificCharacterSet mapped here as requested
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

    Local $sq = DICOM_SequenceOneItem_Implicit("0040","0100",$item)
    $ds &= $sq

    $ds &= DICOM_ElemImplicit("0040","1001",$RequestedProcID)
    Return $ds
EndFunc

; ===================================================================
; PDV / PDU WRAPPERS
; ===================================================================
Func DICOM_WrapCommandAsSinglePDV($cmdBytes, $pcid)
    Local $pdvLen = BinaryLen($cmdBytes) + 2
    Local $pdvLenBE = DICOM_UInt32BE($pdvLen)
    Local $ctxID = Binary("0x" & StringFormat("%02X", $pcid))
    Local $msgCtrl = Binary("0x03")
    Local $pdv = $pdvLenBE & $ctxID & $msgCtrl & $cmdBytes
    Local $pduLen = BinaryLen($pdv)
    Local $pduHeader = Binary("0x0400") & DICOM_UInt32BE($pduLen)
    Return $pduHeader & $pdv
EndFunc

Func DICOM_WrapDatasetAsSinglePDV($ds, $pcid)
    Local $pdvLen = BinaryLen($ds) + 2
    Local $pdvLenBE = DICOM_UInt32BE($pdvLen)
    Local $ctxID = Binary("0x" & StringFormat("%02X", $pcid))
    Local $msgCtrl = Binary("0x02")
    Local $pdv = $pdvLenBE & $ctxID & $msgCtrl & $ds
    Local $pduLen = BinaryLen($pdv)
    Local $pduHeader = Binary("0x0400") & DICOM_UInt32BE($pduLen)
    Return $pduHeader & $pdv
EndFunc

; ===================================================================
; SEQUENCE BUILDER
; ===================================================================
Func DICOM_SequenceOneItem_Implicit($tagGroup, $tagElem, $itemData)
    Local $g = Number("0x" & $tagGroup)
    Local $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)

    Local $itemTag = Binary("0xFEFF00E0")
    Local $itemVL  = DICOM_UInt32LE(BinaryLen($itemData))
    Local $item    = $itemTag & $itemVL & $itemData

    Local $seqVL = DICOM_UInt32LE(BinaryLen($item))
    Return $tag & $seqVL & $item
EndFunc

; ===================================================================
; ELEMENT BUILDERS
; ===================================================================
Func DICOM_ElemImplicit($tagGroup, $tagElem, $value)
    Local $g = Number("0x" & $tagGroup)
    Local $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)

    Local $bVal = StringToBinary($value,4)
    If Mod(BinaryLen($bVal),2) <> 0 Then $bVal &= Binary("0x20")

    Local $vl = DICOM_UInt32LE(BinaryLen($bVal))
    Return $tag & $vl & $bVal
EndFunc

Func DICOM_ElemImplicitUS($tagGroup, $tagElem, $val)
    Local $g = Number("0x" & $tagGroup)
    Local $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)

    Local $bVal = Binary("0x" & StringFormat("%04X",$val))
    $bVal = BinaryMid($bVal,2,1) & BinaryMid($bVal,1,1)

    Local $vl = DICOM_UInt32LE(2)
    Return $tag & $vl & $bVal
EndFunc

Func DICOM_ElemImplicitUL($tagGroup, $tagElem, $val)
    Local $g = Number("0x" & $tagGroup)
    Local $e = Number("0x" & $tagElem)
    Local $tag = Binary("0x" & StringFormat("%04X",$g) & StringFormat("%04X",$e))
    $tag = BinaryMid($tag,2,1) & BinaryMid($tag,1,1) & BinaryMid($tag,4,1) & BinaryMid($tag,3,1)

    Local $bVal = DICOM_UInt32LE($val)
    Local $vl = DICOM_UInt32LE(4)
    Return $tag & $vl & $bVal
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
; MESSAGE EXTRACTORS (Data Parser for Filtering)
; ===================================================================
Func DICOM_ExtractMessageID($bin)
    Local $pos = 13
    Local $len = BinaryLen($bin)

    While $pos + 8 <= $len
        Local $g1 = Hex(BinaryMid($bin, $pos, 1))
        Local $g2 = Hex(BinaryMid($bin, $pos+1, 1))
        Local $e1 = Hex(BinaryMid($bin, $pos+2, 1))
        Local $e2 = Hex(BinaryMid($bin, $pos+3, 1))

        Local $g = $g2 & $g1
        Local $e = $e2 & $e1

        Local $v1 = Hex(BinaryMid($bin, $pos+4, 1))
        Local $v2 = Hex(BinaryMid($bin, $pos+5, 1))
        Local $v3 = Hex(BinaryMid($bin, $pos+6, 1))
        Local $v4 = Hex(BinaryMid($bin, $pos+7, 1))
        Local $vlInt = Dec($v4 & $v3 & $v2 & $v1)

        Local $valPos = $pos + 8

        If $g = "0000" And $e = "0110" Then
            If $vlInt = 2 Then
                Local $m1 = Hex(BinaryMid($bin, $valPos, 1))
                Local $m2 = Hex(BinaryMid($bin, $valPos+1, 1))
                Return Dec($m2 & $m1)
            EndIf
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
    Local $len1 = StringMid($lenHex, 1, 2)
    Local $len2 = StringMid($lenHex, 3, 2)
    Local $len3 = StringMid($lenHex, 5, 2)
    Local $len4 = StringMid($lenHex, 7, 2)
    Local $length = Dec($len4 & $len3 & $len2 & $len1)

    If $length > 0 And $length < 10000 Then
        Local $valHex = StringMid($hex, $pos + 16, $length * 2)
        Local $valStr = BinaryToString(Binary("0x" & $valHex))
        Return StringStripWS(StringReplace($valStr, Chr(0), ""), 3)
    EndIf
    Return ""
EndFunc

; ===================================================================
; CSV LOADER (Expanded to 15 columns)
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
    Local $rows[0][15]

    While 1
        Local $line = FileReadLine($fh)
        If @error Then ExitLoop

        $line = StringStripWS($line, 3)
        If $line = "" Then ContinueLoop

        Local $cols = CSV_Split_RIS($line, 15)
        
        ; Fallback assignments for older records missing new columns
        If $cols[10] = "" Then $cols[10] = @YEAR & @MON & @MDAY
        If $cols[11] = "" Then $cols[11] = @HOUR & @MIN & @SEC
        If $cols[12] = "" Then $cols[12] = $cols[6] ; Default ReqProcDesc to SPSDescription
        If $cols[13] = "" Then $cols[13] = "1.2.826.0.1.3680043.2.1396." & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & "." & Random(1000, 9999, 1)

        Local $count = UBound($rows)
        ReDim $rows[$count + 1][15]

        For $i = 0 To 14
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
    Local $cur = ""
    Local $idx = 0
    Local $inQuotes = False

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
; CSV ENTRY → LINE (Expanded to 15 columns)
; ===================================================================
Func EntryToCSVLine_RIS($entry)
    Local $arr[15]
    $arr[0] = $entry.Item("PatientID")
    $arr[1] = $entry.Item("PatientName")
    $arr[2] = $entry.Item("Accession")
    $arr[3] = $entry.Item("BirthDate")
    $arr[4] = $entry.Item("Sex")
    $arr[5] = $entry.Item("SPSID")
    $arr[6] = $entry.Item("SPSDescription")
    $arr[7] = $entry.Item("RequestedProcedureID")
    $arr[8] = $entry.Item("StationAET")
    $arr[9] = $entry.Item("Modality")
    $arr[10] = $entry.Item("ScheduledDate")
    $arr[11] = $entry.Item("ScheduledTime")
    $arr[12] = $entry.Item("RequestedProcDesc")
    $arr[13] = $entry.Item("StudyInstanceUID")
    $arr[14] = $entry.Item("ReferringPhysicianName")

    Local $s = ""
    For $i = 0 To 14
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
; TELNET CSV INGESTION (Expanded to 15 columns)
; ===================================================================
Func CSVTS_ProcessClientLine($clientIndex, $line)
    $line = StringReplace($line, "~", '"')
    $line = StringStripWS($line, 3)
    If $line = "" Then Return

    ; Header check
    If StringLeft($line, StringLen($CSV_HEADER)) = $CSV_HEADER Then
        If Not FileExists($CSV_FILE) Then
            Local $h = FileOpen($CSV_FILE, 2)
            FileWriteLine($h, $CSV_HEADER)
            FileClose($h)
        EndIf
        TCPSend($g_aClients[$clientIndex][0], "HEADER OK" & @CRLF)
        Return
    EndIf

    ; Split CSV (Tolerates anything from 10 to 15 variables)
    Local $fields = CSV_Split_RIS($line, 15)
    If Not IsArray($fields) Then Return
    If UBound($fields) < 10 Then Return

    Local $PatientID       = StringStripWS($fields[0], 3)
    Local $PatientName     = StringStripWS($fields[1], 3)
    Local $Accession       = StringStripWS($fields[2], 3)
    Local $BirthDate       = StringStripWS($fields[3], 3)
    Local $Sex             = StringUpper(StringStripWS($fields[4], 3))
    Local $SPSID           = StringStripWS($fields[5], 3)
    Local $SPSDescription  = StringStripWS($fields[6], 3)
    Local $ReqProcID       = StringStripWS($fields[7], 3)
    Local $StationAET      = StringStripWS($fields[8], 3)
    Local $Modality        = StringStripWS($fields[9], 3)
    
    ; Setup default fallbacks dynamically
    Local $SchedDate   = (UBound($fields) >= 11 And StringStripWS($fields[10], 3) <> "") ? StringStripWS($fields[10], 3) : @YEAR & @MON & @MDAY
    Local $SchedTime   = (UBound($fields) >= 12 And StringStripWS($fields[11], 3) <> "") ? StringStripWS($fields[11], 3) : @HOUR & @MIN & @SEC
    Local $ReqProcDesc = (UBound($fields) >= 13 And StringStripWS($fields[12], 3) <> "") ? StringStripWS($fields[12], 3) : $SPSDescription
    Local $StudyUID    = (UBound($fields) >= 14 And StringStripWS($fields[13], 3) <> "") ? StringStripWS($fields[13], 3) : "1.2.826.0.1.3680043.2.1396." & @YEAR & @MON & @MDAY & @HOUR & @MIN & @SEC & "." & Random(1000, 9999, 1)
    Local $RefPhys     = (UBound($fields) >= 15 And StringStripWS($fields[14], 3) <> "") ? StringStripWS($fields[14], 3) : ""

    If $PatientID = "" Then Return
    If Not StringRegExp($BirthDate, "^\d{8}$") Then Return
    If Not StringInStr("MFO", $Sex) Then Return
    If $Modality = "" Then Return

    Local $entry = ObjCreate("Scripting.Dictionary")
    $entry.Add("PatientID", $PatientID)
    $entry.Add("PatientName", $PatientName)
    $entry.Add("Accession", $Accession)
    $entry.Add("BirthDate", $BirthDate)
    $entry.Add("Sex", $Sex)
    $entry.Add("SPSID", $SPSID)
    $entry.Add("SPSDescription", $SPSDescription)
    $entry.Add("RequestedProcedureID", $ReqProcID)
    $entry.Add("StationAET", $StationAET)
    $entry.Add("Modality", $Modality)
    $entry.Add("ScheduledDate", $SchedDate)
    $entry.Add("ScheduledTime", $SchedTime)
    $entry.Add("RequestedProcDesc", $ReqProcDesc)
    $entry.Add("StudyInstanceUID", $StudyUID)
    $entry.Add("ReferringPhysicianName", $RefPhys)

    $g_aClients[$clientIndex][4] = $entry
    $g_aClients[$clientIndex][5] = TimerInit()

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
; MAIN LOOP
; ===================================================================
$gPatients_RIS = LoadPatientsCSV_RIS()
DICOM_StartServer()

While 1
    Local $msg = TrayGetMsg()
    Switch $msg
        Case $g_idStart
            CSVTS_StartServer()
        Case $g_idStop
            CSVTS_StopServer()
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