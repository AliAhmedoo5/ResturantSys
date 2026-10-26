$ErrorActionPreference = 'Stop'
if (-not $env:RUNNER_TEMP) { throw 'This startup check runs only in GitHub Actions.' }
$smokeRoot = Join-Path $env:RUNNER_TEMP ([Guid]::NewGuid().ToString('N'))
$extracted = Join-Path $smokeRoot 'app'
$isolatedData = Join-Path $smokeRoot 'program-data'
Expand-Archive -LiteralPath 'dist/resturant-pos-windows-x64.zip' -DestinationPath $extracted
./scripts/ci/verify-windows-bundle.ps1 -BundlePath $extracted
$priorProgramData = $env:ProgramData
$process = $null
try {
    # The application resolves its database from ProgramData; never use real data.
    $env:ProgramData = $isolatedData
    $process = Start-Process -FilePath (Join-Path $extracted 'resturant_sys.exe') -WorkingDirectory $extracted -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $database = Join-Path $isolatedData 'ResturantPOS/data/pos.db'
    do {
        Start-Sleep -Milliseconds 500
        $process.Refresh()
        if ($process.HasExited) { throw "Packaged app exited during startup: $($process.ExitCode)" }
        $ready = (Test-Path -LiteralPath $database) -and $process.MainWindowHandle -ne 0 -and $process.Responding
    } until ($ready -or [DateTime]::UtcNow -ge $deadline)
    if (-not $ready) { throw 'Packaged app did not open a responsive window with an isolated database.' }
    if ($process.MainWindowTitle -ne 'Crunch Cartel POS') { throw "Unexpected app title: $($process.MainWindowTitle)" }
    Start-Sleep -Seconds 10
    $process.Refresh()
    if ($process.HasExited -or -not $process.Responding) { throw 'Packaged app failed its startup stability check.' }
    Write-Output "Extracted package opened a responsive window: $($process.MainWindowTitle)"
} finally {
    $env:ProgramData = $priorProgramData
    if ($null -ne $process -and -not $process.HasExited) {
        $null = $process.CloseMainWindow()
        if (-not $process.WaitForExit(5000)) { Stop-Process -Id $process.Id -Force }
    }
}
python scripts/ci/verify-fresh-database.py $database
if ($LASTEXITCODE -ne 0) { throw 'Fresh database validation failed.' }
Write-Output 'Packaged Windows startup and fresh onboarding database verified.'
