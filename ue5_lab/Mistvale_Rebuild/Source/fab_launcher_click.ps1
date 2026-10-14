param([Parameter(Mandatory)][int]$X,[Parameter(Mandatory)][int]$Y)
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FabClick {
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
[FabClick]::SetForegroundWindow($h) | Out-Null
$rect=New-Object FabClick+RECT
[FabClick]::GetWindowRect($h,[ref]$rect) | Out-Null
[FabClick]::SetCursorPos($rect.Left+$X,$rect.Top+$Y) | Out-Null
Start-Sleep -Milliseconds 150
[FabClick]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
[FabClick]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Write-Output "Clicked launcher at ($X,$Y)"
