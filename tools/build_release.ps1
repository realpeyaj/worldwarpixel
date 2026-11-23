$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    # Locate Godot 4.7.2 console executable
    $GodotExe = $null
    $GodotCandidates = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
    )
    foreach ($Candidate in $GodotCandidates) {
        if (Test-Path $Candidate) {
            $GodotExe = $Candidate
            break
        }
    }
    if (-not $GodotExe) {
        $Cmd = Get-Command godot, Godot_v4.7.2-stable_win64_console -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Cmd) { $GodotExe = $Cmd.Source }
    }
    if (-not $GodotExe) {
        throw "Godot 4.7.2 console executable not found."
    }

    # Locate Go executable
    $GoExe = $null
    $GoCmd = Get-Command go -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($GoCmd) {
        $GoExe = $GoCmd.Source
    } elseif (Test-Path "$env:LOCALAPPDATA\Programs\Go\bin\go.exe") {
        $GoExe = "$env:LOCALAPPDATA\Programs\Go\bin\go.exe"
    } else {
        throw "Go toolchain not found on PATH or in %LOCALAPPDATA%\Programs\Go\bin\go.exe."
    }

    # Read config/version from project.godot (default 1.0.0)
    $Version = '1.0.0'
    $ProjectGodot = Get-Content (Join-Path $RepoRoot 'project.godot') -Raw
    if ($ProjectGodot -match 'config/version\s*=\s*"([^"]+)"') {
        $Version = $Matches[1].Trim()
    }
    $TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }

    $BuildsDir = Join-Path $RepoRoot 'builds'
    $GameDir = Join-Path $BuildsDir 'game'
    $ReleaseDir = Join-Path $BuildsDir 'release'
    $LauncherOut = Join-Path $BuildsDir 'WorldWarPixel.exe'
    $ClientOut = Join-Path $GameDir 'WorldWarPixel-Client.exe'
    $VersionOut = Join-Path $GameDir 'version.txt'

    New-Item -ItemType Directory -Force -Path $GameDir, $ReleaseDir | Out-Null

    $RunningFromBuilds = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($BuildsDir, [System.StringComparison]::OrdinalIgnoreCase) }
    if ($RunningFromBuilds) {
        throw "Close running World War Pixel before building a release."
    }
    Remove-Item -Force (Join-Path $GameDir 'WorldWarPixel-Client.tmp') -ErrorAction SilentlyContinue

    Write-Host "Building World War Pixel $TagVersion..."
    Write-Host "1. Exporting Godot Windows Desktop client -> $ClientOut"
    & $GodotExe --headless --path $RepoRoot --export-release "Windows Desktop" $ClientOut
    if ($LASTEXITCODE -ne 0) {
        throw "Godot export failed with exit code $LASTEXITCODE"
    }
    if (-not (Test-Path $ClientOut)) {
        throw "Expected exported binary missing: $ClientOut"
    }

    Set-Content -Path $VersionOut -Value $TagVersion -Encoding Ascii

    Write-Host "2. Building Go auto-update launcher -> $LauncherOut"
    $WindresExe = $null
    $WindresCmd = Get-Command windres -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($WindresCmd) {
        $WindresExe = $WindresCmd.Source
    } else {
        $FoundWindres = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\MartinStorsjo.LLVM-MinGW*\*\bin\windres.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($FoundWindres) {
            $WindresExe = $FoundWindres.FullName
        }
    }
    if (-not $WindresExe) {
        throw "windres.exe not found (needed to embed app_icon.ico into WorldWarPixel.exe)."
    }

    Push-Location (Join-Path $RepoRoot 'launcher')
    try {
        & $WindresExe -i launcher.rc -o rsrc_windows_amd64.syso -O coff -F pe-x86-64
        if ($LASTEXITCODE -ne 0) {
            throw "windres icon compilation failed with exit code $LASTEXITCODE"
        }
        & $GoExe build -trimpath -ldflags="-s -w -H=windowsgui" -o $LauncherOut .
        if ($LASTEXITCODE -ne 0) {
            throw "Go launcher build failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    Write-Host "3. Packaging release archives in $ReleaseDir"
    $ClientZip = Join-Path $ReleaseDir 'WorldWarPixel-Client.zip'
    $BundleZip = Join-Path $ReleaseDir "WorldWarPixel-Windows-$TagVersion.zip"
    $ChecksumsFile = Join-Path $ReleaseDir 'SHA256SUMS.txt'

    Remove-Item -Force $ClientZip, $BundleZip, $ChecksumsFile -ErrorAction SilentlyContinue

    # Build clean archives using Python zipfile so paths are exact
    python -c "import zipfile, pathlib, sys
repo = pathlib.Path(sys.argv[1])
client_exe = pathlib.Path(sys.argv[2])
version_txt = pathlib.Path(sys.argv[3])
launcher_exe = pathlib.Path(sys.argv[4])
client_zip = pathlib.Path(sys.argv[5])
bundle_zip = pathlib.Path(sys.argv[6])

with zipfile.ZipFile(client_zip, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.write(client_exe, 'WorldWarPixel-Client.exe')

with zipfile.ZipFile(bundle_zip, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.write(launcher_exe, 'WorldWarPixel.exe')
    z.write(client_exe, 'game/WorldWarPixel-Client.exe')
    z.write(version_txt, 'game/version.txt')
" $RepoRoot $ClientOut $VersionOut $LauncherOut $ClientZip $BundleZip
    if ($LASTEXITCODE -ne 0) {
        throw "Release archive packaging failed with exit code $LASTEXITCODE"
    }

    $ClientHash = (Get-FileHash -Algorithm SHA256 $ClientZip).Hash.ToLowerInvariant()
    $BundleHash = (Get-FileHash -Algorithm SHA256 $BundleZip).Hash.ToLowerInvariant()
    $ChecksumLines = @(
        "$ClientHash  WorldWarPixel-Client.zip"
        "$BundleHash  WorldWarPixel-Windows-$TagVersion.zip"
    )
    Set-Content -Path $ChecksumsFile -Value $ChecksumLines -Encoding Ascii

    Write-Host "Build complete:"
    Get-Item $LauncherOut, $ClientOut, $VersionOut, $ClientZip, $BundleZip, $ChecksumsFile |
        Select-Object FullName, Length | Format-Table -AutoSize
} finally {
    Pop-Location
}
