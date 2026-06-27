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

; Folder/File Tracking
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
    CSVTS_Log("DICOM C-STORE SCP listening on port " & $DICOM_PORT)
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
; DICOM CLIENT ROUTER & STORAGE
; ===================================================================
Func DICOM_HandleClient($hSock)
    Local $assocEstablished = False
    Local $timer = TimerInit()
    Local $bReceivingImage = False
    Local $tempFilePath = @ScriptDir & "\temp_" & $hSock & ".dcm"
    Local $hTempFile = -1
    Local $msgID = 1

    While 1
        Local $data = TCPRecv($hSock, 8192, 1)

        If @error = 0 And BinaryLen($data) = 0 Then
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
        Local $pduType = BinaryMid($data, 1, 1)

        Switch $pduType
            Case Binary("0x01") ; A-ASSOCIATE-RQ
                DICOM_SendAAssociateAC_Storage($hSock, $data)
                $assocEstablished = True

            Case Binary("0x04") ; P-DATA-TF
                ; Check if this is the start of a command/data stream
                Local $pdvType = BinaryMid($data, 12, 1) ; Very basic PDV check
                
                ; If command, send C-STORE-RSP. If Data, append to file.
                ; Simplified: We write the raw dataset to a temp file.
                If Not $bReceivingImage Then
                    $hTempFile = FileOpen($tempFilePath, 18) ; Overwrite + Binary
                    $bReceivingImage = True
                EndIf
                
                ; Strip PDU header (first 6 bytes) and append
                Local $pduLen = BinaryLen($data)
                If $pduLen > 6 Then
                    FileWrite($hTempFile, BinaryMid($data, 7))
                EndIf
                
                ; Send generic C-STORE-RSP (Success)
                $msgID = DICOM_ExtractMessageID($data)
                If $msgID <> 0 Then DICOM_SendCStoreRSP($hSock, $msgID)

            Case Binary("0x05") ; A-RELEASE-RQ
                If $hTempFile <> -1 Then FileClose($hTempFile)
                DICOM_SendReleaseRSP($hSock)
                
                ; Move temp file to final location and process
                If FileExists($tempFilePath) Then
                    Local $finalPath = GetNextStoragePath()
                    FileMove($tempFilePath, $finalPath, 1)
                    CSVTS_Log("Image received and saved to: " & $finalPath)
                    
                    ; Process the saved DICOM file and trigger Telnet
                    ProcessAndTriggerTelnet($finalPath)
                EndIf
                ExitLoop
        EndSwitch
    WEnd
EndFunc

; ===================================================================
; POST-PROCESSING & TELNET
; ===================================================================
Func ProcessAndTriggerTelnet($filePath)
    Local $bData = FileRead($filePath)
    
    ; Extract Tags
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
    
    ; Map to 22 Columns (Status = 4)
    Local $row[22]
    $row[0] = $PatientID
    $row[1] = $PatientName
    $row[2] = $Accession
    $row[3] = $BirthDate
    $row[4] = $Sex
    $row[5] = "" ; SPSID (Often not in C-STORE payload)
    $row[6] = "" ; SPSDescription
    $row[7] = "" ; RequestedProcID
    $row[8] = "" ; StationAET
    $row[9] = $Modality
    $row[10] = $StudyDate
    $row[11] = $StudyTime
    $row[12] = $StudyDesc
    $row[13] = $StudyUID
    $row[14] = $RefPhys
    $row[15] = "4" ; COMPLETED
    $row[16] = "" ; ProcedureCode
    $row[17] = "" ; ProcedureCodeDesc
    $row[18] = "" ; CodingScheme
    $row[19] = "" ; PerformingPhys
    $row[20] = "" ; StationName
    $row[21] = "" ; Location

    Local $csvLine = EntryToCSVLine_RIS($row)
    
    ; Write to STOR.CSV
    If Not FileExists($CSV_FILE) Then
        Local $hf = FileOpen($CSV_FILE, 2)
        FileWriteLine($hf, $CSV_HEADER)
        FileClose($hf)
    EndIf
    Local $hfAppend = FileOpen($CSV_FILE, 1)
    FileWriteLine($hfAppend, $csvLine)
    FileClose($hfAppend)
    
    ; Trigger Telnet
    CSVTS_Log("Triggering Telnet Client update for PatientID: " & $PatientID)
    Local $tSock = TCPConnect($TELNET_CLIENT_IP, $TELNET_CLIENT_PORT)
    If $tSock <> -1 Then
        TCPSend($tSock, $csvLine & @CRLF)
        TCPCloseSocket($tSock)
    Else
        CSVTS_Log("Warning: Could not connect to Telnet Client at " & $TELNET_CLIENT_IP & ":" & $TELNET_CLIENT_PORT)
    EndIf
EndFunc

; ===================================================================
; DICOM PROTOCOL HELPERS
; ===================================================================
Func DICOM_SendAAssociateAC_Storage($hSock, $rqData)
    Local $paddedAET = StringLeft($SERVER_AET & "                ", 16)
    Local $hexAET = StringToHexStr($paddedAET)
    
    ; Build a permissive Accept responding to the association
    Local $pdu1 = Binary("0x0200000000D400010000" & $hexAET & "414E592D534355202020202020202020" & _
        "0000000000000000000000000000000000000000000000000000000000000000")

    ; Accept Presentation Context 1 (Implicit VR Little Endian)
    Local $pdu2 = Binary("0x10000015312E322E3834302E31303030382E332E312E312E31" & _
        "210000190100000040000011312E322E3834302E31303030382E312E32" & _
        "210000190300000040000011312E322E3834302E31303030382E312E32")

    Local $pdu3 = Binary("0x5000003951000004000040005200001E312E322E3832362E302E312E333638303034332E322E313339362E3939395500000B43686172727561536F6674")

    TCPSend($hSock, $pdu1)
    TCPSend($hSock, $pdu2)
    TCPSend($hSock, $pdu3)
EndFunc

Func DICOM_SendCStoreRSP($hSock, $msgID)
    Local $cmd = Binary("0x")
    $cmd &= DICOM_ElemImplicit("0000", "0002", "1.2.840.10008.1.1")
    $cmd &= DICOM_ElemImplicitUS("0000", "0100", 0x8001) ; C-STORE-RSP
    $cmd &= DICOM_ElemImplicitUS("0000", "0120", $msgID)
    $cmd &= DICOM_ElemImplicitUS("0000", "0800", 0x0101)
    $cmd &= DICOM_ElemImplicitUS("0000", "0900", 0x0000) ; Success

    Local $groupLen = BinaryLen($cmd)
    Local $cmdFull = DICOM_ElemImplicitUL("0000", "0000", $groupLen) & $cmd

    TCPSend($hSock, DICOM_WrapCommandAsSinglePDV($cmdFull, 1))
EndFunc

Func DICOM_SendReleaseRSP($hSock)
    Local $pdu = Binary("0x0600000000040000")
    TCPSend($hSock, $pdu)
EndFunc

; ===================================================================
; SAFE DATA EXTRACTORS
; ===================================================================
Func DICOM_ExtractTagStringSafe($bin, $hexTagLE)
    Local $hex = Hex($bin)
    
    ; Prevent extraction freezing by truncating search before Pixel Data (7FE0,0010 -> E07F1000)
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
        
        ; Safety break to avoid reading past command group into large datasets
        If $g <> "0000" Then ExitLoop 
        
        $pos = $valPos + $vlInt
    WEnd
    Return 1
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
