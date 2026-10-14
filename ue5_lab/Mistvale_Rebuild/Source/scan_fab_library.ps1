param([int]$Pages=9)
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FabScan {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
$target=Get-Process -Name EpicGamesLauncher -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $target) { throw 'No Epic Launcher window' }
$h=[IntPtr]$target.MainWindowHandle
[FabScan]::SetForegroundWindow($h) | Out-Null
$rect=New-Object FabScan+RECT
[FabScan]::GetWindowRect($h,[ref]$rect) | Out-Null
$width=$rect.Right-$rect.Left
$height=$rect.Bottom-$rect.Top
$outdir=Join-Path (Split-Path -Parent $PSScriptRoot) 'Saved\FabLibraryScan'
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
for ($i=0; $i -lt $Pages; $i++) {
    Start-Sleep -Milliseconds 800
    $bitmap=[Drawing.Bitmap]::new($width,$height)
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,[Drawing.Size]::new($width,$height))
    $path=Join-Path $outdir ('library_{0:d2}.png' -f $i)
    $bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    [FabScan]::SetCursorPos($rect.Left+1100,$rect.Top+500) | Out-Null
    $delta=[BitConverter]::ToUInt32([BitConverter]::GetBytes([int32]-600),0)
    [FabScan]::mouse_event(0x0800,0,0,$delta,[UIntPtr]::Zero)
}
Write-Output "Saved $Pages Fab library overview frames to $outdir"
