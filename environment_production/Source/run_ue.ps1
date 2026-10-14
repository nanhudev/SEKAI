param([ValidateSet('Import','Capture','TerrainImport','TerrainCapture','HiddenCapture','WaterCapture','WaterIsolatedCapture')][string]$Mode='TerrainCapture',[string]$Version='v093')
$env:SEKAI_REVIEW_VERSION=$Version
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$env:SEKAI_ROOT = $root
$runtimeRoot = if ($env:SEKAI_RUNTIME_DIR) { $env:SEKAI_RUNTIME_DIR } else { Join-Path $root '.local' }
if (-not $env:UE_ENGINE_DIR) { throw 'Set UE_ENGINE_DIR to the UE installation directory.' }
New-Item -ItemType Directory -Force -Path "$runtimeRoot\Temp","$runtimeRoot\DDC","$runtimeRoot\User" | Out-Null
$env:TEMP = "$runtimeRoot\Temp"
$env:TMP = "$runtimeRoot\Temp"
[Environment]::SetEnvironmentVariable('UE-LocalDataCachePath',"$runtimeRoot\DDC",'Process')
$engine = Join-Path $env:UE_ENGINE_DIR 'Engine/Binaries/Win64'
$project = Join-Path $root 'ue5_lab/SEKAI_StarterVillage/SEKAI_StarterVillage.uproject'
$common = @($project,'-unattended','-nosplash','-nopause','-DDC=InstalledNoZenLocalFallback',"-LocalDataCachePath=$runtimeRoot\DDC","-UserDir=$runtimeRoot\User",'-NoLiveCoding')
if ($Mode -in @('Import','TerrainImport')) {
    if ($Mode -eq 'TerrainImport' -and (Test-Path -LiteralPath "$root\environment_production\Terrain\$Version\ue_import.json")) {
        throw "$Version is already imported; capture it or derive a new version."
    }
    $script = if ($Mode -eq 'TerrainImport') { 'install_ue_valley.py' } else { 'install_ue_tavern.py' }
    & "$engine\UnrealEditor-Cmd.exe" @common '-run=pythonscript' "-script=$root/environment_production/Source/$script" '-nullrhi' '-stdout'
    if ($Mode -eq 'TerrainImport' -and -not (Test-Path -LiteralPath "$root\environment_production\Terrain\$Version\ue_import.json")) {
        throw "UE did not write a completed import receipt for $Version; import failed."
    }
} else {
    if ($Mode -in @('TerrainCapture','HiddenCapture','WaterCapture','WaterIsolatedCapture') -and -not (Test-Path -LiteralPath "$root\environment_production\Terrain\$Version\ue_import.json")) {
        throw "No completed terrain import receipt for $Version; capture cancelled."
    }
    $script = if ($Mode -eq 'WaterIsolatedCapture') { 'capture_water_isolated.py' } elseif ($Mode -eq 'WaterCapture') { 'capture_water_motion.py' } elseif ($Mode -eq 'HiddenCapture') { 'capture_hidden_angles.py' } elseif ($Mode -eq 'TerrainCapture') { 'capture_ue_valley.py' } else { 'capture_ue_tavern.py' }
    if ($Mode -in @('TerrainCapture','HiddenCapture','WaterCapture','WaterIsolatedCapture')) { $common += "/Game/Environment/Village/Landscape/L_StarterValley_$Version" }
    & "$engine\UnrealEditor-Cmd.exe" @common "-ExecCmds=py $root/environment_production/Source/$script" '-windowed' '-ResX=1400' '-ResY=1000' '-NoScreenMessages' '-stdout' '-nosound'
}
exit $LASTEXITCODE
