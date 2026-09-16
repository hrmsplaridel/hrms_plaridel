# Registers a Windows printer form named "8.5 x 13" (Philippine long bond).
$ErrorActionPreference = 'Stop'
$formName = '8.5 x 13'

Add-Type @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct WinSpoolSize {
  public int cx;
  public int cy;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct WinSpoolRect {
  public int left;
  public int top;
  public int right;
  public int bottom;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct FormInfo1 {
  public uint Flags;
  public string pName;
  public WinSpoolSize Size;
  public WinSpoolRect ImageableArea;
}

public static class WinSpoolForms {
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "OpenPrinterW")]
  public static extern bool OpenPrinter(IntPtr pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "OpenPrinterW")]
  public static extern bool OpenPrinterName(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool AddForm(IntPtr hPrinter, int Level, ref FormInfo1 pForm);

  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  public static extern bool DeleteForm(IntPtr hPrinter, string pFormName);

  [DllImport("winspool.drv", SetLastError = true)]
  public static extern bool ClosePrinter(IntPtr hPrinter);
}
"@

function Open-Spooler([string]$name) {
  $handle = [IntPtr]::Zero
  $ok = $false
  if ([string]::IsNullOrEmpty($name)) {
    $ok = [WinSpoolForms]::OpenPrinter([IntPtr]::Zero, [ref]$handle, [IntPtr]::Zero)
  } else {
    $ok = [WinSpoolForms]::OpenPrinterName($name, [ref]$handle, [IntPtr]::Zero)
  }
  if ($ok) { return $handle }
  return [IntPtr]::Zero
}

$candidates = @('', 'Microsoft Print to PDF')
try {
  $candidates += @(Get-Printer | ForEach-Object { $_.Name })
} catch {}

$hPrinter = [IntPtr]::Zero
$openedName = $null
foreach ($name in $candidates) {
  $hPrinter = Open-Spooler $name
  if ($hPrinter -ne [IntPtr]::Zero) {
    $openedName = $(if ($name) { $name } else { 'local print server' })
    break
  }
}

if ($hPrinter -eq [IntPtr]::Zero) {
  throw "OpenPrinter failed (win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
}

try {
  [void][WinSpoolForms]::DeleteForm($hPrinter, $formName)
  # Thousandths of a millimeter. Assign nested structs as wholes
  # (PowerShell copies value types, so Size.cx = x would not stick).
  $w = [int][Math]::Round(8.5 * 25.4 * 1000)
  $h = [int][Math]::Round(13.0 * 25.4 * 1000)
  $size = New-Object WinSpoolSize
  $size.cx = $w
  $size.cy = $h
  $area = New-Object WinSpoolRect
  $area.left = 0
  $area.top = 0
  $area.right = $w
  $area.bottom = $h
  $form = New-Object FormInfo1
  $form.Flags = 0
  $form.pName = $formName
  $form.Size = $size
  $form.ImageableArea = $area
  $ok = [WinSpoolForms]::AddForm($hPrinter, 1, [ref]$form)
  if (-not $ok) {
    throw "AddForm failed (win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
  }
  Write-Output "Registered printer form '$formName' on '$openedName'."
} finally {
  if ($hPrinter -ne [IntPtr]::Zero) {
    [void][WinSpoolForms]::ClosePrinter($hPrinter)
  }
}
