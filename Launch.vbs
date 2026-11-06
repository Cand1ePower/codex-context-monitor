Option Explicit
Dim shell, fso, folder, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
command = "powershell.exe -NoLogo -NoProfile -WindowStyle Hidden -File " & Chr(34) & folder & "\Watch-Codex.ps1" & Chr(34)
shell.Run command, 0, False
