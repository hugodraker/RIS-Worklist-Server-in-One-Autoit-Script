/* pacs-server01.c
 * PACS Storage SCP - TCC compatible
 * - Compatible A-ASSOCIATE-AC (parses RQ, accepts each PC with Implicit/Explicit VR LE)
 * - C-ECHO + C-STORE
 * - Raw direct-write to SR000000\000001.DCM, rolls every 16000
 * - LastFolderIndex + LastFileIndex persisted in INI
 * - System tray with Start/Stop/Settings/Show Console/Exit
 *
 * Compile: tcc -o pacs-server01.exe pacs-server01.c -lws2_32 -lkernel32 -luser32 -lshell32
 * gcc -O2 -s -mwindows -o pacs-server01.exe PACS-SERVER01.c -lws2_32 -lkernel32 -luser32 -lshell32

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

#define DICOM_RECV_BUF_SIZE     1048576
#define DICOM_SEND_BUF_SIZE     16384
#define MAX_IMAGES_PER_FOLDER   16000
#define MAX_PRES_CONTEXTS       32

#define WM_TRAYICON         (WM_USER + 1)
#define ID_TRAY_TOGGLE      1000
#define ID_TRAY_SETTINGS    1001
#define ID_TRAY_SHOW        1002
#define ID_TRAY_EXIT        1003

#define ID_BTN_STARTSTOP    2001
#define ID_BTN_SAVE         2002
#define ID_BTN_CLOSE        2003
#define ID_EDIT_AET         2010
#define ID_EDIT_PORT        2011
#define ID_CHK_DEBUG        2012

/* ===================== Globals ===================== */
static unsigned int g_DicomPort       = 777;
static unsigned int g_DebugLog        = 1;
static int          g_bRunning        = 0;
static SOCKET       g_dicomListenSock = INVALID_SOCKET;
static unsigned int g_scuMaxPduLen    = 16384;

static unsigned int g_CurrentFolderIndex = 0;
static unsigned int g_CurrentFileIndex   = 0;

static HINSTANCE      g_hInstance     = 0;
static HWND           g_hMainWnd      = 0;
static HWND           g_hSettingsWnd  = 0;
static HMENU          g_hMenu         = 0;
static HWND           g_hLogEdit      = 0;
static HWND           g_hStatusLabel  = 0;
static NOTIFYICONDATA g_nid;

static char g_aeCalled[17]  = "PACS_SCP        ";
static char g_aeCalling[17] = "ANY-SCU         ";

/* DICOM transfer state */
static unsigned char g_dicomRecvBuf[DICOM_RECV_BUF_SIZE];
static unsigned char g_dicomSendBuf[DICOM_SEND_BUF_SIZE];
static unsigned char g_assocAcBuf[4096];

static char g_tmpPath[260];

static char g_currentSOPClass[128];
static char g_currentSOPInst[128];
static int  g_pendingMsgID = 1;
static int  g_pendingPCID  = 1;
static int  g_bReceivingImage = 0;
static HANDLE g_hTempFile = INVALID_HANDLE_VALUE;

static const char *g_pcidToTsUid[MAX_PRES_CONTEXTS];

/* Constant strings */
static const char *szIniFile         = "pacs-server01.ini";
static const char *szWndClass        = "PACSTrayClass";
static const char *szSettingsClass   = "PACSSettingsClass";
static const char *szTrayTip         = "PACS SCP Storage Server";
static const char *szMenuStart       = "Start Server";
static const char *szMenuStop        = "Stop Server";

static const char *szEchoSOPClass    = "1.2.840.10008.1.1";
static const char *szDefaultSOPClass = "1.2.840.10008.5.1.4.1.1.7";
static const char *szDefaultSOPInst  = "1.2.3.4.5.6.7.8.9.0";
static const char *szImplicitVRLE    = "1.2.840.10008.1.2";
static const char *szExplicitVRLE    = "1.2.840.10008.1.2.1";
static const char *szAppCtxUID       = "1.2.840.10008.3.1.1.1";
static const char *szImplClassUID    = "1.2.276.0.7230010.3.0.3.6.4";
static const char *szImplVersionName = "PACS_SCP_TCC";

static const unsigned char releaseRsp[8] = { 0x06,0x00,0x00,0x00,0x00,0x04,0x00,0x00 };

/* ===================== Forward decls ===================== */
static void ServerStart(void);
static void ServerStop(void);

/* ===================== Logging ===================== */

static void LogText(const char *txt) {
    SYSTEMTIME st;
    char line[1280];
    FILE *f;

    GetLocalTime(&st);
    sprintf(line, "[%02d:%02d:%02d] %s\r\n", st.wHour, st.wMinute, st.wSecond, txt);

    printf("%s", line);

    f = fopen("PACS_Server.log", "a");
    if (f) {
        fputs(line, f);
        fclose(f);
    }
    if (g_hLogEdit) {
        SendMessage(g_hLogEdit, EM_SETSEL, -1, -1);
        SendMessage(g_hLogEdit, EM_REPLACESEL, FALSE, (LPARAM)line);
    }
}

/* ===================== INI / Config ===================== */

static void set_ae_title(char *dest, const char *src) {
    int i;
    for (i = 0; i < 16; i++) dest[i] = ' ';
    dest[16] = 0;
    for (i = 0; i < 16 && src[i]; i++) dest[i] = src[i];
}

static void LoadConfig(void) {
    char buf[256];
    DWORD attr;

    /* First-run only: seed defaults */
    attr = GetFileAttributes(szIniFile);
    if (attr == INVALID_FILE_ATTRIBUTES) {
        WritePrivateProfileString("Server",  "AETitle",         "PACS_SCP", szIniFile);
        WritePrivateProfileString("Server",  "DicomPort",       "777",      szIniFile);
        WritePrivateProfileString("Server",  "DebugLog",        "1",        szIniFile);
        WritePrivateProfileString("Storage", "LastFolderIndex", "0",        szIniFile);
        WritePrivateProfileString("Storage", "LastFileIndex",   "0",        szIniFile);
    }

    GetPrivateProfileString("Server", "AETitle", "PACS_SCP", buf, sizeof(buf), szIniFile);
    set_ae_title(g_aeCalled, buf);

    g_DicomPort = GetPrivateProfileInt("Server", "DicomPort", 777, szIniFile);
    g_DebugLog  = GetPrivateProfileInt("Server", "DebugLog",   1,  szIniFile);

    g_CurrentFolderIndex = GetPrivateProfileInt("Storage", "LastFolderIndex", 0, szIniFile);
    g_CurrentFileIndex   = GetPrivateProfileInt("Storage", "LastFileIndex",   0, szIniFile);
}

/* ===================== Storage path ===================== */

static void GetNextStoragePath(char *pOut) {
    char folder[64];
    char val[32];

    g_CurrentFileIndex++;
    if (g_CurrentFileIndex > MAX_IMAGES_PER_FOLDER) {
        g_CurrentFolderIndex++;
        g_CurrentFileIndex = 1;
    }

    sprintf(val, "%u", g_CurrentFolderIndex);
    WritePrivateProfileString("Storage", "LastFolderIndex", val, szIniFile);
    sprintf(val, "%u", g_CurrentFileIndex);
    WritePrivateProfileString("Storage", "LastFileIndex",   val, szIniFile);

    sprintf(folder, "SR%06u", g_CurrentFolderIndex);
    CreateDirectory(folder, NULL);

    sprintf(pOut, "SR%06u\\%06u.DCM", g_CurrentFolderIndex, g_CurrentFileIndex);
}

/* ===================== DICOM helpers ===================== */

static unsigned int ReadBE32(const unsigned char *buf, int off) {
    return ((unsigned int)buf[off+0] << 24) |
           ((unsigned int)buf[off+1] << 16) |
           ((unsigned int)buf[off+2] <<  8) |
           ((unsigned int)buf[off+3]);
}

/* Find an Implicit-VR-LE element by 4-byte little-endian tag. Returns pointer to value, or NULL. */
static const unsigned char *FindCmdElement(const unsigned char *cmd, int cmdLen,
                                            unsigned int tagLE, unsigned int *outLen) {
    int pos = 0;
    while (pos + 8 <= cmdLen) {
        unsigned int t = *(const unsigned int *)(cmd + pos);
        unsigned int l = *(const unsigned int *)(cmd + pos + 4);
        if (t == tagLE) {
            if (outLen) *outLen = l;
            return cmd + pos + 8;
        }
        pos += 8 + l;
    }
    return NULL;
}

static int ExtractCmdString(const unsigned char *cmd, int cmdLen, unsigned int tagLE,
                             char *out, int outSize) {
    unsigned int vlen;
    const unsigned char *p = FindCmdElement(cmd, cmdLen, tagLE, &vlen);
    int copy;
    int i;
    if (!p) return 0;
    copy = (int)vlen;
    if (copy >= outSize) copy = outSize - 1;
    memcpy(out, p, copy);
    out[copy] = 0;
    /* trim trailing spaces / nulls */
    for (i = copy - 1; i >= 0; i--) {
        if (out[i] == ' ' || out[i] == 0) out[i] = 0;
        else break;
    }
    return 1;
}

static unsigned short ExtractCmdUS(const unsigned char *cmd, int cmdLen, unsigned int tagLE) {
    unsigned int vlen;
    const unsigned char *p = FindCmdElement(cmd, cmdLen, tagLE, &vlen);
    if (!p || vlen != 2) return 0;
    return (unsigned short)(p[0] | (p[1] << 8));
}

/* Write an Implicit-VR US element (10 bytes total) */
static int WriteImplicitUS(unsigned char *dest, unsigned short grp,
                            unsigned short elem, unsigned short val) {
    dest[0] = grp & 0xFF; dest[1] = (grp >> 8) & 0xFF;
    dest[2] = elem & 0xFF; dest[3] = (elem >> 8) & 0xFF;
    *(unsigned int *)(dest + 4) = 2;
    dest[8] = val & 0xFF; dest[9] = (val >> 8) & 0xFF;
    return 10;
}

/* Build a command set into `out`. SOP UID is padded to even length internally. */
static int BuildCommandSet(unsigned char *out, const char *sopUid, int sopLen,
                            unsigned short cmdField, unsigned short msgID,
                            unsigned short dsType, unsigned short status) {
    int padLen = (sopLen & 1) ? sopLen + 1 : sopLen;
    unsigned char *p = out + 12;
    int cmdLen;

    /* (0000,0002) Affected SOP Class UID */
    p[0] = 0; p[1] = 0; p[2] = 2; p[3] = 0;
    *(unsigned int *)(p + 4) = padLen;
    memcpy(p + 8, sopUid, sopLen);
    if (padLen > sopLen) p[8 + sopLen] = 0;
    p += 8 + padLen;

    p += WriteImplicitUS(p, 0x0000, 0x0100, cmdField);
    p += WriteImplicitUS(p, 0x0000, 0x0120, msgID);
    p += WriteImplicitUS(p, 0x0000, 0x0800, dsType);
    p += WriteImplicitUS(p, 0x0000, 0x0900, status);

    cmdLen = (int)(p - (out + 12));

    /* (0000,0000) Command Group Length */
    out[0] = 0; out[1] = 0; out[2] = 0; out[3] = 0;
    *(unsigned int *)(out + 4) = 4;
    *(unsigned int *)(out + 8) = cmdLen;

    return cmdLen + 12;
}

/* Send a single P-DATA PDV. */
static void SendPDV(SOCKET s, int pcid, const unsigned char *data, int dataLen, int flags) {
    unsigned char *buf = g_dicomSendBuf;
    unsigned int pdvLen = dataLen + 2;
    unsigned int pduLen = pdvLen + 4;

    buf[0] = 0x04;
    buf[1] = 0x00;

    /* PDU length big-endian */
    buf[2] = (pduLen >> 24) & 0xFF;
    buf[3] = (pduLen >> 16) & 0xFF;
    buf[4] = (pduLen >>  8) & 0xFF;
    buf[5] =  pduLen        & 0xFF;
    /* PDV length big-endian */
    buf[6] = (pdvLen >> 24) & 0xFF;
    buf[7] = (pdvLen >> 16) & 0xFF;
    buf[8] = (pdvLen >>  8) & 0xFF;
    buf[9] =  pdvLen        & 0xFF;

    buf[10] = (unsigned char)pcid;
    buf[11] = (unsigned char)flags;

    memcpy(buf + 12, data, dataLen);
    send(s, (const char *)buf, dataLen + 12, 0);
}

static void SendCEchoRsp(SOCKET s, int pcid, unsigned short msgID) {
    unsigned char cmd[256];
    int n = BuildCommandSet(cmd, szEchoSOPClass, (int)strlen(szEchoSOPClass),
                            0x8030, msgID, 0x0101, 0x0000);
    SendPDV(s, pcid, cmd, n, 0x03);
    LogText("C-ECHO Request received. Replying with C-ECHO-RSP.");
}

static void SendCStoreRsp(SOCKET s, int pcid, unsigned short msgID) {
    unsigned char cmd[512];
    int n = BuildCommandSet(cmd, g_currentSOPClass, (int)strlen(g_currentSOPClass),
                            0x8001, msgID, 0x0101, 0x0000);
    SendPDV(s, pcid, cmd, n, 0x03);
    LogText("C-STORE-RSP sent.");
}

/* ===================== A-ASSOCIATE-AC builder ===================== */

/* Append a 0x21 Presentation Context AC item. Returns bytes written. */
static int AppendPCAC(unsigned char *dest, int pcid, int result, const char *tsUid) {
    int tsLen, padLen, itemLen;

    if (result != 0) {
        /* Rejected: 8 bytes total */
        dest[0] = 0x21; dest[1] = 0;
        dest[2] = 0; dest[3] = 4;
        dest[4] = (unsigned char)pcid; dest[5] = 0;
        dest[6] = (unsigned char)result; dest[7] = 0;
        return 8;
    }

    tsLen = (int)strlen(tsUid);
    padLen = (tsLen & 1) ? tsLen + 1 : tsLen;
    itemLen = padLen + 8;

    dest[0] = 0x21; dest[1] = 0;
    dest[2] = 0; dest[3] = (unsigned char)itemLen;

    dest[4] = (unsigned char)pcid; dest[5] = 0;
    dest[6] = 0; dest[7] = 0;

    /* TS sub-item */
    dest[8]  = 0x40; dest[9]  = 0;
    dest[10] = 0;    dest[11] = (unsigned char)padLen;
    memcpy(dest + 12, tsUid, tsLen);
    if (padLen > tsLen) dest[12 + tsLen] = 0;

    return itemLen + 4;
}

static int AppendAppCtx(unsigned char *dest) {
    int uidLen = (int)strlen(szAppCtxUID);
    int padLen = (uidLen & 1) ? uidLen + 1 : uidLen;

    dest[0] = 0x10; dest[1] = 0;
    dest[2] = 0; dest[3] = (unsigned char)padLen;
    memcpy(dest + 4, szAppCtxUID, uidLen);
    if (padLen > uidLen) dest[4 + uidLen] = 0;

    return padLen + 4;
}

static int AppendUserInfo(unsigned char *dest) {
    int icuLen, icuPad, vnLen, vnPad, total;
    unsigned char *p;

    icuLen = (int)strlen(szImplClassUID);
    icuPad = (icuLen & 1) ? icuLen + 1 : icuLen;
    vnLen  = (int)strlen(szImplVersionName);
    vnPad  = (vnLen & 1) ? vnLen + 1 : vnLen;
    total  = icuPad + vnPad + 16;

    dest[0] = 0x50; dest[1] = 0;
    dest[2] = 0;    dest[3] = (unsigned char)total;

    p = dest + 4;

    /* 0x51 Max PDU Length = 16384 BE */
    p[0] = 0x51; p[1] = 0;
    p[2] = 0;    p[3] = 4;
    p[4] = 0x00; p[5] = 0x00; p[6] = 0x40; p[7] = 0x00;
    p += 8;

    /* 0x52 Implementation Class UID */
    p[0] = 0x52; p[1] = 0;
    p[2] = 0;    p[3] = (unsigned char)icuPad;
    memcpy(p + 4, szImplClassUID, icuLen);
    if (icuPad > icuLen) p[4 + icuLen] = 0;
    p += 4 + icuPad;

    /* 0x55 Implementation Version Name */
    p[0] = 0x55; p[1] = 0;
    p[2] = 0;    p[3] = (unsigned char)vnPad;
    memcpy(p + 4, szImplVersionName, vnLen);
    if (vnPad > vnLen) p[4 + vnLen] = 0;

    return total + 4;
}

static int ParseAndBuildAC(const unsigned char *rq, int rqLen,
                            unsigned char *out, int *outLen) {
    int pos, pcCount = 0;
    unsigned char *cur = out;
    int i;

    for (i = 0; i < MAX_PRES_CONTEXTS; i++) g_pcidToTsUid[i] = NULL;

    /* PDU header type 0x02; PDU length filled in later */
    cur[0] = 0x02; cur[1] = 0;
    cur[2] = 0; cur[3] = 0; cur[4] = 0; cur[5] = 0;
    cur += 6;

    /* Protocol version */
    cur[0] = 0; cur[1] = 1; cur[2] = 0; cur[3] = 0;
    cur += 4;

    /* Called AE Title — echo back what SCU sent */
    memcpy(cur, rq + 4, 16);
    cur += 16;

    /* Calling AE Title */
    memcpy(cur, rq + 20, 16);
    memcpy(g_aeCalling, rq + 20, 16);
    g_aeCalling[16] = 0;
    cur += 16;

    /* 32 reserved bytes */
    memset(cur, 0, 32);
    cur += 32;

    cur += AppendAppCtx(cur);

    /* Walk the RQ variable items starting at offset 68 */
    pos = 68;
    while (pos + 4 <= rqLen) {
        int itemType = rq[pos];
        int itemLen  = (rq[pos + 2] << 8) | rq[pos + 3];
        if (pos + 4 + itemLen > rqLen) break;

        if (itemType == 0x20) {
            /* Presentation Context RQ */
            int pcid = rq[pos + 4];
            int hasImplicit = 0, hasExplicit = 0;
            int subPos = pos + 8;
            const char *accTs = NULL;
            int accResult = 4; /* default: transfer syntaxes not supported */

            while (subPos + 4 <= pos + 4 + itemLen) {
                int subType = rq[subPos];
                int subLen  = (rq[subPos + 2] << 8) | rq[subPos + 3];
                if (subType == 0x40) {
                    if (subLen == 17 &&
                        memcmp(rq + subPos + 4, szImplicitVRLE, 17) == 0)
                        hasImplicit = 1;
                    else if (subLen == 19 &&
                             memcmp(rq + subPos + 4, szExplicitVRLE, 19) == 0)
                        hasExplicit = 1;
                }
                subPos += 4 + subLen;
            }

            if (hasImplicit) {
                accTs = szImplicitVRLE;
                accResult = 0;
            } else if (hasExplicit) {
                accTs = szExplicitVRLE;
                accResult = 0;
            }

            if (accResult == 0 && pcid < MAX_PRES_CONTEXTS)
                g_pcidToTsUid[pcid] = accTs;

            cur += AppendPCAC(cur, pcid, accResult, accTs ? accTs : "");
            pcCount++;
        } else if (itemType == 0x50) {
            /* User Information — pull Max PDU length sub-item 0x51 */
            int subPos = pos + 4;
            while (subPos + 4 <= pos + 4 + itemLen) {
                int subType = rq[subPos];
                int subLen  = (rq[subPos + 2] << 8) | rq[subPos + 3];
                if (subType == 0x51 && subLen == 4) {
                    g_scuMaxPduLen = ((unsigned int)rq[subPos+4] << 24) |
                                     ((unsigned int)rq[subPos+5] << 16) |
                                     ((unsigned int)rq[subPos+6] <<  8) |
                                     ((unsigned int)rq[subPos+7]);
                }
                subPos += 4 + subLen;
            }
        }

        pos += 4 + itemLen;
    }

    cur += AppendUserInfo(cur);

    /* Patch PDU length (BE32) into bytes [2..5] */
    {
        unsigned int pduLen = (unsigned int)(cur - out) - 6;
        out[2] = (pduLen >> 24) & 0xFF;
        out[3] = (pduLen >> 16) & 0xFF;
        out[4] = (pduLen >>  8) & 0xFF;
        out[5] =  pduLen        & 0xFF;
    }

    *outLen = (int)(cur - out);
    return pcCount;
}

static void DICOM_SendAssociateAC(SOCKET s, const unsigned char *rq, int rqLen) {
    int acLen = 0;
    int pcCount;
    char msg[256];
    pcCount = ParseAndBuildAC(rq, rqLen, g_assocAcBuf, &acLen);
    send(s, (const char *)g_assocAcBuf, acLen, 0);
    sprintf(msg, "A-ASSOCIATE-AC sent on socket %u (PDU len %d, %d PCs)",
            (unsigned)s, acLen, pcCount);
    LogText(msg);
}

/* ===================== File I/O ===================== */

static void OpenStorageFile(const char *path) {
    g_hTempFile = CreateFile(path, GENERIC_WRITE, 0, NULL,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
}

static void CloseStorageFile(void) {
    if (g_hTempFile != INVALID_HANDLE_VALUE) {
        CloseHandle(g_hTempFile);
        g_hTempFile = INVALID_HANDLE_VALUE;
    }
}

static void WriteFileBytes(const unsigned char *buf, int n) {
    DWORD wrote;
    if (g_hTempFile != INVALID_HANDLE_VALUE)
        WriteFile(g_hTempFile, buf, n, &wrote, NULL);
}

/* ===================== DICOM client handler ===================== */

static void InitClientState(SOCKET s) {
    g_bReceivingImage = 0;
    g_pendingMsgID = 1;
    g_pendingPCID = 1;
    g_hTempFile = INVALID_HANDLE_VALUE;
    g_scuMaxPduLen = 16384;
    strcpy(g_currentSOPClass, szDefaultSOPClass);
    strcpy(g_currentSOPInst,  szDefaultSOPInst);
}

static void ProcessPDataPDU(SOCKET s, const unsigned char *payload, int pduLen) {
    int pos = 0;
    while (pos + 6 <= pduLen) {
        unsigned int pdvLen = ReadBE32(payload, pos);
        int pcid, flags;
        const unsigned char *frag;
        int fragLen;

        if (pdvLen < 2 || pos + (int)pdvLen + 4 > pduLen) break;

        pcid  = payload[pos + 4];
        flags = payload[pos + 5];
        frag  = payload + pos + 6;
        fragLen = (int)pdvLen - 2;

        if (flags & 1) {
            /* Command PDV */
            unsigned short cmdField = ExtractCmdUS(frag, fragLen, 0x01000000);
            unsigned short msgID    = ExtractCmdUS(frag, fragLen, 0x01100000);
            if (msgID == 0) msgID = 1;

            if (cmdField == 0x0030) {
                SendCEchoRsp(s, pcid, msgID);
            } else if (cmdField == 0x0001) {
                char log[256];
                ExtractCmdString(frag, fragLen, 0x00020000, g_currentSOPClass, sizeof(g_currentSOPClass));
                ExtractCmdString(frag, fragLen, 0x10000000, g_currentSOPInst,  sizeof(g_currentSOPInst));
                sprintf(log, "C-STORE-RQ received. SOP Class=%s", g_currentSOPClass);
                LogText(log);
                g_pendingMsgID = msgID;
                g_pendingPCID  = pcid;
            }
        } else {
            /* Data PDV */
            if (!g_bReceivingImage) {
                GetNextStoragePath(g_tmpPath);
                OpenStorageFile(g_tmpPath);
                if (g_hTempFile == INVALID_HANDLE_VALUE) {
                    pos += (int)pdvLen + 4;
                    continue;
                }
                g_bReceivingImage = 1;
            }
            WriteFileBytes(frag, fragLen);

            if (flags & 2) {
                char log[300];
                CloseStorageFile();
                sprintf(log, "Image saved to: %s", g_tmpPath);
                LogText(log);
                g_bReceivingImage = 0;
                SendCStoreRsp(s, g_pendingPCID, g_pendingMsgID);
            }
        }

        pos += (int)pdvLen + 4;
    }
}

/* Read exactly n bytes from socket. */
static int RecvExact(SOCKET s, unsigned char *buf, int n) {
    int got = 0;
    while (got < n) {
        int r = recv(s, (char *)buf + got, n - got, 0);
        if (r <= 0) return -1;
        got += r;
    }
    return got;
}

static void HandleDicomClient(SOCKET s) {
    InitClientState(s);

    for (;;) {
        unsigned char pduType;
        unsigned int pduLen;
        unsigned char *payload;

        if (RecvExact(s, g_dicomRecvBuf, 6) != 6) break;
        pduType = g_dicomRecvBuf[0];
        pduLen = ReadBE32(g_dicomRecvBuf, 2);

        if (pduLen > DICOM_RECV_BUF_SIZE - 6) break;
        if (pduLen > 0) {
            if (RecvExact(s, g_dicomRecvBuf + 6, pduLen) != (int)pduLen) break;
        }

        payload = g_dicomRecvBuf + 6;

        if (pduType == 0x01) {
            DICOM_SendAssociateAC(s, payload, pduLen);
        } else if (pduType == 0x04) {
            ProcessPDataPDU(s, payload, pduLen);
        } else if (pduType == 0x05) {
            send(s, (const char *)releaseRsp, sizeof(releaseRsp), 0);
            break;
        }
    }

    CloseStorageFile();
}

/* ===================== Socket server ===================== */

static void SetNonBlocking(SOCKET s) {
    u_long mode = 1;
    ioctlsocket(s, FIONBIO, &mode);
}

static void SetBlocking(SOCKET s) {
    u_long mode = 0;
    ioctlsocket(s, FIONBIO, &mode);
}

static int StartDicomServer(void) {
    struct sockaddr_in sin;
    char log[160];

    g_dicomListenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (g_dicomListenSock == INVALID_SOCKET) {
        sprintf(log, "ERROR: socket failed for DICOM port %u", g_DicomPort);
        LogText(log);
        return 0;
    }

    memset(&sin, 0, sizeof(sin));
    sin.sin_family      = AF_INET;
    sin.sin_port        = htons((u_short)g_DicomPort);
    sin.sin_addr.s_addr = INADDR_ANY;

    if (bind(g_dicomListenSock, (struct sockaddr *)&sin, sizeof(sin)) == SOCKET_ERROR ||
        listen(g_dicomListenSock, SOMAXCONN) == SOCKET_ERROR) {
        sprintf(log, "ERROR: Failed to listen on DICOM port %u", g_DicomPort);
        LogText(log);
        closesocket(g_dicomListenSock);
        g_dicomListenSock = INVALID_SOCKET;
        if (g_hStatusLabel) {
            sprintf(log, "Server status: Failed to bind port %u", g_DicomPort);
            SetWindowText(g_hStatusLabel, log);
        }
        return 0;
    }

    SetNonBlocking(g_dicomListenSock);
    sprintf(log, "DICOM SCP listening on port %u", g_DicomPort);
    LogText(log);
    if (g_hStatusLabel) {
        sprintf(log, "Server status: Running on port %u", g_DicomPort);
        SetWindowText(g_hStatusLabel, log);
    }
    return 1;
}

static void PollDicomServer(void) {
    SOCKET s;
    char log[96];

    if (g_dicomListenSock == INVALID_SOCKET) return;
    s = accept(g_dicomListenSock, NULL, NULL);
    if (s == INVALID_SOCKET) return;

    sprintf(log, "DICOM client connected (socket %u)", (unsigned)s);
    LogText(log);
    SetBlocking(s);
    HandleDicomClient(s);
    closesocket(s);
    sprintf(log, "DICOM client disconnected (socket %u)", (unsigned)s);
    LogText(log);
}

static void ServerStart(void) {
    if (g_bRunning) return;
    if (!StartDicomServer()) return;
    g_bRunning = 1;
    LogText("Server STARTED");
    if (g_hMenu)
        ModifyMenu(g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND | MF_STRING,
                   ID_TRAY_TOGGLE, szMenuStop);
}

static void ServerStop(void) {
    if (!g_bRunning) return;
    if (g_dicomListenSock != INVALID_SOCKET) {
        closesocket(g_dicomListenSock);
        g_dicomListenSock = INVALID_SOCKET;
    }
    g_bRunning = 0;
    LogText("Server STOPPED");
    if (g_hStatusLabel) SetWindowText(g_hStatusLabel, "Server status: Stopped");
    if (g_hMenu)
        ModifyMenu(g_hMenu, ID_TRAY_TOGGLE, MF_BYCOMMAND | MF_STRING,
                   ID_TRAY_TOGGLE, szMenuStart);
}

static void ServerLoop(void) {
    MSG msg;
    while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    if (!g_bRunning) return;
    PollDicomServer();
}

/* ===================== Settings dialog ===================== */

static LRESULT CALLBACK SettingsProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    if (uMsg == WM_COMMAND) {
        WORD cmd = LOWORD(wParam);
        if (cmd == ID_BTN_CLOSE) {
            DestroyWindow(hWnd);
            g_hSettingsWnd = 0;
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
            return 0;
        }
        if (cmd == ID_BTN_SAVE) {
            char buf[64];
            UINT newPort;
            UINT newDebug;
            GetDlgItemText(hWnd, ID_EDIT_AET, buf, sizeof(buf));
            set_ae_title(g_aeCalled, buf);
            WritePrivateProfileString("Server", "AETitle", buf, szIniFile);

            newPort = GetDlgItemInt(hWnd, ID_EDIT_PORT, NULL, FALSE);
            sprintf(buf, "%u", newPort);
            WritePrivateProfileString("Server", "DicomPort", buf, szIniFile);
            g_DicomPort = newPort;

            newDebug = IsDlgButtonChecked(hWnd, ID_CHK_DEBUG) ? 1 : 0;
            g_DebugLog = newDebug;
            sprintf(buf, "%u", newDebug);
            WritePrivateProfileString("Server", "DebugLog", buf, szIniFile);
            return 0;
        }
    } else if (uMsg == WM_CLOSE) {
        DestroyWindow(hWnd);
        g_hSettingsWnd = 0;
        return 0;
    }
    return DefWindowProc(hWnd, uMsg, wParam, lParam);
}

static void CreateSettingsClass(void) {
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

static void ShowSettings(void) {
    HWND h;
    char portStr[16];

    if (g_hSettingsWnd) {
        SetForegroundWindow(g_hSettingsWnd);
        return;
    }

    h = CreateWindowEx(0, szSettingsClass, "Settings",
        WS_OVERLAPPED | WS_SYSMENU | WS_CAPTION | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT, 460, 200, NULL, NULL, g_hInstance, NULL);
    g_hSettingsWnd = h;

    CreateWindowEx(0, "STATIC", "Server AET:",
        WS_CHILD | WS_VISIBLE, 10, 10, 100, 20, h, 0, g_hInstance, NULL);
    CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", g_aeCalled,
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 120, 10, 120, 22, h,
        (HMENU)ID_EDIT_AET, g_hInstance, NULL);

    CreateWindowEx(0, "STATIC", "DICOM Port:",
        WS_CHILD | WS_VISIBLE, 260, 10, 80, 20, h, 0, g_hInstance, NULL);
    sprintf(portStr, "%u", g_DicomPort);
    CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", portStr,
        WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_NUMBER, 340, 10, 80, 22, h,
        (HMENU)ID_EDIT_PORT, g_hInstance, NULL);

    CreateWindowEx(0, "STATIC", "Debug Logging:",
        WS_CHILD | WS_VISIBLE, 10, 40, 100, 20, h, 0, g_hInstance, NULL);
    CreateWindowEx(0, "BUTTON", "Enabled",
        WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 120, 40, 80, 20, h,
        (HMENU)ID_CHK_DEBUG, g_hInstance, NULL);
    if (g_DebugLog) CheckDlgButton(h, ID_CHK_DEBUG, BST_CHECKED);

    CreateWindowEx(0, "BUTTON", g_bRunning ? szMenuStop : szMenuStart,
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 10, 100, 100, 30, h,
        (HMENU)ID_BTN_STARTSTOP, g_hInstance, NULL);
    CreateWindowEx(0, "BUTTON", "Save Settings",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 200, 100, 100, 30, h,
        (HMENU)ID_BTN_SAVE, g_hInstance, NULL);
    CreateWindowEx(0, "BUTTON", "Close",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 320, 100, 100, 30, h,
        (HMENU)ID_BTN_CLOSE, g_hInstance, NULL);
}

/* ===================== Main window + tray ===================== */

static LRESULT CALLBACK MainProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    POINT pt;

    if (uMsg == WM_CREATE) {
        g_hStatusLabel = CreateWindowEx(0, "STATIC", "Server status: Stopped",
            WS_CHILD | WS_VISIBLE | SS_LEFT,
            10, 10, 500, 20, hWnd, 0, g_hInstance, NULL);
        CreateWindowEx(0, "STATIC", "Log:",
            WS_CHILD | WS_VISIBLE | SS_LEFT,
            10, 60, 50, 20, hWnd, 0, g_hInstance, NULL);
        g_hLogEdit = CreateWindowEx(WS_EX_CLIENTEDGE, "EDIT", NULL,
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL,
            10, 85, 680, 280, hWnd, 0, g_hInstance, NULL);
        return 0;
    }
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
            return 0;
        }
        if (cmd == ID_TRAY_SETTINGS) { ShowSettings(); return 0; }
        if (cmd == ID_TRAY_SHOW) {
            ShowWindow(hWnd, SW_SHOW);
            SetForegroundWindow(hWnd);
            return 0;
        }
        if (cmd == ID_TRAY_EXIT) {
            ServerStop();
            Shell_NotifyIcon(NIM_DELETE, &g_nid);
            PostQuitMessage(0);
            return 0;
        }
    }
    if (uMsg == WM_CLOSE) {
        ShowWindow(hWnd, SW_HIDE);
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

static void CreateTray(void) {
    WNDCLASSEX wc;
    g_hInstance = GetModuleHandle(NULL);

    memset(&wc, 0, sizeof(wc));
    wc.cbSize        = sizeof(WNDCLASSEX);
    wc.lpfnWndProc   = MainProc;
    wc.hInstance     = g_hInstance;
    wc.hIcon         = LoadIcon(NULL, IDI_APPLICATION);
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = szWndClass;
    RegisterClassEx(&wc);

    CreateSettingsClass();

    g_hMainWnd = CreateWindowEx(0, szWndClass, "PACS SCP Storage Server",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 720, 420,
        NULL, NULL, g_hInstance, NULL);
    ShowWindow(g_hMainWnd, SW_HIDE);

    g_hMenu = CreatePopupMenu();
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_TOGGLE,
               g_bRunning ? szMenuStop : szMenuStart);
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_SETTINGS, "Settings");
    AppendMenu(g_hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_SHOW,     "Show Console");
    AppendMenu(g_hMenu, MF_SEPARATOR, 0, NULL);
    AppendMenu(g_hMenu, MF_STRING,    ID_TRAY_EXIT,     "Exit");

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
    char log[300];

    LogText("PACS SCP Storage Server starting...");
    LoadConfig();
    sprintf(log, "Config: AET=%s DicomPort=%u DebugLog=%u Folder=%u File=%u",
            g_aeCalled, g_DicomPort, g_DebugLog,
            g_CurrentFolderIndex, g_CurrentFileIndex);
    LogText(log);

    WSAStartup(MAKEWORD(2, 2), &wsa);
    CreateTray();
    ServerStart();

    for (;;) {
        ServerLoop();
        if (PeekMessage(&qmsg, NULL, WM_QUIT, WM_QUIT, PM_NOREMOVE)) break;
        Sleep(10);
    }

    ServerStop();
    WSACleanup();
    return 0;
}