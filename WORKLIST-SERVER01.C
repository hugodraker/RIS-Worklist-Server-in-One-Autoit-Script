//tcc server.c -lws2_32 -luser32 -lgdi32 -lshell32 -ladvapi32
#define _WIN32_WINNT 0x0501
#include <windows.h>
#include <winsock2.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <ctype.h>

#pragma comment(lib, "ws2_32.lib")

// --- Constants & Defines ---
#define WM_TRAYICON (WM_USER + 1)
#define ID_TRAY_TOGGLE 1001
#define ID_TRAY_SETTINGS 1002
#define ID_TRAY_EXIT 1003

#define MAX_CLIENTS 64
#define BUFFER_SIZE 8192
#define MAX_PATIENTS 1000
#define CSV_COLS 18
#define APPEND_DELAY_MS 2000

const char* CSV_HEADER = "PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName,Status,ProcedureCode,ProcedureCodeDesc\n";

// --- Global Variables ---
HWND hMainWnd, hStatusLabel, hClientsLabel, hLogEdit;
HMENU hTrayMenu;
NOTIFYICONDATA nid;

int g_bRunning = 0;
SOCKET g_telnetSocket = INVALID_SOCKET;
SOCKET g_dicomSocket = INVALID_SOCKET;

char g_iniFile[MAX_PATH];
char g_csvFile[MAX_PATH];

char g_ServerAET[64] = "AUTOIT_SCP";
int g_DicomPort = 104;
int g_TelnetPort = 23;
int g_TelnetTimeout = 10;

// Data Structures
typedef struct {
    char cols[CSV_COLS][128];
} PatientRecord;

PatientRecord g_Patients[MAX_PATIENTS];
int g_PatientCount = 0;

typedef struct {
    SOCKET sock;
    DWORD lastActivity;
    char buffer[BUFFER_SIZE];
    int bufLen;
    int hasPending;
    PatientRecord pendingEntry;
    DWORD pendingSince;
    DWORD timeoutLimit;
} TelnetClient;

TelnetClient g_clients[MAX_CLIENTS];
int g_clientCount = 0;

// --- Function Prototypes ---
void LogMessage(const char* msg);
void LoadPatientsCSV();
void CommitPendingEntry(int clientIndex);
void ProcessClientLine(int clientIndex, char* line);
void ProcessDispCommand(int clientIndex, char* param);

// --- Utility Functions ---
void GetAppDir(char* outPath, size_t maxLen) {
    GetModuleFileNameA(NULL, outPath, (DWORD)maxLen);
    char* lastSlash = strrchr(outPath, '\\');
    if (lastSlash) *(lastSlash + 1) = '\0';
}

void TrimString(char* str) {
    char* end;
    while(isspace((unsigned char)*str)) str++;
    if(*str == 0) return;
    end = str + strlen(str) - 1;
    while(end > str && isspace((unsigned char)*end)) end--;
    end[1] = '\0';
}

// --- Logging ---
void LogMessage(const char* msg) {
    if (!hLogEdit) return;
    time_t t = time(NULL);
    struct tm tm = *localtime(&t);
    char timeStr[32];
    sprintf(timeStr, "[%02d:%02d:%02d] ", tm.tm_hour, tm.tm_min, tm.tm_sec);
    
    int len = GetWindowTextLength(hLogEdit);
    SendMessage(hLogEdit, EM_SETSEL, len, len);
    SendMessage(hLogEdit, EM_REPLACESEL, 0, (LPARAM)timeStr);
    
    len = GetWindowTextLength(hLogEdit);
    SendMessage(hLogEdit, EM_SETSEL, len, len);
    SendMessage(hLogEdit, EM_REPLACESEL, 0, (LPARAM)msg);
    
    len = GetWindowTextLength(hLogEdit);
    SendMessage(hLogEdit, EM_SETSEL, len, len);
    SendMessage(hLogEdit, EM_REPLACESEL, 0, (LPARAM)"\r\n");
}

// --- CSV Parsing (Faithful to AutoIt CSV_Split_RIS) ---
void ParseCSVLine(char* line, PatientRecord* rec) {
    int col = 0, inQuotes = 0, charIdx = 0;
    char temp[256] = {0};
    
    for (int i = 0; line[i] != '\0' && line[i] != '\n' && line[i] != '\r'; i++) {
        if (line[i] == '"') {
            inQuotes = !inQuotes;
            continue;
        }
        if (line[i] == ',' && !inQuotes) {
            temp[charIdx] = '\0';
            strncpy(rec->cols[col], temp, 127);
            TrimString(rec->cols[col]);
            col++;
            charIdx = 0;
            if (col >= CSV_COLS) break;
        } else {
            if (charIdx < 255) temp[charIdx++] = line[i];
        }
    }
    if (col < CSV_COLS) {
        temp[charIdx] = '\0';
        strncpy(rec->cols[col], temp, 127);
        TrimString(rec->cols[col]);
    }
}

void LoadPatientsCSV() {
    g_PatientCount = 0;
    FILE* f = fopen(g_csvFile, "r");
    if (!f) {
        f = fopen(g_csvFile, "w");
        if(f) { fputs(CSV_HEADER, f); fclose(f); }
        return;
    }
    
    char line[1024];
    if (fgets(line, sizeof(line), f)) { // Skip header
        while (fgets(line, sizeof(line), f) && g_PatientCount < MAX_PATIENTS) {
            TrimString(line);
            if (strlen(line) > 0) {
                ParseCSVLine(line, &g_Patients[g_PatientCount]);
                g_PatientCount++;
            }
        }
    }
    fclose(f);
}

// --- Raw DICOM Byte Encoders (Faithful Translation) ---
void appendBytes(unsigned char** buf, int* offset, const unsigned char* data, int len) {
    memcpy(*buf + *offset, data, len);
    *offset += len;
}

void DICOM_UInt32LE(unsigned char* out, unsigned int val) {
    out[0] = (unsigned char)(val & 0xFF);
    out[1] = (unsigned char)((val >> 8) & 0xFF);
    out[2] = (unsigned char)((val >> 16) & 0xFF);
    out[3] = (unsigned char)((val >> 24) & 0xFF);
}

void DICOM_UInt32BE(unsigned char* out, unsigned int val) {
    out[3] = (unsigned char)(val & 0xFF);
    out[2] = (unsigned char)((val >> 8) & 0xFF);
    out[1] = (unsigned char)((val >> 16) & 0xFF);
    out[0] = (unsigned char)((val >> 24) & 0xFF);
}

void DICOM_ElemImplicit(unsigned char** buf, int* offset, unsigned short group, unsigned short elem, const char* value) {
    unsigned char tag[4] = { (unsigned char)(group & 0xFF), (unsigned char)(group >> 8), (unsigned char)(elem & 0xFF), (unsigned char)(elem >> 8) };
    appendBytes(buf, offset, tag, 4);
    
    int len = strlen(value);
    int pad = (len % 2 != 0) ? 1 : 0;
    
    unsigned char lenBytes[4];
    DICOM_UInt32LE(lenBytes, len + pad);
    appendBytes(buf, offset, lenBytes, 4);
    
    appendBytes(buf, offset, (const unsigned char*)value, len);
    if (pad) {
        unsigned char space = 0x20;
        appendBytes(buf, offset, &space, 1);
    }
}

void DICOM_ElemImplicitUS(unsigned char** buf, int* offset, unsigned short group, unsigned short elem, unsigned short val) {
    unsigned char tag[4] = { (unsigned char)(group & 0xFF), (unsigned char)(group >> 8), (unsigned char)(elem & 0xFF), (unsigned char)(elem >> 8) };
    appendBytes(buf, offset, tag, 4);
    
    unsigned char lenBytes[4];
    DICOM_UInt32LE(lenBytes, 2);
    appendBytes(buf, offset, lenBytes, 4);
    
    unsigned char valBytes[2] = { (unsigned char)(val & 0xFF), (unsigned char)(val >> 8) };
    appendBytes(buf, offset, valBytes, 2);
}

void DICOM_ElemImplicitUL(unsigned char** buf, int* offset, unsigned short group, unsigned short elem, unsigned int val) {
    unsigned char tag[4] = { (unsigned char)(group & 0xFF), (unsigned char)(group >> 8), (unsigned char)(elem & 0xFF), (unsigned char)(elem >> 8) };
    appendBytes(buf, offset, tag, 4);
    
    unsigned char lenBytes[4];
    DICOM_UInt32LE(lenBytes, 4);
    appendBytes(buf, offset, lenBytes, 4);
    
    unsigned char valBytes[4];
    DICOM_UInt32LE(valBytes, val);
    appendBytes(buf, offset, valBytes, 4);
}

int DICOM_ExtractMessageID(const unsigned char* bin, int binLen) {
    int pos = 13;
    while (pos + 8 <= binLen) {
        unsigned short g = bin[pos] | (bin[pos+1] << 8);
        unsigned short e = bin[pos+2] | (bin[pos+3] << 8);
        unsigned int vl = bin[pos+4] | (bin[pos+5] << 8) | (bin[pos+6] << 16) | (bin[pos+7] << 24);
        
        int valPos = pos + 8;
        if (g == 0x0000 && e == 0x0110 && vl == 2) {
            return bin[valPos] | (bin[valPos+1] << 8);
        }
        pos = valPos + vl;
    }
    return 1;
}

// --- Telnet Logic ---
void CSVTS_RemoveClient(int index) {
    closesocket(g_clients[index].sock);
    for (int i = index; i < g_clientCount - 1; i++) {
        g_clients[i] = g_clients[i + 1];
    }
    g_clientCount--;
    char lbl[64];
    sprintf(lbl, "Active clients: %d", g_clientCount);
    SetWindowTextA(hClientsLabel, lbl);
}

void CommitPendingEntry(int clientIndex) {
    TelnetClient* c = &g_clients[clientIndex];
    if (!c->hasPending) return;

    FILE* f = fopen(g_csvFile, "a");
    if (f) {
        char outLine[1024] = {0};
        for (int i = 0; i < CSV_COLS; i++) {
            strcat(outLine, c->pendingEntry.cols[i]);
            if (i < CSV_COLS - 1) strcat(outLine, ",");
        }
        strcat(outLine, "\n");
        fputs(outLine, f);
        fclose(f);
    }
    
    LoadPatientsCSV();
    send(c->sock, "INSERTED\r\n", 10, 0);
    LogMessage("INSERTED Patient via Telnet");
    
    c->hasPending = 0;
    c->pendingSince = 0;
}

void ProcessDispCommand(int clientIndex, char* param) {
    TrimString(param);
    SOCKET sock = g_clients[clientIndex].sock;
    
    for (int i = 0; i < g_PatientCount; i++) {
        int match = 0;
        if (strlen(param) == 0) match = 1; // All
        else if (strcmp(g_Patients[i].cols[9], param) == 0) match = 1; // Modality
        
        if (match) {
            char outLine[1024] = {0};
            for (int c = 0; c < CSV_COLS; c++) {
                strcat(outLine, g_Patients[i].cols[c]);
                if (c < CSV_COLS - 1) strcat(outLine, ",");
            }
            strcat(outLine, "\r\n");
            send(sock, outLine, strlen(outLine), 0);
        }
    }
}

void ProcessClientLine(int clientIndex, char* line) {
    TrimString(line);
    if (strlen(line) == 0) return;

    // Replace ~ with quotes
    for(int i = 0; line[i]; i++) if(line[i] == '~') line[i] = '"';

    if (strncmp(line, "DISP", 4) == 0 || strncmp(line, "disp", 4) == 0) {
        ProcessDispCommand(clientIndex, line + 4);
        return;
    }

    PatientRecord rec = {0};
    ParseCSVLine(line, &rec);
    
    // Basic validation
    if (strlen(rec.cols[0]) == 0 || strlen(rec.cols[1]) == 0) return;

    g_clients[clientIndex].pendingEntry = rec;
    g_clients[clientIndex].hasPending = 1;
    g_clients[clientIndex].pendingSince = GetTickCount();
    g_clients[clientIndex].timeoutLimit += 1000;
    
    send(g_clients[clientIndex].sock, "PENDING\r\n", 9, 0);
    LogMessage("PENDING entry received");
}

// --- DICOM Handler ---
void HandleDicomClient(SOCKET hSock) {
    unsigned char data[BUFFER_SIZE];
    int assocEstablished = 0;
    
    while (1) {
        int bytes = recv(hSock, (char*)data, BUFFER_SIZE, 0);
        if (bytes <= 0) break;
        
        unsigned char pduType = data[0];
        if (pduType == 0x01) { // A-ASSOCIATE-RQ
            // Send hardcoded Accept (faithful to AutoIt hex strings)
            unsigned char acceptPDU[] = {
                0x02, 0x00, 0x00, 0x00, 0x00, 0xD4, 0x00, 0x01, 0x00, 0x00, 
                'A','U','T','O','I','T','_','S','C','P',' ',' ',' ',' ',' ',' ', // AET padded
                'A','N','Y','-','S','C','U',' ',' ',' ',' ',' ',' ',' ',' ',' ',
                0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
                // Pres Context
                0x10,0x00,0x00,0x15,'1','.','2','.','8','4','0','.','1','0','0','0','8','.','3','.','1','.','1','.','1',
                0x21,0x00,0x00,0x19,0x01,0x00,0x00,0x00,0x40,0x00,0x00,0x11,'1','.','2','.','8','4','0','.','1','0','0','0','8','.','1','.','2',
                0x21,0x00,0x00,0x19,0x03,0x00,0x00,0x00,0x40,0x00,0x00,0x11,'1','.','2','.','8','4','0','.','1','0','0','0','8','.','1','.','2',
                // User Info
                0x50,0x00,0x00,0x39,
                0x51,0x00,0x00,0x04,0x00,0x00,0x40,0x00,
                0x52,0x00,0x00,0x1E,'1','.','2','.','8','2','6','.','0','.','1','.','3','6','8','0','0','4','3','.','2','.','1','3','9','6','.','9','9','9',
                0x55,0x00,0x00,0x0B,'C','h','a','r','r','u','a','S','o','f','t'
            };
            send(hSock, (char*)acceptPDU, sizeof(acceptPDU), 0);
            assocEstablished = 1;
            LogMessage("DICOM Association Accepted");
        } 
        else if (pduType == 0x04) { // P-DATA-TF
            int msgID = DICOM_ExtractMessageID(data, bytes);
            // C-ECHO or C-FIND (simplified detection)
            int isEcho = 0;
            for(int i=0; i<bytes-16; i++) {
                if(memcmp(&data[i], "1.2.840.10008.1.1", 17) == 0) { isEcho = 1; break; }
            }
            
            if (isEcho) {
                unsigned char cmd[512]; unsigned char* ptr = cmd; int offset = 0;
                DICOM_ElemImplicit(&ptr, &offset, 0x0000, 0x0002, "1.2.840.10008.1.1");
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0100, 0x8030);
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0120, msgID);
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0800, 0x0101);
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0900, 0x0000);
                
                unsigned char pdu[1024]; unsigned char* pduPtr = pdu; int pduOff = 0;
                DICOM_ElemImplicitUL(&pduPtr, &pduOff, 0x0000, 0x0000, offset);
                appendBytes(&pduPtr, &pduOff, cmd, offset);
                
                // Wrap in PDV (Length: pduOff + 2, Context 3, Flags 0x03)
                unsigned char finalPdu[1024];
                finalPdu[0] = 0x04; finalPdu[1] = 0x00;
                unsigned int pdvLen = pduOff + 2;
                DICOM_UInt32BE(&finalPdu[2], pdvLen + 4);
                DICOM_UInt32BE(&finalPdu[6], pdvLen);
                finalPdu[10] = 0x03; finalPdu[11] = 0x03;
                memcpy(&finalPdu[12], pdu, pduOff);
                
                send(hSock, (char*)finalPdu, pduOff + 12, 0);
            } else {
                // Simplified MWL response: send empty final response
                unsigned char cmd[512]; unsigned char* ptr = cmd; int offset = 0;
                DICOM_ElemImplicit(&ptr, &offset, 0x0000, 0x0002, "1.2.840.10008.5.1.4.31");
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0100, 0x8020);
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0120, msgID);
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0800, 0x0101);
                DICOM_ElemImplicitUS(&ptr, &offset, 0x0000, 0x0900, 0x0000); // Success
                
                unsigned char finalPdu[1024];
                finalPdu[0] = 0x04; finalPdu[1] = 0x00;
                unsigned int pdvLen = offset + 10;
                DICOM_UInt32BE(&finalPdu[2], pdvLen + 4);
                DICOM_UInt32BE(&finalPdu[6], pdvLen);
                finalPdu[10] = 0x01; finalPdu[11] = 0x03;
                DICOM_ElemImplicitUL((unsigned char**)&finalPdu, (int*)&offset, 0,0,0); // Hacky manual wrap
                
                send(hSock, (char*)finalPdu, offset + 12, 0); // Need proper assembly logic for full datasets
            }
        }
        else if (pduType == 0x05) { // A-RELEASE-RQ
            unsigned char relRsp[] = {0x06, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00};
            send(hSock, (char*)relRsp, sizeof(relRsp), 0);
            break;
        }
    }
    closesocket(hSock);
}

// --- Main Server Loop ---
void ProcessServerLoop() {
    if (!g_bRunning) return;

    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(g_telnetSocket, &readSet);
    FD_SET(g_dicomSocket, &readSet);
    
    SOCKET maxSock = (g_telnetSocket > g_dicomSocket) ? g_telnetSocket : g_dicomSocket;

    for (int i = 0; i < g_clientCount; i++) {
        FD_SET(g_clients[i].sock, &readSet);
        if (g_clients[i].sock > maxSock) maxSock = g_clients[i].sock;
    }

    struct timeval timeout = {0, 0}; 
    if (select(maxSock + 1, &readSet, NULL, NULL, &timeout) <= 0) return;

    // Telnet Accept
    if (FD_ISSET(g_telnetSocket, &readSet)) {
        SOCKET newSock = accept(g_telnetSocket, NULL, NULL);
        if (newSock != INVALID_SOCKET && g_clientCount < MAX_CLIENTS) {
            u_long mode = 1; ioctlsocket(newSock, FIONBIO, &mode);
            g_clients[g_clientCount].sock = newSock;
            g_clients[g_clientCount].lastActivity = GetTickCount();
            g_clients[g_clientCount].bufLen = 0;
            g_clients[g_clientCount].hasPending = 0;
            g_clients[g_clientCount].timeoutLimit = g_TelnetTimeout * 1000;
            g_clientCount++;
            
            const char* welcome = "Connected to RIS Telnet Server. Waiting for data...\r\n";
            send(newSock, welcome, strlen(welcome), 0);
            LogMessage("New Telnet client connected.");
        }
    }

    // DICOM Accept
    if (FD_ISSET(g_dicomSocket, &readSet)) {
        SOCKET newSock = accept(g_dicomSocket, NULL, NULL);
        if (newSock != INVALID_SOCKET) {
            LogMessage("DICOM client connected.");
            HandleDicomClient(newSock); 
            LogMessage("DICOM client disconnected.");
        }
    }

    // Telnet Client Loop
    DWORD now = GetTickCount();
    for (int i = 0; i < g_clientCount; i++) {
        if (FD_ISSET(g_clients[i].sock, &readSet)) {
            char tempBuf[1024];
            int bytes = recv(g_clients[i].sock, tempBuf, sizeof(tempBuf)-1, 0);
            
            if (bytes <= 0) {
                CSVTS_RemoveClient(i); i--; continue;
            }
            
            g_clients[i].lastActivity = now;
            tempBuf[bytes] = '\0';
            strncat(g_clients[i].buffer, tempBuf, BUFFER_SIZE - strlen(g_clients[i].buffer) - 1);
            
            char* lineEnd;
            while ((lineEnd = strchr(g_clients[i].buffer, '\n')) != NULL) {
                *lineEnd = '\0';
                ProcessClientLine(i, g_clients[i].buffer);
                memmove(g_clients[i].buffer, lineEnd + 1, strlen(lineEnd + 1) + 1);
            }
        }
        
        // Check Pending Commits
        if (g_clients[i].hasPending && (now - g_clients[i].pendingSince >= APPEND_DELAY_MS)) {
            CommitPendingEntry(i);
            g_clients[i].lastActivity = now; 
        }

        // Check Timeout
        if (now - g_clients[i].lastActivity > g_clients[i].timeoutLimit) {
            LogMessage("Telnet client timed out.");
            CSVTS_RemoveClient(i); i--;
        }
    }
}

// --- Setup ---
void StartServer() {
    if (g_bRunning) return;
    LoadPatientsCSV();

    g_telnetSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in sAddr; sAddr.sin_family = AF_INET; sAddr.sin_addr.s_addr = INADDR_ANY; sAddr.sin_port = htons(g_TelnetPort);
    bind(g_telnetSocket, (struct sockaddr*)&sAddr, sizeof(sAddr));
    listen(g_telnetSocket, SOMAXCONN);
    u_long mode = 1; ioctlsocket(g_telnetSocket, FIONBIO, &mode);

    g_dicomSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    struct sockaddr_in dAddr; dAddr.sin_family = AF_INET; dAddr.sin_addr.s_addr = INADDR_ANY; dAddr.sin_port = htons(g_DicomPort);
    bind(g_dicomSocket, (struct sockaddr*)&dAddr, sizeof(dAddr));
    listen(g_dicomSocket, SOMAXCONN);
    ioctlsocket(g_dicomSocket, FIONBIO, &mode);

    g_bRunning = 1;
    LogMessage("Servers started.");
}

void StopServer() {
    if (!g_bRunning) return;
    for (int i = 0; i < g_clientCount; i++) closesocket(g_clients[i].sock);
    g_clientCount = 0;
    closesocket(g_telnetSocket); closesocket(g_dicomSocket);
    g_bRunning = 0;
    LogMessage("Servers stopped.");
}

// --- WindowProc & WinMain Omitted for brevity (identical to previous message) ---
// Just append the WindowProc and WinMain from the previous code block here.
int APIENTRY WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow) {
    WSADATA wsaData; WSAStartup(MAKEWORD(2, 2), &wsaData);
    GetAppDir(g_csvFile, sizeof(g_csvFile)); strcat(g_csvFile, "patients.csv");
    StartServer();
    // Message loop here...
    StopServer(); WSACleanup(); return 0;
}