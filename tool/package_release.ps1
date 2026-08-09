# Builds the Windows release and packages it as a versioned, ready-to-ship zip.
#
#   powershell -ExecutionPolicy Bypass -File tool\package_release.ps1
#
# Output: dist\tali-<version>-windows-x64.zip
# The version is read from pubspec.yaml, so bumping it there is the only step
# needed for the next release.

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# --- Version from pubspec.yaml (strip any +build suffix) ---
$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(.+)$'
if (-not $versionLine) { throw 'No version: line in pubspec.yaml' }
$version = $versionLine.Matches[0].Groups[1].Value.Trim().Split('+')[0]
Write-Host "Packaging version $version"

# --- Build ---
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }

$releaseDir = 'build\windows\x64\runner\Release'
if (-not (Test-Path "$releaseDir\tali.exe")) {
    throw "Build output missing: $releaseDir\tali.exe"
}

# --- Stage the distributable folder ---
$stage = "dist\tali-$version-windows-x64"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$releaseDir\*" $stage -Recurse

# --- VC++ runtime DLLs ---
# Flutter's bundle does not include the MSVC runtime; users without the
# VC++ Redistributable get a missing-DLL error. Copy the three DLLs from the
# Visual Studio redist folder when available (they are licensed for exactly
# this kind of app-local deployment); otherwise the README points users at
# the redist installer.
$vcDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')
$redistRoots = @(
    "${env:ProgramFiles}\Microsoft Visual Studio",
    "${env:ProgramFiles(x86)}\Microsoft Visual Studio"
) | Where-Object { Test-Path $_ }
$copied = 0
foreach ($dll in $vcDlls) {
    $candidates = $redistRoots | ForEach-Object {
        Get-ChildItem -Path $_ -Recurse -Filter $dll -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\Redist\\.*\\x64\\.*\.CRT\\' }
    }
    # Prefer the desktop CRT over the 'onecore' variant when both exist.
    $found = ($candidates | Where-Object { $_.FullName -notmatch 'onecore' } |
        Select-Object -First 1)
    if (-not $found) { $found = $candidates | Select-Object -First 1 }
    if ($found) { Copy-Item $found.FullName $stage; $copied++ }
}
if ($copied -lt $vcDlls.Count) {
    Write-Warning "Only $copied/$($vcDlls.Count) VC++ runtime DLLs found; users may need the VC++ Redistributable (noted in README)."
}

# --- Docs into the zip ---
foreach ($doc in 'README.md', 'LICENSE', 'CHANGELOG.md', 'POLICY.md') {
    Copy-Item $doc $stage
}

# --- Zip it ---
$zip = "dist\tali-$version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip
$sizeMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "Done: $zip ($sizeMb MB)"
Write-Host 'Smoke-test the staged folder on a machine without Flutter before publishing.'
