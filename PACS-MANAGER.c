/*
 * PACS-MANAGER.c
 *
 * Win32 process control launcher.
 *
 * - Reads/writes PACS-MANAGER.ini next to the EXE
 * - Dynamic rows from Row1..RowN
 * - 3 columns, 4:1:1 width ratio, resizable & maximizable
 * - Column 1 is a clickable label that toggles Start/Stop
 *     green = matching process basename running
 *     red   = stopped
 *     gray  = no process configured
 * - Start uses the FULL path from Process= verbatim
 * - Stop kills every process whose EXE basename matches
 *   the configured basename, case-insensitive, regardless of path
 * - Flat Edit menu: row entries + Add Row + Exit
 * - Edit window: 3 Name/Description pairs + Browse + Auto-Start + Save/Delete/Cancel
 * - First two rows cannot be deleted
 * - Window size and position are saved to [Window] in the INI on exit
 * - No popup messages on errors (silent by design)
 *
 * Build:
 *   MinGW-w64:
 *     gcc -O2 -s -mwindows -o PACS-MANAGER.exe PACS-MANAGER.c 
 *         -luser32 -lgdi32 -lcomdlg32 -lshell32 -lkernel32
 *
 *   MSVC (Developer Command Prompt):
 *     cl /O2 PACS-MANAGER.c /link /SUBSYSTEM:WINDOWS \
 *         user32.lib gdi32.lib comdlg32.lib shell32.lib kernel32.lib
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

#define CLR_RUN_RGB         RGB(0x66, 0xCC, 0x66)
#define CLR_STOP_RGB        RGB(0xE0, 0x70, 0x70)
#define CLR_NONE_RGB        RGB(0xF0, 0xF0, 0xF0)

typedef enum {
    ST_NONE = 0,
    ST_RUN  = 1,
    ST_STOP = 2
} RowState;

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
/*                                                                     */
/* Some Windows SDK import libs only export the unsuffixed names       */
/* (Process32First / Process32Next).  Try those first, then fall       */
/* back to the explicit "A" variants.                                  */
/* ------------------------------------------------------------------ */

static void init_toolhelp(void)
{
    HMODULE hK32 = GetModuleHandleA("kernel32.dll");
    if (!hK32) hK32 = LoadLibraryA("kernel32.dll");
    if (!hK32) return;

    pCreateToolhelp32Snapshot =
        (PFN_CreateToolhelp32Snapshot)GetProcAddress(hK32, "CreateToolhelp32Snapshot");

    pProcess32First = (PFN_Process32First)GetProcAddress(hK32, "Process32First");
    if (!pProcess32First) {
        pProcess32First =
            (PFN_Process32First)GetProcAddress(hK32, "Process32FirstA");
    }

    pProcess32Next = (PFN_Process32Next)GetProcAddress(hK32, "Process32Next");
    if (!pProcess32Next) {
        pProcess32Next =
            (PFN_Process32Next)GetProcAddress(hK32, "Process32NextA");
    }
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

    for (char *p = tmp; *p; ++p) {
        if (*p == '/') *p = '\\';
    }

    const char *base = strrchr(tmp, '\\');
    base = base ? base + 1 : tmp;
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

    write_one_row("Row1",
                  "Worklist", "WORKLIST-SERVER01.EXE", 1,
                  "View Log",    "WORKLIST_Server.log",
                  "Edit Config", "WORKLIST-SERVER01.ini");
    write_one_row("Row2",
                  "PACS", "PACS-SERVER01.EXE", 1,
                  "View Log",    "PACS_Server.log",
                  "Edit Config", "PACS-SERVER01.ini");
    write_one_row("Row3",
                  "Desc3", "", 0,
                  "Desc3A", "", "Desc3B", "");
}

static void load_rows_from_ini(void)
{
    memset(g_rows, 0, sizeof(g_rows));
    g_nRows = 0;

    for (int i = 1; i <= MAX_ROWS; ++i) {
        char sec[32], probe[16];
        wsprintfA(sec, "Row%d", i);

        GetPrivateProfileStringA(sec, "Name",    "", probe, sizeof(probe), g_iniPath);
        int hasName = probe[0] != 0;
        GetPrivateProfileStringA(sec, "Process", "", probe, sizeof(probe), g_iniPath);
        int hasProc = probe[0] != 0;

        if (!hasName && !hasProc) break;

        if (g_nRows >= MAX_ROWS) break;
        ROW *r = &g_rows[g_nRows++];
        GetPrivateProfileStringA(sec, "Name",    "", r->szName,    sizeof(r->szName),    g_iniPath);
        GetPrivateProfileStringA(sec, "Process", "", r->szProcess, sizeof(r->szProcess), g_iniPath);
        r->bAutoStart = GetPrivateProfileIntA(sec, "AutoStart", 0, g_iniPath);
        GetPrivateProfileStringA(sec, "NameA",   "", r->szNameA,   sizeof(r->szNameA),   g_iniPath);
        GetPrivateProfileStringA(sec, "TargetA", "", r->szTargetA, sizeof(r->szTargetA), g_iniPath);
        GetPrivateProfileStringA(sec, "NameB",   "", r->szNameB,   sizeof(r->szNameB),   g_iniPath);
        GetPrivateProfileStringA(sec, "TargetB", "", r->szTargetB, sizeof(r->szTargetB), g_iniPath);
    }

    while (g_nRows < 2) {
        ROW *r = &g_rows[g_nRows];
        wsprintfA(r->szName,  "Desc%d",  g_nRows + 1);
        wsprintfA(r->szNameA, "Desc%dA", g_nRows + 1);
        wsprintfA(r->szNameB, "Desc%dB", g_nRows + 1);
        r->bAutoStart = 0;
        g_nRows++;
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

    char buf[32];

    wsprintfA(buf, "%d", (int)wp.rcNormalPosition.left);
    WritePrivateProfileStringA("Window", "X", buf, g_iniPath);

    wsprintfA(buf, "%d", (int)wp.rcNormalPosition.top);
    WritePrivateProfileStringA("Window", "Y", buf, g_iniPath);

    wsprintfA(buf, "%d",
              (int)(wp.rcNormalPosition.right - wp.rcNormalPosition.left));
    WritePrivateProfileStringA("Window", "W", buf, g_iniPath);

    wsprintfA(buf, "%d",
              (int)(wp.rcNormalPosition.bottom - wp.rcNormalPosition.top));
    WritePrivateProfileStringA("Window", "H", buf, g_iniPath);

    WritePrivateProfileStringA("Window", "Maximized",
                               wp.showCmd == SW_SHOWMAXIMIZED ? "1" : "0",
                               g_iniPath);
}

/* ------------------------------------------------------------------ */
/* Process detection / control                                         */
/* ------------------------------------------------------------------ */

static int is_process_running(const char *exeLower)
{
    if (!exeLower || !exeLower[0]) return 0;
    if (!pCreateToolhelp32Snapshot || !pProcess32First || !pProcess32Next)
        return 0;

    HANDLE hSnap = pCreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32 pe;
    pe.dwSize = sizeof(pe);

    int found = 0;
    if (pProcess32First(hSnap, &pe)) {
        do {
            char name[MAX_PATH];
            lstrcpynA(name, pe.szExeFile, sizeof(name));
            str_lower(name);
            if (lstrcmpA(name, exeLower) == 0) {
                found = 1;
                break;
            }
        } while (pProcess32Next(hSnap, &pe));
    }
    CloseHandle(hSnap);
    return found;
}

static void stop_process_by_name(const char *exeLower)
{
    if (!exeLower || !exeLower[0]) return;
    if (!pCreateToolhelp32Snapshot || !pProcess32First || !pProcess32Next)
        return;

    HANDLE hSnap = pCreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return;

    PROCESSENTRY32 pe;
    pe.dwSize = sizeof(pe);

    if (pProcess32First(hSnap, &pe)) {
        do {
            char name[MAX_PATH];
            lstrcpynA(name, pe.szExeFile, sizeof(name));
            str_lower(name);
            if (lstrcmpA(name, exeLower) == 0) {
                HANDLE hProc = OpenProcess(PROCESS_TERMINATE, FALSE, pe.th32ProcessID);
                if (hProc) {
                    TerminateProcess(hProc, 0);
                    CloseHandle(hProc);
                }
            }
        } while (pProcess32Next(hSnap, &pe));
    }
    CloseHandle(hSnap);
}

static void start_process_by_path(const char *fullPath)
{
    if (!fullPath || !fullPath[0]) return;

    char path[MAX_PATH];
    lstrcpynA(path, fullPath, sizeof(path));
    strip_quotes_trim(path);

    if (GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES) return;

    char dir[MAX_PATH] = {0};
    lstrcpynA(dir, path, sizeof(dir));
    char *slash = strrchr(dir, '\\');
    if (slash) {
        *slash = 0;
        ShellExecuteA(g_hMain, "open", path, NULL, dir, SW_SHOWNORMAL);
    } else {
        ShellExecuteA(g_hMain, "open", path, NULL, NULL, SW_SHOWNORMAL);
    }
}

static void wait_process_state(const char *exeLower, int wantAppear, int ms)
{
    if (!exeLower || !exeLower[0]) return;

    DWORD t0 = GetTickCount();
    while (GetTickCount() - t0 < (DWORD)ms) {
        int run = is_process_running(exeLower);
        if (wantAppear ?  run : !run) return;

        MSG m;
        while (PeekMessage(&m, NULL, 0, 0, PM_REMOVE)) {
            TranslateMessage(&m);
            DispatchMessage(&m);
        }
        Sleep(WAIT_POLL_MS);
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
    int W = rc.right;
    int H = rc.bottom;

    int usableW = W - GAP * 4;
    if (usableW < MIN_COL_U * 6) usableW = MIN_COL_U * 6;
    int colU = usableW / 6;
    if (colU < MIN_COL_U) colU = MIN_COL_U;
    int col1 = colU * 4;
    int col2 = colU;
    int col3 = colU;
    int gridW = col1 + col2 + col3 + GAP * 2;

    int xStart = (W - gridW) / 2;
    if (xStart < GAP) xStart = GAP;

    int usableH = H - (Y_TOP + GAP) - (g_nRows - 1) * GAP;
    if (usableH < g_nRows * BTN_H_MIN) usableH = g_nRows * BTN_H_MIN;
    int btnH = usableH / g_nRows;
    if (btnH < BTN_H_MIN) btnH = BTN_H_MIN;
    if (btnH > BTN_H_MAX) btnH = BTN_H_MAX;

    int contentH = g_nRows * btnH + (g_nRows - 1) * GAP;
    int yStart = (H - contentH) / 2;
    if (yStart < Y_TOP) yStart = Y_TOP;

    for (int i = 0; i < g_nRows; ++i) {
        int y  = yStart + i * (btnH + GAP);
        int x1 = xStart;
        int x2 = x1 + col1 + GAP;
        int x3 = x2 + col2 + GAP;

        HWND h;
        h = GetDlgItem(g_hMain, ID_LBL_BASE  + i); if (h) MoveWindow(h, x1, y, col1, btnH, TRUE);
        h = GetDlgItem(g_hMain, ID_BTNA_BASE + i); if (h) MoveWindow(h, x2, y, col2, btnH, TRUE);
        h = GetDlgItem(g_hMain, ID_BTNB_BASE + i); if (h) MoveWindow(h, x3, y, col3, btnH, TRUE);
    }
    InvalidateRect(g_hMain, NULL, TRUE);
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
    if (!r->szProcess[0]) {
        g_rowState[i] = ST_NONE;
        SetWindowTextA(hLbl, r->szName);
        InvalidateRect(hLbl, NULL, TRUE);
        UpdateWindow(hLbl);
        return;
    }

    char base[MAX_PATH];
    get_exe_basename(r->szProcess, base, sizeof(base));
    int running = is_process_running(base);

    char buf[256];
    wsprintfA(buf, "%s %s", running ? "Stop " : "Start", r->szName);

    g_rowState[i] = running ? ST_RUN : ST_STOP;
    SetWindowTextA(hLbl, buf);
    InvalidateRect(hLbl, NULL, TRUE);
    UpdateWindow(hLbl);
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
    }
}

/* ------------------------------------------------------------------ */
/* Menu                                                                */
/* ------------------------------------------------------------------ */

static void rebuild_edit_menu(void)
{
    if (!g_hEditMenu) return;

    int count = GetMenuItemCount(g_hEditMenu);
    for (int k = count - 1; k >= 0; --k)
        DeleteMenu(g_hEditMenu, k, MF_BYPOSITION);

    for (int i = 0; i < g_nRows; ++i) {
        const char *label = g_rows[i].szName[0] ? g_rows[i].szName : "(empty)";
        AppendMenuA(g_hEditMenu, MF_STRING, ID_MENU_BASE + i, label);
    }
    AppendMenuA(g_hEditMenu, MF_SEPARATOR, 0, NULL);
    AppendMenuA(g_hEditMenu, MF_STRING, IDM_ADDROW, "Add Row");
    AppendMenuA(g_hEditMenu, MF_SEPARATOR, 0, NULL);
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

        h = CreateWindowExA(0, "STATIC", "",
                            WS_CHILD | WS_VISIBLE |
                            SS_NOTIFY | SS_CENTER | SS_CENTERIMAGE | SS_SUNKEN,
                            0, 0, 10, 10,
                            g_hMain, (HMENU)(INT_PTR)(ID_LBL_BASE + i),
                            g_hInst, NULL);
        if (h) SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        h = CreateWindowExA(0, "BUTTON", g_rows[i].szNameA,
                            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                            0, 0, 10, 10,
                            g_hMain, (HMENU)(INT_PTR)(ID_BTNA_BASE + i),
                            g_hInst, NULL);
        if (h) SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        h = CreateWindowExA(0, "BUTTON", g_rows[i].szNameB,
                            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                            0, 0, 10, 10,
                            g_hMain, (HMENU)(INT_PTR)(ID_BTNB_BASE + i),
                            g_hInst, NULL);
        if (h) SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);
    }
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
    layout_buttons();
    rebuild_edit_menu();
    refresh_all_rows();
}

static void delete_row_at(int idx)
{
    if (idx < 2 || idx >= g_nRows) return;
    for (int i = idx; i < g_nRows - 1; ++i)
        g_rows[i] = g_rows[i + 1];
    memset(&g_rows[g_nRows - 1], 0, sizeof(ROW));
    g_nRows--;

    save_rows_to_ini();
    destroy_main_controls();
    build_main_controls();
    layout_buttons();
    rebuild_edit_menu();
    refresh_all_rows();
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

    if (GetOpenFileNameA(&ofn)) {
        SetWindowTextA(hEdit, buf);
    }
}

static void build_edit_controls(HWND hWnd)
{
    HWND h;

    /* Group 0 */
    h = CreateWindowExA(0, "STATIC", "Main button (Description = full path to .EXE)",
                       WS_CHILD | WS_VISIBLE, 15, 12, 580, 16, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    h = CreateWindowExA(0, "STATIC", "Name",
                       WS_CHILD | WS_VISIBLE, 15, 36, 90, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edName[0] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                  110, 34, 480, 22, hWnd,
                                  (HMENU)(INT_PTR)IDE_NAME0, g_hInst, NULL);
    SendMessage(g_edName[0], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    h = CreateWindowExA(0, "STATIC", "Description",
                       WS_CHILD | WS_VISIBLE, 15, 64, 90, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edDesc[0] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                  110, 62, 380, 22, hWnd,
                                  (HMENU)(INT_PTR)IDE_DESC0, g_hInst, NULL);
    SendMessage(g_edDesc[0], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edBrow[0] = CreateWindowExA(0, "BUTTON", "Browse",
                                  WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                  500, 60, 90, 24, hWnd,
                                  (HMENU)(INT_PTR)IDE_BROW0, g_hInst, NULL);
    SendMessage(g_edBrow[0], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    /* Group 1 */
    h = CreateWindowExA(0, "STATIC", "Helper A (column 2 - launches any file)",
                       WS_CHILD | WS_VISIBLE, 15, 100, 580, 16, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    h = CreateWindowExA(0, "STATIC", "Name",
                       WS_CHILD | WS_VISIBLE, 15, 124, 90, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edName[1] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                  110, 122, 480, 22, hWnd,
                                  (HMENU)(INT_PTR)IDE_NAME1, g_hInst, NULL);
    SendMessage(g_edName[1], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    h = CreateWindowExA(0, "STATIC", "Description",
                       WS_CHILD | WS_VISIBLE, 15, 152, 90, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edDesc[1] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                  110, 150, 380, 22, hWnd,
                                  (HMENU)(INT_PTR)IDE_DESC1, g_hInst, NULL);
    SendMessage(g_edDesc[1], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edBrow[1] = CreateWindowExA(0, "BUTTON", "Browse",
                                  WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                  500, 148, 90, 24, hWnd,
                                  (HMENU)(INT_PTR)IDE_BROW1, g_hInst, NULL);
    SendMessage(g_edBrow[1], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    /* Group 2 */
    h = CreateWindowExA(0, "STATIC", "Helper B (column 3 - launches any file)",
                       WS_CHILD | WS_VISIBLE, 15, 188, 580, 16, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    h = CreateWindowExA(0, "STATIC", "Name",
                       WS_CHILD | WS_VISIBLE, 15, 212, 90, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edName[2] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                  110, 210, 480, 22, hWnd,
                                  (HMENU)(INT_PTR)IDE_NAME2, g_hInst, NULL);
    SendMessage(g_edName[2], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    h = CreateWindowExA(0, "STATIC", "Description",
                       WS_CHILD | WS_VISIBLE, 15, 240, 90, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edDesc[2] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "",
                                  WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                  110, 238, 380, 22, hWnd,
                                  (HMENU)(INT_PTR)IDE_DESC2, g_hInst, NULL);
    SendMessage(g_edDesc[2], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_edBrow[2] = CreateWindowExA(0, "BUTTON", "Browse",
                                  WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                  500, 236, 90, 24, hWnd,
                                  (HMENU)(INT_PTR)IDE_BROW2, g_hInst, NULL);
    SendMessage(g_edBrow[2], WM_SETFONT, (WPARAM)g_hFont, TRUE);

    /* Auto-Start */
    h = CreateWindowExA(0, "STATIC", "Auto-Start at launch",
                       WS_CHILD | WS_VISIBLE, 15, 276, 130, 18, hWnd, 0, g_hInst, NULL);
    SendMessage(h, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_hEdAuto = CreateWindowExA(0, "BUTTON", "",
                                WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
                                150, 274, 20, 20, hWnd,
                                (HMENU)(INT_PTR)IDE_AUTO, g_hInst, NULL);

    /* Save / Delete / Cancel */
    g_hEdSave = CreateWindowExA(0, "BUTTON", "Save",
                                WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                110, 320, 90, 28, hWnd,
                                (HMENU)(INT_PTR)IDE_SAVE, g_hInst, NULL);
    SendMessage(g_hEdSave, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_hEdDel = CreateWindowExA(0, "BUTTON", "Delete",
                               WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                               260, 320, 90, 28, hWnd,
                               (HMENU)(INT_PTR)IDE_DEL, g_hInst, NULL);
    SendMessage(g_hEdDel, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    g_hEdCancel = CreateWindowExA(0, "BUTTON", "Cancel",
                                  WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                                  410, 320, 90, 28, hWnd,
                                  (HMENU)(INT_PTR)IDE_CANCEL, g_hInst, NULL);
    SendMessage(g_hEdCancel, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    /* Populate */
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
        if (g_editRow < 2) EnableWindow(g_hEdDel, FALSE);
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
        int id = LOWORD(wp);
        switch (id) {
        case IDE_CANCEL:
            DestroyWindow(hWnd);
            return 0;
        case IDE_SAVE:
            save_edit_fields();
            DestroyWindow(hWnd);
            return 0;
        case IDE_DEL:
            if (g_editRow >= 2) {
                int row = g_editRow;
                DestroyWindow(hWnd);
                delete_row_at(row);
            }
            return 0;
        case IDE_BROW0: do_browse(hWnd, g_edDesc[0]); return 0;
        case IDE_BROW1: do_browse(hWnd, g_edDesc[1]); return 0;
        case IDE_BROW2: do_browse(hWnd, g_edDesc[2]); return 0;
        }
        break;
    }

    case WM_CLOSE:
        DestroyWindow(hWnd);
        return 0;

    case WM_DESTROY:
        EnableWindow(g_hMain, TRUE);
        SetForegroundWindow(g_hMain);
        g_hEditWnd = NULL;
        g_editRow  = -1;
        rebuild_edit_menu();
        refresh_all_rows();
        return 0;
    }
    return DefWindowProc(hWnd, msg, wp, lp);
}

static void open_edit_window(int rowIndex)
{
    if (rowIndex < 0 || rowIndex >= g_nRows) return;
    g_editRow = rowIndex;

    char title[64];
    wsprintfA(title, "Edit Row %d", rowIndex + 1);

    EnableWindow(g_hMain, FALSE);

    HWND h = CreateWindowExA(WS_EX_DLGMODALFRAME,
                             kClassEdit, title,
                             WS_CAPTION | WS_SYSMENU | WS_SIZEBOX |
                             WS_VISIBLE | WS_POPUP,
                             CW_USEDEFAULT, CW_USEDEFAULT,
                             620, 410,
                             g_hMain, NULL, g_hInst, NULL);
    if (!h) {
        EnableWindow(g_hMain, TRUE);
        g_editRow = -1;
    }
}

/* ------------------------------------------------------------------ */
/* Main window procedure                                               */
/* ------------------------------------------------------------------ */

static LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE: {
        g_hMain = hWnd;

        HMENU bar = CreateMenu();
        g_hEditMenu = CreatePopupMenu();
        AppendMenuA(bar, MF_POPUP, (UINT_PTR)g_hEditMenu, "&Edit");
        SetMenu(hWnd, bar);

        rebuild_edit_menu();
        build_main_controls();
        layout_buttons();
        refresh_all_rows();
        SetTimer(hWnd, TIMER_ID, TIMER_MS, NULL);
        return 0;
    }

    case WM_SIZE:
        layout_buttons();
        return 0;

    case WM_TIMER:
        if (wp == TIMER_ID) refresh_all_rows();
        return 0;

    case WM_CTLCOLORSTATIC: {
        HWND hCtl = (HWND)lp;
        int id = GetDlgCtrlID(hCtl);
        int idx = id - ID_LBL_BASE;
        if (idx >= 0 && idx < g_nRows) {
            HDC hdc = (HDC)wp;
            SetBkMode(hdc, TRANSPARENT);
            switch (g_rowState[idx]) {
            case ST_RUN:  return (LRESULT)g_hbrRun;
            case ST_STOP: return (LRESULT)g_hbrStop;
            default:      return (LRESULT)g_hbrNone;
            }
        }
        break;
    }

    case WM_COMMAND: {
        int id = LOWORD(wp);
        int code = HIWORD(wp);

        if (id == IDM_EXIT)   { DestroyWindow(hWnd); return 0; }
        if (id == IDM_ADDROW) { add_new_row();        return 0; }

        if (id >= ID_MENU_BASE && id < ID_MENU_BASE + g_nRows) {
            open_edit_window(id - ID_MENU_BASE);
            return 0;
        }

        if (code == STN_CLICKED &&
            id >= ID_LBL_BASE && id < ID_LBL_BASE + g_nRows) {
            int i = id - ID_LBL_BASE;
            ROW *r = &g_rows[i];
            if (r->szProcess[0]) {
                char base[MAX_PATH];
                get_exe_basename(r->szProcess, base, sizeof(base));
                if (is_process_running(base)) {
                    stop_process_by_name(base);
                    wait_process_state(base, 0, WAIT_TIMEOUT_MS);
                } else {
                    start_process_by_path(r->szProcess);
                    wait_process_state(base, 1, WAIT_TIMEOUT_MS);
                }
            }
            refresh_row(i);
            return 0;
        }

        if (id >= ID_BTNA_BASE && id < ID_BTNA_BASE + g_nRows) {
            int i = id - ID_BTNA_BASE;
            if (g_rows[i].szTargetA[0])
                ShellExecuteA(hWnd, "open", g_rows[i].szTargetA, NULL, NULL, SW_SHOW);
            return 0;
        }

        if (id >= ID_BTNB_BASE && id < ID_BTNB_BASE + g_nRows) {
            int i = id - ID_BTNB_BASE;
            if (g_rows[i].szTargetB[0])
                ShellExecuteA(hWnd, "open", g_rows[i].szTargetB, NULL, NULL, SW_SHOW);
            return 0;
        }
        break;
    }

    case WM_CLOSE:
        save_window_placement();
        DestroyWindow(hWnd);
        return 0;

    case WM_DESTROY:
        save_window_placement();
        KillTimer(hWnd, TIMER_ID);
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProc(hWnd, msg, wp, lp);
}

/* ------------------------------------------------------------------ */
/* WinMain                                                             */
/* ------------------------------------------------------------------ */

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow)
{
    (void)hPrev;
    (void)lpCmd;
    g_hInst = hInst;

    g_hbrRun  = CreateSolidBrush(CLR_RUN_RGB);
    g_hbrStop = CreateSolidBrush(CLR_STOP_RGB);
    g_hbrNone = CreateSolidBrush(CLR_NONE_RGB);

    g_hFont = (HFONT)GetStockObject(DEFAULT_GUI_FONT);

    init_toolhelp();

    WNDCLASSEXA wc;
    memset(&wc, 0, sizeof(wc));
    wc.cbSize        = sizeof(wc);
    wc.style         = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInst;
    wc.hIcon         = LoadIcon(NULL, IDI_APPLICATION);
    wc.hIconSm       = wc.hIcon;
    wc.hCursor       = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = kClassMain;
    RegisterClassExA(&wc);

    WNDCLASSEXA we;
    memset(&we, 0, sizeof(we));
    we.cbSize        = sizeof(we);
    we.style         = CS_HREDRAW | CS_VREDRAW;
    we.lpfnWndProc   = EditWndProc;
    we.hInstance     = hInst;
    we.hIcon         = LoadIcon(NULL, IDI_APPLICATION);
    we.hIconSm       = we.hIcon;
    we.hCursor       = LoadCursor(NULL, IDC_ARROW);
    we.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    we.lpszClassName = kClassEdit;
    RegisterClassExA(&we);

    resolve_ini_path();
    ensure_default_ini();
    load_rows_from_ini();

    /* Defaults */
    int defW = COL_U_DEF * 6 + GAP * 2 + X_PAD * 2;
    int defH = Y_TOP + g_nRows * (BTN_H_DEF + GAP) + GAP + 60;

    /* Read saved placement */
    int winX = GetPrivateProfileIntA("Window", "X",         (int)CW_USEDEFAULT, g_iniPath);
    int winY = GetPrivateProfileIntA("Window", "Y",         (int)CW_USEDEFAULT, g_iniPath);
    int winW = GetPrivateProfileIntA("Window", "W",         defW,               g_iniPath);
    int winH = GetPrivateProfileIntA("Window", "H",         defH,               g_iniPath);
    int bMax = GetPrivateProfileIntA("Window", "Maximized", 0,                  g_iniPath);

    HWND hWnd = CreateWindowExA(0, kClassMain, "Process Control",
                                WS_OVERLAPPEDWINDOW,
                                winX, winY, winW, winH,
                                NULL, NULL, hInst, NULL);
    if (!hWnd) return 0;

    ShowWindow(hWnd, bMax ? SW_SHOWMAXIMIZED : nShow);
    UpdateWindow(hWnd);

    auto_start_rows();

    MSG msg;
    while (GetMessage(&msg, NULL, 0, 0)) {
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    if (g_hbrRun)  DeleteObject(g_hbrRun);
    if (g_hbrStop) DeleteObject(g_hbrStop);
    if (g_hbrNone) DeleteObject(g_hbrNone);

    return (int)msg.wParam;
}