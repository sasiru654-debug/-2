Option Explicit
If WScript.Arguments.Count < 1 Then WScript.Quit 1
Dim sh, cmd, i, a
Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File " & Chr(34) & WScript.Arguments(0) & Chr(34)
For i = 1 To WScript.Arguments.Count - 1
    a = WScript.Arguments(i)
    If Len(a) > 3 And Right(a, 1) = "\" Then a = Left(a, Len(a) - 1)
    If a = "-TargetPath" Or a = "-ForceEditor" Then
        cmd = cmd & " " & a
    Else
        cmd = cmd & " " & Chr(34) & Replace(a, Chr(34), Chr(34) & Chr(34)) & Chr(34)
    End If
Next
sh.Run cmd, 0, False
