' Silent launcher for the HRMS PM2 logon task.
' Task Scheduler + powershell -WindowStyle Hidden still opens a blank console
' on interactive logon; WScript Run with window style 0 keeps it fully hidden.
Option Explicit

Dim shell, scriptDir, ps1Path, command, exitCode
Set shell = CreateObject("WScript.Shell")

scriptDir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
ps1Path = scriptDir & "\start-pm2-at-logon.ps1"

command = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & ps1Path & """ -SilentHost"
exitCode = shell.Run(command, 0, True)

WScript.Quit exitCode
