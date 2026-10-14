Add-Type -AssemblyName System.Drawing
$dir=Join-Path (Split-Path -Parent $PSScriptRoot) 'Saved\FabLibraryScan'
$files=Get-ChildItem -LiteralPath $dir -Filter 'library_*.png' | Sort-Object Name
for ($group=0; $group -lt [math]::Ceiling($files.Count/4); $group++) {
    $sheet=[Drawing.Bitmap]::new(1920,1360)
    $g=[Drawing.Graphics]::FromImage($sheet)
    $g.Clear([Drawing.Color]::Black)
    for ($slot=0; $slot -lt 4; $slot++) {
        $idx=$group*4+$slot
        if ($idx -ge $files.Count) { break }
        $img=[Drawing.Image]::FromFile($files[$idx].FullName)
        $src=[Drawing.Rectangle]::new(580,150,960,680)
        $dst=[Drawing.Rectangle]::new(($slot%2)*960,[math]::Floor($slot/2)*680,960,680)
        $g.DrawImage($img,$dst,$src,[Drawing.GraphicsUnit]::Pixel)
        $img.Dispose()
    }
    $out=Join-Path $dir ('contact_{0:d2}.png' -f $group)
    $sheet.Save($out,[Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose()
    $sheet.Dispose()
    Write-Output $out
}
