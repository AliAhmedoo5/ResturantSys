param([Parameter(Mandatory)][string]$BundlePath)
$ErrorActionPreference = 'Stop'
$bundle = (Resolve-Path -LiteralPath $BundlePath).Path
foreach ($relative in @('resturant_sys.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll', 'data/icudtl.dat', 'data/flutter_assets', 'data/flutter_assets/assets/brand/crunch-cartel-icon.png', 'data/flutter_assets/assets/brand/crunch-cartel-wordmark.png', 'data/flutter_assets/assets/fonts/knewave/Knewave-Regular.ttf', 'data/flutter_assets/assets/fonts/knewave/OFL.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $bundle $relative))) {
        throw "Release bundle is incomplete: $relative"
    }
}
Write-Output 'Windows bundle includes executable, assets and required runtimes.'
