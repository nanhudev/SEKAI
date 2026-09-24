$ErrorActionPreference = 'Stop'
$project = 'F:\SEKAI'
$marker = 'F-SEKAI-MVP04'
$port = $null

if (-not (Test-Path -LiteralPath (Join-Path $project 'package.json'))) {
    throw "SEKAI project not found: $project"
}

function Test-SekaiServer([int]$candidate) {
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$candidate/" -TimeoutSec 2 -UseBasicParsing
        return $response.StatusCode -eq 200 -and $response.Content -match $marker
    } catch { return $false }
}

function Test-PortInUse([int]$candidate) {
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $connected = $client.ConnectAsync('127.0.0.1', $candidate).Wait(250)
        $client.Dispose()
        return $connected
    } catch { return $false }
}

Push-Location $project
try { npm run build; if ($LASTEXITCODE -ne 0) { throw 'SEKAI build failed' } }
finally { Pop-Location }

foreach ($candidate in 5180..5188) {
    if (Test-SekaiServer $candidate) { $port = $candidate; break }
}

if ($null -eq $port) {
    foreach ($candidate in 5180..5188) {
        if (-not (Test-PortInUse $candidate)) { $port = $candidate; break }
    }
    if ($null -eq $port) { throw 'No free local SEKAI port found.' }
    if (-not (Test-Path -LiteralPath (Join-Path $project 'node_modules\vite\bin\vite.js'))) {
        Push-Location $project
        try { npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' } }
        finally { Pop-Location }
    }
    $vite = Join-Path $project 'node_modules\vite\bin\vite.js'
    Start-Process -FilePath 'node.exe' -ArgumentList @("`"$vite`"", 'preview', '--host', '127.0.0.1', '--strictPort', '--port', "$port") -WorkingDirectory $project -WindowStyle Hidden | Out-Null
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-SekaiServer $port) { $ready = $true; break }
    }
    if (-not $ready) { throw "SEKAI did not start on port $port" }
}

Start-Process "http://127.0.0.1:$port/"
