$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path 'build/windows/x64/runner/Release').Path
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $installation) { throw 'Visual C++ toolchain not found.' }
$redistRoot = Join-Path $installation 'VC/Redist/MSVC'
$crt = Get-ChildItem -LiteralPath $redistRoot -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'x64/Microsoft.VC143.CRT' } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_ 'msvcp140.dll') } |
    Select-Object -First 1
if (-not $crt) { throw 'Redistributable x64 Visual C++ runtime not found.' }
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
    Copy-Item -LiteralPath (Join-Path $crt $dll) -Destination $bundle
}
./scripts/ci/verify-windows-bundle.ps1 -BundlePath $bundle
Copy-Item -LiteralPath 'docs/windows-release.md' -Destination (Join-Path $bundle 'START-HERE.md')
Copy-Item -LiteralPath 'pubspec.lock' -Destination $bundle
flutter --version --machine | Set-Content -LiteralPath (Join-Path $bundle 'flutter-toolchain.json') -Encoding utf8
if ($LASTEXITCODE -ne 0) { throw 'Could not record the Flutter toolchain.' }
$version = (Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value
@{
    application = 'ResturantPOS'
    version = $version
    source_commit = $env:GITHUB_SHA
    workflow_run = "$env:GITHUB_SERVER_URL/$env:GITHUB_REPOSITORY/actions/runs/$env:GITHUB_RUN_ID"
    built_at_utc = [DateTime]::UtcNow.ToString('o')
    platform = 'windows-x64'
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $bundle 'build-manifest.json') -Encoding utf8
New-Item -ItemType Directory -Force -Path dist | Out-Null
$zip = Join-Path (Resolve-Path 'dist').Path 'resturant-pos-windows-x64.zip'
Compress-Archive -Path "$bundle/*" -DestinationPath $zip -Force
$digest = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  resturant-pos-windows-x64.zip" | Set-Content -LiteralPath 'dist/SHA256SUMS.txt' -Encoding ascii
Copy-Item -LiteralPath (Join-Path $bundle 'build-manifest.json') -Destination dist
Write-Output "Packaged source $env:GITHUB_SHA; SHA256 $digest"
