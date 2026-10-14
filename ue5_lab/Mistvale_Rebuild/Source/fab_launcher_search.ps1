param([string]$Query='StyleHex')
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FabMouse {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
'@
$target=Get-Process -Name EpicGamesLauncher -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $target) { throw 'No Epic Launcher window' }
$h=[IntPtr]$target.MainWindowHandle
[FabMouse]::ShowWindow($h,9) | Out-Null
[FabMouse]::SetForegroundWindow($h) | Out-Null
Start-Sleep -Milliseconds 300
$rect=New-Object FabMouse+RECT
[FabMouse]::GetWindowRect($h,[ref]$rect) | Out-Null
[FabMouse]::SetCursorPos($rect.Left+720,$rect.Top+66) | Out-Null
[FabMouse]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
[FabMouse]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
Start-Sleep -Milliseconds 250
[Windows.Forms.SendKeys]::SendWait('^a')
[Windows.Forms.SendKeys]::SendWait($Query)
[Windows.Forms.SendKeys]::SendWait('{ENTER}')
Write-Output 'Submitted Fab search in Epic Launcher'
