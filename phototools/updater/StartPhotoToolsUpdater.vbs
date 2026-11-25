Option Explicit
Dim fso, sh, scriptDir, ps1Path, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = fso.BuildPath(scriptDir, "PhotoToolsUpdater.ps1")
If Not fso.FileExists(ps1Path) Then
    MsgBox "PhotoToolsUpdater.ps1 was not found in: " & scriptDir, vbCritical, "PhotoTools Updater"
    WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & ps1Path & Chr(34)
sh.Run cmd, 0, False
