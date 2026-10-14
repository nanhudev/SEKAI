param([switch]$InvokeLibrary)
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$target=Get-Process -Name EpicGamesLauncher -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $target) { throw 'No Epic Launcher window' }
$root=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$target.MainWindowHandle)
$all=$root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$found=@()
for ($i=0; $i -lt $all.Count; $i++) {
    $el=$all.Item($i)
    $name=$el.Current.Name
    if ($name -and ($name -match '我的库|My Library|快速搭建|Quick')) {
        $found += [pscustomobject]@{Name=$name; Type=$el.Current.ControlType.ProgrammaticName; Rect=$el.Current.BoundingRectangle.ToString(); Element=$el}
    }
}
$found | Select-Object Name,Type,Rect | Format-Table -AutoSize
if ($InvokeLibrary) {
    $item=$found | Where-Object { $_.Name -match '我的库|My Library' } | Select-Object -First 1
    if (-not $item) { throw 'Library UIA element not found' }
    $pattern=$item.Element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
    Write-Output 'Invoked Fab library navigation'
}
