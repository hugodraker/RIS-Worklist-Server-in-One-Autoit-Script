/* worklist-server01.c
 * RIS Telnet + DICOM MWL SCP - TCC compatible
 * Compile: tcc -o worklist-server01.exe worklist-server01.c -lws2_32 -lkernel32 -luser32 -lshell32
 */

#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0501
#include <windows.h>
#include <winsock2.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>

#define MAX_CLIENTS         16
#define RECV_SIZE           2048
#define CLIENT_BUF_SIZE     4096
#define FIELD_COUNT         22
#define FIELD_SIZE          128
#define ENTRY_SIZE          (FIELD_COUNT * FIELD_SIZE)
#define LINE_SIZE           8192
#define APPEND_DELAY_MS     2000
#define DEFAULT_TIMEOUT_MS  10000

#define WM_TRAYICON         (WM_USER + 1)
#define ID_TRAY_TOGGLE      1000
#define ID_TRAY_SHOW        1001
#define ID_TRAY_EXIT        1002

/* ===================== Globals ===================== */
static unsigned int g_TelnetPort      = 23;
static unsigned int g_DicomPort       = 104;
static unsigned int g_TelnetTimeout   = 10;
static unsigned int g_DebugLog        = 1;
static int          g_bRunning        = 0;
static SOCKET       g_listenSocket    = INVALID_SOCKET;
static SOCKET       g_dicomListenSock = INVALID_SOCKET;

static HINSTANCE    g_hInstance       = 0;
static HWND         g_hMainWnd        = 0;
static HMENU        g_hMenu           = 0;
static NOTIFYICONDATA g_nid;

static char g_aeCalled[17] = "AUTOIT_SCP      ";

/* Client state */
static SOCKET g_clients[MAX_CLIENTS];
static DWORD  g_clientLastTick[MAX_CLIENTS];
static DWORD  g_clientTimeout[MAX_CLIENTS];
static int    g_clientBufLen[MAX_CLIENTS];
static char   g_clientBuffers[MAX_CLIENTS][CLIENT_BUF_SIZE];
static int    g_pendingFlag[MAX_CLIENTS];
static DWORD  g_pendingSince[MAX_CLIENTS];
static char   g_pendingEntries[MAX_CLIENTS][ENTRY_SIZE];

static char g_recvBuf[RECV_SIZE];
static char g_fileLine[LINE_SIZE];
static char g_lineOut[LINE_SIZE];
static char g_tmpEntry[ENTRY_SIZE];
static char g_dispParam[256];
static unsigned char g_dicomRecvBuf[16384];
static unsigned char g_dicomSendBuf[16384];
static unsigned char g_mwlDsBuf[8192];
static unsigned char g_spsBuf[2048];
static char g_iniBuf[256];

static const char *szIniFile          = "worklist-server01.ini";
static const char *szCSVFile          = "patients.csv";
static const char *szCSVTempFile      = "patients.tmp";
static const char *szWndClass         = "WorklistTrayClass";
static const char *szTrayTip          = "RIS Telnet + DICOM MWL SCP";
static const char *szMenuStart        = "Start Server";
static const char *szMenuStop         = "Stop Server";

static const char *szEchoSOPClass     = "1.2.840.10008.1.1";
static const char *szMwlSOPClass      = "1.2.840.10008.5.1.4.31";

static const char *szCSVHeader =
    "PatientID,PatientName,Accession,BirthDate,Sex,"
    "SPSID,SPSDescription,RequestedProcedureID,"
    "StationAET,Modality,ScheduledDate,ScheduledTime,"
    "RequestedProcDesc,StudyInstanceUID,"
    "ReferringPhysicianName,Status,ProcedureCode,"
    "ProcedureCodeDesc,CodingScheme,"
    "PerformingPhysician,StationName,Location";

/* DICOM A-ASSOCIATE-AC static blobs */
static const unsigned char pdu1_prefix[10] = {
    0x02,0x00,0x00,0x00,0x00,0xD4,0x00,0x01,0x00,0x00
};
static const char pdu1_ae_calling[16] = "ANY-SCU         ";

static const unsigned char pdu_appctx[25] = {
    0x10,0x00,0x00,0x15,
    '1','.','2','.','8','4','0','.','1','0','0','0','8','.','3','.','1','.','1','.','1'
};

static const unsigned char pdu2_static[58] = {
    0x21,0x00,0x00,0x19,0x01,0x00,0x00,0x00,0x40,0x00,0x00,0x11,
    '1','.','2','.','8','4','0','.','1','0','0','0','8','.','1','.','2',
    0x21,0x00,0x00,0x19,0x03,0x00,0x00,0x00,0x40,0x00,0x00,0x11,
    '1','.','2','.','8','4','0','.','1','0','0','0','8','.','1','.','2'
};

static const unsigned char pdu3_static[61] = {
    0x50,0x00,0x00,0x39,0x51,0x00,0x00,0x04,0x00,0x00,0x40,0x00,
    0x52,0x00,0x00,0x1E,
    '1','.','2','.','8','2','6','.','0','.','1','.','3','6','8','0','0','4','3','.','2','.','1','3','9','6','.','9','9','9',
    0x55,0x00,0x00,0x0B,
    'A','u','t','o','i','t','P','A','C','S','1'
};

/* Forward decls */
static void ServerStart(void);
static void ServerStop(void);

/* ===================== INI / Config ===================== */

static void set_ae_title(const char *src) {
    int i;
    for (i = 0; i < 16; i++) g_aeCalled[i] = ' ';
    g_aeCalled[16] = 0;
    for (i = 0; i < 16 && src[i]; i++) g_aeCalled[i] = src[i];
}

static void LoadConfig(void) {
    GetPrivateProfileString("Server", "AETitle", "AUTOIT_SCP",
        g_iniBuf, sizeof(g_iniBuf), szIniFile);
    set_ae_title(g_iniBuf);

    g_DicomPort     = GetPrivateProfileInt("Server", "DicomPort",     104, szIniFile);
    g_TelnetPort    = GetPrivateProfileInt("Server", "TelnetPort",     23, szIniFile);
    g_TelnetTimeout = GetPrivateProfileInt("Server", "TelnetTimeout",  10, szIniFile);
    g_DebugLog      = GetPrivateProfileInt("Server", "DebugLog",        1, szIniFile);

    /* write defaults back so first run creates the file */
    WritePrivateProfileString("Server", "AETitle",       g_aeCalled, szIniFile);
    WritePrivateProfileString("Server", "DicomPort",     "104",      szIniFile);
    WritePrivateProfileString("Server", "TelnetPort",    "23",       szIniFile);
    WritePrivateProfileString("Server", "TelnetTimeout", "10",       szIniFile);
    WritePrivateProfileString("Server", "DebugLog",      "1",        szIniFile);

    GetPrivateProfileString("Lists", "Modalities",          "CR;DX;CT;MR;US;OT",   g_iniBuf, sizeof(g_iniBuf), szIniFile);
    WritePrivateProfileString("Lists","Modalities",          g_iniBuf, szIniFile);
    GetPrivateProfileString("Lists", "AETitles",            "AET1;AET2",           g_iniBuf, sizeof(g_iniBuf), szIniFile);
    WritePrivateProfileString("Lists","AETitles",            g_iniBuf, szIniFile);
    GetPrivateProfileString("Lists", "ReferringPhysicians", "Dr. Smith;Dr. Brown", g_iniBuf, sizeof(g_iniBuf), szIniFile);
    WritePrivateProfileString("Lists","ReferringPhysicians", g_iniBuf, szIniFile);
    GetPrivateProfileString("Lists", "Procedures",          "Chest X-Ray;CT Head", g_iniBuf, sizeof(g_iniBuf), szIniFile);
    WritePrivateProfileString("Lists","Procedures",          g_iniBuf, szIniFile);
    GetPrivateProfileString("Lists", "ProcedureCodes",      "PCODE01;PCODE02",     g_iniBuf, sizeof(g_iniBuf), szIniFile);
    WritePrivateProfileString("Lists","ProcedureCodes",      g_iniBuf, szIniFile);
}

/* ===================== Helpers ===================== */

static void send_text(SOCKET s, const char *t) {
    int n = (int)strlen(t);
    if (n > 0) send(s, t, n, 0);
}

static char *field_ptr(char *entry, int idx) {
    return entry + idx * FIELD_SIZE;
}

static void trim_in_place(char *s) {
    int i, n;
    char *p = s;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    n = (int)strlen(s);
    for (i = n - 1; i >= 0; i--) {
        if (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n')
            s[i] = 0;
        else
            break;
    }
}

static int starts_disp(const char *line) {
    return (toupper(line[0]) == 'D' &&
            toupper(line[1]) == 'I' &&
            toupper(line[2]) == 'S' &&
            toupper(line[3]) == 'P');
}

static int stri_equals(const char *a, const char *b) {
    while (*a && *b) {
        if (toupper(*a) != toupper(*b)) return 0;
        a++; b++;
    }
    return *a == 0 && *b == 0;
}

static int is_eight_digits(const char *s) {
    int i;
    for (i = 0; i < 8; i++) {
        if (s[i] < '0' || s[i] > '9') return 0;
    }
    return s[8] == 0;
}

static int is_sex_valid(const char *s) {
    if (s[0] == 0 || s[1] != 0) return 0;
    return s[0] == 'M' || s[0] == 'F' || s[0] == 'O';
}

static int is_status_valid(const char *s) {
    if (s[0] == 0 || s[1] != 0) return 0;
    return s[0] >= '1' && s[0] <= '4';
}

static int is_time_valid_or_empty(const char *s) {
    if (s[0] == 0) return 1;
    return (isdigit((unsigned char)s[0]) && isdigit((unsigned char)s[1]) &&
            s[2] == ':' &&
            isdigit((unsigned char)s[3]) && isdigit((unsigned char)s[4]) &&
            s[5] == 0);
}

static void strip_colons(const char *src, char *dst) {
    while (*src) {
        if (*src != ':') *dst++ = *src;
        src++;
    }
    *dst = 0;
}

/* ===================== CSV Parse / Build ===================== */

static void parse_csv_line(const char *line, char *entry) {
    int fi = 0, ci = 0, quote = 0;
    int i;
    memset(entry, 0, ENTRY_SIZE);
    for (i = 0; line[i]; i++) {
        char c = line[i];
        if (c == '\r' || c == '\n') break;
        if (c == '~') c = '"';
        if (c == '"') { quote = !quote; continue; }
        if (c == ',' && !quote) {
            field_ptr(entry, fi)[ci] = 0;
            fi++;
            if (fi >= FIELD_COUNT) break;
            ci = 0;
            continue;
        }
        if (ci < FIELD_SIZE - 1) {
            field_ptr(entry, fi)[ci++] = c;
        }
    }
    if (fi < FIELD_COUNT) field_ptr(entry, fi)[ci] = 0;
    for (i = 0; i < FIELD_COUNT; i++) trim_in_place(field_ptr(entry, i));
}

static int validate_entry(char *entry) {
    if (field_ptr(entry, 0)[0] == 0) return 0;
    if (field_ptr(entry, 1)[0] == 0) return 0;
    if (!is_eight_digits(field_ptr(entry, 3))) return 0;
    if (!is_sex_valid(field_ptr(entry, 4))) return 0;
    if (field_ptr(entry, 6)[0] == 0) return 0;
    if (field_ptr(entry, 9)[0] == 0) return 0;
    if (!is_eight_digits(field_ptr(entry, 10))) return 0;
    if (!is_status_valid(field_ptr(entry, 15))) return 0;
    if (!is_time_valid_or_empty(field_ptr(entry, 11))) return 0;
    return 1;
}

static int needs_quote(const char *f) {
    while (*f) {
        if (*f == ',' || *f == '"') return 1;
        f++;
    }
    return 0;
}

static void build_csv_line(char *entry, char *out) {
    int i;
    char *p = out;
    for (i = 0; i < FIELD_COUNT; i++) {
        const char *f = field_ptr(entry, i);
        int q = needs_quote(f);
        if (i > 0) *p++ = ',';
        if (q) *p++ = '"';
        while (*f) {
            if (q && *f == '"') { *p++ = '"'; *p++ = '"'; }
            else *p++ = *f;
            f++;
        }
        if (q) *p++ = '"';
    }
    *p = 0;
}

/* ===================== CSV File ===================== */

static void ensure_csv(void) {
    FILE *f = fopen(szCSVFile, "r");
    if (f) { fclose(f); return; }
    f = fopen(szCSVFile, "w");
    if (!f) return;
    fprintf(f, "%s\r\n", szCSVHeader);
    fclose(f);
}

static int first_field_equals(const char *line, const char *pid) {
    while (*line && *line != ',' && *line != '\r' && *line != '\n') {
        if (*pid == 0 || *line != *pid) return 0;
        line++; pid++;
    }
    return *pid == 0 && (*line == ',' || *line == 0 || *line == '\r' || *line == '\n');
}

static int update_csv_by_patient(char *entry, const char *lineOut) {
    FILE *in, *out;
    int found = 0;
    const char *pid;

    ensure_csv();
    pid = field_ptr(entry, 0);

    in = fopen(szCSVFile, "r");
    out = fopen(szCSVTempFile, "w");
    if (!out) {
        if (in) fclose(in);
        return 0;
    }

    if (in && fgets(g_fileLine, LINE_SIZE, in)) {
        fputs(g_fileLine, out);
    } else {
        fprintf(out, "%s\r\n", szCSVHeader);
    }

    if (in) {
        while (fgets(g_fileLine, LINE_SIZE, in)) {
            if (!found && first_field_equals(g_fileLine, pid)) {
                fprintf(out, "%s\r\n", lineOut);
                found = 1;
            } else {
                fputs(g_fileLine, out);
            }
        }
    }
    if (!found) fprintf(out, "%s\r\n", lineOut);

    if (in) fclose(in);
    fclose(out);
    remove(szCSVFile);
    rename(szCSVTempFile, szCSVFile);
    return found;
}

/* ===================== DICOM Encoders ===================== */

static int write_implicit_us(unsigned char *p, unsigned short grp,
                              unsigned short elem, unsigned short val) {
    p[0] = grp & 0xFF; p[1] = (grp >> 8) & 0xFF;
    p[2] = elem & 0xFF; p[3] = (elem >> 8) & 0xFF;
    *(unsigned int*)(p + 4) = 2;
    p[8] = val & 0xFF; p[9] = (val >> 8) & 0xFF;
    return 10;
}

static int write_implicit_str(unsigned char *p, unsigned short grp,
                               unsigned short elem, const char *s) {
    int n = (int)strlen(s);
    int pad = (n & 1) ? n + 1 : n;
    p[0] = grp & 0xFF; p[1] = (grp >> 8) & 0xFF;
    p[2] = elem & 0xFF; p[3] = (elem >> 8) & 0xFF;
    *(unsigned int*)(p + 4) = pad;
    if (n > 0) memcpy(p + 8, s, n);
    if (pad > n) p[8 + n] = 0x20;
    return 8 + pad;
}

static int build_command_set(unsigned char *out, const char *sopUid, int sopLen,
                              unsigned short cmdField, unsigned short msgID,
                              unsigned short dsType, unsigned short status) {
    unsigned char *p = out + 12;
    int cmdLen;
    p[0] = 0; p[1] = 0; p[2] = 2; p[3] = 0;
    *(unsigned int*)(p + 4) = sopLen;
    memcpy(p + 8, sopUid, sopLen);
    p += 8 + sopLen;
    p += write_implicit_us(p, 0x0000, 0x0100, cmdField);
    p += write_implicit_us(p, 0x0000, 0x0120, msgID);
    p += write_implicit_us(p, 0x0000, 0x0800, dsType);
    p += write_implicit_us(p, 0x0000, 0x0900, status);
    cmdLen = (int)(p - (out + 12));
    out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 0;
    *(unsigned int*)(out + 4) = 4;
    *(unsigned int*)(out + 8) = cmdLen;
    return cmdLen + 12;
}

static unsigned int be32(unsigned int v) {
    return ((v & 0xFF) << 24) | ((v & 0xFF00) << 8) |
           ((v & 0xFF0000) >> 8) | ((v & 0xFF000000) >> 24);
}

static void send_pdv(SOCKET s, int pcid, const unsigned char *data, int dataLen, int flags) {
    unsigned char *p = g_dicomSendBuf;
    int pdvLen = dataLen + 2;
    int pduLen = pdvLen + 4;
    p[0] = 0x04; p[1] = 0x00;
    *(unsigned int*)(p + 2) = be32(pduLen);
    *(unsigned int*)(p + 6) = be32(pdvLen);
    p[10] = (unsigned char)pcid;
    p[11] = (unsigned char)flags;
    memcpy(p + 12, data, dataLen);
    send(s, (const char*)g_dicomSendBuf, dataLen + 12, 0);
}

/* ===================== A-ASSOCIATE-AC ===================== */

static void dicom_send_associate_ac(SOCKET s) {
    unsigned char buf[512];
    unsigned char *p = buf;
    int total;
    memcpy(p, pdu1_prefix, 10); p += 10;
    memcpy(p, g_aeCalled, 16);  p += 16;
    memcpy(p, pdu1_ae_calling, 16); p += 16;
    memset(p, 0, 32); p += 32;
    memcpy(p, pdu_appctx, 25); p += 25;
    memcpy(p, pdu2_static, 58); p += 58;
    memcpy(p, pdu3_static, 61); p += 61;
    total = (int)(p - buf);
    send(s, (const char*)buf, total, 0);
    printf("A-ASSOCIATE-AC sent on socket %u\r\n", (unsigned)s);
}

static void send_c_echo_rsp(SOCKET s, int pcid, unsigned short msgID) {
    unsigned char cmd[256];
    int cmdLen = build_command_set(cmd, szEchoSOPClass, 18, 0x8030, msgID, 0x0101, 0x0000);
    send_pdv(s, pcid, cmd, cmdLen, 0x03);
}

/* ===================== MWL Dataset Builder ===================== */

static int build_mwl_dataset(char *entry, unsigned char *out) {
    unsigned char *p = out;
    unsigned char *sps;
    int spsLen;
    char timeBuf[16];

    p += write_implicit_str(p, 0x0008, 0x0050, field_ptr(entry, 2));
    p += write_implicit_str(p, 0x0008, 0x0090, field_ptr(entry, 14));
    p += write_implicit_str(p, 0x0010, 0x0010, field_ptr(entry, 1));
    p += write_implicit_str(p, 0x0010, 0x0020, field_ptr(entry, 0));
    p += write_implicit_str(p, 0x0010, 0x0030, field_ptr(entry, 3));
    p += write_implicit_str(p, 0x0010, 0x0040, field_ptr(entry, 4));
    p += write_implicit_str(p, 0x0020, 0x000D, field_ptr(entry, 13));
    p += write_implicit_str(p, 0x0032, 0x1060, field_ptr(entry, 12));

    sps = g_spsBuf;
    sps += write_implicit_str(sps, 0x0008, 0x0060, field_ptr(entry, 9));
    sps += write_implicit_str(sps, 0x0040, 0x0001, field_ptr(entry, 8));
    sps += write_implicit_str(sps, 0x0040, 0x0002, field_ptr(entry, 10));
    strip_colons(field_ptr(entry, 11), timeBuf);
    sps += write_implicit_str(sps, 0x0040, 0x0003, timeBuf);
    sps += write_implicit_str(sps, 0x0040, 0x0006, field_ptr(entry, 19));
    sps += write_implicit_str(sps, 0x0040, 0x0007, field_ptr(entry, 6));
    sps += write_implicit_str(sps, 0x0040, 0x0009, field_ptr(entry, 5));
    sps += write_implicit_str(sps, 0x0040, 0x0010, field_ptr(entry, 20));
    sps += write_implicit_str(sps, 0x0040, 0x0011, field_ptr(entry, 21));
    spsLen = (int)(sps - g_spsBuf);

    /* (0040,0100) SPS Sequence header */
    p[0] = 0x40; p[1] = 0x00; p[2] = 0x00; p[3] = 0x01;
    *(unsigned int*)(p + 4) = spsLen + 8;
    p += 8;
    /* Item header */
    p[0] = 0xFE; p[1] = 0xFF; p[2] = 0x00; p[3] = 0xE0;
    *(unsigned int*)(p + 4) = spsLen;
    p += 8;
    memcpy(p, g_spsBuf, spsLen);
    p += spsLen;

    p += write_implicit_str(p, 0x0040, 0x1001, field_ptr(entry, 7));

    return (int)(p - out);
}

static void send_c_find_pending(SOCKET s, int pcid, unsigned short msgID,
                                 const unsigned char *ds, int dsLen) {
    unsigned char cmd[256];
    int cmdLen = build_command_set(cmd, szMwlSOPClass, 22, 0x8020, msgID, 0x0102, 0xFF00);
    send_pdv(s, pcid, cmd, cmdLen, 0x03);
    send_pdv(s, pcid, ds, dsLen, 0x02);
}

static void send_c_find_final(SOCKET s, int pcid, unsigned short msgID) {
    unsigned char cmd[256];
    int cmdLen = build_command_set(cmd, szMwlSOPClass, 22, 0x8020, msgID, 0x0101, 0x0000);
    send_pdv(s, pcid, cmd, cmdLen, 0x03);
}

static void send_mwl_results(SOCKET s, int pcid, unsigned short msgID) {
    FILE *f = fopen(szCSVFile, "r");
    if (!f) {
        send_c_find_final(s, pcid, msgID);
        return;
    }
    fgets(g_fileLine, LINE_SIZE, f); /* skip header */
    while (fgets(g_fileLine, LINE_SIZE, f)) {
        int dsLen;
        parse_csv_line(g_fileLine, g_tmpEntry);
        if (field_ptr(g_tmpEntry, 0)[0] == 0) continue;
        printf("  MWL match: PatientID=%s\r\n", field_ptr(g_tmpEntry, 0));
        dsLen = build_mwl_dataset(g_tmpEntry, g_mwlDsBuf);
        send_c_find_pending(s, pcid, msgID, g_mwlDsBuf, dsLen);
    }
    fclose(f);
    send_c_find_final(s, pcid, msgID);
}

/* ===================== DICOM Client Handler ===================== */

static unsigned short extract_msg_id(const unsigned char *bin, int binLen) {
    int pos = 12;
    int limit = binLen - 20;
    while (pos < limit) {
        unsigned short g = *(unsigned short*)(bin + pos);
        unsigned short e = *(unsigned short*)(bin + pos + 2);
        unsigned int  l  = *(unsigned int*)(bin + pos + 4);
        if (g == 0x0000 && e == 0x0110 && l == 2) {
            return *(unsigned short*)(bin + pos + 8);
        }
        pos++;
    }
    return 1;
}

static const unsigned char *mem_find(const unsigned char *buf, int bufLen,
                                      const char *s) {
    int n = (int)strlen(s);
    int i;
    for (i = 0; i <= bufLen - n; i++) {
        if (memcmp(buf + i, s, n) == 0) return buf + i;
    }
    return NULL;
}

static void dicom_handle_client(SOCKET s) {
    for (;;) {
        int cb = recv(s, (char*)g_dicomRecvBuf, sizeof(g_dicomRecvBuf), 0);
        unsigned char t;
        if (cb <= 0) return;
        t = g_dicomRecvBuf[0];
        if (t == 0x01) {
            dicom_send_associate_ac(s);
        } else if (t == 0x04) {
            int pcid = g_dicomRecvBuf[10];
            if (mem_find(g_dicomRecvBuf, cb, szEchoSOPClass)) {
                unsigned short msgID = extract_msg_id(g_dicomRecvBuf, cb);
                printf("C-ECHO sock=%u MsgID=%u PCID=%d\r\n", (unsigned)s, msgID, pcid);
                send_c_echo_rsp(s, pcid, msgID);
            } else if (mem_find(g_dicomRecvBuf, cb, szMwlSOPClass)) {
                unsigned short msgID = extract_msg_id(g_dicomRecvBuf, cb);
                printf("C-FIND sock=%u MsgID=%u PCID=%d\r\n", (unsigned)s, msgID, pcid);
                send_mwl_results(s, pcid, msgID);
            }
        } else if (t == 0x05) {
            unsigned char rel[8] = { 0x06,0x00,0x00,0x00,0x00,0x04,0x00,0x00 };
            send(s, (const char*)rel, 8, 0);
            return;
        }
    }
}

/* ===================== Telnet socket layer ===================== */

static void set_nonblocking(SOCKET s) {
    u_long mode = 1;
    ioctlsocket(s, FIONBIO, &mode);
}

static void set_blocking(SOCKET s) {
    u_long mode = 0;
    ioctlsocket(s, FIONBIO, &mode);
}

static int start_telnet_server(void) {
    struct sockaddr_in sin;
    g_listenSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (g_listenSocket == INVALID_SOCKET) {
        printf("ERROR: telnet socket() failed\r\n");
        return 0;
    }
    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((u_short)g_TelnetPort);
    sin.sin_addr.s_addr = INADDR_ANY;
    if (bind(g_listenSocket, (struct sockaddr*)&sin, sizeof(sin)) == SOCKET_ERROR ||
        listen(g_listenSocket, SOMAXCONN) == SOCKET_ERROR) {
        printf("ERROR: Failed to bind/listen telnet port %u\r\n", g_TelnetPort);
        closesocket(g_listenSocket);
        g_listenSocket = INVALID_SOCKET;
        return 0;
    }
    set_nonblocking(g_listenSocket);
    printf("Telnet listening on port %u\r\n", g_TelnetPort);
    return 1;
}

static int start_dicom_server(void) {
    struct sockaddr_in sin;
    g_dicomListenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (g_dicomListenSock == INVALID_SOCKET) return 0;
    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((u_short)g_DicomPort);
    sin.sin_addr.s_addr = INADDR_ANY;
    if (bind(g_dicomListenSock, (struct sockaddr*)&sin, sizeof(sin)) == SOCKET_ERROR ||
        listen(g_dicomListenSock, SOMAXCONN) == SOCKET_ERROR) {
        printf("ERROR: Failed to bind/listen DICOM port %u\r\n", g_DicomPort);
        closesocket(g_dicomListenSock);
        g_dicomListenSock = INVALID_SOCKET;
        return 0;
    }
    set_nonblocking(g_dicomListenSock);
    printf("DICOM listening on port %u\r\n", g_DicomPort);
    return 1;
}

static int find_free_slot(void) {
    int i;
    for (i = 0; i < MAX_CLIENTS; i++)
        if (g_clients[i] == 0) return i;
    return -1;
}

static void add_client(SOCKET s) {
    int idx = find_free_slot();
    if (idx < 0) { closesocket(s); return; }
    set_nonblocking(s);
    g_clients[idx] = s;
    g_clientBufLen[idx] = 0;
    memset(g_clientBuffers[idx], 0, CLIENT_BUF_SIZE);
    g_clientLastTick[idx] = GetTickCount();
    g_clientTimeout[idx] = DEFAULT_TIMEOUT_MS;
    g_pendingFlag[idx] = 0;
    g_pendingSince[idx] = 0;
    printf("Telnet Client connected on socket %u\r\n", (unsigned)s);
    send_text(s, "Connected to RIS Telnet Server. Waiting for data...\r\n");
}

static void remove_client(int idx) {
    if (g_clients[idx]) {
        printf("Client disconnected on socket %u\r\n", (unsigned)g_clients[idx]);
        closesocket(g_clients[idx]);
    }
    g_clients[idx] = 0;
    g_clientBufLen[idx] = 0;
    g_pendingFlag[idx] = 0;
    g_pendingSince[idx] = 0;
}

static void accept_new_clients(void) {
    for (;;) {
        SOCKET s = accept(g_listenSocket, NULL, NULL);
        if (s == INVALID_SOCKET) return;
        add_client(s);
    }
}

static void poll_dicom_server(void) {
    SOCKET s = accept(g_dicomListenSock, NULL, NULL);
    if (s == INVALID_SOCKET) return;
    printf("DICOM Client connected on socket %u\r\n", (unsigned)s);
    set_blocking(s);
    dicom_handle_client(s);
    closesocket(s);
    printf("DICOM Client disconnected on socket %u\r\n", (unsigned)s);
}

/* ===================== DISP / Pending ===================== */

static void extract_disp_param(const char *line, char *out) {
    line += 4;
    while (*line == ' ') line++;
    while (*line && *line != '\r' && *line != '\n') *out++ = *line++;
    *out = 0;
}

static int is_date_range(const char *p) {
    return p[8] == ' ' && p[17] == 0;
}

static int line_matches_disp(const char *line, const char *param) {
    char tmp[ENTRY_SIZE];
    const char *date;
    if (param[0] == 0) return 1;
    parse_csv_line(line, tmp);
    if (is_eight_digits(param)) {
        return strcmp(field_ptr(tmp, 10), param) == 0;
    }
    if (is_date_range(param)) {
        date = field_ptr(tmp, 10);
        if (strncmp(date, param, 8) < 0) return 0;
        if (strncmp(date, param + 9, 8) > 0) return 0;
        return 1;
    }
    return stri_equals(field_ptr(tmp, 9), param);
}

static void process_disp(int idx, const char *line) {
    FILE *f;
    SOCKET s = g_clients[idx];
    extract_disp_param(line, g_dispParam);
    f = fopen(szCSVFile, "r");
    if (!f) return;
    fgets(g_fileLine, LINE_SIZE, f); /* header */
    while (fgets(g_fileLine, LINE_SIZE, f)) {
        if (line_matches_disp(g_fileLine, g_dispParam))
            send_text(s, g_fileLine);
    }
    fclose(f);
}

static void commit_pending(int idx) {
    int found;
    const char *pid;
    SOCKET s = g_clients[idx];
    build_csv_line(g_pendingEntries[idx], g_lineOut);
    found = update_csv_by_patient(g_pendingEntries[idx], g_lineOut);
    pid = field_ptr(g_pendingEntries[idx], 0);
    if (found) {
        send_text(s, "UPDATED\r\n");
        printf("UPDATED PatientID %s\r\n", pid);
    } else {
        send_text(s, "INSERTED\r\n");
        printf("INSERTED PatientID %s\r\n", pid);
    }
    g_pendingFlag[idx] = 0;
    g_pendingSince[idx] = 0;
}

static void process_client_line(int idx, char *line) {
    char entry[ENTRY_SIZE];
    trim_in_place(line);
    if (line[0] == 0) return;
    if (starts_disp(line)) { process_disp(idx, line); return; }
    parse_csv_line(line, entry);
    if (!validate_entry(entry)) {
        send_text(g_clients[idx], "INVALID LINE\r\n");
        return;
    }
    memcpy(g_pendingEntries[idx], entry, ENTRY_SIZE);
    g_pendingFlag[idx] = 1;
    g_pendingSince[idx] = GetTickCount();
    g_clientTimeout[idx] += 1000;
    send_text(g_clients[idx], "PENDING\r\n");
    printf("PENDING PatientID %s\r\n", field_ptr(g_pendingEntries[idx], 0));
}

static void check_pending_and_timeout(int idx) {
    DWORD now;
    SOCKET s = g_clients[idx];
    if (!s) return;
    now = GetTickCount();
    if (g_pendingFlag[idx] && (now - g_pendingSince[idx]) >= APPEND_DELAY_MS) {
        commit_pending(idx);
        g_clientLastTick[idx] = GetTickCount();
    }
    if ((now - g_clientLastTick[idx]) >= g_clientTimeout[idx]) {
        printf("Client on socket %u timed out\r\n", (unsigned)s);
        remove_client(idx);
    }
}

static void append_received_bytes(int idx, const char *bytes, int n) {
    int i;
    char *buf = g_clientBuffers[idx];
    int cur = g_clientBufLen[idx];
    for (i = 0; i < n; i++) {
        char c = bytes[i];
        if (c == '\r') continue;
        if (c == '\n') {
            buf[cur] = 0;
            process_client_line(idx, buf);
            cur = 0;
            memset(buf, 0, CLIENT_BUF_SIZE);
            continue;
        }
        if (cur < CLIENT_BUF_SIZE - 1) buf[cur++] = c;
    }
    g_clientBufLen[idx] = cur;
}

static void poll_client(int idx) {
    SOCKET s = g_clients[idx];
    int n;
    if (!s) return;
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
    check_pending_and_timeout(idx);
}

/* ===================== Server start/stop ===================== */

static void ServerStart(void) {
    if (g_bRunning) return;
    if (!start_telnet_server()) return;
    if (!start_dicom_server()) return;
    g_bRunning = 1;
    printf("Server STARTED\r\n");
    if (g_hMenu)
        ModifyMenu(g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND | MF_STRING,
                   ID_TRAY_TOGGLE, szMenuStop);
}

static void ServerStop(void) {
    int i;
    if (!g_bRunning) return;
    for (i = 0; i < MAX_CLIENTS; i++) remove_client(i);
    if (g_listenSocket != INVALID_SOCKET) {
        closesocket(g_listenSocket);
        g_listenSocket = INVALID_SOCKET;
    }
    if (g_dicomListenSock != INVALID_SOCKET) {
        closesocket(g_dicomListenSock);
        g_dicomListenSock = INVALID_SOCKET;
    }
    g_bRunning = 0;
    printf("Server STOPPED\r\n");
    if (g_hMenu)
        ModifyMenu(g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND | MF_STRING,
                   ID_TRAY_TOGGLE, szMenuStart);
}

static void server_loop(void) {
    MSG msg;
    int i;
    while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    if (!g_bRunning) return;
    accept_new_clients();
    poll_dicom_server();
    for (i = 0; i < MAX_CLIENTS; i++) poll_client(i);
}

/* ===================== Tray / Window ===================== */

static LRESULT CALLBACK WndProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    POINT pt;
    if (uMsg == WM_TRAYICON) {
        if (lParam == WM_RBUTTONUP) {
            GetCursorPos(&pt);
            SetForegroundWindow(hWnd);
            TrackPopupMenu(g_hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hWnd, NULL);
        }
        return 0;
    }
    if (uMsg == WM_COMMAND) {
        WORD cmd = LOWORD(wParam);
        if (cmd == ID_TRAY_TOGGLE) {
            if (g_bRunning) ServerStop(); else ServerStart();
        } else if (cmd == ID_TRAY_SHOW) {
            HWND c = GetConsoleWindow();
            if (c) ShowWindow(c, SW_SHOW);
        } else if (cmd == ID_TRAY_EXIT) {
            ServerStop();
            Shell_NotifyIcon(NIM_DELETE, &g_nid);
            PostQuitMessage(0);
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

static void create_tray(void) {
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

    g_hMainWnd = CreateWindowEx(0, szWndClass, szTrayTip, 0,
                                 0, 0, 0, 0, HWND_MESSAGE, NULL, g_hInstance, NULL);

    g_hMenu = CreatePopupMenu();
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_TOGGLE,
               g_bRunning ? szMenuStop : szMenuStart);
    AppendMenu(g_hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_SHOW, "Show Console");
    AppendMenu(g_hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_EXIT, "Exit");

    memset(&g_nid, 0, sizeof(g_nid));
    g_nid.cbSize           = sizeof(NOTIFYICONDATA);
    g_nid.hWnd             = g_hMainWnd;
    g_nid.uID              = 1;
    g_nid.uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    g_nid.uCallbackMessage = WM_TRAYICON;
    g_nid.hIcon            = LoadIcon(NULL, IDI_APPLICATION);
    lstrcpy(g_nid.szTip, szTrayTip);
    Shell_NotifyIcon(NIM_ADD, &g_nid);
}

/* ===================== Main ===================== */

int main(void) {
    WSADATA wsa;
    MSG qmsg;

    printf("RIS Telnet + DICOM MWL SCP starting...\r\n");
    LoadConfig();
    printf("Config: AET=%s TelnetPort=%u DicomPort=%u DebugLog=%u\r\n",
           g_aeCalled, g_TelnetPort, g_DicomPort, g_DebugLog);

    memset(g_clients, 0, sizeof(g_clients));
    WSAStartup(MAKEWORD(2,2), &wsa);
    ensure_csv();
    create_tray();
    ServerStart();

    for (;;) {
        server_loop();
        if (PeekMessage(&qmsg, NULL, WM_QUIT, WM_QUIT, PM_NOREMOVE)) break;
        Sleep(10);
    }

    ServerStop();
    WSACleanup();
    return 0;
}