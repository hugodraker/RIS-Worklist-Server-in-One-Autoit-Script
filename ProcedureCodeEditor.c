/*
    ProcedureCodeEditor.c

    BUILD / RUN INSTRUCTIONS:

    MinGW-w64:
        gcc -O2 -s -mwindows -o ProcedureCodeEditor.exe ProcedureCodeEditor.c -luser32 -lgdi32 -lcomdlg32 -lcomctl32 -lshell32 -lkernel32

    MSVC Developer Command Prompt:
        cl /O2 ProcedureCodeEditor.c /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib comdlg32.lib comctl32.lib shell32.lib kernel32.lib

    Current fixes:
        - Edit-row window controls resize correctly when the edit window is resized/maximized.
        - Edit-row Save / Close buttons are anchored to the bottom-right and no longer get obscured.
        - Edit-row window has minimum size constraints.
        - Build instructions always included in this source header.
        - MinGW build uses -s.
        - Header row is preserved and never overwritten by data rows.
        - Header click sorts ascending / toggles descending.
        - Save makes current sorted/reordered order permanent in the CSV.
        - Drag/drop selected rows to reorder before the drop target.
        - Column widths save/load from INI.
        - Last opened file auto-loads.
*/

#define WIN32_LEAN_AND_MEAN
#define _WIN32_IE     0x0600
#define _WIN32_WINNT  0x0600
#define WINVER        0x0600

#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef GET_X_LPARAM
#define GET_X_LPARAM(lp) ((int)(short)LOWORD(lp))
#endif

#ifndef GET_Y_LPARAM
#define GET_Y_LPARAM(lp) ((int)(short)HIWORD(lp))
#endif

#ifndef LVS_EX_DOUBLEBUFFER
#define LVS_EX_DOUBLEBUFFER 0x00010000
#endif

#ifndef LVS_EX_HEADERDRAGDROP
#define LVS_EX_HEADERDRAGDROP 0x00000010
#endif

#ifndef LVM_SETINSERTMARK
#define LVM_SETINSERTMARK (LVM_FIRST + 166)
#endif

#ifndef LVIM_AFTER
#define LVIM_AFTER 0x00000001
#endif

typedef struct tagPCE_LVINSERTMARK {
    UINT cbSize;
    DWORD dwFlags;
    int iItem;
    DWORD dwReserved;
} PCE_LVINSERTMARK;

#define APP_TITLE       "Procedure Code Editor"
#define MAIN_CLASS      "PCE_MainWindow"
#define EDIT_CLASS      "PCE_EditWindow"

#define DEFAULT_CSV     "procedurecodes.csv"

#define MAX_COLS        64
#define DEF_COLS        4
#define MAX_CELL        2048

#define MIN_W           700
#define MIN_H           380

#define EDIT_MIN_W      520
#define EDIT_MIN_H      260

#define GAP             10
#define TOP_LABEL_H     22
#define BOTTOM_H        42
#define BTN_H           28

#define ID_LV           1001
#define ID_LABEL_FILE   1002
#define ID_BROWSE       1003
#define ID_SAVE         1004
#define ID_ADD          1005
#define ID_DELETE       1006
#define ID_UP           1007
#define ID_DOWN         1008
#define ID_DIRECT       1009

#define ID_EDIT_BASE_LABEL  3000
#define ID_EDIT_BASE_INPUT  4000
#define ID_EDIT_SAVE        5001
#define ID_EDIT_CLOSE       5002

typedef struct RowDataTag {
    char **cells;
} RowData;

static HINSTANCE g_hInst = NULL;
static HWND g_hMain = NULL;
static HWND g_hLV = NULL;
static HWND g_hFileLabel = NULL;

static HWND g_btnBrowse = NULL;
static HWND g_btnSave = NULL;
static HWND g_btnAdd = NULL;
static HWND g_btnDelete = NULL;
static HWND g_btnUp = NULL;
static HWND g_btnDown = NULL;
static HWND g_chkDirect = NULL;

static HFONT g_hFont = NULL;

static char g_iniPath[MAX_PATH] = {0};
static char g_curFile[MAX_PATH] = {0};

static int g_cols = DEF_COLS;
static char g_headers[MAX_COLS][128];

static int g_dirty = 0;
static int g_directEdit = 0;

static int g_sortCol = -1;
static int g_sortAsc = 1;

static int g_dragging = 0;
static int g_dragTarget = -1;

static HWND g_hInplaceEdit = NULL;
static WNDPROC g_oldEditProc = NULL;
static int g_editRow = -1;
static int g_editCol = -1;

static HWND g_hEditDlg = NULL;
static int g_editDlgRow = -1;
static HWND g_editLabels[MAX_COLS];
static HWND g_editInputs[MAX_COLS];
static HWND g_editSaveBtn = NULL;
static HWND g_editCloseBtn = NULL;

static LRESULT CALLBACK MainWndProc(HWND, UINT, WPARAM, LPARAM);
static LRESULT CALLBACK EditWndProc(HWND, UINT, WPARAM, LPARAM);
static LRESULT CALLBACK InplaceEditProc(HWND, UINT, WPARAM, LPARAM);

static void InitHeaders(void);
static void ResolveIniPath(void);
static void LoadSettings(int *x, int *y, int *w, int *h, int *maximized);
static void SaveSettings(void);

static void RebuildColumns(void);
static void LoadColumnWidths(void);
static void SaveColumnWidths(void);
static void AutoSizeColumnsFiveToOne(void);

static void LayoutControls(void);
static void LayoutEditDialog(HWND hwnd);
static void UpdateFileLabel(void);

static int LoadCsv(const char *path);
static int SaveCsv(const char *path);
static void DoBrowse(void);
static void DoSave(void);

static void AddRow(void);
static void DeleteSelectedRows(void);
static void MoveSelectedRows(int dir);
static void SwapRows(int r1, int r2);
static void SortByColumn(int col);

static void BeginDrag(void);
static int ComputeDragTarget(int x, int y);
static void DrawInsertMark(int target);
static void ReorderSelectedRowsBefore(int target);

static void StartInplaceEdit(int row, int col);
static void EndInplaceEdit(int save);

static void ShowEditDialog(int row);
static void CloseEditDialog(void);
static void SaveEditDialog(void);

static char **CsvParseLine(const char *line, int *count);
static void FreeFields(char **fields, int count);
static void CsvWriteField(FILE *f, const char *text);

static void SafeCopy(char *dst, size_t dstSize, const char *src)
{
    if (!dst || dstSize == 0) return;
    if (!src) src = "";
    lstrcpynA(dst, src, (int)dstSize);
}

static void TrimTrailingCrLf(char *s)
{
    size_t n;
    if (!s) return;
    n = strlen(s);
    while (n > 0 && (s[n - 1] == '\r' || s[n - 1] == '\n')) {
        s[n - 1] = 0;
        n--;
    }
}

static void GetExeDirectory(char *out, size_t outSize)
{
    GetModuleFileNameA(NULL, out, (DWORD)outSize);
    char *slash = strrchr(out, '\\');
    if (slash) *(slash + 1) = 0;
}

static void MakeDefaultCsvPath(char *out, size_t outSize)
{
    char dir[MAX_PATH];
    GetExeDirectory(dir, sizeof(dir));
    SafeCopy(out, outSize, dir);
    lstrcatA(out, DEFAULT_CSV);
}

static void GetListCell(int row, int col, char *out, int outSize)
{
    if (!out || outSize <= 0) return;
    out[0] = 0;
    ListView_GetItemText(g_hLV, row, col, out, outSize);
}

static void SetListCell(int row, int col, const char *text)
{
    ListView_SetItemText(g_hLV, row, col, (LPSTR)(text ? text : ""));
}

static int InsertListRow(int row)
{
    LVITEMA item;
    memset(&item, 0, sizeof(item));
    item.mask = LVIF_TEXT;
    item.iItem = row;
    item.iSubItem = 0;
    item.pszText = "";
    return ListView_InsertItem(g_hLV, &item);
}

static int AddListRowAtEnd(void)
{
    int n = ListView_GetItemCount(g_hLV);
    return InsertListRow(n);
}

static void InitHeaders(void)
{
    int i;
    for (i = 0; i < MAX_COLS; i++) g_headers[i][0] = 0;

    SafeCopy(g_headers[0], sizeof(g_headers[0]), "Name");
    SafeCopy(g_headers[1], sizeof(g_headers[1]), "Desc");
    SafeCopy(g_headers[2], sizeof(g_headers[2]), "Cat");
    SafeCopy(g_headers[3], sizeof(g_headers[3]), "Notes");
}

static void ResolveIniPath(void)
{
    GetModuleFileNameA(NULL, g_iniPath, sizeof(g_iniPath));

    char *slash = strrchr(g_iniPath, '\\');
    char *dot = strrchr(g_iniPath, '.');

    if (dot && (!slash || dot > slash)) *dot = 0;
    lstrcatA(g_iniPath, ".ini");
}

static void LoadSettings(int *x, int *y, int *w, int *h, int *maximized)
{
    *x = GetPrivateProfileIntA("Window", "X", CW_USEDEFAULT, g_iniPath);
    *y = GetPrivateProfileIntA("Window", "Y", CW_USEDEFAULT, g_iniPath);
    *w = GetPrivateProfileIntA("Window", "W", 900, g_iniPath);
    *h = GetPrivateProfileIntA("Window", "H", 600, g_iniPath);
    *maximized = GetPrivateProfileIntA("Window", "Maximized", 0, g_iniPath);

    if (*w < MIN_W) *w = 900;
    if (*h < MIN_H) *h = 600;

    g_directEdit = GetPrivateProfileIntA("Settings", "DirectEdit", 0, g_iniPath);
}

static void SaveSettings(void)
{
    WINDOWPLACEMENT wp;
    char buf[64];

    SaveColumnWidths();

    memset(&wp, 0, sizeof(wp));
    wp.length = sizeof(wp);

    if (GetWindowPlacement(g_hMain, &wp)) {
        wsprintfA(buf, "%d", (int)wp.rcNormalPosition.left);
        WritePrivateProfileStringA("Window", "X", buf, g_iniPath);

        wsprintfA(buf, "%d", (int)wp.rcNormalPosition.top);
        WritePrivateProfileStringA("Window", "Y", buf, g_iniPath);

        wsprintfA(buf, "%d", (int)(wp.rcNormalPosition.right - wp.rcNormalPosition.left));
        WritePrivateProfileStringA("Window", "W", buf, g_iniPath);

        wsprintfA(buf, "%d", (int)(wp.rcNormalPosition.bottom - wp.rcNormalPosition.top));
        WritePrivateProfileStringA("Window", "H", buf, g_iniPath);

        WritePrivateProfileStringA("Window", "Maximized",
            (wp.showCmd == SW_SHOWMAXIMIZED) ? "1" : "0", g_iniPath);
    }

    WritePrivateProfileStringA("Settings", "DirectEdit", g_directEdit ? "1" : "0", g_iniPath);

    if (g_curFile[0]) {
        WritePrivateProfileStringA("Recent", "LastFile", g_curFile, g_iniPath);
    }
}

static void RebuildColumns(void)
{
    int i;
    HWND hHeader = ListView_GetHeader(g_hLV);
    int count = hHeader ? Header_GetItemCount(hHeader) : 0;

    for (i = count - 1; i >= 0; i--) ListView_DeleteColumn(g_hLV, i);

    for (i = 0; i < g_cols; i++) {
        LVCOLUMNA col;
        char fallback[64];

        if (g_headers[i][0] == 0) {
            wsprintfA(fallback, "Col%d", i + 1);
            SafeCopy(g_headers[i], sizeof(g_headers[i]), fallback);
        }

        memset(&col, 0, sizeof(col));
        col.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_FMT | LVCF_SUBITEM;
        col.fmt = LVCFMT_LEFT;
        col.cx = 120;
        col.iSubItem = i;
        col.pszText = g_headers[i];

        ListView_InsertColumn(g_hLV, i, &col);
    }

    LoadColumnWidths();
}

static void AutoSizeColumnsFiveToOne(void)
{
    RECT rc;
    int width, totalWeight, nameW, otherW, i;

    if (g_cols <= 0) return;

    GetClientRect(g_hLV, &rc);
    width = rc.right - rc.left - 4;
    if (width < 100) return;

    if (g_cols == 1) {
        ListView_SetColumnWidth(g_hLV, 0, width);
        return;
    }

    totalWeight = 5 + (g_cols - 1);
    nameW = (width * 5) / totalWeight;
    otherW = (width - nameW) / (g_cols - 1);
    if (otherW < 40) otherW = 40;

    ListView_SetColumnWidth(g_hLV, 0, nameW);
    for (i = 1; i < g_cols; i++) ListView_SetColumnWidth(g_hLV, i, otherW);
}

static void LoadColumnWidths(void)
{
    int i, loaded = 0;

    for (i = 0; i < g_cols; i++) {
        char key[32];
        int w;

        wsprintfA(key, "C%d", i);
        w = GetPrivateProfileIntA("Columns", key, -1, g_iniPath);

        if (w > 0) {
            ListView_SetColumnWidth(g_hLV, i, w);
            loaded = 1;
        }
    }

    if (!loaded) AutoSizeColumnsFiveToOne();
}

static void SaveColumnWidths(void)
{
    int i;
    char buf[64];

    wsprintfA(buf, "%d", g_cols);
    WritePrivateProfileStringA("Columns", "Count", buf, g_iniPath);

    for (i = 0; i < g_cols; i++) {
        char key[32];
        int w = ListView_GetColumnWidth(g_hLV, i);

        wsprintfA(key, "C%d", i);
        wsprintfA(buf, "%d", w);
        WritePrivateProfileStringA("Columns", key, buf, g_iniPath);
    }
}

static void LayoutControls(void)
{
    RECT rc;
    int w, h;
    int lvY, lvH;
    int btnY, chkW, available, btnW, x;

    if (!g_hMain) return;

    GetClientRect(g_hMain, &rc);
    w = rc.right - rc.left;
    h = rc.bottom - rc.top;

    if (w < MIN_W) w = MIN_W;
    if (h < MIN_H) h = MIN_H;

    MoveWindow(g_hFileLabel, GAP, GAP, w - (GAP * 2), TOP_LABEL_H, TRUE);

    lvY = GAP + TOP_LABEL_H + 4;
    lvH = h - lvY - BOTTOM_H - GAP;
    if (lvH < 80) lvH = 80;

    MoveWindow(g_hLV, GAP, lvY, w - (GAP * 2), lvH, TRUE);

    btnY = h - BOTTOM_H + ((BOTTOM_H - BTN_H) / 2);
    chkW = 120;
    available = w - (GAP * 2) - chkW - GAP;
    btnW = (available - (5 * GAP)) / 6;
    if (btnW < 65) btnW = 65;

    x = GAP;

    MoveWindow(g_btnBrowse, x, btnY, btnW, BTN_H, TRUE);
    x += btnW + GAP;

    MoveWindow(g_btnSave, x, btnY, btnW, BTN_H, TRUE);
    x += btnW + GAP;

    MoveWindow(g_btnAdd, x, btnY, btnW, BTN_H, TRUE);
    x += btnW + GAP;

    MoveWindow(g_btnDelete, x, btnY, btnW, BTN_H, TRUE);
    x += btnW + GAP;

    MoveWindow(g_btnUp, x, btnY, btnW, BTN_H, TRUE);
    x += btnW + GAP;

    MoveWindow(g_btnDown, x, btnY, btnW, BTN_H, TRUE);

    MoveWindow(g_chkDirect, w - GAP - chkW, btnY, chkW, BTN_H, TRUE);
}

static void LayoutEditDialog(HWND hwnd)
{
    RECT rc;
    int w, h, c;
    int labelX = 12;
    int labelW = 140;
    int inputX = 160;
    int rowH = 32;
    int top = 14;
    int buttonY;
    int inputW;

    if (!hwnd) return;

    GetClientRect(hwnd, &rc);
    w = rc.right - rc.left;
    h = rc.bottom - rc.top;

    if (w < EDIT_MIN_W) w = EDIT_MIN_W;
    if (h < EDIT_MIN_H) h = EDIT_MIN_H;

    inputW = w - inputX - 20;
    if (inputW < 120) inputW = 120;

    buttonY = h - 42;
    if (buttonY < top + (g_cols * rowH) + 8)
        buttonY = top + (g_cols * rowH) + 8;

    for (c = 0; c < g_cols; c++) {
        int y = top + (c * rowH);

        if (g_editLabels[c]) {
            MoveWindow(g_editLabels[c], labelX, y + 4, labelW, 20, TRUE);
        }

        if (g_editInputs[c]) {
            MoveWindow(g_editInputs[c], inputX, y, inputW, 24, TRUE);
        }
    }

    if (g_editSaveBtn) {
        MoveWindow(g_editSaveBtn, w - 220, h - 42, 90, 28, TRUE);
    }

    if (g_editCloseBtn) {
        MoveWindow(g_editCloseBtn, w - 115, h - 42, 90, 28, TRUE);
    }
}

static void UpdateFileLabel(void)
{
    char buf[MAX_PATH + 16];

    if (g_curFile[0]) SafeCopy(buf, sizeof(buf), g_curFile);
    else SafeCopy(buf, sizeof(buf), "(no file)");

    if (g_dirty) lstrcatA(buf, "  *");

    SetWindowTextA(g_hFileLabel, buf);
}

static char **CsvParseLine(const char *line, int *count)
{
    int cap = 8;
    int n = 0;
    char **fields = (char **)calloc((size_t)cap, sizeof(char *));
    const char *p = line;

    if (!fields) {
        *count = 0;
        return NULL;
    }

    while (*p) {
        char field[MAX_CELL];
        int fi = 0;
        int inQuote = 0;
        field[0] = 0;

        if (*p == '"') {
            inQuote = 1;
            p++;
        }

        while (*p) {
            if (inQuote) {
                if (*p == '"') {
                    if (*(p + 1) == '"') {
                        if (fi < MAX_CELL - 1) field[fi++] = '"';
                        p += 2;
                        continue;
                    } else {
                        p++;
                        inQuote = 0;
                        continue;
                    }
                } else {
                    if (fi < MAX_CELL - 1) field[fi++] = *p;
                    p++;
                    continue;
                }
            } else {
                if (*p == ',') {
                    p++;
                    break;
                }
                if (*p == '\r' || *p == '\n') break;
                if (fi < MAX_CELL - 1) field[fi++] = *p;
                p++;
            }
        }

        field[fi] = 0;

        if (n >= cap) {
            cap *= 2;
            char **nf = (char **)realloc(fields, (size_t)cap * sizeof(char *));
            if (!nf) break;
            fields = nf;
        }

        fields[n] = (char *)calloc(strlen(field) + 1, 1);
        if (fields[n]) strcpy(fields[n], field);
        n++;

        if (*p == 0 || *p == '\r' || *p == '\n') break;
    }

    if (n == 0) {
        fields[0] = (char *)calloc(1, 1);
        n = 1;
    }

    *count = n;
    return fields;
}

static void FreeFields(char **fields, int count)
{
    int i;
    if (!fields) return;
    for (i = 0; i < count; i++) free(fields[i]);
    free(fields);
}

static void CsvWriteField(FILE *f, const char *text)
{
    int needQuote = 0;
    const char *p;

    if (!text) text = "";

    for (p = text; *p; p++) {
        if (*p == ',' || *p == '"' || *p == '\r' || *p == '\n') {
            needQuote = 1;
            break;
        }
    }

    if (!needQuote) {
        fputs(text, f);
        return;
    }

    fputc('"', f);
    for (p = text; *p; p++) {
        if (*p == '"') fputc('"', f);
        fputc(*p, f);
    }
    fputc('"', f);
}

static int LoadCsv(const char *path)
{
    FILE *f;
    char *buffer;
    long size;
    char *p;
    char *lineStart;
    int lineIndex = 0;

    f = fopen(path, "rb");
    if (!f) return 0;

    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size < 0) {
        fclose(f);
        return 0;
    }

    buffer = (char *)calloc((size_t)size + 2, 1);
    if (!buffer) {
        fclose(f);
        return 0;
    }

    fread(buffer, 1, (size_t)size, f);
    fclose(f);

    buffer[size] = '\n';
    buffer[size + 1] = 0;

    ListView_DeleteAllItems(g_hLV);

    p = buffer;
    lineStart = p;

    while (*p) {
        if (*p == '\n') {
            char saved = *p;
            *p = 0;
            TrimTrailingCrLf(lineStart);

            if (lineIndex == 0) {
                int hc = 0;
                char **fields = CsvParseLine(lineStart, &hc);
                int i;

                g_cols = (hc > DEF_COLS) ? hc : DEF_COLS;
                if (g_cols > MAX_COLS) g_cols = MAX_COLS;

                InitHeaders();

                for (i = 0; i < hc && i < MAX_COLS; i++) {
                    if (fields && fields[i] && fields[i][0]) {
                        SafeCopy(g_headers[i], sizeof(g_headers[i]), fields[i]);
                    }
                }

                FreeFields(fields, hc);
                RebuildColumns();
            } else {
                if (lineStart[0] != 0) {
                    int fc = 0;
                    char **fields = CsvParseLine(lineStart, &fc);
                    int row = AddListRowAtEnd();
                    int c;

                    for (c = 0; c < g_cols; c++) {
                        if (fields && c < fc && fields[c]) SetListCell(row, c, fields[c]);
                        else SetListCell(row, c, "");
                    }

                    FreeFields(fields, fc);
                }
            }

            *p = saved;
            p++;
            lineStart = p;
            lineIndex++;
        } else {
            p++;
        }
    }

    free(buffer);

    SafeCopy(g_curFile, sizeof(g_curFile), path);
    g_dirty = 0;
    g_sortCol = -1;
    g_sortAsc = 1;

    WritePrivateProfileStringA("Recent", "LastFile", g_curFile, g_iniPath);
    UpdateFileLabel();

    return 1;
}

static int SaveCsv(const char *path)
{
    FILE *f;
    int c, r, rows;
    char cell[MAX_CELL];

    f = fopen(path, "wb");
    if (!f) return 0;

    for (c = 0; c < g_cols; c++) {
        if (c > 0) fputc(',', f);
        CsvWriteField(f, g_headers[c]);
    }
    fputs("\r\n", f);

    rows = ListView_GetItemCount(g_hLV);

    for (r = 0; r < rows; r++) {
        for (c = 0; c < g_cols; c++) {
            if (c > 0) fputc(',', f);
            GetListCell(r, c, cell, sizeof(cell));
            CsvWriteField(f, cell);
        }
        fputs("\r\n", f);
    }

    fclose(f);

    SafeCopy(g_curFile, sizeof(g_curFile), path);
    g_dirty = 0;
    WritePrivateProfileStringA("Recent", "LastFile", g_curFile, g_iniPath);
    UpdateFileLabel();
    return 1;
}

static void DoBrowse(void)
{
    char file[MAX_PATH] = {0};
    OPENFILENAMEA ofn;

    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_hMain;
    ofn.lpstrFilter = "CSV files (*.csv)\0*.csv\0All files (*.*)\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = sizeof(file);
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrDefExt = "csv";

    if (GetOpenFileNameA(&ofn)) LoadCsv(file);
}

static void DoSave(void)
{
    if (g_curFile[0]) {
        SaveCsv(g_curFile);
        return;
    }

    char file[MAX_PATH] = {0};
    OPENFILENAMEA ofn;

    memset(&ofn, 0, sizeof(ofn));
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = g_hMain;
    ofn.lpstrFilter = "CSV files (*.csv)\0*.csv\0All files (*.*)\0*.*\0";
    ofn.lpstrFile = file;
    ofn.nMaxFile = sizeof(file);
    ofn.Flags = OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST | OFN_HIDEREADONLY;
    ofn.lpstrDefExt = "csv";

    if (GetSaveFileNameA(&ofn)) SaveCsv(file);
}

static void AddRow(void)
{
    int row = AddListRowAtEnd();
    int c;

    for (c = 1; c < g_cols; c++) SetListCell(row, c, "");

    ListView_SetItemState(g_hLV, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);
    ListView_SetItemState(g_hLV, row, LVIS_SELECTED | LVIS_FOCUSED, LVIS_SELECTED | LVIS_FOCUSED);
    ListView_EnsureVisible(g_hLV, row, FALSE);

    g_dirty = 1;
    UpdateFileLabel();
}

static void DeleteSelectedRows(void)
{
    int selected[4096];
    int n = 0;
    int i;
    int idx = -1;

    while ((idx = ListView_GetNextItem(g_hLV, idx, LVNI_SELECTED)) != -1) {
        if (n < 4096) selected[n++] = idx;
    }

    if (n <= 0) return;

    for (i = n - 1; i >= 0; i--) ListView_DeleteItem(g_hLV, selected[i]);

    g_dirty = 1;
    UpdateFileLabel();
}

static void SwapRows(int r1, int r2)
{
    int c;
    char a[MAX_CELL];
    char b[MAX_CELL];

    if (r1 < 0 || r2 < 0) return;
    if (r1 >= ListView_GetItemCount(g_hLV)) return;
    if (r2 >= ListView_GetItemCount(g_hLV)) return;

    for (c = 0; c < g_cols; c++) {
        GetListCell(r1, c, a, sizeof(a));
        GetListCell(r2, c, b, sizeof(b));
        SetListCell(r1, c, b);
        SetListCell(r2, c, a);
    }
}

static void MoveSelectedRows(int dir)
{
    int selected[4096];
    int n = 0;
    int idx = -1;
    int i;
    int count = ListView_GetItemCount(g_hLV);

    while ((idx = ListView_GetNextItem(g_hLV, idx, LVNI_SELECTED)) != -1) {
        if (n < 4096) selected[n++] = idx;
    }

    if (n <= 0) return;

    if (dir < 0) {
        if (selected[0] <= 0) return;
        for (i = 0; i < n; i++) {
            SwapRows(selected[i], selected[i] - 1);
            selected[i]--;
        }
    } else {
        if (selected[n - 1] >= count - 1) return;
        for (i = n - 1; i >= 0; i--) {
            SwapRows(selected[i], selected[i] + 1);
            selected[i]++;
        }
    }

    ListView_SetItemState(g_hLV, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);

    for (i = 0; i < n; i++) {
        ListView_SetItemState(g_hLV, selected[i],
            LVIS_SELECTED | (i == 0 ? LVIS_FOCUSED : 0),
            LVIS_SELECTED | LVIS_FOCUSED);
    }

    g_dirty = 1;
    UpdateFileLabel();
}

static void SortByColumn(int col)
{
    int rows, r, c, i, j;
    RowData *data;

    if (col < 0 || col >= g_cols) return;

    if (g_sortCol == col) g_sortAsc = !g_sortAsc;
    else {
        g_sortCol = col;
        g_sortAsc = 1;
    }

    rows = ListView_GetItemCount(g_hLV);
    if (rows <= 1) return;

    data = (RowData *)calloc((size_t)rows, sizeof(RowData));
    if (!data) return;

    for (r = 0; r < rows; r++) {
        data[r].cells = (char **)calloc((size_t)g_cols, sizeof(char *));
        for (c = 0; c < g_cols; c++) {
            char buf[MAX_CELL];
            GetListCell(r, c, buf, sizeof(buf));
            data[r].cells[c] = (char *)calloc(strlen(buf) + 1, 1);
            if (data[r].cells[c]) strcpy(data[r].cells[c], buf);
        }
    }

    for (i = 0; i < rows - 1; i++) {
        for (j = i + 1; j < rows; j++) {
            char *a = data[i].cells[col] ? data[i].cells[col] : "";
            char *b = data[j].cells[col] ? data[j].cells[col] : "";
            int cmp = lstrcmpiA(a, b);
            int doSwap = g_sortAsc ? (cmp > 0) : (cmp < 0);

            if (doSwap) {
                RowData tmp = data[i];
                data[i] = data[j];
                data[j] = tmp;
            }
        }
    }

    ListView_DeleteAllItems(g_hLV);

    for (r = 0; r < rows; r++) {
        int row = AddListRowAtEnd();
        for (c = 0; c < g_cols; c++) SetListCell(row, c, data[r].cells[c] ? data[r].cells[c] : "");
    }

    for (r = 0; r < rows; r++) {
        for (c = 0; c < g_cols; c++) free(data[r].cells[c]);
        free(data[r].cells);
    }
    free(data);

    g_dirty = 1;
    UpdateFileLabel();
}

static void BeginDrag(void)
{
    if (ListView_GetSelectedCount(g_hLV) <= 0) return;
    g_dragging = 1;
    g_dragTarget = -1;
    SetCapture(g_hMain);
    DrawInsertMark(-1);
}

static int ComputeDragTarget(int x, int y)
{
    LVHITTESTINFO ht;
    int count, row;
    RECT rc;

    count = ListView_GetItemCount(g_hLV);
    if (count <= 0) return 0;

    memset(&ht, 0, sizeof(ht));
    ht.pt.x = x;
    ht.pt.y = y;

    row = ListView_HitTest(g_hLV, &ht);

    if (row < 0) {
        if (ListView_GetItemRect(g_hLV, count - 1, &rc, LVIR_BOUNDS)) {
            if (y >= rc.bottom) return count;
        }
        return 0;
    }

    if (ListView_GetItemRect(g_hLV, row, &rc, LVIR_BOUNDS)) {
        int mid = (rc.top + rc.bottom) / 2;
        if (y < mid) return row;
        return row + 1;
    }

    return row;
}

static void DrawInsertMark(int target)
{
    PCE_LVINSERTMARK im;
    int count;

    memset(&im, 0, sizeof(im));
    im.cbSize = sizeof(im);

    if (target < 0) {
        im.iItem = -1;
        im.dwFlags = 0;
    } else {
        count = ListView_GetItemCount(g_hLV);
        if (count <= 0) {
            im.iItem = -1;
            im.dwFlags = 0;
        } else if (target >= count) {
            im.iItem = count - 1;
            im.dwFlags = LVIM_AFTER;
        } else {
            im.iItem = target;
            im.dwFlags = 0;
        }
    }

    SendMessage(g_hLV, LVM_SETINSERTMARK, 0, (LPARAM)&im);
}

static void ReorderSelectedRowsBefore(int target)
{
    int selected[4096];
    int n = 0;
    int idx = -1;
    int count, i, c, adjusted, newCount;
    RowData *snap;

    count = ListView_GetItemCount(g_hLV);
    if (count <= 1) return;

    while ((idx = ListView_GetNextItem(g_hLV, idx, LVNI_SELECTED)) != -1) {
        if (n < 4096) selected[n++] = idx;
    }

    if (n <= 0) return;

    if (target < 0) target = 0;
    if (target > count) target = count;

    for (i = 0; i < n; i++) {
        if (target == selected[i] || target == selected[i] + 1) return;
    }

    snap = (RowData *)calloc((size_t)n, sizeof(RowData));
    if (!snap) return;

    for (i = 0; i < n; i++) {
        snap[i].cells = (char **)calloc((size_t)g_cols, sizeof(char *));
        for (c = 0; c < g_cols; c++) {
            char buf[MAX_CELL];
            GetListCell(selected[i], c, buf, sizeof(buf));
            snap[i].cells[c] = (char *)calloc(strlen(buf) + 1, 1);
            if (snap[i].cells[c]) strcpy(snap[i].cells[c], buf);
        }
    }

    adjusted = target;
    for (i = 0; i < n; i++) {
        if (selected[i] < target) adjusted--;
    }
    if (adjusted < 0) adjusted = 0;

    for (i = n - 1; i >= 0; i--) ListView_DeleteItem(g_hLV, selected[i]);

    newCount = ListView_GetItemCount(g_hLV);
    if (adjusted > newCount) adjusted = newCount;

    for (i = 0; i < n; i++) {
        int row = InsertListRow(adjusted + i);
        for (c = 0; c < g_cols; c++) SetListCell(row, c, snap[i].cells[c] ? snap[i].cells[c] : "");
    }

    ListView_SetItemState(g_hLV, -1, 0, LVIS_SELECTED | LVIS_FOCUSED);

    for (i = 0; i < n; i++) {
        ListView_SetItemState(g_hLV, adjusted + i,
            LVIS_SELECTED | (i == 0 ? LVIS_FOCUSED : 0),
            LVIS_SELECTED | LVIS_FOCUSED);
    }

    ListView_EnsureVisible(g_hLV, adjusted, FALSE);

    for (i = 0; i < n; i++) {
        for (c = 0; c < g_cols; c++) free(snap[i].cells[c]);
        free(snap[i].cells);
    }
    free(snap);

    g_dirty = 1;
    UpdateFileLabel();
}

static LRESULT CALLBACK InplaceEditProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_KEYDOWN:
        if (wp == VK_RETURN) {
            EndInplaceEdit(1);
            return 0;
        }
        if (wp == VK_ESCAPE) {
            EndInplaceEdit(0);
            return 0;
        }
        break;

    case WM_KILLFOCUS:
        EndInplaceEdit(1);
        return 0;
    }

    return CallWindowProc(g_oldEditProc, hwnd, msg, wp, lp);
}

static void StartInplaceEdit(int row, int col)
{
    RECT rc;
    char text[MAX_CELL];
    int width, height;

    EndInplaceEdit(1);

    if (row < 0 || col < 0) return;
    if (!ListView_GetSubItemRect(g_hLV, row, col, LVIR_BOUNDS, &rc)) return;

    if (col == 0) rc.right = rc.left + ListView_GetColumnWidth(g_hLV, 0);

    width = rc.right - rc.left;
    height = rc.bottom - rc.top;

    if (width < 40) width = 80;
    if (height < 18) height = 22;

    GetListCell(row, col, text, sizeof(text));

    g_hInplaceEdit = CreateWindowExA(0, "EDIT", text,
        WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL,
        rc.left, rc.top, width, height,
        g_hLV, NULL, g_hInst, NULL);

    if (!g_hInplaceEdit) return;

    SendMessage(g_hInplaceEdit, WM_SETFONT, (WPARAM)g_hFont, TRUE);
    SendMessage(g_hInplaceEdit, EM_SETSEL, 0, -1);

    g_oldEditProc = (WNDPROC)SetWindowLongPtr(g_hInplaceEdit, GWLP_WNDPROC, (LONG_PTR)InplaceEditProc);

    g_editRow = row;
    g_editCol = col;

    SetFocus(g_hInplaceEdit);
}

static void EndInplaceEdit(int save)
{
    char text[MAX_CELL];

    if (!g_hInplaceEdit) return;

    if (save && g_editRow >= 0 && g_editCol >= 0) {
        GetWindowTextA(g_hInplaceEdit, text, sizeof(text));
        SetListCell(g_editRow, g_editCol, text);
        g_dirty = 1;
        UpdateFileLabel();
    }

    DestroyWindow(g_hInplaceEdit);

    g_hInplaceEdit = NULL;
    g_oldEditProc = NULL;
    g_editRow = -1;
    g_editCol = -1;
}

static void ShowEditDialog(int row)
{
    int dlgH, y, c;
    char title[64];

    if (row < 0 || row >= ListView_GetItemCount(g_hLV)) return;

    if (g_hEditDlg) {
        DestroyWindow(g_hEditDlg);
        g_hEditDlg = NULL;
    }

    memset(g_editLabels, 0, sizeof(g_editLabels));
    memset(g_editInputs, 0, sizeof(g_editInputs));
    g_editSaveBtn = NULL;
    g_editCloseBtn = NULL;

    dlgH = 110 + (g_cols * 32);
    if (dlgH < 300) dlgH = 300;
    if (dlgH > 760) dlgH = 760;

    wsprintfA(title, "Edit Row %d", row + 1);

    g_hEditDlg = CreateWindowExA(WS_EX_DLGMODALFRAME, EDIT_CLASS, title,
        WS_CAPTION | WS_SYSMENU | WS_SIZEBOX | WS_MAXIMIZEBOX | WS_VISIBLE | WS_POPUP,
        CW_USEDEFAULT, CW_USEDEFAULT, 660, dlgH,
        g_hMain, NULL, g_hInst, NULL);

    if (!g_hEditDlg) return;

    g_editDlgRow = row;

    y = 14;

    for (c = 0; c < g_cols; c++) {
        char cell[MAX_CELL];

        g_editLabels[c] = CreateWindowExA(0, "STATIC", g_headers[c],
            WS_CHILD | WS_VISIBLE,
            12, y + 4, 140, 20,
            g_hEditDlg, (HMENU)(INT_PTR)(ID_EDIT_BASE_LABEL + c), g_hInst, NULL);

        SendMessage(g_editLabels[c], WM_SETFONT, (WPARAM)g_hFont, TRUE);

        GetListCell(row, c, cell, sizeof(cell));

        g_editInputs[c] = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", cell,
            WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
            160, y, 430, 24,
            g_hEditDlg, (HMENU)(INT_PTR)(ID_EDIT_BASE_INPUT + c), g_hInst, NULL);

        SendMessage(g_editInputs[c], WM_SETFONT, (WPARAM)g_hFont, TRUE);

        y += 32;
}

    g_editSaveBtn = CreateWindowExA(0, "BUTTON", "Save",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        390, dlgH - 70, 90, 28,
        g_hEditDlg, (HMENU)(INT_PTR)ID_EDIT_SAVE, g_hInst, NULL);

    g_editCloseBtn = CreateWindowExA(0, "BUTTON", "Close",
        WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
        500, dlgH - 70, 90, 28,
        g_hEditDlg, (HMENU)(INT_PTR)ID_EDIT_CLOSE, g_hInst, NULL);

    SendMessage(g_editSaveBtn, WM_SETFONT, (WPARAM)g_hFont, TRUE);
    SendMessage(g_editCloseBtn, WM_SETFONT, (WPARAM)g_hFont, TRUE);

    LayoutEditDialog(g_hEditDlg);

    ShowWindow(g_hEditDlg, SW_SHOW);
    UpdateWindow(g_hEditDlg);
}

static void CloseEditDialog(void)
{
    if (g_hEditDlg) {
        DestroyWindow(g_hEditDlg);
        g_hEditDlg = NULL;
    }

    g_editDlgRow = -1;
    memset(g_editLabels, 0, sizeof(g_editLabels));
    memset(g_editInputs, 0, sizeof(g_editInputs));
    g_editSaveBtn = NULL;
    g_editCloseBtn = NULL;
}

static void SaveEditDialog(void)
{
    int c;
    char text[MAX_CELL];

    if (!g_hEditDlg) return;
    if (g_editDlgRow < 0) return;

    for (c = 0; c < g_cols; c++) {
        if (g_editInputs[c]) {
            GetWindowTextA(g_editInputs[c], text, sizeof(text));
            SetListCell(g_editDlgRow, c, text);
        }
    }

    g_dirty = 1;
    UpdateFileLabel();
}

static LRESULT CALLBACK EditWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_SIZE:
        LayoutEditDialog(hwnd);
        return 0;

    case WM_GETMINMAXINFO:
    {
        MINMAXINFO *mmi = (MINMAXINFO *)lp;
        mmi->ptMinTrackSize.x = EDIT_MIN_W;
        mmi->ptMinTrackSize.y = EDIT_MIN_H;
        return 0;
    }

    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case ID_EDIT_SAVE:
            SaveEditDialog();
            return 0;

        case ID_EDIT_CLOSE:
            CloseEditDialog();
            return 0;
        }
        break;

    case WM_CLOSE:
        CloseEditDialog();
        return 0;

    case WM_DESTROY:
        if (hwnd == g_hEditDlg) {
            g_hEditDlg = NULL;
            g_editDlgRow = -1;
            memset(g_editLabels, 0, sizeof(g_editLabels));
            memset(g_editInputs, 0, sizeof(g_editInputs));
            g_editSaveBtn = NULL;
            g_editCloseBtn = NULL;
        }
        return 0;
    }

    return DefWindowProc(hwnd, msg, wp, lp);
}

static LRESULT CALLBACK MainWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE:
    {
        char last[MAX_PATH];
        char defaultCsv[MAX_PATH];

        g_hMain = hwnd;
        g_hFont = (HFONT)GetStockObject(DEFAULT_GUI_FONT);

        g_hFileLabel = CreateWindowExA(0, "STATIC", "",
            WS_CHILD | WS_VISIBLE | SS_LEFTNOWORDWRAP | SS_SUNKEN,
            0, 0, 100, TOP_LABEL_H,
            hwnd, (HMENU)(INT_PTR)ID_LABEL_FILE, g_hInst, NULL);
        SendMessage(g_hFileLabel, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        g_hLV = CreateWindowExA(WS_EX_CLIENTEDGE, WC_LISTVIEWA, "",
            WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SHOWSELALWAYS,
            0, 0, 100, 100,
            hwnd, (HMENU)(INT_PTR)ID_LV, g_hInst, NULL);

        ListView_SetExtendedListViewStyle(g_hLV,
            LVS_EX_FULLROWSELECT | LVS_EX_GRIDLINES | LVS_EX_DOUBLEBUFFER | LVS_EX_HEADERDRAGDROP);

        SendMessage(g_hLV, WM_SETFONT, (WPARAM)g_hFont, TRUE);

        InitHeaders();
        RebuildColumns();

        g_btnBrowse = CreateWindowExA(0, "BUTTON", "Browse",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 80, BTN_H, hwnd, (HMENU)(INT_PTR)ID_BROWSE, g_hInst, NULL);

        g_btnSave = CreateWindowExA(0, "BUTTON", "Save",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 80, BTN_H, hwnd, (HMENU)(INT_PTR)ID_SAVE, g_hInst, NULL);

        g_btnAdd = CreateWindowExA(0, "BUTTON", "Add Row",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 80, BTN_H, hwnd, (HMENU)(INT_PTR)ID_ADD, g_hInst, NULL);

        g_btnDelete = CreateWindowExA(0, "BUTTON", "Delete Row",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 80, BTN_H, hwnd, (HMENU)(INT_PTR)ID_DELETE, g_hInst, NULL);

        g_btnUp = CreateWindowExA(0, "BUTTON", "+",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 80, BTN_H, hwnd, (HMENU)(INT_PTR)ID_UP, g_hInst, NULL);

        g_btnDown = CreateWindowExA(0, "BUTTON", "-",
            WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            0, 0, 80, BTN_H, hwnd, (HMENU)(INT_PTR)ID_DOWN, g_hInst, NULL);

        g_chkDirect = CreateWindowExA(0, "BUTTON", "Direct Edit",
            WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX,
            0, 0, 120, BTN_H, hwnd, (HMENU)(INT_PTR)ID_DIRECT, g_hInst, NULL);

        SendMessage(g_btnBrowse, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_btnSave, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_btnAdd, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_btnDelete, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_btnUp, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_btnDown, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_chkDirect, WM_SETFONT, (WPARAM)g_hFont, TRUE);
        SendMessage(g_chkDirect, BM_SETCHECK, g_directEdit ? BST_CHECKED : BST_UNCHECKED, 0);

        LayoutControls();
        UpdateFileLabel();

        MakeDefaultCsvPath(defaultCsv, sizeof(defaultCsv));
        GetPrivateProfileStringA("Recent", "LastFile", defaultCsv, last, sizeof(last), g_iniPath);

        if (GetFileAttributesA(last) != INVALID_FILE_ATTRIBUTES) {
            LoadCsv(last);
        } else {
            SafeCopy(g_curFile, sizeof(g_curFile), last);
            UpdateFileLabel();
        }

        return 0;
    }

    case WM_SIZE:
        LayoutControls();
        return 0;

    case WM_GETMINMAXINFO:
    {
        MINMAXINFO *mmi = (MINMAXINFO *)lp;
        mmi->ptMinTrackSize.x = MIN_W;
        mmi->ptMinTrackSize.y = MIN_H;
        return 0;
    }

    case WM_COMMAND:
    {
        int id = LOWORD(wp);

        switch (id) {
        case ID_BROWSE:
            EndInplaceEdit(1);
            DoBrowse();
            return 0;

        case ID_SAVE:
            EndInplaceEdit(1);
            DoSave();
            return 0;

        case ID_ADD:
            EndInplaceEdit(1);
            AddRow();
            return 0;

        case ID_DELETE:
            EndInplaceEdit(1);
            DeleteSelectedRows();
            return 0;

        case ID_UP:
            EndInplaceEdit(1);
            MoveSelectedRows(-1);
            return 0;

        case ID_DOWN:
            EndInplaceEdit(1);
            MoveSelectedRows(1);
            return 0;

        case ID_DIRECT:
            g_directEdit = (SendMessage(g_chkDirect, BM_GETCHECK, 0, 0) == BST_CHECKED);
            WritePrivateProfileStringA("Settings", "DirectEdit", g_directEdit ? "1" : "0", g_iniPath);
            if (!g_directEdit) EndInplaceEdit(1);
            return 0;
        }
        break;
    }

    case WM_NOTIFY:
    {
        NMHDR *hdr = (NMHDR *)lp;

        if (hdr->hwndFrom == g_hLV) {
            switch (hdr->code) {
            case NM_DBLCLK:
            {
                NMITEMACTIVATE *ia = (NMITEMACTIVATE *)lp;
                int row = ia->iItem;
                int col = ia->iSubItem;

                if (row < 0) return 0;
                if (col < 0) col = 0;

                if (g_directEdit) StartInplaceEdit(row, col);
                else ShowEditDialog(row);
                return 0;
            }

            case LVN_COLUMNCLICK:
            {
                NMLISTVIEW *nl = (NMLISTVIEW *)lp;
                SortByColumn(nl->iSubItem);
                return 0;
            }

            case LVN_BEGINDRAG:
                BeginDrag();
                return 0;
            }
        }

        break;
    }

    case WM_MOUSEMOVE:
        if (g_dragging) {
            POINT pt;
            RECT rcLV;

            pt.x = GET_X_LPARAM(lp);
            pt.y = GET_Y_LPARAM(lp);

            GetWindowRect(g_hLV, &rcLV);

            {
                POINT topLeft;
                topLeft.x = rcLV.left;
                topLeft.y = rcLV.top;
                ScreenToClient(hwnd, &topLeft);

                pt.x -= topLeft.x;
                pt.y -= topLeft.y;
            }

            g_dragTarget = ComputeDragTarget(pt.x, pt.y);
            DrawInsertMark(g_dragTarget);
            SetCursor(LoadCursor(NULL, IDC_SIZENS));
        }
        return 0;

    case WM_LBUTTONUP:
        if (g_dragging) {
            g_dragging = 0;
            ReleaseCapture();
            DrawInsertMark(-1);

            if (g_dragTarget >= 0) ReorderSelectedRowsBefore(g_dragTarget);
            g_dragTarget = -1;
        }
        return 0;

    case WM_CLOSE:
        EndInplaceEdit(1);
        SaveSettings();
        DestroyWindow(hwnd);
        return 0;

    case WM_DESTROY:
        SaveSettings();
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProc(hwnd, msg, wp, lp);
}

int WINAPI WinMain(HINSTANCE hInst, HINSTANCE hPrev, LPSTR lpCmd, int nShow)
{
    INITCOMMONCONTROLSEX icc;
    WNDCLASSEXA wc;
    WNDCLASSEXA we;
    MSG msg;
    int x, y, w, h, maximized;

    (void)hPrev;
    (void)lpCmd;

    g_hInst = hInst;

    icc.dwSize = sizeof(icc);
    icc.dwICC = ICC_LISTVIEW_CLASSES | ICC_STANDARD_CLASSES;
    InitCommonControlsEx(&icc);

    ResolveIniPath();
    LoadSettings(&x, &y, &w, &h, &maximized);

    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = MainWndProc;
    wc.hInstance = hInst;
    wc.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    wc.hIconSm = wc.hIcon;
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    wc.lpszClassName = MAIN_CLASS;
    RegisterClassExA(&wc);

    memset(&we, 0, sizeof(we));
    we.cbSize = sizeof(we);
    we.lpfnWndProc = EditWndProc;
    we.hInstance = hInst;
    we.hIcon = LoadIcon(NULL, IDI_APPLICATION);
    we.hIconSm = we.hIcon;
    we.hCursor = LoadCursor(NULL, IDC_ARROW);
    we.hbrBackground = (HBRUSH)(COLOR_BTNFACE + 1);
    we.lpszClassName = EDIT_CLASS;
    RegisterClassExA(&we);

    g_hMain = CreateWindowExA(0, MAIN_CLASS, APP_TITLE,
        WS_OVERLAPPEDWINDOW,
        x, y, w, h,
        NULL, NULL, hInst, NULL);

    if (!g_hMain) return 0;

    ShowWindow(g_hMain, maximized ? SW_SHOWMAXIMIZED : nShow);
    UpdateWindow(g_hMain);

    while (GetMessage(&msg, NULL, 0, 0)) {
        if (g_hEditDlg && IsDialogMessage(g_hEditDlg, &msg)) continue;
        TranslateMessage(&msg);
        DispatchMessage(&msg);
    }

    return (int)msg.wParam;
}

