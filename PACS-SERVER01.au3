;#RequireAdmin

#include <Array.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <EditConstants.au3>
#include <File.au3>
#include <Date.au3>
#include <TrayConstants.au3>

Opt("TrayAutoPause", 0)
Opt("TrayMenuMode", 3)

; ===================================================================
; DYNAMIC INI & CONFIGURATION
; ===================================================================
Global $INI_FILE = @ScriptDir & "\" & StringRegExpReplace(@ScriptName, "\.[^.]*$", "") & ".ini"
Global Const $CSV_FILE = @ScriptDir & "\STOR.csv"

Global Const $CSV_HEADER = "PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName,Status,ProcedureCode,ProcedureCodeDesc,CodingScheme,PerformingPhysician,StationName,Location"

Global $SERVER_AET = "PACS_SCP"
Global $DICOM_PORT = 777
Global $TELNET_CLIENT_IP = "127.0.0.1"
Global $TELNET_CLIENT_PORT = 23
Global $DEBUG_LOG = 1 
Global $MAX_IMAGES_PER_FOLDER = 16000

; ===================================================================
; GLOBALS
; ===================================================================
Global $g_bRunning = False
Global $g_dicomsock = -1

Global $g_CurrentFolderIndex = 0
Global $g_CurrentFileIndex = 0

Global $g_hStatusLabel = 0
Global $g_hClientsLabel = 0
Global $g_hLogEdit = 0

Global $g_idToggle = 0
Global $g_idSettings = 0
Global $g_idExit = 0

; ===================================================================
; INITIALIZE TCP & CONFIG
; ===================================================================
TCPStartup()

If Not FileExists($INI_FILE) Then
    IniWrite($INI_FILE, "Server", "AETitle", "PACS_SCP")
    IniWrite($INI_FILE, "Server", "DicomPort", "777")
    IniWrite($INI_FILE, "Server", "DebugLog", "1")
    IniWrite($INI_FILE, "Storage", "LastFolderIndex", "0")
    IniWrite($INI_FILE, "Storage", "LastFileIndex", "0")
EndIf

$SERVER_AET = IniRead($INI_FILE, "Server", "AETitle", "PACS_SCP")
$DICOM_PORT = Number(IniRead($INI_FILE, "Server", "DicomPort", "777"))
$DEBUG_LOG = Number(IniRead($INI_FILE, "Server", "DebugLog", "1"))
$g_CurrentFolderIndex = Number(IniRead($INI_FILE, "Storage", "LastFolderIndex", "0"))
$g_CurrentFileIndex = Number(IniRead($INI_FILE, "Storage", "LastFileIndex", "0"))

; ===================================================================
; STORAGE PATH LOGIC
; ===================================================================
Func GetNextStoragePath()
    $g_CurrentFileIndex += 1
    If $g_CurrentFileIndex > $MAX_IMAGES_PER_FOLDER Then
        $g_CurrentFolderIndex += 1
        $g_CurrentFileIndex = 1
    EndIf
    
    IniWrite($INI_FILE, "Storage", "LastFolderIndex", $g_CurrentFolderIndex)
    IniWrite($INI_FILE, "Storage", "LastFileIndex", $g_CurrentFileIndex)

    Local $folderName = "SR" & StringFormat("%06i", $g_CurrentFolderIndex)
    Local $dirPath = @ScriptDir & "\" & $folderName
    
    If Not FileExists($dirPath) Then DirCreate($dirPath)
    
    Local $fileName = StringFormat("%05i", $g_CurrentFileIndex) & ".DCM"
    Return $dirPath & "\" & $fileName
EndFunc

; ===================================================================
; GUI + TRAY CREATION
; ===================================================================
Func CSVTS_TrayCreate()
    $g_idToggle   = TrayCreateItem("Server Running")
    TrayItemSetState($g_idToggle, $TRAY_UNCHECKED) 
    $g_idSettings = TrayCreateItem("Settings")
    TrayCreateItem("")
    $g_idExit     = TrayCreateItem("Exit")
    TraySetToolTip("PACS SCP Storage Server")
    TraySetState()
EndFunc

Func CSVTS_CreateMainGUI()
    GUICreate("AutoIt PACS SCP Storage Server", 700, 380, -1, -1, BitOR($WS_SIZEBOX, $WS_SYSMENU))
    GUISetOnEvent($GUI_EVENT_CLOSE, "CSVTS_HideMainGUI")

    $g_hStatusLabel = GUICtrlCreateLabel("Server status: Stopped", 10, 10, 500, 20)
    GUICtrlCreateLabel("Log:", 10, 60, 50, 20)
    $g_hLogEdit = GUICtrlCreateEdit("", 10, 85, 680, 280, BitOR($ES_AUTOVSCROLL, $ES_READONLY, $WS_VSCROLL))

    GUISetState(@SW_HIDE)
EndFunc

Func CSVTS_HideMainGUI()
    GUISetState(@SW_HIDE)
EndFunc

Func CSVTS_ShowSettings()
    Local $h = GUICreate("Settings", 440, 150)
    
    GUICtrlCreateLabel("Server AET:", 10, 10, 100, 20)
    Local $inAET = GUICtrlCreateInput($SERVER_AET, 120, 10, 120, 20)
    
    GUICtrlCreateLabel("DICOM Port:", 260, 10, 80, 20)
    Local $inDcmPort = GUICtrlCreateInput($DICOM_PORT, 340, 10, 80, 20)
    
    GUICtrlCreateLabel("Debug Logging:", 10, 40, 100, 20)
    Local $chkDebug = GUICtrlCreateCheckbox("Enabled", 120, 40, 80, 20)
    If $DEBUG_LOG Then GUICtrlSetState($chkDebug, $GUI_CHECKED)

    Local $sBtnText = $g_bRunning ? "Stop Server" : "Start Server"
    Local $btnStartStop = GUICtrlCreateButton($sBtnText, 10, 100, 100, 30)
    Local $btnSave = GUICtrlCreateButton("Save Settings", 200, 100, 100, 30)
    Local $btnClose = GUICtrlCreateButton("Close", 320, 100, 100, 30)
    
    GUISetState(@SW_SHOW, $h)

    While 1
        Local $m = GUIGetMsg(1)
        If $m[0] = $GUI_EVENT_CLOSE Or $m[0] = $btnClose Then ExitLoop
        
        If $m[0] = $btnStartStop Then
            If $g_bRunning Then
                DICOM_StopServer()
                GUICtrlSetData($btnStartStop, "Start Server")
                TrayItemSetState($g_idToggle, $TRAY_UNCHECKED)
            Else
                DICOM_StartServer()
                GUICtrlSetData($btnStartStop, "Stop Server")
                TrayItemSetState($g_idToggle, $TRAY_CHECKED)
            EndIf
        EndIf

        If $m[0] = $btnSave Then
            $SERVER_AET = GUICtrlRead($inAET)
            $DICOM_PORT = GUICtrlRead($inDcmPort)
            $DEBUG_LOG = (BitAND(GUICtrlRead($chkDebug), $GUI_CHECKED) = $GUI_CHECKED) ? 1 : 0
            
            IniWrite($INI_FILE, "Server", "AETitle", $SERVER_AET)
            IniWrite($INI_FILE, "Server", "DicomPort", $DICOM_PORT)
            IniWrite($INI_FILE, "Server", "DebugLog", $DEBUG_LOG)
            
            MsgBox(64, "Saved", "Settings saved successfully." & @CRLF & "Port changes require a server restart.", 0, $h)
        EndIf
        Sleep(50)
    WEnd
    GUIDelete($h)
EndFunc

Func CSVTS_Log($s)
    If Not $DEBUG_LOG Then Return
    If $g_hLogEdit Then
        Local $text = GUICtrlRead($g_hLogEdit)
        $text &= "[" & @HOUR & ":" & @MIN & ":" & @SEC & "] " & $s & @CRLF
        GUICtrlSetData($g_hLogEdit, $text)
    EndIf
    FileWriteLine(@ScriptDir & "\PACS_Server.log", "[" & @HOUR & ":" & @MIN & ":" & @SEC & "] " & $s)
EndFunc

; ===================================================================
; DICOM SERVER CONTROL
; ===================================================================
Func DICOM_StartServer()
    If $g_bRunning Then Return
    $g_dicomsock = TCPListen("0.0.0.0", $DICOM_PORT)
    If $g_dicomsock = -1 Then
        CSVTS_Log("ERROR: Failed to listen on DICOM port " & $DICOM_PORT)
        If $g_hStatusLabel Then GUICtrlSetData($g_hStatusLabel, "Server status: Failed to bind port " & $DICOM_PORT)
        Return
    EndIf
    $g_bRunning = True
    CSVTS_Log("DICOM SCP listening on port " & $DICOM_PORT)
    If $g_hStatusLabel Then GUICtrlSetData($g_hStatusLabel, "Server status: Running on port " & $DICOM_PORT)
EndFunc

Func DICOM_StopServer()
    If $g_dicomsock <> -1 Then
        TCPCloseSocket($g_dicomsock)
        $g_dicomsock = -1
        $g_bRunning = False
        CSVTS_Log("DICOM PACS SCP stopped")
        If $g_hStatusLabel Then GUICtrlSetData($g_hStatusLabel, "Server status: Stopped")
    EndIf
EndFunc

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
; DICOM CLIENT ROUTER & TCP BUFFERING
; ===================================================================
Func DICOM_HandleClient($hSock)
    Local $assocEstablished = False
    Local $timer = TimerInit()
    Local $bReceivingImage = False
    Local $tempFilePath = @ScriptDir & "\temp_" & $hSock & ".dcm"
    Local $hTempFile = -1
    Local $msgID = 1
    
    ; Setup default identifiers to build the File Meta Header
    Local $currentSOPClass = "1.2.840.10008.5.1.4.1.1.7"
    Local $currentSOPInst = "1.2.3.4.5.6.7.8.9.0"
    
    Local $streamBuffer = Binary("")

    While 1
        Local $recvData = TCPRecv($hSock, 16384, 1)

        If @error = 0 And BinaryLen($recvData) = 0 Then
            If TimerDiff($timer) > 15000 Then ExitLoop 
            Sleep(5)
            ContinueLoop
        EndIf

        If @error <> 0 Then
            If $hTempFile <> -1 Then FileClose($hTempFile)
            If $assocEstablished Then DICOM_SendReleaseRSP($hSock)
            ExitLoop
        EndIf

        $timer = TimerInit()
        $streamBuffer &= $recvData

        While BinaryLen($streamBuffer) >= 6
            Local $pduType = BinaryMid($streamBuffer, 1, 1)
            Local $pduLen = DICOM_ReadUInt32BE($streamBuffer, 3)
            
            If BinaryLen($streamBuffer) < $pduLen + 6 Then ExitLoop
            
            Local $pduPayload = BinaryMid($streamBuffer, 7, $pduLen)
            $streamBuffer = BinaryMid($streamBuffer, $pduLen + 7)

            Switch $pduType
                Case Binary("0x01") ; A-ASSOCIATE-RQ
                    DICOM_SendAAssociateAC_Storage($hSock, $pduPayload)
                    $assocEstablished = True

                Case Binary("0x04") ; P-DATA-TF
                    Local $pos = 1
                    While $pos <= $pduLen
                        Local $pdvLen = DICOM_ReadUInt32BE($pduPayload, $pos)
                        Local $pcid = Dec(Hex(BinaryMid($pduPayload, $pos + 4, 1)))
                        Local $mch = Dec(Hex(BinaryMid($pduPayload, $pos + 5, 1)))
                        
                        Local $isCommand = BitAND($mch, 1)
                        Local $isLastFragment = BitAND($mch, 2)
                        
                        Local $fragmentData = BinaryMid($pduPayload, $pos + 6, $pdvLen - 2)

                        If $isCommand Then
                            ; Extract vital Command fields
                            Local $cmdField = DICOM_ExtractCommandUS($fragmentData, "00000001") ; 0000,0100
                            Local $extMsgID = DICOM_ExtractCommandUS($fragmentData, "00001001") ; 0000,0110
                            If $extMsgID <> 0 Then $msgID = $extMsgID
                            
                            If $cmdField = 0x0030 Then ; C-ECHO-RQ
                                CSVTS_Log("C-ECHO Request received. Replying with C-ECHO-RSP.")
                                DICOM_SendCEchoRSP($hSock, $msgID, $pcid)
                            ElseIf $cmdField = 0x0001 Then ; C-STORE-RQ
                                Local $tClass = DICOM_ExtractCommandString($fragmentData, "00000200") ; 0000,0002
                                Local $tInst = DICOM_ExtractCommandString($fragmentData, "00000010")  ; 0000,1000
                                If $tClass <> "" Then $currentSOPClass = $tClass
                                If $tInst <> "" Then $currentSOPInst = $tInst
                            EndIf
                        Else
                            ; Image Data
                            If Not $bReceivingImage Then
                                $hTempFile = FileOpen($tempFilePath, 18) ; Overwrite + Binary
                                
                                ; Write Part 10 Preamble
                                Local $preamble = Binary("0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")
                                FileWrite($hTempFile, $preamble)
                                FileWrite($hTempFile, Binary("0x4449434D")) ; "DICM"
                                
                                ; WRITE MISSING FILE META HEADER (Fixes Viewer Warning!)
                                Local $fmi = DICOM_CreateFMI($currentSOPClass, $currentSOPInst, "1.2.840.10008.1.2")
                                FileWrite($hTempFile, $fmi)
                                
                                $bReceivingImage = True
                            EndIf
                            
                            FileWrite($hTempFile, $fragmentData)
                        EndIf

                        If $isLastFragment And Not $isCommand Then
                            DICOM_SendCStoreRSP($hSock, $msgID, $pcid)
                        EndIf
                        
                        $pos += ($pdvLen + 4)
                    WEnd

                Case Binary("0x05") ; A-RELEASE-RQ
                    If $hTempFile <> -1 Then FileClose($hTempFile)
                    DICOM_SendReleaseRSP($hSock)
                    
                    If FileExists($tempFilePath) Then
                        Local $finalPath = GetNextStoragePath()
                        FileMove($tempFilePath, $finalPath, 1)
                        CSVTS_Log("Image received securely and saved to: " & $finalPath)
                        ProcessAndTriggerTelnet($finalPath)
                    EndIf
                    ExitLoop 2 
            EndSwitch
        WEnd
    WEnd
EndFunc

; ===================================================================
; POST-PROCESSING & TELNET
; ===================================================================
Func ProcessAndTriggerTelnet($filePath)
    Local $bData = FileRead($filePath)
    
    Local $PatientID       = DICOM_ExtractTagStringSafe($bData, "10002000")
    Local $PatientName     = DICOM_ExtractTagStringSafe($bData, "10001000")
    Local $Accession       = DICOM_ExtractTagStringSafe($bData, "08005000")
    Local $BirthDate       = DICOM_ExtractTagStringSafe($bData, "10003000")
    Local $Sex             = DICOM_ExtractTagStringSafe($bData, "10004000")
    Local $Modality        = DICOM_ExtractTagStringSafe($bData, "08006000")
    Local $StudyDate       = DICOM_ExtractTagStringSafe($bData, "08002000")
    Local $StudyTime       = DICOM_ExtractTagStringSafe($bData, "08003000")
    Local $StudyDesc       = DICOM_ExtractTagStringSafe($bData, "08003010")
    Local $StudyUID        = DICOM_ExtractTagStringSafe($bData, "20000D00")
    Local $RefPhys         = DICOM_ExtractTagStringSafe($bData, "08009000")
    
    Local $row[22]
    $row[0] = $PatientID
    $row[1] = $PatientName
    $row[2] = $Accession
    $row[3] = $BirthDate
    $row[4] = $Sex
    $row[5] = "" 
    $row[6] = "" 
    $row[7] = "" 
    $row[8] = "" 
    $row[9] = $Modality
    $row[10] = $StudyDate
    $row[11] = $StudyTime
    $row[12] = $StudyDesc
    $row[13] = $StudyUID
    $row[14] = $RefPhys
    $row[15] = "4" 
    $row[16] = "" 
    $row[17] = "" 
    $row[18] = "" 
    $row[19] = "" 
    $row[20] = "" 
    $row[21] = "" 

    Local $csvLine = EntryToCSVLine_RIS($row)
    
    If Not FileExists($CSV_FILE) Then
        Local $hf = FileOpen($CSV_FILE, 2)
        FileWriteLine($hf, $CSV_HEADER)
        FileClose($hf)
    EndIf
    Local $hfAppend = FileOpen($CSV_FILE, 1)
    FileWriteLine($hfAppend, $csvLine)
    FileClose($hfAppend)
    
    CSVTS_Log("Triggering Telnet Client update for PatientID: " & $PatientID)
    Local $tSock = TCPConnect($TELNET_CLIENT_IP, $TELNET_CLIENT_PORT)
    If $tSock <> -1 Then
        TCPSend($tSock, $csvLine & @CRLF)
        TCPCloseSocket($tSock)
    EndIf
EndFunc

; ===================================================================
; DICOM PROTOCOL RESPONSES
; ===================================================================
Func DICOM_SendAAssociateAC_Storage($hSock, $rqPayload)
    Local $paddedAET = StringLeft($SERVER_AET & "                ", 16)
    Local $hexAET = StringToHexStr($paddedAET)
    
    Local $fixedBody = Binary("0x00010000") & Binary("0x" & $hexAET) & Binary("0x414E592D5343552020202020202020200000000000000000000000000000000000000000000000000000000000000000")
    
    Local $pduLen = BinaryLen($rqPayload)
    Local $pos = 69 
    Local $pdu2 = Binary("0x")
    Local $hasAppContext = False
    
    While $pos + 4 <= $pduLen
        Local $itemType = Dec(Hex(BinaryMid($rqPayload, $pos, 1)))
        Local $bHigh = Dec(Hex(BinaryMid($rqPayload, $pos + 2, 1)))
        Local $bLow = Dec(Hex(BinaryMid($rqPayload, $pos + 3, 1)))
        Local $itemLen = ($bHigh * 256) + $bLow
        
        If $pos + 4 + $itemLen > $pduLen + 1 Then ExitLoop
        
        If $itemType = 0x10 Then
            $pdu2 &= BinaryMid($rqPayload, $pos, $itemLen + 4)
            $hasAppContext = True
        ElseIf $itemType = 0x20 Then
            Local $pcid = Dec(Hex(BinaryMid($rqPayload, $pos + 4, 1)))
            $pdu2 &= Binary("0x21000019") & Binary("0x" & StringFormat("%02X", $pcid)) & Binary("0x000000") & _
                     Binary("0x40000011312E322E3834302E31303030382E312E32")
        EndIf
        
        Local $step = $itemLen + 4
        If $step <= 4 Then $step = 4
        $pos += $step
    WEnd
    
    If Not $hasAppContext Then
        $pdu2 = Binary("0x10000015312E322E3834302E31303030382E332E312E312E31") & $pdu2
    EndIf

    Local $pdu3 = Binary("0x5000003951000004000040005200001E312E322E3832362E302E312E333638303034332E322E313339362E3939395500000B43686172727561536F6674")

    Local $totalPayloadLength = BinaryLen($fixedBody) + BinaryLen($pdu2) + BinaryLen($pdu3)
    Local $pduHeader = Binary("0x0200") & DICOM_UInt32BE($totalPayloadLength)

    TCPSend($hSock, $pduHeader & $fixedBody & $pdu2 & $pdu3)
EndFunc

Func DICOM_SendCStoreRSP($hSock, $msgID, $pcid = 1)
    Local $cmd = Binary("0x")
    $cmd &= DICOM_ElemImplicit("0000", "0002", "1.2.840.10008.1.1")
    $cmd &= DICOM_ElemImplicitUS("0000", "0100", 0x8001) ; C-STORE-RSP
    $cmd &= DICOM_ElemImplicitUS("0000", "0120", $msgID)
    $cmd &= DICOM_ElemImplicitUS("0000", "0800", 0x0101)
    $cmd &= DICOM_ElemImplicitUS("0000", "0900", 0x0000) ; Success

    Local $groupLen = BinaryLen($cmd)
    Local $cmdFull = DICOM_ElemImplicitUL("0000", "0000", $groupLen) & $cmd

    TCPSend($hSock, DICOM_WrapCommandAsSinglePDV($cmdFull, $pcid))
EndFunc

Func DICOM_SendCEchoRSP($hSock, $msgID, $pcid = 1)
    Local $cmd = Binary("0x")
    $cmd &= DICOM_ElemImplicit("0000", "0002", "1.2.840.10008.1.1") 
    $cmd &= DICOM_ElemImplicitUS("0000", "0100", 0x8030) ; C-ECHO-RSP
    $cmd &= DICOM_ElemImplicitUS("0000", "0120", $msgID) 
    $cmd &= DICOM_ElemImplicitUS("0000", "0800", 0x0101) 
    $cmd &= DICOM_ElemImplicitUS("0000", "0900", 0x0000) ; Success

    Local $groupLen = BinaryLen($cmd)
    Local $cmdFull = DICOM_ElemImplicitUL("0000", "0000", $groupLen) & $cmd

    TCPSend($hSock, DICOM_WrapCommandAsSinglePDV($cmdFull, $pcid))
EndFunc

Func DICOM_SendReleaseRSP($hSock)
    Local $pdu = Binary("0x0600000000040000")
    TCPSend($hSock, $pdu)
EndFunc

; ===================================================================
; FILE META INFORMATION BUILDER (Fixes the Corruption Warning)
; ===================================================================
Func DICOM_CreateFMI($sopClass, $sopInstance, $tsUID)
    Local $fmi = Binary("")
    $fmi &= Binary("0x020001004F420000020000000001")
    
    If Mod(StringLen($sopClass), 2) <> 0 Then $sopClass &= Chr(0)
    Local $bSOPClass = StringToBinary($sopClass)
    Local $lenHex = StringFormat("%04X", BinaryLen($bSOPClass))
    $lenHex = StringMid($lenHex, 3, 2) & StringMid($lenHex, 1, 2)
    $fmi &= Binary("0x020002005549") & Binary("0x" & $lenHex) & $bSOPClass
    
    If Mod(StringLen($sopInstance), 2) <> 0 Then $sopInstance &= Chr(0)
    Local $bSOPInst = StringToBinary($sopInstance)
    $lenHex = StringFormat("%04X", BinaryLen($bSOPInst))
    $lenHex = StringMid($lenHex, 3, 2) & StringMid($lenHex, 1, 2)
    $fmi &= Binary("0x020003005549") & Binary("0x" & $lenHex) & $bSOPInst
    
    Local $ts = $tsUID
    If Mod(StringLen($ts), 2) <> 0 Then $ts &= Chr(0)
    Local $bTS = StringToBinary($ts)
    $lenHex = StringFormat("%04X", BinaryLen($bTS))
    $lenHex = StringMid($lenHex, 3, 2) & StringMid($lenHex, 1, 2)
    $fmi &= Binary("0x020010005549") & Binary("0x" & $lenHex) & $bTS
    
    Local $imp = "1.2.276.0.7230010.3.0.3.6.4"
    If Mod(StringLen($imp), 2) <> 0 Then $imp &= Chr(0)
    Local $bImp = StringToBinary($imp)
    $lenHex = StringFormat("%04X", BinaryLen($bImp))
    $lenHex = StringMid($lenHex, 3, 2) & StringMid($lenHex, 1, 2)
    $fmi &= Binary("0x020012005549") & Binary("0x" & $lenHex) & $bImp

    Local $fmiLen = BinaryLen($fmi)
    Local $lenHex4 = StringFormat("%08X", $fmiLen)
    $lenHex4 = StringMid($lenHex4, 7, 2) & StringMid($lenHex4, 5, 2) & StringMid($lenHex4, 3, 2) & StringMid($lenHex4, 1, 2)
    Local $groupLenElem = Binary("0x02000000554C0400") & Binary("0x" & $lenHex4)

    Return $groupLenElem & $fmi
EndFunc

; ===================================================================
; SAFE COMMAND EXTRACTORS
; ===================================================================
Func DICOM_ExtractCommandString($bin, $tagHexLE)
    Local $hex = Hex($bin)
    Local $pos = StringInStr($hex, $tagHexLE)
    If $pos > 0 Then
        Local $lenHex = StringMid($hex, $pos + 8, 8)
        Local $length = Dec(StringMid($lenHex, 7, 2) & StringMid($lenHex, 5, 2) & StringMid($lenHex, 3, 2) & StringMid($lenHex, 1, 2))
        If $length > 0 And $length < 1000 Then
            Return StringStripWS(StringReplace(BinaryToString(Binary("0x" & StringMid($hex, $pos + 16, $length * 2))), Chr(0), ""), 3)
        EndIf
    EndIf
    Return ""
EndFunc

Func DICOM_ExtractCommandUS($bin, $tagHexLE)
    Local $hex = Hex($bin)
    Local $pos = StringInStr($hex, $tagHexLE)
    If $pos > 0 Then
        Local $valHex = StringMid($hex, $pos + 16, 4)
        Return Dec(StringMid($valHex, 3, 2) & StringMid($valHex, 1, 2))
    EndIf
    Return 0
EndFunc

Func DICOM_ReadUInt32BE($bin, $offset)
    Return Dec(Hex(BinaryMid($bin, $offset, 1))) * 16777216 + _
           Dec(Hex(BinaryMid($bin, $offset+1, 1))) * 65536 + _
           Dec(Hex(BinaryMid($bin, $offset+2, 1))) * 256 + _
           Dec(Hex(BinaryMid($bin, $offset+3, 1)))
EndFunc

Func DICOM_ExtractTagStringSafe($bin, $hexTagLE)
    Local $hex = Hex($bin)
    Local $pixelPos = StringInStr($hex, "E07F1000")
    If $pixelPos > 0 Then $hex = StringLeft($hex, $pixelPos)
    
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
; DICOM ENCODERS
; ===================================================================
Func DICOM_WrapCommandAsSinglePDV($cmdBytes, $pcid)
    Local $pdvLenBE = DICOM_UInt32BE(BinaryLen($cmdBytes) + 2)
    Local $ctxID = Binary("0x" & StringFormat("%02X", $pcid))
    Local $pdv = $pdvLenBE & $ctxID & Binary("0x03") & $cmdBytes
    Return Binary("0x0400") & DICOM_UInt32BE(BinaryLen($pdv)) & $pdv
EndFunc

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

Func DICOM_UInt32LE($iVal)
    Local $b = Binary("0x" & StringFormat("%08X",$iVal))
    Return BinaryMid($b,4,1) & BinaryMid($b,3,1) & BinaryMid($b,2,1) & BinaryMid($b,1,1)
EndFunc

Func DICOM_UInt32BE($iVal)
    Return Binary("0x" & StringFormat("%08X",$iVal))
EndFunc

Func StringToHexStr($s)
    Local $hex = ""
    For $i = 1 To StringLen($s)
        $hex &= Hex(Asc(StringMid($s, $i, 1)), 2)
    Next
    Return $hex
EndFunc

; ===================================================================
; CSV ARRAY TO LINE
; ===================================================================
Func EntryToCSVLine_RIS($arr)
    Local $s = ""
    For $i = 0 To 21
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
; MAIN LOOP
; ===================================================================
CSVTS_TrayCreate()
CSVTS_CreateMainGUI()

DICOM_StartServer()
TrayItemSetState($g_idToggle, $TRAY_CHECKED)

While 1
    Local $msg = TrayGetMsg()
    Switch $msg
        Case $g_idToggle
            If $g_bRunning Then
                DICOM_StopServer()
                TrayItemSetState($g_idToggle, $TRAY_UNCHECKED)
            Else
                DICOM_StartServer()
                TrayItemSetState($g_idToggle, $TRAY_CHECKED)
            EndIf
        Case $g_idSettings
            CSVTS_ShowSettings()
        Case $g_idExit
            ExitLoop
    EndSwitch

    DICOM_ServerLoop()
    Sleep(10)
WEnd

DICOM_StopServer()
TCPShutdown()