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
folder = BrowseForFolderModern("Select a folder to add to PATH")

If folder = "" Then
    WScript.Echo "Cancelled."
    WScript.Quit
End If

WScript.Echo "Selected: " & folder

Function BrowseForFolderModern(prompt)
    Dim objShell, objFolder
    Set objShell = CreateObject("Shell.Application")
    Set objFolder = objShell.BrowseForFolder(0, prompt, &H10, 0)
    If objFolder Is Nothing Then
        BrowseForFolderModern = ""
    Else
        BrowseForFolderModern = objFolder.Self.Path
    End If
End Function

' ============================================================
'  Add folder to SYSTEM PATH
' ============================================================
Dim wsh, env, currentPath, newPath
Set wsh = CreateObject("WScript.Shell")
Set env = wsh.Environment("SYSTEM")

currentPath = env("Path")

' Normalize slashes
folder = Replace(folder, "/", "\")

' Check if already present
If InStr(1, ";" & LCase(currentPath) & ";", ";" & LCase(folder) & ";") > 0 Then
    WScript.Echo "Folder already exists in PATH."
Else
    If Right(currentPath, 1) = ";" Then
        newPath = currentPath & folder
    Else
        newPath = currentPath & ";" & folder
    End If

    env("Path") = newPath
    WScript.Echo "Added to PATH: " & folder
End If

' ============================================================
'  Broadcast WM_SETTINGCHANGE so PATH updates immediately
' ============================================================
Call RefreshEnvironment()

Sub RefreshEnvironment()
    Dim HWND_BROADCAST, WM_SETTINGCHANGE
    HWND_BROADCAST = &HFFFF
    WM_SETTINGCHANGE = &H1A

    Dim shell
    Set shell = CreateObject("WScript.Shell")
    shell.Run "powershell -command ""[void][Windows.Win32.PInvoke]::SendMessage([IntPtr]" & HWND_BROADCAST & ", " & WM_SETTINGCHANGE & ", 0, 'Environment')""", 0, True
End Sub

WScript.Echo "PATH updated successfully."
