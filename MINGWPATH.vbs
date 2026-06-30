Option Explicit

' ============================================================
'  Auto‑elevate to Administrator
' ============================================================
If Not IsAdmin() Then
    CreateObject("Shell.Application").ShellExecute _
        "wscript.exe", Chr(34) & WScript.ScriptFullName & Chr(34), "", "runas", 1
    WScript.Quit
End If

Function IsAdmin()
    On Error Resume Next
    Dim fso: Set fso = CreateObject("Scripting.FileSystemObject")
    fso.CreateTextFile("C:\Windows\Temp\admin_test.txt", True).Write "test"
    If Err.Number = 0 Then
        fso.DeleteFile("C:\Windows\Temp\admin_test.txt")
        IsAdmin = True
    Else
        IsAdmin = False
    End If
    On Error GoTo 0
End Function

' ============================================================
'  Modern Folder Picker (Shell FileOpenDialog)
' ============================================================
Dim folder
folder = BrowseForFolderModern("Select your MinGW‑w64 folder")

If folder = "" Then
    WScript.Echo "Cancelled."
    WScript.Quit
End If

WScript.Echo "Selected: " & folder

Function BrowseForFolderModern(prompt)
    Dim objShell, objFolder
    Set objShell = CreateObject("Shell.Application")

    ' Use FileOpenDialog in folder mode
    Set objFolder = objShell.BrowseForFolder(0, prompt, &H10, 0)
    ' &H10 = BIF_NEWDIALOGSTYLE (modern dialog)

    If objFolder Is Nothing Then
        BrowseForFolderModern = ""
    Else
        BrowseForFolderModern = objFolder.Self.Path
    End If
End Function

' ============================================================
'  Build list of possible MinGW bin folders
' ============================================================
Dim fso, binPaths, p
Set fso = CreateObject("Scripting.FileSystemObject")

binPaths = Array( _
    folder & "\bin", _
    folder & "\mingw64\bin", _
    folder & "\mingw32\bin", _
    folder & "\usr\bin" _
)

' ============================================================
'  Read