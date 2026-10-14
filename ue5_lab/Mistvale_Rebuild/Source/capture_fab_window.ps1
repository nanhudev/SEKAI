param([string]$ProcessName='EpicGamesLauncher',[string]$FileName='FabWindow.png')
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class WinWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
}
'@
$target = Get-Process -Name $ProcessName -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $target) { throw "No visible $ProcessName window" }
$h = [IntPtr]$target.MainWindowHandle
[WinWindow]::ShowWindow($h, 9) | Out-Null
[WinWindow]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 600
$rect = New-Object WinWindow+RECT
[WinWindow]::GetWindowRect($h, [ref]$rect) | Out-Null
$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
if ($width -lt 200 -or $height -lt 200) { throw "Invalid window size ${width}x${height}" }
$bitmap = [Drawing.Bitmap]::new($width,$height)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,[Drawing.Size]::new($width,$height))
$out = Join-Path (Split-Path -Parent $PSScriptRoot) ("Saved\"+$FileName)
$bitmap.Save($out,[Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
Write-Output "Saved $out $width x $height"
