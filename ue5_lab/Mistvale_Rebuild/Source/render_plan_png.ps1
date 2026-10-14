Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$items = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'blockout_layout.json') -Raw | ConvertFrom-Json
$out = Join-Path $root 'Review\blockout_plan.png'
$bmp = [Drawing.Bitmap]::new(910,1200)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([Drawing.Color]::FromArgb(216,223,200))
function XP([double]$v) { return [single](55 + ($v + 252) * 1.58) }
function YP([double]$v) { return [single](1150 - ($v + 353) * 1.53) }
function Paint([string]$hex) { return [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($hex)) }
$riverOuter = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#adcbd2'),51)
$riverInner = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#598fa0'),34)
$riverOuter.StartCap = 'Round'; $riverOuter.EndCap = 'Round'
$riverInner.StartCap = 'Round'; $riverInner.EndCap = 'Round'
for ($x=-250;$x -lt 250;$x+=5) {
    $y1=-88+13*[math]::Sin(($x+25)/105)+4*[math]::Sin($x/39)
    $x2=$x+5
    $y2=-88+13*[math]::Sin(($x2+25)/105)+4*[math]::Sin($x2/39)
    $g.DrawLine($riverOuter,(XP $x),(YP $y1),(XP $x2),(YP $y2))
    $g.DrawLine($riverInner,(XP $x),(YP $y1),(XP $x2),(YP $y2))
}

function Box($a,[string]$color) {
    $cx=XP $a.x; $cy=YP $a.y
    $w=[single]($a.sx*1.58); $h=[single]($a.sy*1.53)
    $save=$g.Save()
    $g.TranslateTransform($cx,$cy)
    $g.RotateTransform([single](-$a.yaw))
    $brush=Paint $color
    $g.FillRectangle($brush,[single](-$w/2),[single](-$h/2),$w,$h)
    $brush.Dispose()
    $g.Restore($save)
}
foreach($a in $items) {
    if($a.name -match '^(GoldenRoute_|LowerMarketLoop_|MarketEastLoop_|RiversideStreet_|UpperResidential_|ChurchLane_|DockTrack_)') { Box $a '#b39b74' }
}
foreach($a in $items) {
    if($a.name -match '_House_|^CornerBuilding_') { Box $a '#f7eee0' }
    elseif($a.name -match '^HERO_') { Box $a '#bc7e60' }
    elseif($a.name -match '^MarketStall_|^MarketSquare_') { Box $a '#e4bd6e' }
    elseif($a.name -match 'Bridge_DECK$') { Box $a '#737877' }
}
$font=[Drawing.Font]::new('Arial',13,[Drawing.FontStyle]::Bold)
$small=[Drawing.Font]::new('Arial',9)
$ink=Paint '#26372f'
$g.DrawString('MISTVALE UE5  |  PASS 01 COMPOSITION PLAN',$font,$ink,55,11)
$g.DrawString('Greybox spatial audit - not an in-engine beauty screenshot',$small,$ink,55,44)
foreach($point in @(@('SOUTH FOREST',4,-280),@('RIVERSIDE',-170,-175),@('MARKET',4,104),@('GUILD',-55,164),@('CHURCH',100,217),@('NORTH GATE',0,302))) {
    $g.DrawString([string]$point[0],$small,$ink,(XP ([double]$point[1])),(YP ([double]$point[2])))
}
$g.DrawString('81 town masses  |  2 crossings  |  new 504 x 706 m valley',$small,$ink,55,1170)
$bmp.Save($out,[Drawing.Imaging.ImageFormat]::Png)
$ink.Dispose();$font.Dispose();$small.Dispose();$riverOuter.Dispose();$riverInner.Dispose();$g.Dispose();$bmp.Dispose()
Write-Output $out
