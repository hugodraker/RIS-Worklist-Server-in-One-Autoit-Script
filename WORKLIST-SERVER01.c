/*
    WORKLIST-SERVER01.c

    BUILD / RUN INSTRUCTIONS:

    MinGW-w64 console build:
        gcc -O2 -s -o WORKLIST-SERVER01.exe WORKLIST-SERVER01.c -lws2_32 -lkernel32 -luser32 -lshell32

    MinGW-w64 tray/windowed build:
        gcc -O2 -s -mwindows -o WORKLIST-SERVER01.exe WORKLIST-SERVER01.c -lws2_32 -lkernel32 -luser32 -lshell32

    TCC:
        tcc -o WORKLIST-SERVER01.exe WORKLIST-SERVER01.c -lws2_32 -lkernel32 -luser32 -lshell32

    Purpose:
        RIS Telnet + DICOM Modality Worklist SCP.

    Current compatibility focus:
        - C-ECHO-RQ / C-ECHO-RSP success.
        - C-FIND-RQ / C-FIND-RSP for Modality Worklist.
        - AutoIt-style MWL dataset generation.
        - Implicit VR Little Endian MWL responses to avoid corrupted datasets.
        - System tray menu with Settings and Show Console Window.
        - Primary/left-click on tray icon opens tray menu.
        - Right-click on tray icon opens tray menu.

    CSV file:
        patients.csv

    CSV header:
        PatientID,PatientName,Accession,BirthDate,Sex,SPSID,SPSDescription,
        RequestedProcedureID,StationAET,Modality,ScheduledDate,ScheduledTime,
        RequestedProcDesc,StudyInstanceUID,ReferringPhysicianName,Status,
        ProcedureCode,ProcedureCodeDesc,CodingScheme,PerformingPhysician,
        StationName,Location
*/

#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0501

#include <winsock2.h>
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#ifndef snprintf
#define snprintf _snprintf
#endif

#define MAX_CLIENTS         16
#define RECV_SIZE           2048
#define CLIENT_BUF_SIZE     4096
#define DEFAULT_TIMEOUT_MS  10000

#define FIELD_COUNT         22
#define FIELD_SIZE          128
#define ENTRY_SIZE          (FIELD_COUNT * FIELD_SIZE)
#define LINE_SIZE           8192

#define DICOM_RECV_BUF_SIZE 1048576
#define DICOM_SEND_BUF_SIZE 1048576
#define MAX_PC              64
#define MAX_UID             128

#define WM_TRAYICON         (WM_USER + 1)

#define ID_TRAY_TOGGLE      1000
#define ID_TRAY_SETTINGS    1001
#define ID_TRAY_SHOW        1002
#define ID_TRAY_EXIT        1003

#define ID_BTN_STARTSTOP    2001
#define ID_BTN_SAVE         2002
#define ID_BTN_CLOSE        2003
#define ID_EDIT_AET         2010
#define ID_EDIT_TELNETPORT  2011
#define ID_EDIT_DICOMPORT   2012
#define ID_EDIT_TIMEOUT     2013
#define ID_CHK_DEBUG        2014
#define ID_STATUS_LABEL     2015

#define TS_IMPLICIT_LE      "1.2.840.10008.1.2"
#define TS_EXPLICIT_LE      "1.2.840.10008.1.2.1"
#define SOP_VERIFICATION    "1.2.840.10008.1.1"
#define SOP_MWL_FIND        "1.2.840.10008.5.1.4.31"
#define APP_CONTEXT         "1.2.840.10008.3.1.1.1"
#define IMPL_CLASS_UID      "1.2.826.0.1.3680043.2.1396.999"
#define IMPL_VERSION_NAME   "WORKLIST_C"

typedef struct PC_INFO_TAG {
    int id;
    int accepted;
    int isVerification;
    int isMWL;
    int hasImplicit;
    int hasExplicit;
    char abstractSyntax[MAX_UID];
    char transferSyntax[MAX_UID];
} PC_INFO;

static unsigned int g_TelnetPort      = 23;
static unsigned int g_DicomPort       = 104;
static unsigned int g_TelnetTimeout   = 10;
static unsigned int g_DebugLog        = 1;

static int          g_bRunning        = 0;
static SOCKET       g_listenSocket    = INVALID_SOCKET;
static SOCKET       g_dicomListenSock = INVALID_SOCKET;

static SOCKET       g_clients[MAX_CLIENTS];
static DWORD        g_clientLastTick[MAX_CLIENTS];
static DWORD        g_clientTimeout[MAX_CLIENTS];
static int          g_clientBufLen[MAX_CLIENTS];
static char         g_clientBuffers[MAX_CLIENTS][CLIENT_BUF_SIZE];

static HINSTANCE    g_hInstance       = 0;
static HWND         g_hMainWnd        = 0;
static HWND         g_hSettingsWnd    = 0;
static HWND         g_hStatusLabel    = 0;
static HMENU        g_hMenu           = 0;
static NOTIFYICONDATA g_nid;

static char g_aeCalled[17]  = "AUTOIT_SCP      ";
static char g_aeCalling[17] = "ANY-SCU         ";

static char g_recvBuf[RECV_SIZE];
static char g_iniBuf[256];

static unsigned char g_dicomRecvBuf[DICOM_RECV_BUF_SIZE];
static unsigned char g_dicomSendBuf[DICOM_SEND_BUF_SIZE];
static unsigned char g_datasetBuf[DICOM_SEND_BUF_SIZE];
static unsigned char g_cmdBuf[4096];

static PC_INFO g_pc[MAX_PC];
static int g_pcCount = 0;
static unsigned int g_peerMaxPDU = 16384;

static const char *szIniFile        = "WORKLIST-SERVER01.ini";
static const char *szCSVFile        = "patients.csv";
static const char *szTmpFile        = "patients.tmp";
static const char *szWndClass       = "WorklistTrayClass";
static const char *szSettingsClass  = "WorklistSettingsClass";
static const char *szTrayTip        = "RIS Telnet + DICOM MWL SCP";
static const char *szMenuStart      = "Start Server";
static const char *szMenuStop       = "Stop Server";

static const char *szCSVHeader =
"PatientID,PatientName,Accession,BirthDate,Sex,"
"SPSID,SPSDescription,RequestedProcedureID,"
"StationAET,Modality,ScheduledDate,ScheduledTime,"
"RequestedProcDesc,StudyInstanceUID,"
"ReferringPhysicianName,Status,ProcedureCode,"
"ProcedureCodeDesc,CodingScheme,"
"PerformingPhysician,StationName,Location";

static void ServerStart(void);
static void ServerStop(void);
static void UpdateTrayMenuText(void);
static void ShowSettings(void);
static void ShowConsoleWindow(void);
static void ShowTrayMenu(HWND hWnd);

/* ============================================================
   Utility
   ============================================================ */

static int ci_ncmp(const char *a, const char *b, int n)
{
    int i;

    for (i = 0; i < n; i++) {
        int ca = toupper((unsigned char)a[i]);
        int cb = toupper((unsigned char)b[i]);

        if (ca != cb)
            return ca - cb;

        if (a[i] == 0 || b[i] == 0)
            break;
    }

    return 0;
}

static void trim_in_place(char *s)
{
    int i, n;
    char *p = s;

    if (!s) return;

    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n')
        p++;

    if (p != s)
        memmove(s, p, strlen(p) + 1);

    n = (int)strlen(s);

    for (i = n - 1; i >= 0; i--) {
        if (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')
            s[i] = 0;
        else
            break;
    }
}

static void set_ae_title(const char *src)
{
    int i;

    for (i = 0; i < 16; i++)
        g_aeCalled[i] = ' ';

    g_aeCalled[16] = 0;

    if (!src) return;

    for (i = 0; i < 16 && src[i]; i++)
        g_aeCalled[i] = src[i];
}

static void copy_ae_trim(char *dst, const unsigned char *src)
{
    int i;

    memcpy(dst, src, 16);
    dst[16] = 0;

    for (i = 15; i >= 0; i--) {
        if (dst[i] == ' ' || dst[i] == 0)
            dst[i] = 0;
        else
            break;
    }
}

static void LogText(const char *s)
{
    if (!s) return;

    if (g_DebugLog)
        printf("%s\r\n", s);
}

static void send_text(SOCKET s, const char *t)
{
    int n;

    if (!t) return;

    n = (int)strlen(t);
    if (n > 0)
        send(s, t, n, 0);
}

static unsigned short rd_le16(const unsigned char *p)
{
    return (unsigned short)(p[0] | (p[1] << 8));
}

static unsigned int rd_le32(const unsigned char *p)
{
    return ((unsigned int)p[0]) |
           ((unsigned int)p[1] << 8) |
           ((unsigned int)p[2] << 16) |
           ((unsigned int)p[3] << 24);
}

static unsigned short rd_be16(const unsigned char *p)
{
    return (unsigned short)((p[0] << 8) | p[1]);
}

static unsigned int rd_be32(const unsigned char *p)
{
    return ((unsigned int)p[0] << 24) |
           ((unsigned int)p[1] << 16) |
           ((unsigned int)p[2] << 8) |
           ((unsigned int)p[3]);
}

static void wr_be16(unsigned char *p, unsigned int v)
{
    p[0] = (unsigned char)((v >> 8) & 0xFF);
    p[1] = (unsigned char)(v & 0xFF);
}

static void wr_be32(unsigned char *p, unsigned int v)
{
    p[0] = (unsigned char)((v >> 24) & 0xFF);
    p[1] = (unsigned char)((v >> 16) & 0xFF);
    p[2] = (unsigned char)((v >> 8) & 0xFF);
    p[3] = (unsigned char)(v & 0xFF);
}

static void wr_le16(unsigned char *p, unsigned int v)
{
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
}

static void wr_le32(unsigned char *p, unsigned int v)
{
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

static char *field_ptr(char *entry, int idx)
{
    return entry + idx * FIELD_SIZE;
}

static const char *field_cptr(const char *entry, int idx)
{
    return entry + idx * FIELD_SIZE;
}

static void strip_colons(const char *src, char *dst)
{
    while (*src) {
        if (*src != ':')
            *dst++ = *src;
        src++;
    }

    *dst = 0;
}

/* ============================================================
   INI / config
   ============================================================ */

static void CreateDefaultIniIfMissing(void)
{
    DWORD attr = GetFileAttributes(szIniFile);

    if (attr != INVALID_FILE_ATTRIBUTES)
        return;

    WritePrivateProfileString("Server", "AETitle", "AUTOIT_SCP", szIniFile);
    WritePrivateProfileString("Server", "DicomPort", "104", szIniFile);
    WritePrivateProfileString("Server", "TelnetPort", "23", szIniFile);
    WritePrivateProfileString("Server", "TelnetTimeout", "10", szIniFile);
    WritePrivateProfileString("Server", "DebugLog", "1", szIniFile);

    WritePrivateProfileString("Lists", "Modalities", "CR;DX;CT;MR;US;OT", szIniFile);
    WritePrivateProfileString("Lists", "AETitles", "AET1;AET2", szIniFile);
    WritePrivateProfileString("Lists", "ReferringPhysicians", "Dr. Smith;Dr. Brown", szIniFile);
    WritePrivateProfileString("Lists", "Procedures", "Chest X-Ray;CT Head", szIniFile);
    WritePrivateProfileString("Lists", "ProcedureCodes", "PCODE01;PCODE02", szIniFile);
}

static void LoadConfig(void)
{
    CreateDefaultIniIfMissing();

    GetPrivateProfileString("Server", "AETitle", "AUTOIT_SCP",
        g_iniBuf, sizeof(g_iniBuf), szIniFile);

    set_ae_title(g_iniBuf);

    g_TelnetPort = GetPrivateProfileInt("Server", "TelnetPort", 23, szIniFile);
    g_DicomPort = GetPrivateProfileInt("Server", "DicomPort", 104, szIniFile);
    g_TelnetTimeout = GetPrivateProfileInt("Server", "TelnetTimeout", 10, szIniFile);
    g_DebugLog = GetPrivateProfileInt("Server", "DebugLog", 1, szIniFile);

    if (g_TelnetPort == 0) g_TelnetPort = 23;
    if (g_DicomPort == 0) g_DicomPort = 104;
    if (g_TelnetTimeout == 0) g_TelnetTimeout = 10;
}

static void SaveConfigValue(const char *section, const char *key, unsigned int val)
{
    char buf[64];
    sprintf(buf, "%u", val);
    WritePrivateProfileString(section, key, buf, szIniFile);
}

/* ============================================================
   CSV
   ============================================================ */

static void ensure_csv(void)
{
    FILE *f = fopen(szCSVFile, "r");

    if (f) {
        fclose(f);
        return;
    }

    f = fopen(szCSVFile, "w");
    if (!f) return;

    fprintf(f, "%s\r\n", szCSVHeader);
    fclose(f);
}

static void parse_csv_line(const char *line, char *entry)
{
    int fi = 0;
    int ci = 0;
    int quote = 0;
    int i;

    memset(entry, 0, ENTRY_SIZE);

    for (i = 0; line[i]; i++) {
        char c = line[i];

        if (c == '\r' || c == '\n')
            break;

        if (c == '~')
            c = '"';

        if (c == '"') {
            if (quote && line[i + 1] == '"') {
                if (ci < FIELD_SIZE - 1)
                    field_ptr(entry, fi)[ci++] = '"';
                i++;
                continue;
            }

            quote = !quote;
            continue;
        }

        if (c == ',' && !quote) {
            field_ptr(entry, fi)[ci] = 0;
            fi++;

            if (fi >= FIELD_COUNT)
                break;

            ci = 0;
            continue;
        }

        if (ci < FIELD_SIZE - 1)
            field_ptr(entry, fi)[ci++] = c;
    }

    if (fi < FIELD_COUNT)
        field_ptr(entry, fi)[ci] = 0;

    for (i = 0; i < FIELD_COUNT; i++)
        trim_in_place(field_ptr(entry, i));
}

static int needs_quote(const char *f)
{
    while (*f) {
        if (*f == ',' || *f == '"')
            return 1;
        f++;
    }

    return 0;
}

static void build_csv_line(char *entry, char *out)
{
    int i;
    char *p = out;

    for (i = 0; i < FIELD_COUNT; i++) {
        const char *f = field_ptr(entry, i);
        int q = needs_quote(f);

        if (i > 0)
            *p++ = ',';

        if (q)
            *p++ = '"';

        while (*f) {
            if (q && *f == '"') {
                *p++ = '"';
                *p++ = '"';
            } else {
                *p++ = *f;
            }

            f++;
        }

        if (q)
            *p++ = '"';
    }

    *p = 0;
}

static int first_field_equals(const char *line, const char *pid)
{
    while (*line && *line != ',' && *line != '\r' && *line != '\n') {
        if (*pid == 0 || *line != *pid)
            return 0;

        line++;
        pid++;
    }

    return *pid == 0 &&
           (*line == ',' || *line == 0 || *line == '\r' || *line == '\n');
}

static int update_csv_by_patient(char *entry, const char *lineOut)
{
    FILE *in;
    FILE *out;
    int found = 0;
    const char *pid = field_ptr(entry, 0);
    char line[LINE_SIZE];

    in = fopen(szCSVFile, "r");
    out = fopen(szTmpFile, "w");

    if (!out)
        return 0;

    if (!in) {
        fprintf(out, "%s\r\n", szCSVHeader);
        fprintf(out, "%s\r\n", lineOut);
        fclose(out);
        MoveFileEx(szTmpFile, szCSVFile, MOVEFILE_REPLACE_EXISTING);
        return 0;
    }

    if (fgets(line, sizeof(line), in))
        fprintf(out, "%s", line);
    else
        fprintf(out, "%s\r\n", szCSVHeader);

    while (fgets(line, sizeof(line), in)) {
        if (first_field_equals(line, pid)) {
            fprintf(out, "%s\r\n", lineOut);
            found = 1;
        } else {
            fprintf(out, "%s", line);
        }
    }

    if (!found)
        fprintf(out, "%s\r\n", lineOut);

    fclose(in);
    fclose(out);

    MoveFileEx(szTmpFile, szCSVFile, MOVEFILE_REPLACE_EXISTING);

    return found;
}

/* ============================================================
   Winsock helpers
   ============================================================ */

static void set_nonblocking(SOCKET s)
{
    u_long mode = 1;
    ioctlsocket(s, FIONBIO, &mode);
}

static void set_blocking(SOCKET s)
{
    u_long mode = 0;
    ioctlsocket(s, FIONBIO, &mode);
}

/* ============================================================
   Console
   ============================================================ */

static void ShowConsoleWindow(void)
{
    HWND hCon;

    hCon = GetConsoleWindow();

    if (!hCon) {
        AllocConsole();

        freopen("CONOUT$", "w", stdout);
        freopen("CONOUT$", "w", stderr);
        freopen("CONIN$", "r", stdin);

        SetConsoleTitle("WORKLIST-SERVER01 Console");
        hCon = GetConsoleWindow();
    }

    if (hCon) {
        ShowWindow(hCon, SW_SHOW);
        SetForegroundWindow(hCon);
    }

    printf("Console window shown.\r\n");
}

/* ============================================================
   DICOM implicit element builders, AutoIt-style
   ============================================================ */

static int dicom_elem_implicit_str(unsigned char *p,
    unsigned short group, unsigned short elem, const char *s)
{
    int n;
    int pad;

    if (!s)
        s = "";

    n = (int)strlen(s);
    pad = (n & 1) ? n + 1 : n;

    wr_le16(p + 0, group);
    wr_le16(p + 2, elem);
    wr_le32(p + 4, (unsigned int)pad);

    if (n)
        memcpy(p + 8, s, n);

    if (pad > n)
        p[8 + n] = 0x20;

    return 8 + pad;
}

static int dicom_elem_implicit_us(unsigned char *p,
    unsigned short group, unsigned short elem, unsigned short val)
{
    wr_le16(p + 0, group);
    wr_le16(p + 2, elem);
    wr_le32(p + 4, 2);
    wr_le16(p + 8, val);
    return 10;
}

static int dicom_elem_implicit_ul(unsigned char *p,
    unsigned short group, unsigned short elem, unsigned int val)
{
    wr_le16(p + 0, group);
    wr_le16(p + 2, elem);
    wr_le32(p + 4, 4);
    wr_le32(p + 8, val);
    return 12;
}

static int dicom_item_one(unsigned char *p, const unsigned char *itemData, int itemLen)
{
    wr_le16(p + 0, 0xFFFE);
    wr_le16(p + 2, 0xE000);
    wr_le32(p + 4, (unsigned int)itemLen);

    if (itemLen > 0)
        memcpy(p + 8, itemData, itemLen);

    return 8 + itemLen;
}

static int dicom_sequence_one_item_implicit(unsigned char *p,
    unsigned short group, unsigned short elem,
    const unsigned char *itemData, int itemLen)
{
    int itemTotal;

    wr_le16(p + 0, group);
    wr_le16(p + 2, elem);

    itemTotal = 8 + itemLen;

    wr_le32(p + 4, (unsigned int)itemTotal);

    return 8 + dicom_item_one(p + 8, itemData, itemLen);
}

/* ============================================================
   DICOM command helpers
   ============================================================ */

static const unsigned char *find_cmd_elem(const unsigned char *cmd, int len,
    unsigned short group, unsigned short elem, unsigned int *outLen)
{
    int pos = 0;

    while (pos + 8 <= len) {
        unsigned short g = rd_le16(cmd + pos);
        unsigned short e = rd_le16(cmd + pos + 2);
        unsigned int l = rd_le32(cmd + pos + 4);

        if (pos + 8 + (int)l > len)
            break;

        if (g == group && e == elem) {
            if (outLen)
                *outLen = l;

            return cmd + pos + 8;
        }

        pos += 8 + (int)l;
    }

    return NULL;
}

static unsigned short cmd_get_us(const unsigned char *cmd, int len,
    unsigned short group, unsigned short elem)
{
    unsigned int vl = 0;
    const unsigned char *p = find_cmd_elem(cmd, len, group, elem, &vl);

    if (!p || vl < 2)
        return 0;

    return rd_le16(p);
}

static int build_rsp_cmd(unsigned char *out,
    const char *affectedSOP,
    unsigned short cmdField,
    unsigned short msgIdRespondedTo,
    unsigned short dataSetType,
    unsigned short status)
{
    unsigned char *p = out + 12;
    int cmdLen;

    p += dicom_elem_implicit_str(p, 0x0000, 0x0002, affectedSOP);
    p += dicom_elem_implicit_us(p,  0x0000, 0x0100, cmdField);
    p += dicom_elem_implicit_us(p,  0x0000, 0x0120, msgIdRespondedTo);
    p += dicom_elem_implicit_us(p,  0x0000, 0x0800, dataSetType);
    p += dicom_elem_implicit_us(p,  0x0000, 0x0900, status);

    cmdLen = (int)(p - (out + 12));

    dicom_elem_implicit_ul(out, 0x0000, 0x0000, (unsigned int)cmdLen);

    return cmdLen + 12;
}

static void send_pdv(SOCKET s, int pcid,
    const unsigned char *data, int dataLen, int flags)
{
    unsigned char *p = g_dicomSendBuf;
    unsigned int pdvLen = (unsigned int)dataLen + 2;
    unsigned int pduLen = pdvLen + 4;

    p[0] = 0x04;
    p[1] = 0x00;
    wr_be32(p + 2, pduLen);
    wr_be32(p + 6, pdvLen);
    p[10] = (unsigned char)pcid;
    p[11] = (unsigned char)flags;

    memcpy(p + 12, data, dataLen);

    send(s, (const char *)g_dicomSendBuf, dataLen + 12, 0);
}

static void send_c_echo_rsp(SOCKET s, int pcid, unsigned short msgID)
{
    int n = build_rsp_cmd(g_cmdBuf, SOP_VERIFICATION,
        0x8030, msgID, 0x0101, 0x0000);

    send_pdv(s, pcid, g_cmdBuf, n, 0x03);

    LogText("C-ECHO-RSP success sent.");
}

static void send_c_find_final(SOCKET s, int pcid, unsigned short msgID)
{
    int n = build_rsp_cmd(g_cmdBuf, SOP_MWL_FIND,
        0x8020, msgID, 0x0101, 0x0000);

    send_pdv(s, pcid, g_cmdBuf, n, 0x03);

    LogText("C-FIND final success sent.");
}

static void send_c_find_pending(SOCKET s, int pcid, unsigned short msgID,
    const unsigned char *ds, int dsLen)
{
    int n = build_rsp_cmd(g_cmdBuf, SOP_MWL_FIND,
        0x8020, msgID, 0x0102, 0xFF00);

    send_pdv(s, pcid, g_cmdBuf, n, 0x03);
    send_pdv(s, pcid, ds, dsLen, 0x02);
}

/* ============================================================
   DICOM MWL dataset builder, matched to AutoIt order
   ============================================================ */

static int build_code_sequence_item(char *entry, unsigned char *out)
{
    unsigned char *p = out;

    p += dicom_elem_implicit_str(p, 0x0008, 0x0100, field_cptr(entry, 16));
    p += dicom_elem_implicit_str(p, 0x0008, 0x0102, field_cptr(entry, 18));
    p += dicom_elem_implicit_str(p, 0x0008, 0x0104, field_cptr(entry, 17));

    return (int)(p - out);
}

static int build_mwl_dataset_autoit_style(char *entry, unsigned char *out)
{
    unsigned char *p = out;
    unsigned char item[16384];
    unsigned char codeItem[4096];
    unsigned char codeSeq[8192];
    unsigned char *q = item;
    int codeItemLen;
    int codeSeqLen;
    char timeNoColon[32];

    strip_colons(field_cptr(entry, 11), timeNoColon);

    /*
        Root dataset order copied from AutoIt:
        0008,0005
        0008,0050
        0008,0090
        0010,0010
        0010,0020
        0010,0030
        0010,0040
        0020,000D
        0032,1060
        0040,0100 sequence
        0040,1001
    */

    p += dicom_elem_implicit_str(p, 0x0008, 0x0005, "ISO_IR 100");
    p += dicom_elem_implicit_str(p, 0x0008, 0x0050, field_cptr(entry, 2));
    p += dicom_elem_implicit_str(p, 0x0008, 0x0090, field_cptr(entry, 14));

    p += dicom_elem_implicit_str(p, 0x0010, 0x0010, field_cptr(entry, 1));
    p += dicom_elem_implicit_str(p, 0x0010, 0x0020, field_cptr(entry, 0));
    p += dicom_elem_implicit_str(p, 0x0010, 0x0030, field_cptr(entry, 3));
    p += dicom_elem_implicit_str(p, 0x0010, 0x0040, field_cptr(entry, 4));

    p += dicom_elem_implicit_str(p, 0x0020, 0x000D, field_cptr(entry, 13));
    p += dicom_elem_implicit_str(p, 0x0032, 0x1060, field_cptr(entry, 12));

    /*
        SPS item order copied from AutoIt:
        0008,0060
        0040,0001
        0040,0002
        0040,0003
        0040,0006
        0040,0007
        0040,0008 optional code sequence
        0040,0009
        0040,0010
        0040,0011
    */

    q += dicom_elem_implicit_str(q, 0x0008, 0x0060, field_cptr(entry, 9));

    q += dicom_elem_implicit_str(q, 0x0040, 0x0001, field_cptr(entry, 8));
    q += dicom_elem_implicit_str(q, 0x0040, 0x0002, field_cptr(entry, 10));
    q += dicom_elem_implicit_str(q, 0x0040, 0x0003, timeNoColon);
    q += dicom_elem_implicit_str(q, 0x0040, 0x0006, field_cptr(entry, 19));
    q += dicom_elem_implicit_str(q, 0x0040, 0x0007, field_cptr(entry, 6));

    if (field_cptr(entry, 16)[0] != 0) {
        codeItemLen = build_code_sequence_item(entry, codeItem);
        codeSeqLen = dicom_sequence_one_item_implicit(codeSeq,
            0x0040, 0x0008, codeItem, codeItemLen);

        memcpy(q, codeSeq, codeSeqLen);
        q += codeSeqLen;
    }

    q += dicom_elem_implicit_str(q, 0x0040, 0x0009, field_cptr(entry, 5));
    q += dicom_elem_implicit_str(q, 0x0040, 0x0010, field_cptr(entry, 20));
    q += dicom_elem_implicit_str(q, 0x0040, 0x0011, field_cptr(entry, 21));

    p += dicom_sequence_one_item_implicit(p, 0x0040, 0x0100, item, (int)(q - item));

    p += dicom_elem_implicit_str(p, 0x0040, 0x1001, field_cptr(entry, 7));

    return (int)(p - out);
}

static int match_date_range(const char *valDate, const char *queryDate)
{
    char q[128];
    char *dash;

    if (!queryDate || !queryDate[0])
        return 1;

    strncpy(q, queryDate, sizeof(q) - 1);
    q[sizeof(q) - 1] = 0;
    trim_in_place(q);

    if (q[0] == 0 || strcmp(q, "*") == 0)
        return 1;

    dash = strchr(q, '-');

    if (dash) {
        *dash = 0;
        dash++;

        if (q[0] && strcmp(valDate, q) < 0)
            return 0;

        if (dash[0] && strcmp(valDate, dash) > 0)
            return 0;

        return 1;
    }

    return strcmp(valDate, q) == 0;
}

static void send_mwl_results(SOCKET s, int pcid, unsigned short msgID,
    const char *reqModality, const char *reqDate)
{
    FILE *f;
    char line[LINE_SIZE];
    char entry[ENTRY_SIZE];
    int count = 0;

    f = fopen(szCSVFile, "r");

    if (!f) {
        send_c_find_final(s, pcid, msgID);
        return;
    }

    /* skip header */
    fgets(line, sizeof(line), f);

    while (fgets(line, sizeof(line), f)) {
        int dsLen;
        const char *rowModality;
        const char *rowDate;

        parse_csv_line(line, entry);

        if (field_ptr(entry, 0)[0] == 0)
            continue;

        rowModality = field_cptr(entry, 9);
        rowDate = field_cptr(entry, 10);

        if (reqModality && reqModality[0] && strcmp(reqModality, "*") != 0) {
            if (strcmp(rowModality, reqModality) != 0)
                continue;
        }

        if (!match_date_range(rowDate, reqDate))
            continue;

        dsLen = build_mwl_dataset_autoit_style(entry, g_datasetBuf);

        send_c_find_pending(s, pcid, msgID, g_datasetBuf, dsLen);

        count++;
    }

    fclose(f);

    send_c_find_final(s, pcid, msgID);

    {
        char msg[128];
        sprintf(msg, "C-FIND completed, %d pending result(s) sent.", count);
        LogText(msg);
    }
}

/* ============================================================
   DICOM association
   ============================================================ */

static void clear_pcs(void)
{
    int i;

    g_pcCount = 0;
    g_peerMaxPDU = 16384;

    for (i = 0; i < MAX_PC; i++)
        memset(&g_pc[i], 0, sizeof(g_pc[i]));
}

static PC_INFO *find_pc(int pcid)
{
    int i;

    for (i = 0; i < g_pcCount; i++) {
        if (g_pc[i].id == pcid)
            return &g_pc[i];
    }

    return NULL;
}

static int uid_equals(const char *a, const char *b)
{
    return strcmp(a, b) == 0;
}

static void copy_uid_item(char *dst, int dstSize,
    const unsigned char *src, int len)
{
    int n = len;
    int i;

    if (n >= dstSize)
        n = dstSize - 1;

    memcpy(dst, src, n);
    dst[n] = 0;

    for (i = n - 1; i >= 0; i--) {
        if (dst[i] == 0 || dst[i] == ' ')
            dst[i] = 0;
        else
            break;
    }
}

static void parse_presentation_context(const unsigned char *item, int itemLen)
{
    int pos;
    PC_INFO pc;

    if (g_pcCount >= MAX_PC)
return;

    memset(&pc, 0, sizeof(pc));

    if (itemLen < 4)
        return;

    pc.id = item[0];

    pos = 4;

    while (pos + 4 <= itemLen) {
        int type = item[pos];
        int len = rd_be16(item + pos + 2);
        const unsigned char *val = item + pos + 4;

        if (pos + 4 + len > itemLen)
            break;

        if (type == 0x30) {
            copy_uid_item(pc.abstractSyntax, sizeof(pc.abstractSyntax), val, len);
        } else if (type == 0x40) {
            char ts[MAX_UID];

            copy_uid_item(ts, sizeof(ts), val, len);

            if (uid_equals(ts, TS_IMPLICIT_LE))
                pc.hasImplicit = 1;

            if (uid_equals(ts, TS_EXPLICIT_LE))
                pc.hasExplicit = 1;
        }

        pos += 4 + len;
    }

    pc.isVerification = uid_equals(pc.abstractSyntax, SOP_VERIFICATION);
    pc.isMWL = uid_equals(pc.abstractSyntax, SOP_MWL_FIND);

    /*
        Important compatibility choice:
        The AutoIt server always returns Implicit VR LE datasets.
        To avoid corrupt worklists, accept MWL only if Implicit VR LE was proposed.
    */
    if ((pc.isVerification || pc.isMWL) && pc.hasImplicit) {
        pc.accepted = 1;
        strcpy(pc.transferSyntax, TS_IMPLICIT_LE);
    } else {
        pc.accepted = 0;
        strcpy(pc.transferSyntax, TS_IMPLICIT_LE);
    }

    g_pc[g_pcCount++] = pc;
}

static void parse_assoc_rq(const unsigned char *rq, int rqLen)
{
    int pos = 74;

    clear_pcs();

    if (rqLen >= 42) {
        copy_ae_trim(g_aeCalled, rq + 10);
        copy_ae_trim(g_aeCalling, rq + 26);
    }

    while (pos + 4 <= rqLen) {
        int type = rq[pos];
        int len = rd_be16(rq + pos + 2);
        const unsigned char *val = rq + pos + 4;

        if (pos + 4 + len > rqLen)
            break;

        if (type == 0x20) {
            parse_presentation_context(val, len);
        } else if (type == 0x50) {
            int upos = 0;

            while (upos + 4 <= len) {
                int stype = val[upos];
                int slen = rd_be16(val + upos + 2);
                const unsigned char *sval = val + upos + 4;

                if (upos + 4 + slen > len)
                    break;

                if (stype == 0x51 && slen == 4)
                    g_peerMaxPDU = rd_be32(sval);

                upos += 4 + slen;
            }
        }

        pos += 4 + len;
    }
}

static int append_item_uid(unsigned char *p, int type, const char *uid)
{
    int len = (int)strlen(uid);
    int pad = (len & 1) ? len + 1 : len;

    p[0] = (unsigned char)type;
    p[1] = 0;
    wr_be16(p + 2, (unsigned int)pad);
    memcpy(p + 4, uid, len);

    if (pad > len)
        p[4 + len] = 0;

    return 4 + pad;
}

static int append_pc_ac(unsigned char *p, PC_INFO *pc)
{
    unsigned char *start = p;
    unsigned char *body;
    int bodyLen;

    p[0] = 0x21;
    p[1] = 0;
    p += 4;

    body = p;

    p[0] = (unsigned char)pc->id;
    p[1] = 0;
    p[2] = pc->accepted ? 0 : 3;
    p[3] = 0;
    p += 4;

    p += append_item_uid(p, 0x40, pc->transferSyntax);

    bodyLen = (int)(p - body);
    wr_be16(start + 2, (unsigned int)bodyLen);

    return (int)(p - start);
}

static int append_user_info(unsigned char *p)
{
    unsigned char *start = p;
    unsigned char *body;
    int bodyLen;

    p[0] = 0x50;
    p[1] = 0;
    p += 4;

    body = p;

    p[0] = 0x51;
    p[1] = 0;
    wr_be16(p + 2, 4);
    wr_be32(p + 4, 16384);
    p += 8;

    p += append_item_uid(p, 0x52, IMPL_CLASS_UID);
    p += append_item_uid(p, 0x55, IMPL_VERSION_NAME);

    bodyLen = (int)(p - body);
    wr_be16(start + 2, (unsigned int)bodyLen);

    return (int)(p - start);
}

static void send_associate_ac(SOCKET s, const unsigned char *rq, int rqLen)
{
    unsigned char ac[8192];
    unsigned char *p = ac;
    unsigned char *lenPtr;
    int i;
    int pduLen;

    parse_assoc_rq(rq, rqLen);

    p[0] = 0x02;
    p[1] = 0;
    lenPtr = p + 2;
    p += 6;

    p[0] = 0;
    p[1] = 1;
    p[2] = 0;
    p[3] = 0;
    p += 4;

    memcpy(p, rq + 10, 16);
    p += 16;

    memcpy(p, rq + 26, 16);
    p += 16;

    memset(p, 0, 32);
    p += 32;

    p += append_item_uid(p, 0x10, APP_CONTEXT);

    for (i = 0; i < g_pcCount; i++)
        p += append_pc_ac(p, &g_pc[i]);

    p += append_user_info(p);

    pduLen = (int)(p - ac - 6);
    wr_be32(lenPtr, (unsigned int)pduLen);

    send(s, (const char *)ac, (int)(p - ac), 0);

    {
        char msg[256];
        sprintf(msg, "A-ASSOCIATE-AC sent, %d presentation context(s).", g_pcCount);
        LogText(msg);
    }
}

static void send_release_rp(SOCKET s)
{
    unsigned char rel[10];

    rel[0] = 0x06;
    rel[1] = 0;
    wr_be32(rel + 2, 4);
    rel[6] = 0;
    rel[7] = 0;
    rel[8] = 0;
    rel[9] = 0;

    send(s, (const char *)rel, 10, 0);
}

/* ============================================================
   DICOM client handling
   ============================================================ */

static int recv_exact(SOCKET s, unsigned char *buf, int n)
{
    int got = 0;

    while (got < n) {
        int r = recv(s, (char *)buf + got, n - got, 0);

        if (r <= 0)
            return -1;

        got += r;
    }

    return got;
}

static void extract_query_filters(const unsigned char *ds, int dsLen,
    char *modality, int modalitySize,
    char *date, int dateSize)
{
    int pos = 0;

    modality[0] = 0;
    date[0] = 0;

    /*
        Simple implicit-VR extractor for the same filters the AutoIt version uses:
            0008,0060 Modality
            0040,0002 Scheduled Date
    */
    while (pos + 8 <= dsLen) {
        unsigned short g = rd_le16(ds + pos);
        unsigned short e = rd_le16(ds + pos + 2);
        unsigned int l = rd_le32(ds + pos + 4);

        if (pos + 8 + (int)l > dsLen)
            break;

        if (g == 0x0008 && e == 0x0060) {
            int n = (int)l;

            if (n >= modalitySize)
                n = modalitySize - 1;

            memcpy(modality, ds + pos + 8, n);
            modality[n] = 0;
            trim_in_place(modality);
        }

        if (g == 0x0040 && e == 0x0002) {
            int n = (int)l;

            if (n >= dateSize)
                n = dateSize - 1;

            memcpy(date, ds + pos + 8, n);
            date[n] = 0;
            trim_in_place(date);
        }

        pos += 8 + (int)l;
    }
}

static void process_pdata(SOCKET s, const unsigned char *payload, int len)
{
    int pos = 0;

    static unsigned char cmdAccum[65536];
    static int cmdLen = 0;

    static unsigned char dsAccum[65536];
    static int dsLen = 0;

    static int pendingFind = 0;
    static int pendingPCID = 1;
    static unsigned short pendingMsgID = 1;

    while (pos + 6 <= len) {
        unsigned int pdvLen = rd_be32(payload + pos);
        int pcid;
        int flags;
        const unsigned char *frag;
        int fragLen;

        if (pdvLen < 2)
            return;

        if (pos + 4 + (int)pdvLen > len)
            return;

        pcid = payload[pos + 4];
        flags = payload[pos + 5];
        frag = payload + pos + 6;
        fragLen = (int)pdvLen - 2;

        if (flags & 0x01) {
            if (cmdLen + fragLen < (int)sizeof(cmdAccum)) {
                memcpy(cmdAccum + cmdLen, frag, fragLen);
                cmdLen += fragLen;
            }

            if (flags & 0x02) {
                unsigned short cmdField;
                unsigned short msgID;
                PC_INFO *pc;

                cmdField = cmd_get_us(cmdAccum, cmdLen, 0x0000, 0x0100);
                msgID    = cmd_get_us(cmdAccum, cmdLen, 0x0000, 0x0110);

                pc = find_pc(pcid);

                if (cmdField == 0x0030) {
                    LogText("C-ECHO-RQ received.");
                    send_c_echo_rsp(s, pcid, msgID);
                    pendingFind = 0;
                    dsLen = 0;
                } else if (cmdField == 0x0020) {
                    LogText("C-FIND-RQ command received.");
                    pendingFind = 1;
                    pendingPCID = pcid;
                    pendingMsgID = msgID;
                    dsLen = 0;

                    if (!pc || !pc->accepted || !pc->isMWL) {
                        send_c_find_final(s, pcid, msgID);
                        pendingFind = 0;
                    }
                } else {
                    char msg[128];
                    sprintf(msg, "Unsupported command field 0x%04X", cmdField);
                    LogText(msg);
                    pendingFind = 0;
                    dsLen = 0;
                }

                cmdLen = 0;
            }
        } else {
            if (dsLen + fragLen < (int)sizeof(dsAccum)) {
                memcpy(dsAccum + dsLen, frag, fragLen);
                dsLen += fragLen;
            }

            if (flags & 0x02) {
                if (pendingFind) {
                    char reqModality[128];
                    char reqDate[128];

                    extract_query_filters(dsAccum, dsLen,
                        reqModality, sizeof(reqModality),
                        reqDate, sizeof(reqDate));

                    if (reqModality[0] || reqDate[0]) {
                        char msg[256];
                        sprintf(msg, "MWL query filter Modality=[%s] Date=[%s]",
                            reqModality[0] ? reqModality : "*",
                            reqDate[0] ? reqDate : "*");
                        LogText(msg);
                    }

                    send_mwl_results(s, pendingPCID, pendingMsgID, reqModality, reqDate);
                    pendingFind = 0;
                    dsLen = 0;
                }
            }
        }

        pos += 4 + (int)pdvLen;
    }

    /*
        AutoIt often responds immediately after the C-FIND command if no dataset
        query is sent separately. This avoids hanging SCUs that send command-only.
    */
    if (pendingFind && dsLen == 0) {
        send_mwl_results(s, pendingPCID, pendingMsgID, "", "");
        pendingFind = 0;
    }
}

static void dicom_handle_client(SOCKET s)
{
    unsigned char hdr[6];

    set_blocking(s);

    for (;;) {
        int pduType;
        unsigned int pduLen;

        if (recv_exact(s, hdr, 6) < 0)
            return;

        pduType = hdr[0];
        pduLen = rd_be32(hdr + 2);

        if (pduLen > DICOM_RECV_BUF_SIZE)
            return;

        if (recv_exact(s, g_dicomRecvBuf, (int)pduLen) < 0)
            return;

        if (pduType == 0x01) {
            unsigned char fullRq[1048576];

            if (pduLen + 6 <= sizeof(fullRq)) {
                fullRq[0] = hdr[0];
                fullRq[1] = hdr[1];
                memcpy(fullRq + 2, hdr + 2, 4);
                memcpy(fullRq + 6, g_dicomRecvBuf, pduLen);

                send_associate_ac(s, fullRq, (int)pduLen + 6);
            }
        } else if (pduType == 0x04) {
            process_pdata(s, g_dicomRecvBuf, (int)pduLen);
        } else if (pduType == 0x05) {
            send_release_rp(s);
            return;
        } else if (pduType == 0x07) {
            return;
        } else {
            return;
        }
    }
}

/* ============================================================
   Telnet server
   ============================================================ */

static int start_telnet_server(void)
{
    struct sockaddr_in sin;

    g_listenSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

    if (g_listenSocket == INVALID_SOCKET) {
        LogText("ERROR: telnet socket() failed");
        return 0;
    }

    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((u_short)g_TelnetPort);
    sin.sin_addr.s_addr = INADDR_ANY;

    if (bind(g_listenSocket, (struct sockaddr *)&sin, sizeof(sin)) == SOCKET_ERROR ||
        listen(g_listenSocket, SOMAXCONN) == SOCKET_ERROR) {
        char msg[160];

        sprintf(msg, "ERROR: Failed to bind/listen telnet port %u", g_TelnetPort);
        LogText(msg);

        closesocket(g_listenSocket);
        g_listenSocket = INVALID_SOCKET;
        return 0;
    }

    set_nonblocking(g_listenSocket);

    {
        char msg[160];
        sprintf(msg, "Telnet listening on port %u", g_TelnetPort);
        LogText(msg);
    }

    return 1;
}

static int find_free_slot(void)
{
    int i;

    for (i = 0; i < MAX_CLIENTS; i++) {
        if (g_clients[i] == 0)
            return i;
    }

    return -1;
}

static void add_client(SOCKET s)
{
    int idx = find_free_slot();

    if (idx < 0) {
        closesocket(s);
        return;
    }

    set_nonblocking(s);

    g_clients[idx] = s;
    g_clientBufLen[idx] = 0;
    memset(g_clientBuffers[idx], 0, CLIENT_BUF_SIZE);
    g_clientLastTick[idx] = GetTickCount();
    g_clientTimeout[idx] = g_TelnetTimeout * 1000;

    LogText("Telnet client connected.");
    send_text(s, "Connected to RIS Telnet Server.\r\n");
}

static void remove_client(int idx)
{
    if (g_clients[idx]) {
        closesocket(g_clients[idx]);
    }

    g_clients[idx] = 0;
    g_clientBufLen[idx] = 0;
    memset(g_clientBuffers[idx], 0, CLIENT_BUF_SIZE);

    LogText("Telnet client disconnected.");
}

static void accept_new_clients(void)
{
    for (;;) {
        SOCKET s = accept(g_listenSocket, NULL, NULL);

        if (s == INVALID_SOCKET)
            return;

        add_client(s);
    }
}

static void process_disp(int idx)
{
    FILE *f = fopen(szCSVFile, "r");

    if (f) {
        char buf[4096];

        while (fgets(buf, sizeof(buf), f))
            send_text(g_clients[idx], buf);

        fclose(f);
    }
}

static void process_client_line(int idx, char *line)
{
    char entry[ENTRY_SIZE];
    char lineOut[LINE_SIZE];
    int found;

    trim_in_place(line);

    if (line[0] == 0)
        return;

    if (ci_ncmp(line, "DISP", 4) == 0) {
        process_disp(idx);
        return;
    }

    parse_csv_line(line, entry);

    if (field_ptr(entry, 0)[0] == 0) {
        send_text(g_clients[idx], "INVALID LINE\r\n");
        return;
    }

    build_csv_line(entry, lineOut);
    found = update_csv_by_patient(entry, lineOut);

    if (found)
        send_text(g_clients[idx], "UPDATED\r\n");
    else
        send_text(g_clients[idx], "INSERTED\r\n");
}

static void append_received_bytes(int idx, const char *bytes, int n)
{
    int i;
    char *buf = g_clientBuffers[idx];
    int cur = g_clientBufLen[idx];

    for (i = 0; i < n; i++) {
        char c = bytes[i];

        if (c == '\r')
            continue;

        if (c == '\n') {
            buf[cur] = 0;
            process_client_line(idx, buf);
            cur = 0;
            memset(buf, 0, CLIENT_BUF_SIZE);
            continue;
        }

        if (cur < CLIENT_BUF_SIZE - 1)
            buf[cur++] = c;
    }

    g_clientBufLen[idx] = cur;
}

static void poll_client(int idx)
{
    SOCKET s = g_clients[idx];
    int n;

    if (!s)
        return;

    n = recv(s, g_recvBuf, RECV_SIZE, 0);

    if (n > 0) {
        g_clientLastTick[idx] = GetTickCount();
        append_received_bytes(idx, g_recvBuf, n);
    } else if (n == 0) {
        remove_client(idx);
        return;
    } else if (WSAGetLastError() != WSAEWOULDBLOCK) {
        remove_client(idx);
        return;
    }

    if ((GetTickCount() - g_clientLastTick[idx]) >= g_clientTimeout[idx]) {
        send_text(s, "TIMEOUT\r\n");
        remove_client(idx);
    }
}

/* ============================================================
   DICOM listener
   ============================================================ */

static int start_dicom_server(void)
{
    struct sockaddr_in sin;

    g_dicomListenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);

    if (g_dicomListenSock == INVALID_SOCKET) {
        LogText("ERROR: DICOM socket() failed");
        return 0;
    }

    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((u_short)g_DicomPort);
    sin.sin_addr.s_addr = INADDR_ANY;

    if (bind(g_dicomListenSock, (struct sockaddr *)&sin, sizeof(sin)) == SOCKET_ERROR ||
        listen(g_dicomListenSock, SOMAXCONN) == SOCKET_ERROR) {
        char msg[160];

        sprintf(msg, "ERROR: Failed to bind/listen DICOM port %u", g_DicomPort);
        LogText(msg);

        closesocket(g_dicomListenSock);
        g_dicomListenSock = INVALID_SOCKET;
        return 0;
    }

    set_nonblocking(g_dicomListenSock);

    {
        char msg[160];
        sprintf(msg, "DICOM listening on port %u", g_DicomPort);
        LogText(msg);
    }

    return 1;
}

static void poll_dicom_server(void)
{
    SOCKET s = accept(g_dicomListenSock, NULL, NULL);

    if (s == INVALID_SOCKET)
        return;

    LogText("DICOM client connected.");

    dicom_handle_client(s);

    closesocket(s);

    LogText("DICOM client disconnected.");
}

/* ============================================================
   Server start / stop / loop
   ============================================================ */

static void ServerStart(void)
{
    if (g_bRunning)
        return;

    if (!start_telnet_server())
        return;

    if (!start_dicom_server()) {
        if (g_listenSocket != INVALID_SOCKET) {
            closesocket(g_listenSocket);
            g_listenSocket = INVALID_SOCKET;
        }

        return;
    }

    g_bRunning = 1;
    LogText("Server STARTED");

    UpdateTrayMenuText();

    if (g_hStatusLabel)
        SetWindowText(g_hStatusLabel, "Server status: Running");
}

static void ServerStop(void)
{
    int i;

    if (!g_bRunning)
        return;

    for (i = 0; i < MAX_CLIENTS; i++)
        remove_client(i);

    if (g_listenSocket != INVALID_SOCKET) {
        closesocket(g_listenSocket);
        g_listenSocket = INVALID_SOCKET;
    }

    if (g_dicomListenSock != INVALID_SOCKET) {
        closesocket(g_dicomListenSock);
        g_dicomListenSock = INVALID_SOCKET;
    }

    g_bRunning = 0;
    LogText("Server STOPPED");

    UpdateTrayMenuText();

    if (g_hStatusLabel)
        SetWindowText(g_hStatusLabel, "Server status: Stopped");
}

static void server_loop(void)
{
    int i;

    if (!g_bRunning)
        return;

    accept_new_clients();
    poll_dicom_server();

    for (i = 0; i < MAX_CLIENTS; i++)
        poll_client(i);
}

/* ============================================================
   Tray / Settings
   ============================================================ */

static void UpdateTrayMenuText(void)
{
    if (!g_hMenu)
        return;

    ModifyMenu(g_hMenu, ID_TRAY_TOGGLE,
        MF_BYCOMMAND | MF_STRING,
        ID_TRAY_TOGGLE,
        g_bRunning ? szMenuStop : szMenuStart);
}

static void ShowTrayMenu(HWND hWnd)
{
    POINT pt;

    if (!g_hMenu)
        return;

    UpdateTrayMenuText();

    GetCursorPos(&pt);
    SetForegroundWindow(hWnd);

    TrackPopupMenu(g_hMenu,
        TPM_RIGHTBUTTON | TPM_BOTTOMALIGN,
        pt.x, pt.y,
        0,
        hWnd,
        NULL);

    PostMessage(hWnd, WM_NULL, 0, 0);
}

static void SaveSettingsFromDialog(HWND hWnd)
{
    char buf[128];
    unsigned int newTelnetPort;
    unsigned int newDicomPort;
    unsigned int newTimeout;

    GetDlgItemText(hWnd, ID_EDIT_AET, buf, sizeof(buf));

    if (buf[0] == 0)
        strcpy(buf, "AUTOIT_SCP");

    set_ae_title(buf);
    WritePrivateProfileString("Server", "AETitle", buf, szIniFile);

    GetDlgItemText(hWnd, ID_EDIT_TELNETPORT, buf, sizeof(buf));
    newTelnetPort = (unsigned int)atoi(buf);
    if (newTelnetPort == 0) newTelnetPort = 23;
    g_TelnetPort = newTelnetPort;
    SaveConfigValue("Server", "TelnetPort", g_TelnetPort);

    GetDlgItemText(hWnd, ID_EDIT_DICOMPORT, buf, sizeof(buf));
    newDicomPort = (unsigned int)atoi(buf);
    if (newDicomPort == 0) newDicomPort = 104;
    g_DicomPort = newDicomPort;
    SaveConfigValue("Server", "DicomPort", g_DicomPort);

    GetDlgItemText(hWnd, ID_EDIT_TIMEOUT, buf, sizeof(buf));
    newTimeout = (unsigned int)atoi(buf);
    if (newTimeout == 0) newTimeout = 10;
    g_TelnetTimeout = newTimeout;
    SaveConfigValue("Server", "TelnetTimeout", g_TelnetTimeout);

    g_DebugLog =
        (SendMessage(GetDlgItem(hWnd, ID_CHK_DEBUG), BM_GETCHECK, 0, 0) == BST_CHECKED)
        ? 1 : 0;

    WritePrivateProfileString("Server", "DebugLog", g_DebugLog ? "1" : "0", szIniFile);

    if (g_hStatusLabel) {
        SetWindowText(g_hStatusLabel,
            g_bRunning ?
            "Server status: Running. Restart required for port changes." :
            "Server status: Stopped. Settings saved.");
    }
}

static LRESULT CALLBACK SettingsProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
    char buf[128];

    switch (uMsg) {
    case WM_CREATE:
    {
        HWND h;

        CreateWindowEx(0, "STATIC", "AE Title:",
            WS_CHILD | WS_VISIBLE,
            12, 18, 120, 20,
            hWnd, NULL, g_hInstance, NULL);

        memset(buf, 0, sizeof(buf));
        memcpy(buf, g_aeCalled, 16);
        buf[16] = 0;
        trim_in_place(buf);

        CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", buf,
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            145, 14, 180, 24,
            hWnd, (HMENU)ID_EDIT_AET, g_hInstance, NULL);

        CreateWindowEx(0, "STATIC", "Telnet Port:",
            WS_CHILD | WS_VISIBLE,
            12, 52, 120, 20,
            hWnd, NULL, g_hInstance, NULL);

        sprintf(buf, "%u", g_TelnetPort);

        CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", buf,
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_NUMBER,
            145, 48, 90, 24,
            hWnd, (HMENU)ID_EDIT_TELNETPORT, g_hInstance, NULL);

        CreateWindowEx(0, "STATIC", "DICOM Port:",
            WS_CHILD | WS_VISIBLE,
            12, 86, 120, 20,
            hWnd, NULL, g_hInstance, NULL);

        sprintf(buf, "%u", g_DicomPort);

        CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", buf,
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_NUMBER,
            145, 82, 90, 24,
            hWnd, (HMENU)ID_EDIT_DICOMPORT, g_hInstance, NULL);

        CreateWindowEx(0, "STATIC", "Timeout Seconds:",
            WS_CHILD | WS_VISIBLE,
            12, 120, 120, 20,
            hWnd, NULL, g_hInstance, NULL);

        sprintf(buf, "%u", g_TelnetTimeout);

        CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", buf,
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_NUMBER,
            145, 116, 90, 24,
            hWnd, (HMENU)ID_EDIT_TIMEOUT, g_hInstance, NULL);

        h = CreateWindowEx(0, "BUTTON", "Debug Log",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
            145, 150, 120, 24,
            hWnd, (HMENU)ID_CHK_DEBUG, g_hInstance, NULL);

        SendMessage(h, BM_SETCHECK, g_DebugLog ? BST_CHECKED : BST_UNCHECKED, 0);

        CreateWindowEx(0, "BUTTON",
            g_bRunning ? szMenuStop : szMenuStart,
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            12, 190, 110, 28,
            hWnd, (HMENU)ID_BTN_STARTSTOP, g_hInstance, NULL);

        CreateWindowEx(0, "BUTTON", "Save",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            135, 190, 90, 28,
            hWnd, (HMENU)ID_BTN_SAVE, g_hInstance, NULL);

        CreateWindowEx(0, "BUTTON", "Close",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            235, 190, 90, 28,
            hWnd, (HMENU)ID_BTN_CLOSE, g_hInstance, NULL);

        g_hStatusLabel = CreateWindowEx(0, "STATIC",
            g_bRunning ? "Server status: Running" : "Server status: Stopped",
            WS_CHILD | WS_VISIBLE | SS_SUNKEN,
            12, 232, 313, 22,
            hWnd, (HMENU)ID_STATUS_LABEL, g_hInstance, NULL);

        return 0;
    }

    case WM_COMMAND:
    {
        WORD cmd = LOWORD(wParam);

        if (cmd == ID_BTN_CLOSE) {
            DestroyWindow(hWnd);
            g_hSettingsWnd = 0;
            return 0;
        }

        if (cmd == ID_BTN_SAVE) {
            SaveSettingsFromDialog(hWnd);
            return 0;
        }

        if (cmd == ID_BTN_STARTSTOP) {
            if (g_bRunning) {
                ServerStop();
                SetDlgItemText(hWnd, ID_BTN_STARTSTOP, szMenuStart);
            } else {
                ServerStart();
                SetDlgItemText(hWnd, ID_BTN_STARTSTOP, szMenuStop);
            }

            if (g_hStatusLabel) {
                SetWindowText(g_hStatusLabel,
                    g_bRunning ? "Server status: Running" : "Server status: Stopped");
            }

            UpdateTrayMenuText();
            return 0;
        }

        return 0;
    }

    case WM_CLOSE:
        DestroyWindow(hWnd);
        g_hSettingsWnd = 0;
        return 0;

    case WM_DESTROY:
        if (hWnd == g_hSettingsWnd)
            g_hSettingsWnd = 0;

        return 0;
    }

    return DefWindowProc(hWnd, uMsg, wParam, lParam);
}

static void CreateSettingsClass(void)
{
    WNDCLASSEX wc;

    memset(&wc, 0, sizeof(wc));
    wc.cbSize        = sizeof(WNDCLASSEX);
    wc.lpfnWndProc   = SettingsProc;
    wc.hInstance     = g_hInstance;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = szSettingsClass;

    RegisterClassEx(&wc);
}

static void ShowSettings(void)
{
    if (g_hSettingsWnd && IsWindow(g_hSettingsWnd)) {
        ShowWindow(g_hSettingsWnd, SW_SHOW);
        SetForegroundWindow(g_hSettingsWnd);
        return;
    }

    g_hSettingsWnd = CreateWindowEx(
        WS_EX_DLGMODALFRAME,
        szSettingsClass,
        "WORKLIST Server Settings",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT, CW_USEDEFAULT,
        360, 310,
        g_hMainWnd,
        NULL,
        g_hInstance,
        NULL);

    if (g_hSettingsWnd) {
        ShowWindow(g_hSettingsWnd, SW_SHOW);
        UpdateWindow(g_hSettingsWnd);
    }
}

/* ============================================================
   Main tray window
   ============================================================ */

static LRESULT CALLBACK WndProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam)
{
    if (uMsg == WM_TRAYICON) {
        if (lParam == WM_RBUTTONUP ||
            lParam == WM_LBUTTONUP ||
            lParam == WM_CONTEXTMENU) {
            ShowTrayMenu(hWnd);
        }

        return 0;
    }

    if (uMsg == WM_COMMAND) {
        WORD cmd = LOWORD(wParam);

        if (cmd == ID_TRAY_TOGGLE) {
            if (g_bRunning)
                ServerStop();
            else
                ServerStart();

            UpdateTrayMenuText();
            return 0;
        }

        if (cmd == ID_TRAY_SETTINGS) {
            ShowSettings();
            return 0;
        }

        if (cmd == ID_TRAY_SHOW) {
            ShowConsoleWindow();
            return 0;
        }

        if (cmd == ID_TRAY_EXIT) {
            ServerStop();
            Shell_NotifyIcon(NIM_DELETE, &g_nid);
            PostQuitMessage(0);
            return 0;
        }

        return 0;
    }

    if (uMsg == WM_DESTROY) {
        ServerStop();
        Shell_NotifyIcon(NIM_DELETE, &g_nid);
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProc(hWnd, uMsg, wParam, lParam);
}

static void create_tray(void)
{
    WNDCLASSEX wc;

    g_hInstance = GetModuleHandle(NULL);

    memset(&wc, 0, sizeof(wc));
    wc.cbSize        = sizeof(WNDCLASSEX);
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = g_hInstance;
    wc.hIcon         = LoadIcon(NULL, IDI_APPLICATION);
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = szWndClass;

    RegisterClassEx(&wc);
    CreateSettingsClass();

    g_hMainWnd = CreateWindowEx(
        0,
        szWndClass,
        "WORKLIST-SERVER01",
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT,
        300, 200,
        NULL,
        NULL,
        g_hInstance,
        NULL);

    g_hMenu = CreatePopupMenu();

    AppendMenu(g_hMenu, MF_STRING, ID_TRAY_TOGGLE,
        g_bRunning ? szMenuStop : szMenuStart);

    AppendMenu(g_hMenu, MF_STRING, ID_TRAY_SETTINGS,
        "Settings");

    AppendMenu(g_hMenu, MF_STRING, ID_TRAY_SHOW,
        "Show Console Window");

    AppendMenu(g_hMenu, MF_SEPARATOR, 0, NULL);

    AppendMenu(g_hMenu, MF_STRING, ID_TRAY_EXIT,
        "Exit");

    memset(&g_nid, 0, sizeof(g_nid));
    g_nid.cbSize = sizeof(g_nid);
    g_nid.hWnd = g_hMainWnd;
    g_nid.uID = 1;
    g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAYICON;
    g_nid.hIcon = LoadIcon(NULL, IDI_APPLICATION);

    lstrcpyn(g_nid.szTip, szTrayTip, sizeof(g_nid.szTip));

    Shell_NotifyIcon(NIM_ADD, &g_nid);
}

/* ============================================================
   Main
   ============================================================ */

int main(void)
{
    WSADATA wsa;
    MSG msg;
    int i;

    for (i = 0; i < MAX_CLIENTS; i++) {
        g_clients[i] = 0;
        g_clientBufLen[i] = 0;
        g_clientLastTick[i] = 0;
        g_clientTimeout[i] = DEFAULT_TIMEOUT_MS;
    }

    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        return 1;
    }

    LoadConfig();
    ensure_csv();
    create_tray();

    ServerStart();

    for (;;) {
        while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
            if (msg.message == WM_QUIT) {
                ServerStop();
                WSACleanup();
                return 0;
            }

            TranslateMessage(&msg);
            DispatchMessage(&msg);
        }

        server_loop();
        Sleep(10);
    }

    WSACleanup();
    return 0;
}