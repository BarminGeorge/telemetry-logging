$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$server = $null
$configuration = Join-Path (Get-Location) 'appsettings.Development.json'
$original = [IO.File]::ReadAllBytes($configuration)

try {
    dotnet build telemetry.csproj --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }

    New-Item -ItemType Directory -Force .logs | Out-Null
    $server = Start-Process dotnet -WindowStyle Hidden -PassThru `
        -ArgumentList 'bin/Debug/net8.0/telemetry.dll --urls http://127.0.0.1:5187 --environment Development' `
        -RedirectStandardOutput .logs/verification.stdout.log `
        -RedirectStandardError .logs/verification.stderr.log

    $ready = $false
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try {
            Invoke-WebRequest http://127.0.0.1:5187/ -UseBasicParsing -TimeoutSec 1 | Out-Null
            $ready = $true
            break
        } catch {
            if ($server.HasExited) { throw 'Application exited. See .logs/verification.stderr.log.' }
            Start-Sleep -Milliseconds 250
        }
    }
    if (-not $ready) { throw 'Application did not start.' }

    $marker = [guid]::NewGuid().ToString('N')
    Invoke-WebRequest "http://127.0.0.1:5187/Privacy?check=$marker" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Invoke-WebRequest "http://127.0.0.1:5187/css/site.css?check=$marker" -UseBasicParsing -TimeoutSec 5 | Out-Null
    Start-Sleep -Milliseconds 300

    $console = Get-Content .logs/verification.stdout.log -Raw
    if ($console -notmatch 'INF.*HTTP GET /Privacy responded 200') { throw 'Missing readable request log.' }
    if ($console -match 'HTTP GET /css/site.css') { throw 'Static file request was logged.' }
    $events = Get-ChildItem .logs/log-*.txt | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
    if (-not ($events | Where-Object {
        $_.RequestPath -eq '/Privacy' -and $_.StatusCode -eq 200 -and
        $_.SourceContext -eq 'Serilog.AspNetCore.RequestLoggingMiddleware' -and $null -ne $_.Elapsed
    })) { throw 'Missing structured request log.' }

    Stop-Process -Id $server.Id
    $server.WaitForExit()
    $server = $null

    [IO.File]::WriteAllText($configuration, '')
    $failure = dotnet bin/Debug/net8.0/telemetry.dll --environment Development 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1) { throw 'Invalid JSON should cause startup to fail.' }
    $startupLog = Get-ChildItem .logs/start-host-log-*.txt | Sort-Object LastWriteTime | Select-Object -Last 1
    $fatal = Get-Content $startupLog.FullName -Raw
    if ($fatal -notmatch 'FTL.*Application terminated unexpectedly' -or
        $fatal -notmatch 'appsettings.Development.json' -or
        $failure -notmatch 'Application terminated unexpectedly') { throw 'Missing startup exception log.' }

    Write-Output 'PASS: JSON requests, readable console, static file exclusion, startup exception.'
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id }
    [IO.File]::WriteAllBytes($configuration, $original)
    Pop-Location
}
