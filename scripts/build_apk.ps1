# Builds the release APK and copies it to dist/ as Aurora-Music-v<version>-build<n>.apk
# (version and build number come from pubspec.yaml).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $env:Path = "C:\flutter\bin;" + $env:Path
}

$versionLine = Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)' | Select-Object -First 1
if (-not $versionLine) { throw 'version not found in pubspec.yaml' }
$parts = $versionLine.Matches[0].Groups[1].Value -split '\+'
$name = "Aurora-Music-v$($parts[0])"
if ($parts.Count -gt 1) { $name += "-build$($parts[1])" }

$defines = @()
if (Test-Path .env) { $defines = @('--dart-define-from-file=.env') }
flutter build apk --release @defines
if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

New-Item -ItemType Directory -Force dist | Out-Null
$target = Join-Path dist "$name.apk"
Copy-Item build\app\outputs\flutter-apk\app-release.apk $target -Force
Write-Host "APK: $target"
