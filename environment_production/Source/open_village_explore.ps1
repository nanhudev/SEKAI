param([switch]$Verify,[string]$Version='v092')
$ErrorActionPreference = 'Stop'
$runtimeRoot = 'E:\SEKAI_Environment_Runtime'
$projectPath = 'F:\SEKAI\ue5_lab\SEKAI_StarterVillage\SEKAI_StarterVillage.uproject'
$enginePath = 'F:\UE_5.8\Engine\Binaries\Win64\UnrealEditor.exe'
$mapPath = "/Game/Environment/Village/Landscape/L_StarterValley_${Version}_Explore"
$env:SEKAI_REVIEW_VERSION=$Version
$running = Get-CimInstance Win32_Process -Filter "Name='UnrealEditor.exe'" | Where-Object { $_.CommandLine -like "*$projectPath*" -and $_.CommandLine -like '*_Explore*' -and $_.CommandLine -like '*-game*' }
$tourWindow = $running | ForEach-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue } | Select-Object -First 1
if ($tourWindow) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class VillageWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
}
'@
    $window = $tourWindow.MainWindowHandle
    if ($window -ne 0) { [VillageWindow]::ShowWindow($window,9) | Out-Null; [VillageWindow]::SetForegroundWindow($window) | Out-Null }
    exit
}
New-Item -ItemType Directory -Force -Path "$runtimeRoot\Temp","$runtimeRoot\DDC","$runtimeRoot\User" | Out-Null
$env:TEMP = "$runtimeRoot\Temp"
$env:TMP = "$runtimeRoot\Temp"
[Environment]::SetEnvironmentVariable('UE-LocalDataCachePath',"$runtimeRoot\DDC",'Process')
$launchArgs = @($projectPath,$mapPath,'-game','-windowed','-ResX=1600','-ResY=900','-NoLiveCoding',
    '-NoScreenMessages','-unattended','-DDC=InstalledNoZenLocalFallback',"-LocalDataCachePath=$runtimeRoot\DDC","-UserDir=$runtimeRoot\User", "-abslog=$runtimeRoot\village_explore.log")
if ($Verify) {
    $env:SEKAI_EXPLORE_VERIFY_EXIT='1'
    $launchArgs += '-ExecCmds="py F:/SEKAI/environment_production/Source/probe_village_explore.py"'
    Start-Process -FilePath $enginePath -ArgumentList $launchArgs -WindowStyle Hidden -PassThru | Select-Object Id,ProcessName
} else {
    $env:SEKAI_EXPLORE_VERIFY_EXIT='0'
    Start-Process -FilePath $enginePath -ArgumentList $launchArgs -PassThru | Select-Object Id,ProcessName
}
