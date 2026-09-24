$ErrorActionPreference = 'Stop'
$project = 'F:\SEKAI'
$port = 5174
$url = "http://127.0.0.1:$port/"

if (-not (Test-Path -LiteralPath (Join-Path $project 'package.json'))) {
    throw "SEKAI project not found: $project"
}

function Test-SekaiServer {
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec 2 -UseBasicParsing
        return $response.StatusCode -eq 200 -and $response.Content -match 'SEKAI'
    } catch {
        return $false
    }
}

if (-not (Test-SekaiServer)) {
    if (-not (Test-Path -LiteralPath (Join-Path $project 'node_modules\vite\bin\vite.js'))) {
        Push-Location $project
        try { npm ci; if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' } }
        finally { Pop-Location }
    }
    $vite = Join-Path $project 'node_modules\vite\bin\vite.js'
    Start-Process -FilePath 'node.exe' -ArgumentList @("`"$vite`"", '--host', '127.0.0.1', '--port', "$port") -WorkingDirectory $project -WindowStyle Hidden | Out-Null
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-SekaiServer) { $ready = $true; break }
    }
    if (-not $ready) { throw "SEKAI did not start at $url" }
}

Start-Process $url
