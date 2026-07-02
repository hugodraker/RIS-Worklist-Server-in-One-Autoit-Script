/*
 * PACS-MANAGER.c
 * Win32 process control launcher.
 *   - Reads/writes PACS-MANAGER.ini next to the EXE
 *   - Dynamic rows from Row1..RowN
 *   - 3 columns, 4:1:1 width ratio, resizable & maximizable
 *   - Column 1 is a clickable label that toggles Start/Stop
 *   - Start uses the FULL path from Process= verbatim
 *   - Stop kills every process whose EXE basename matches
 *     the configured basename, case-insensitive, regardless of path
 *   - Flat Edit menu: row entries + Add Row + Exit
 *   - Edit window: 3 Name/Description pairs + Browse + Auto-Start + Save/Delete/Cancel
 *   - First two rows cannot be deleted
 *   - Window size and position are saved to [Window] in the INI on exit
 *   - No popup messages on errors (silent by design)
 *
 * NEW: Watchdog timer
 *   - Monitors Row1 and Row2 only.
 *   - If the user had a row running (g_wantRunning=1) and the process
 *     disappears, it is relaunched from Process= verbatim.
 *   - Per-row cool-down avoids relaunch storms.
 *   - Config in [Watchdog]:
 *        Enabled=1
 *        CooldownMs=5000
 *
 * Build:
 *   MinGW-w64:
 *     gcc -O2 -mwindows -o PACS-MANAGER.exe PACS-MANAGER.c -lcomdlg32 -lshell32 -ladvapi32
 *   MSVC (Developer Command Prompt):
 *     cl /O2 /W3 PACS-MANAGER.c /link /SUBSYSTEM:WINDOWS ^
 *        user32.lib gdi32.lib comdlg32.lib shell32.lib advapi32.lib
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commdlg.h>
#include <shellapi.h>
#include <tlhelp32.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>

/* ------------------------------------------------------------------ */
/* Configuration                                                       */
/* ------------------------------------------------------------------ */

#define MAX_ROWS            32

#define ID_LBL_BASE         2000
#define ID_BTNA_BASE        3000
#define ID_BTNB_BASE        4000
#define ID_MENU_BASE        5000

#define IDM_ADDROW          9001
#define IDM_EXIT            9002

#define TIMER_ID            1
#define TIMER_MS            800

#define WAIT_TIMEOUT_MS     3000
#define WAIT_POLL_MS        100

#define GAP                 10
#define Y_TOP               12
#define X_PAD               40
#define MIN_COL_U           24
#define COL_U_DEF           80
#define BTN_H_DEF           32
#define BTN_H_MIN           24
#define BTN_H_MAX           120

/* Watchdog defaults */
#define WATCHDOG_ROWS       2       /* monitor Row1 and Row2 only     */
#define WD_COOLDOWN_DEF_MS  5000

#define CLR_RUN_RGB         RGB(0x66, 0xCC, 0x66)
#define CLR_STOP_RGB        RGB(0xE0, 0x70, 0x70)
#define CLR_NONE_RGB        RGB(0xF0, 0xF0, 0xF0)

typedef enum { RS_NONE = 0, RS_RUN = 1, RS_STOP = 2 } RowState;

typedef struct {
    char szName[128];
    char szProcess[260];
    int  bAutoStart;
    char szNameA[128];
    char szTargetA[260];
    char szNameB[128];
    char szTargetB[260];
} ROW;

/* Edit window control IDs */
enum {
    IDE_NAME0 = 100, IDE_DESC0, IDE_BROW0,
    IDE_NAME1 = 110, IDE_DESC1, IDE_BROW1,
    IDE_NAME2 = 120, IDE_DESC2, IDE_BROW2,
    IDE_AUTO  = 130,
    IDE_SAVE  = 200, IDE_DEL,   IDE_CANCEL
};

/* Runtime-loaded Toolhelp32 signatures */
typedef HANDLE (WINAPI *PFN_CreateToolhelp32Snapshot)(DWORD, DWORD);
typedef BOOL   (WINAPI *PFN_Process32First)(HANDLE, LPPROCESSENTRY32);
typedef BOOL   (WINAPI *PFN_Process32Next) (HANDLE, LPPROCESSENTRY32);

/* ------------------------------------------------------------------ */
/* Globals                                                             */
/* ------------------------------------------------------------------ */

static HINSTANCE g_hInst       = NULL;
static HWND      g_hMain       = NULL;
static HWND      g_hEditWnd    = NULL;
static HMENU     g_hEditMenu   = NULL;
static HFONT     g_hFont       = NULL;

static HBRUSH    g_hbrRun      = NULL;
static HBRUSH    g_hbrStop     = NULL;
static HBRUSH    g_hbrNone     = NULL;

static char      g_iniPath[MAX_PATH] = {0};

static ROW       g_rows[MAX_ROWS];
static int       g_nRows = 0;
static RowState  g_rowState[MAX_ROWS];

/* Watchdog runtime state */
static int       g_wantRunning[MAX_ROWS]     = {0};
static DWORD     g_lastRelaunchTick[MAX_ROWS] = {0};
static int       g_wdEnabled                 = 1;
static DWORD     g_wdCooldownMs              = WD_COOLDOWN_DEF_MS;

static int       g_editRow = -1;
static HWND      g_edName[3] = {0};
static HWND      g_edDesc[3] = {0};
static HWND      g_edBrow[3] = {0};
static HWND      g_hEdAuto   = NULL;
static HWND      g_hEdSave   = NULL;
static HWND      g_hEdDel    = NULL;
static HWND      g_hEdCancel = NULL;

static const char kClassMain[] = "PACSManagerWnd";
static const char kClassEdit[] = "PACSManagerEditWnd";

static PFN_CreateToolhelp32Snapshot pCreateToolhelp32Snapshot = NULL;
static PFN_Process32First           pProcess32First           = NULL;
static PFN_Process32Next            pProcess32Next            = NULL;

/* ------------------------------------------------------------------ */
/* Runtime Toolhelp loader                                             */
/* ------------------------------------------------------------------ */

static void init_toolhelp(void)
{
    HMODULE hK32 = GetModuleHandleA("kernel32.dll");
    if (!hK32) hK32 = LoadLibraryA("kernel32.dll");
    if (!hK32) return;

    pCreateToolhelp32Snapshot =
        (PFN_CreateToolhelp32Snapshot)GetProcAddress(hK32, "CreateToolhelp32Snapshot");

    pProcess32First = (PFN_Process32First)GetProcAddress(hK32, "Process32First");
    if (!pProcess32First)
        pProcess32First = (PFN_Process32First)GetProcAddress(hK32, "Process32FirstA");

    pProcess32Next = (PFN_Process32Next)GetProcAddress(hK32, "Process32Next");
    if (!pProcess32Next)
        pProcess32Next = (PFN_Process32Next)GetProcAddress(hK32, "Process32NextA");
}

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

static void str_lower(char *s)
{
    for (; *s; ++s) {
        if (*s >= 'A' && *s <= 'Z')
            *s = (char)(*s + 32);
    }
}

static void strip_quotes_trim(char *s)
{
    if (!s) return;
    size_t n = strlen(s);
    while (n > 0) {
        char c = s[n - 1];
        if (c == ' ' || c == '\t' || c == '"' || c == '\r' || c == '\n') {
            s[--n] = 0;
        } else break;
    }
    size_t lead = 0;
    while (s[lead] == ' ' || s[lead] == '\t' || s[lead] == '"')
        lead++;
    if (lead) {
        memmove(s, s + lead, strlen(s + lead) + 1);
    }
}

static void get_exe_basename(const char *path, char *out, size_t outsz)
{
    char tmp[MAX_PATH];
    if (!path || !out || outsz == 0) {
        if (out && outsz) out[0] = 0;
        return;
    }
    lstrcpynA(tmp, path, sizeof(tmp));
    strip_quotes_trim(tmp);

    const char *base = tmp;
    const char *p;
    for (p = tmp; *p; ++p) {
        if (*p == '\\' || *p == '/') base = p + 1;
    }
    lstrcpynA(out, base, (int)outsz);
    str_lower(out);
}

/* ------------------------------------------------------------------ */
/* INI                                                                 */
/* ------------------------------------------------------------------ */

static void resolve_ini_path(void)
{
    GetModuleFileNameA(NULL, g_iniPath, sizeof(g_iniPath));
    char *dot   = strrchr(g_iniPath, '.');
    char *slash = strrchr(g_iniPath, '\\');
    if (dot && (!slash || dot > slash)) {
        *dot = 0;
    }
    lstrcatA(g_iniPath, ".ini");
}

static void write_one_row(const char *sec,
                          const char *n, const char *p, int autoStart,
                          const char *nA, const char *tA,
                          const char *nB, const char *tB)
{
    WritePrivateProfileStringA(sec, "Name",      n,  g_iniPath);
    WritePrivateProfileStringA(sec, "Process",   p,  g_iniPath);
    WritePrivateProfileStringA(sec, "AutoStart", autoStart ? "1" : "0", g_iniPath);
    WritePrivateProfileStringA(sec, "NameA",     nA, g_iniPath);
    WritePrivateProfileStringA(sec, "TargetA",   tA, g_iniPath);
    WritePrivateProfileStringA(sec, "NameB",     nB, g_iniPath);
    WritePrivateProfileStringA(sec, "TargetB",   tB, g_iniPath);
}

static void ensure_default_ini(void)
{
    DWORD attrs = GetFileAttributesA(g_iniPath);
    if (attrs != INVALID_FILE_ATTRIBUTES) return;

    write_one_row("Row1", "PACS Server", "", 0, "NameA", "", "NameB", "");
    write_one_row("Row2", "Worklist",    "", 0, "NameA", "", "NameB", "");

    WritePrivateProfileStringA("Window",   "X",          "-1",   g_iniPath);
    WritePrivateProfileStringA("Window",   "Y",          "-1",   g_iniPath);
    WritePrivateProfileStringA("Window",   "W",          "560",  g_iniPath);
    WritePrivateProfileStringA("Window",   "H",          "260",  g_iniPath);
    WritePrivateProfileStringA("Watchdog", "Enabled",    "1",    g_iniPath);
    WritePrivateProfileStringA("Watchdog", "CooldownMs", "5000", g_iniPath);
}

static void load_watchdog_from_ini(void)
{
    g_wdEnabled    = GetPrivateProfileIntA("Watchdog", "Enabled",    1,                     g_iniPath) ? 1 : 0;
    g_wdCooldownMs = (DWORD)GetPrivateProfileIntA("Watchdog", "CooldownMs", WD_COOLDOWN_DEF_MS, g_iniPath);
    if (g_wdCooldownMs < 500)   g_wdCooldownMs = 500;
    if (g_wdCooldownMs > 600000) g_wdCooldownMs = 600000;
}

static void load_rows_from_ini(void)
{
    memset(g_rows, 0, sizeof(g_rows));
    g_nRows = 0;

    for (int i = 1; i <= MAX_ROWS; ++i) {
        char sec[32];
        wsprintfA(sec, "Row%d", i);
        char name[128] = {0};
        GetPrivateProfileStringA(sec, "Name", "", name, sizeof(name), g_iniPath);
        if (!name[0]) break;

        ROW *r = &g_rows[g_nRows];
        lstrcpynA(r->szName, name, sizeof(r->szName));
        GetPrivateProfileStringA(sec, "Process", "", r->szProcess, sizeof(r->szProcess), g_iniPath);
        r->bAutoStart = GetPrivateProfileIntA(sec, "AutoStart", 0, g_iniPath) ? 1 : 0;
        GetPrivateProfileStringA(sec, "NameA",   "", r->szNameA,   sizeof(r->szNameA),   g_iniPath);
        GetPrivateProfileStringA(sec, "TargetA", "", r->szTargetA, sizeof(r->szTargetA), g_iniPath);
        GetPrivateProfileStringA(sec, "NameB",   "", r->szNameB,   sizeof(r->szNameB),   g_iniPath);
        GetPrivateProfileStringA(sec, "TargetB", "", r->szTargetB, sizeof(r->szTargetB), g_iniPath);
        g_nRows++;
    }

    for (int i = 0; i < MAX_ROWS; ++i) {
        g_rowState[i]         = RS_NONE;
        g_wantRunning[i]      = 0;
        g_lastRelaunchTick[i] = 0;
    }
}

static void save_rows_to_ini(void)
{
    for (int i = 1; i <= MAX_ROWS; ++i) {
        char sec[32];
        wsprintfA(sec, "Row%d", i);
        WritePrivateProfileStringA(sec, NULL, NULL, g_iniPath);
    }
    for (int i = 0; i < g_nRows; ++i) {
        char sec[32];
        wsprintfA(sec, "Row%d", i + 1);
        ROW *r = &g_rows[i];
        write_one_row(sec,
                      r->szName, r->szProcess, r->bAutoStart,
                      r->szNameA, r->szTargetA,
                      r->szNameB, r->szTargetB);
    }
}

static void save_window_placement(void)
{
    if (!g_hMain) return;

    WINDOWPLACEMENT wp;
    memset(&wp, 0, sizeof(wp));
    wp.length = sizeof(wp);
    if (!GetWindowPlacement(g_hMain, &wp)) return;

    RECT r = wp.rcNormalPosition;
    char buf[32];

    wsprintfA(buf, "%ld", r.left);         WritePrivateProfileStringA("Window", "X", buf, g_iniPath);
    wsprintfA(buf, "%ld", r.top);          WritePrivateProfileStringA("Window", "Y", buf, g_iniPath);
    wsprintfA(buf, "%ld", r.right - r.left);  WritePrivateProfileStringA("Window", "W", buf, g_iniPath);
    wsprintfA(buf, "%ld", r.bottom - r.top);  WritePrivateProfileStringA("Window", "H", buf, g_iniPath);

    WritePrivateProfileStringA("Watchdog", "Enabled",
                               g_wdEnabled ? "1" : "0", g_iniPath);
    wsprintfA(buf, "%lu", g_wdCooldownMs);
    WritePrivateProfileStringA("Watchdog", "CooldownMs", buf, g_iniPath);
}

/* ------------------------------------------------------------------ */
/* Process detection / control                                         */
/* ------------------------------------------------------------------ */

static int is_process_running(const char *exeLower)
{
    if (!exeLower || !exeLower[0]) return 0;
    if (!pCreateToolhelp32Snapshot || !pProcess32First || !pProcess32Next)
        return 0;

    HANDLE snap = pCreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32 pe;
    memset(&pe, 0, sizeof(pe));
    pe.dwSize = sizeof(pe);

    int found = 0;
    if (pProcess32First(snap, &pe)) {
        do {
            char nm[MAX_PATH];
            lstrcpynA(nm, pe.szExeFile, sizeof(nm));
            str_lower(nm);
            if (lstrcmpA(nm, exeLower) == 0) { found = 1; break; }
        } while (pProcess32Next(snap, &pe));
    }
    CloseHandle(snap);
    return found;
}

static void stop_process_by_name(const char *exeLower)
{
    if (!exeLower || !exeLower[0]) return;
    if (!pCreateToolhelp32Snapshot || !pProcess32First || !pProcess32Next)
        return;

    HANDLE snap = pCreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) return;

    PROCESSENTRY32 pe;
    memset(&pe, 0, sizeof(pe));
    pe.dwSize = sizeof(pe);

    if (pProcess32First(snap, &pe)) {
        do {
            char nm[MAX_PATH];
            lstrcpynA(nm, pe.szExeFile, sizeof(nm));
            str_lower(nm);
            if (lstrcmpA(nm, exeLower) == 0) {
                HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, pe.th32ProcessID);
                if (h) {
                    TerminateProcess(h, 0);
                    CloseHandle(h);
                }
            }
        } while (pProcess32Next(snap, &pe));
    }
    CloseHandle(snap);
}

static void start_process_by_path(const char *fullPath)
{
    if (!fullPath || !fullPath[0]) return;

    char clean[MAX_PATH];
    lstrcpynA(clean, fullPath, sizeof(clean));
    strip_quotes_trim(clean);
    if (!clean[0]) return;

    char dir[MAX_PATH] = {0};
    lstrcpynA(dir, clean, sizeof(dir));
    char *slash = strrchr(dir, '\\');
    if (!slash) slash = strrchr(dir, '/');
    if (slash) *slash = 0; else dir[0] = 0;

    STARTUPINFOA si;
    PROCESS_INFORMATION pi;
    memset(&si, 0, sizeof(si));
    memset(&pi, 0, sizeof(pi));
    si.cb = sizeof(si);

    char cmd[MAX_PATH + 4];
    wsprintfA(cmd, "\"%s\"", clean);

    if (CreateProcessA(NULL, cmd, NULL, NULL, FALSE,
                       0, NULL, dir[0] ? dir : NULL, &si, &pi)) {
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
}

static void wait_process_state(const char *exeLower, int wantAppear, int ms)
{
    if (!exeLower || !exeLower[0]) return;
    int elapsed = 0;
    while (elapsed < ms) {
        int running = is_process_running(exeLower);
        if ((wantAppear && running) || (!wantAppear && !running))
            return;
        Sleep(WAIT_POLL_MS);
        elapsed += WAIT_POLL_MS;
    }
}

/* ------------------------------------------------------------------ */
/* Watchdog                                                            */
/* ------------------------------------------------------------------ */

static void watchdog_tick(void)
{
    if (!g_wdEnabled) return;

    DWORD now = GetTickCount();
    int nWatch = g_nRows < WATCHDOG_ROWS ? g_nRows : WATCHDOG_ROWS;

    for (int i = 0; i < nWatch; ++i) {
        ROW *r = &g_rows[i];
        if (!g_wantRunning[i])   continue;
        if (!r->szProcess[0])    continue;

        char base[MAX_PATH];
        get_exe_basename(r->szProcess, base, sizeof(base));
        if (!base[0]) continue;

        if (is_process_running(base)) continue;

        /* Cool-down */
        DWORD last = g_lastRelaunchTick[i];
        if (last != 0 && (now - last) < g_wdCooldownMs) continue;

        g_lastRelaunchTick[i] = now ? now : 1;
        start_process_by_path(r->szProcess);
    }
}

/* ------------------------------------------------------------------ */
/* Layout                                                              */
/* ------------------------------------------------------------------ */

static void layout_buttons(void)
{
    if (!g_hMain || g_nRows <= 0) return;

    RECT rc;
    GetClientRect(g_hMain, &rc);
    int W = rc.right - rc.left;
    int H = rc.bottom - rc.top;

    int avail = W - 2 * X_PAD - 2 * GAP;
    if (avail < 6 * MIN_COL_U) avail = 6 * MIN_COL_U;

    int unit = avail / 6;
    if (unit < MIN_COL_U) unit = MIN_COL_U;

    int colLbl = 4 * unit;
    int colA   = unit;
    int colB   = unit;

    int rowH = (H - Y_TOP - GAP) / g_nRows - GAP;
    if (rowH < BTN_H_MIN) rowH = BTN_H_MIN;
    if (rowH > BTN_H_MAX) rowH = BTN_H_MAX;
    if (rowH < BTN_H_DEF) rowH = BTN_H_DEF;

    int y = Y_TOP;
    for (int i = 0; i < g_nRows; ++i) {
        int x = X_PAD;
        HWND h;
        if ((h = GetDlgItem(g_hMain, ID_LBL_BASE  + i)) != NULL)
            MoveWindow(h, x, y, colLbl, rowH, TRUE);
        x += colLbl + GAP;
        if ((h = GetDlgItem(g_hMain, ID_BTNA_BASE + i)) != NULL)
            MoveWindow(h, x, y, colA, rowH, TRUE);
        x += colA + GAP;
        if ((h = GetDlgItem(g_hMain, ID_BTNB_BASE + i)) != NULL)
            MoveWindow(h, x, y, colB, rowH, TRUE);
        y += rowH + GAP;
    }
}

/* ------------------------------------------------------------------ */
/* Row refresh                                                         */
/* ------------------------------------------------------------------ */

static void refresh_row(int i)
{
    if (i < 0 || i >= g_nRows) return;
    HWND hLbl = GetDlgItem(g_hMain, ID_LBL_BASE + i);
    if (!hLbl) return;

    ROW *r = &g_rows[i];
    char base[MAX_PATH];
    get_exe_basename(r->szProcess, base, sizeof(base));

    RowState st = RS_NONE;
    if (base[0])
        st = is_process_running(base) ? RS_RUN : RS_STOP;

    g_rowState[i] = st;

    char label[256];
    const char *tag =
        (st == RS_RUN)  ? "[RUN] " :
        (st == RS_STOP) ? "[STOP] " : "";
    wsprintfA(label, "%s%s", tag, r->szName[0] ? r->szName : "(unnamed)");
    SetWindowTextA(hLbl, label);
    InvalidateRect(hLbl, NULL, TRUE);
}

static void refresh_all_rows(void)
{
    for (int i = 0; i < g_nRows; ++i)
        refresh_row(i);
}

/* ------------------------------------------------------------------ */
/* Auto start                                                          */
/* ------------------------------------------------------------------ */

static void auto_start_rows(void)
{
    for (int i = 0; i < g_nRows; ++i) {
        ROW *r = &g_rows[i];
        if (!r->bAutoStart || !r->szProcess[0]) continue;

        char base[MAX_PATH];
        get_exe_basename(r->szProcess, base, sizeof(base));
        if (!is_process_running(base))
            start_process_by_path(r->szProcess);

        if (i < WATCHDOG_ROWS) g_wantRunning[i] = 1;
    }
}

/* ------------------------------------------------------------------ */
/* Menu                                                                */
/* ------------------------------------------------------------------ */

static void rebuild_edit_menu(void)
{
    if (!g_hEditMenu) return;

    while (GetMenuItemCount(g_hEditMenu) > 0)
        RemoveMenu(g_hEditMenu, 0, MF_BYPOSITION);

    for (int i = 0; i < g_nRows; ++i) {
        char item[160];
        wsprintfA(item, "Row %d: %s", i + 1,
                  g_rows[i].szName[0] ? g_rows[i].szName : "(unnamed)");
        AppendMenuA(g_hEditMenu, MF_STRING, ID_MENU_BASE + i, item);
    }
    AppendMenuA(g_hEditMenu, MF_SEPARATOR, 0, NULL);
    AppendMenuA(g_hEditMenu, MF_STRING, IDM_ADDROW, "Add Row");
    AppendMenuA(g_hEditMenu, MF_STRING, IDM_EXIT,   "Exit");

    DrawMenuBar(g_hMain);
}

/* ------------------------------------------------------------------ */
/* Build / Destroy main controls                                       */
/* ------------------------------------------------------------------ */

static void destroy_main_controls(void)
{
    for (int i = 0; i < MAX_ROWS; ++i) {
        HWND h;
        if ((h = GetDlgItem(g_hMain, ID_LBL_BASE  + i)) != NULL) DestroyWindow(h);
        if ((h = GetDlgItem(g_hMain, ID_BTNA_BASE + i)) != NULL) DestroyWindow(h);
        if ((h = GetDlgItem(g_hMain, ID_BTNB_BASE + i)) != NULL) DestroyWindow(h);
    }
}

static void build_main_controls(void)
{
    for (int i = 0; i < g_nRows; ++i) {
        HWND h;
        h = CreateWindowExA(0, "BUTTON", g_rows[i].szName,
                            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW | BS_NOTIFY,
                            0, 0, 10, 10, g_hMain,
                            (HMENU)(INT_PTR)(ID_LBL_BASE + i), g_hInst, NULL);
        if (h && g_hFont) SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        h = CreateWindowExA(0, "BUTTON",
                            g_rows[i].szNameA[0] ? g_rows[i].szNameA : "A",
                            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                            0, 0, 10, 10, g_hMain,
                            (HMENU)(INT_PTR)(ID_BTNA_BASE + i), g_hInst, NULL);
        if (h && g_hFont) SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        h = CreateWindowExA(0, "BUTTON",
                            g_rows[i].szNameB[0] ? g_rows[i].szNameB : "B",
                            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                            0, 0, 10, 10, g_hMain,
                            (HMENU)(INT_PTR)(ID_BTNB_BASE + i), g_hInst, NULL);
        if (h && g_hFont) SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);
    }
    layout_buttons();
    refresh_all_rows();
}

/* ------------------------------------------------------------------ */
/* Add / Delete row                                                    */
/* ------------------------------------------------------------------ */

static void add_new_row(void)
{
    if (g_nRows >= MAX_ROWS) return;
    ROW *r = &g_rows[g_nRows];
    memset(r, 0, sizeof(*r));
    wsprintfA(r->szName,  "Desc%d",  g_nRows + 1);
    wsprintfA(r->szNameA, "Desc%dA", g_nRows + 1);
    wsprintfA(r->szNameB, "Desc%dB", g_nRows + 1);
    r->bAutoStart = 0;
    g_nRows++;

    save_rows_to_ini();
    destroy_main_controls();
    build_main_controls();
    rebuild_edit_menu();
}

static void delete_row_at(int idx)
{
    if (idx < 2 || idx >= g_nRows) return;
    for (int i = idx; i < g_nRows - 1; ++i) {
        g_rows[i]         = g_rows[i + 1];
        g_wantRunning[i]  = g_wantRunning[i + 1];
    }
    memset(&g_rows[g_nRows - 1], 0, sizeof(ROW));
    g_wantRunning[g_nRows - 1] = 0;
    g_nRows--;

    save_rows_to_ini();
    destroy_main_controls();
    build_main_controls();
    rebuild_edit_menu();
}

/* ------------------------------------------------------------------ */
/* Edit window                                                         */
/* ------------------------------------------------------------------ */

static void do_browse(HWND hParent, HWND hEdit)
{
    char buf[MAX_PATH] = {0};
    OPENFILENAMEA ofn;
    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner   = hParent;
    ofn.lpstrFilter = "All files (*.*)\0*.*\0";
    ofn.lpstrFile   = buf;
    ofn.nMaxFile    = sizeof(buf);
    ofn.Flags       = OFN_FILEMUSTEXIST | OFN_HIDEREADONLY;

    if (GetOpenFileNameA(&ofn))
        SetWindowTextA(hEdit, buf);
}

static void build_edit_controls(HWND hWnd)
{
    HWND h;
    int y = 12;
    const int W_LBL = 90, W_ED = 300, W_BR = 80, H_ROW = 26, GAPY = 8;

    static const char *hdrs[3] = { "Row / Process", "Button A", "Button B" };
    for (int i = 0; i < 3; ++i) {
        CreateWindowExA(0, "STATIC", hdrs[i],
                        WS_CHILD | WS_VISIBLE,
                        12, y, W_LBL, H_ROW, hWnd, NULL, g_hInst, NULL);

        CreateWindowExA(0, "STATIC", "Name:",
                        WS_CHILD | WS_VISIBLE,
                        12, y + H_ROW + GAPY, W_LBL, H_ROW,
                        hWnd, NULL, g_hInst, NULL);
        g_edName[i] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
                        12 + W_LBL, y + H_ROW + GAPY, W_ED, H_ROW, hWnd,
                        (HMENU)(INT_PTR)(IDE_NAME0 + i * 10), g_hInst, NULL);

        CreateWindowExA(0, "STATIC", i == 0 ? "Process:" : "Target:",
                        WS_CHILD | WS_VISIBLE,
                        12, y + 2 * (H_ROW + GAPY), W_LBL, H_ROW,
                        hWnd, NULL, g_hInst, NULL);
        g_edDesc[i] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                        WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL,
                        12 + W_LBL, y + 2 * (H_ROW + GAPY), W_ED, H_ROW, hWnd,
                        (HMENU)(INT_PTR)(IDE_DESC0 + i * 10), g_hInst, NULL);
        g_edBrow[i] = CreateWindowExA(0, "BUTTON", "Browse...",
                        WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                        12 + W_LBL + W_ED + 6, y + 2 * (H_ROW + GAPY),
                        W_BR, H_ROW, hWnd,
                        (HMENU)(INT_PTR)(IDE_BROW0 + i * 10), g_hInst, NULL);

        y += 3 * (H_ROW + GAPY) + 8;

        if (g_hFont) {
            SendMessage(g_edName[i], WM_SETFONT, (WPARAM)g_hFont, TRUE);
            SendMessage(g_edDesc[i], WM_SETFONT, (WPARAM)g_hFont, TRUE);
            SendMessage(g_edBrow[i], WM_SETFONT, (WPARAM)g_hFont, TRUE);
        }
    }

    g_hEdAuto = CreateWindowExA(0, "BUTTON", "Auto-Start",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX,
                    12, y, 140, H_ROW, hWnd,
                    (HMENU)(INT_PTR)IDE_AUTO, g_hInst, NULL);
    y += H_ROW + GAPY;

    g_hEdSave = CreateWindowExA(0, "BUTTON", "Save",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    12, y, 90, H_ROW, hWnd,
                    (HMENU)(INT_PTR)IDE_SAVE, g_hInst, NULL);
    g_hEdDel  = CreateWindowExA(0, "BUTTON", "Delete",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    112, y, 90, H_ROW, hWnd,
                    (HMENU)(INT_PTR)IDE_DEL, g_hInst, NULL);
    g_hEdCancel = CreateWindowExA(0, "BUTTON", "Cancel",
                    WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                    212, y, 90, H_ROW, hWnd,
                    (HMENU)(INT_PTR)IDE_CANCEL, g_hInst, NULL);

    if (g_hFont) {
        SendMessage(g_hEdAuto,   WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_hEdSave,   WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_hEdDel,    WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_hEdCancel, WM_SETFONT, (WPARAM)g_hFont, TRUE);
    }

    if (g_editRow >= 0 && g_editRow < g_nRows) {
        ROW *r = &g_rows[g_editRow];
        SetWindowTextA(g_edName[0], r->szName);
        SetWindowTextA(g_edDesc[0], r->szProcess);
        SetWindowTextA(g_edName[1], r->szNameA);
        SetWindowTextA(g_edDesc[1], r->szTargetA);
        SetWindowTextA(g_edName[2], r->szNameB);
        SetWindowTextA(g_edDesc[2], r->szTargetB);
        SendMessage(g_hEdAuto, BM_SETCHECK,
                    r->bAutoStart ? BST_CHECKED : BST_UNCHECKED, 0);
        if (g_editRow < 2)
            EnableWindow(g_hEdDel, FALSE);
    }
}

static void save_edit_fields(void)
{
    if (g_editRow < 0 || g_editRow >= g_nRows) return;
    ROW *r = &g_rows[g_editRow];
    GetWindowTextA(g_edName[0], r->szName,    sizeof(r->szName));
    GetWindowTextA(g_edDesc[0], r->szProcess, sizeof(r->szProcess));
    GetWindowTextA(g_edName[1], r->szNameA,   sizeof(r->szNameA));
    GetWindowTextA(g_edDesc[1], r->szTargetA, sizeof(r->szTargetA));
    GetWindowTextA(g_edName[2], r->szNameB,   sizeof(r->szNameB));
    GetWindowTextA(g_edDesc[2], r->szTargetB, sizeof(r->szTargetB));
    r->bAutoStart = (SendMessage(g_hEdAuto, BM_GETCHECK, 0, 0) == BST_CHECKED) ? 1 : 0;
    save_rows_to_ini();
}

static LRESULT CALLBACK EditWndProc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE:
        g_hEditWnd = hWnd;
        build_edit_controls(hWnd);
        return 0;

    case WM_COMMAND: {
        WORD id = LOWORD(wp);
        if (id == IDE_BROW0) { do_browse(hWnd, g_edDesc[0]); return 0; }
        if (id == IDE_BROW1) { do_browse(hWnd, g_edDesc[1]); return 0; }
        if (id == IDE_BROW2) { do_browse(hWnd, g_edDesc[2]); return 0; }
        if (id == IDE_SAVE) {
            save_edit_fields();
            destroy_main_controls();
            build_main_controls();
            rebuild_edit_menu();
            DestroyWindow(hWnd);
            return 0;
        }
        if (id == IDE_DEL) {
            if (g_editRow >= 2) delete_row_at(g_editRow);
            DestroyWindow(hWnd);
            return 0;
        }
        if (id == IDE_CANCEL) { DestroyWindow(hWnd); return 0; }
        break;
    }

    case WM_CLOSE:
        DestroyWindow(hWnd);
        return 0;

    case WM_DESTROY:
        g_hEditWnd = NULL;
        g_editRow  = -1;
        return 0;
    }
    return DefWindowProcA(hWnd, msg, wp, lp);
}

static void open_edit_window(int rowIndex)
{
    if (rowIndex < 0 || rowIndex >= g_nRows) return;
    g_editRow = rowIndex;

    WNDCLASSA wc;
    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc   = EditWndProc;
    wc.hInstance     = g_hInst;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = kClassEdit;
    RegisterClassA(&wc);

    char title[160];
    wsprintfA(title, "Edit Row %d", rowIndex + 1);
    HWND hWnd = CreateWindowExA(0, kClassEdit, title,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        CW_USEDEFAULT, CW_USEDEFAULT, 520, 380,
        g_hMain, NULL, g_hInst, NULL);
    if (!hWnd) return;
    ShowWindow(hWnd, SW_SHOW);
    UpdateWindow(hWnd);
}

/* ------------------------------------------------------------------ */
/* Main window procedure                                               */
/* ------------------------------------------------------------------ */

static void handle_label_click(int i)
{
    if (i < 0 || i >= g_nRows) return;
    ROW *r = &g_rows[i];
    if (!r->szProcess[0]) return;

    char base[MAX_PATH];
    get_exe_basename(r->szProcess, base, sizeof(base));
    if (!base[0]) return;

    if (is_process_running(base)) {
        stop_process_by_name(base);
        wait_process_state(base, 0, WAIT_TIMEOUT_MS);
        if (i < WATCHDOG_ROWS) {
            g_wantRunning[i]      = 0;
            g_lastRelaunchTick[i] = 0;
        }
    } else {
        start_process_by_path(r->szProcess);
        wait_process_state(base, 1, WAIT_TIMEOUT_MS);
        if (i < WATCHDOG_ROWS) {
            g_wantRunning[i]      = 1;
            g_lastRelaunchTick[i] = GetTickCount();
        }
    }
    refresh_row(i);
}

static void handle_action_button(int idx, int isA)
{
    if (idx < 0 || idx >= g_nRows) return;
    ROW *r = &g_rows[idx];
    const char *target = isA ? r->szTargetA : r->szTargetB;
    if (!target || !target[0]) return;

    ShellExecuteA(g_hMain, "open", target, NULL, NULL, SW_SHOWNORMAL);
}

static LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE: {
        g_hMain = hWnd;

        g_hFont = CreateFontA(-14, 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                              DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                              CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                              DEFAULT_PITCH | FF_SWISS, "Segoe UI");

        g_hbrRun  = CreateSolidBrush(CLR_RUN_RGB);
        g_hbrStop = CreateSolidBrush(CLR_STOP_RGB);
        g_hbrNone = CreateSolidBrush(CLR_NONE_RGB);

        HMENU hMenuBar = CreateMenu();
        g_hEditMenu    = CreatePopupMenu();
        AppendMenuA(hMenuBar, MF_POPUP, (UINT_PTR)g_hEditMenu, "Edit");
        SetMenu(hWnd, hMenuBar);

        build_main_controls();
        rebuild_edit_menu();

        SetTimer(hWnd, TIMER_ID, TIMER_MS, NULL);
        auto_start_rows();
        return 0;
    }

    case WM_SIZE:
        layout_buttons();
        return 0;

    case WM_TIMER:
        if (wp == TIMER_ID) {
            watchdog_tick();
            refresh_all_rows();
        }
        return 0;

    case WM_DRAWITEM: {
        LPDRAWITEMSTRUCT dis = (LPDRAWITEMSTRUCT)lp;
        int id  = (int)wp;
        int idx = -1;
        if (id >= ID_LBL_BASE && id < ID_LBL_BASE + MAX_ROWS)
            idx = id - ID_LBL_BASE;
        if (idx < 0 || idx >= g_nRows) break;

        HBRUSH br = g_hbrNone;
        if (g_rowState[idx] == RS_RUN)  br = g_hbrRun;
        if (g_rowState[idx] == RS_STOP) br = g_hbrStop;
        FillRect(dis->hDC, &dis->rcItem, br);

        SetBkMode(dis->hDC, TRANSPARENT);
        char buf[256];
        GetWindowTextA(dis->hwndItem, buf, sizeof(buf));
        DrawTextA(dis->hDC, buf, -1, &dis->rcItem,
                  DT_CENTER | DT_VCENTER | DT_SINGLELINE);

        if (dis->itemState & ODS_FOCUS)
            DrawFocusRect(dis->hDC, &dis->rcItem);
        return TRUE;
    }

    case WM_COMMAND: {
        WORD id   = LOWORD(wp);
        WORD code = HIWORD(wp);

        if (id >= ID_LBL_BASE && id < ID_LBL_BASE + MAX_ROWS) {
            if (code == BN_CLICKED) handle_label_click(id - ID_LBL_BASE);
            return 0;
        }
        if (id >= ID_BTNA_BASE && id < ID_BTNA_BASE + MAX_ROWS) {
            handle_action_button(id - ID_BTNA_BASE, 1);
            return 0;
        }
        if (id >= ID_BTNB_BASE && id < ID_BTNB_BASE + MAX_ROWS) {
            handle_action_button(id - ID_BTNB_BASE, 0);
            return 0;
        }
        if (id >= ID_MENU_BASE && id < ID_MENU_BASE + MAX_ROWS) {
            open_edit_window(id - ID_MENU_BASE);
            return 0;
        }
        if (id == IDM_ADDROW) { add_new_row(); return 0; }
        if (id == IDM_EXIT)   { DestroyWindow(hWnd); return 0; }
        break;
    }

    case WM_CLOSE:
        DestroyWindow(hWnd);
        return 0;

    case WM_DESTROY:
        save_window_placement();
        KillTimer(hWnd, TIMER_ID);
        if (g_hFont)  { DeleteObject(g_hFont);  g_hFont  = NULL; }
        if (g_hbrRun) { DeleteObject(g_hbrRun); g_hbrRun = NULL; }
        if (g_hbrStop){ DeleteObject(g_hbrStop);g_hbrStop= NULL; }
        if (g_hbrNone){ DeleteObject(g_hbrNone);g_hbrNone= NULL; }
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(hWnd, msg, wp, lp);
}

/* ------------------------------------------------------------------ */
/* WinMain                                                             */
/* ------------------------------------------------------------------ */

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow)
{
    (void)hPrev;
    (void)lpCmd;
    g_hInst = hInst;

    init_toolhelp();
    resolve_ini_path();
    ensure_default_ini();
    load_rows_from_ini();
    load_watchdog_from_ini();

    WNDCLASSA wc;
    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = kClassMain;
    if (!RegisterClassA(&wc)) return 0;

    int x = GetPrivateProfileIntA("Window", "X", -1,  g_iniPath);
    int y = GetPrivateProfileIntA("Window", "Y", -1,  g_iniPath);
    int w = GetPrivateProfileIntA("Window", "W", 560, g_iniPath);
    int h = GetPrivateProfileIntA("Window", "H", 260, g_iniPath);
    if (w < 320) w = 320;
    if (h < 180) h = 180;

    HWND hWnd = CreateWindowExA(0, kClassMain, "PACS Manager",
        WS_OVERLAPPEDWINDOW,
        (x < 0) ? CW_USEDEFAULT : x,
        (y < 0) ? CW_USEDEFAULT : y,
        w, h, NULL, NULL, hInst, NULL);
    if (!hWnd) return 0;

    ShowWindow(hWnd, nShow);
    UpdateWindow(hWnd);

    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }
    return (int)msg.wParam;
}