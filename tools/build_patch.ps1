param(
    [string]$Version = "",
    [switch]$Delta
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $RepoRoot
try {
    $GodotExe = $null
    foreach ($Candidate in @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"
    )) {
        if (Test-Path $Candidate) { $GodotExe = $Candidate; break }
    }
    if (-not $GodotExe) {
        $Cmd = Get-Command godot, Godot_v4.7.2-stable_win64_console -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Cmd) { $GodotExe = $Cmd.Source }
    }
    if (-not $GodotExe) { throw "Godot 4.7.2 console executable not found." }

    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = '1.0.0'
        $ProjectGodot = Get-Content (Join-Path $RepoRoot 'project.godot') -Raw
        if ($ProjectGodot -match 'config/version\s*=\s*"([^"]+)"') {
            $Version = $Matches[1].Trim()
        }
    }
    $TagVersion = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }

    $BuildsDir = Join-Path $RepoRoot 'builds'
    $GameDir = Join-Path $BuildsDir 'game'
    $ReleaseDir = Join-Path $BuildsDir 'release'
    $PckOut = Join-Path $GameDir 'WorldWarPixel-Client.pck'
    $VersionOut = Join-Path $GameDir 'version.txt'
    $PatchNotesSrc = Join-Path $RepoRoot 'PATCH_NOTES.md'
    $PatchNotesGame = Join-Path $GameDir 'PATCH_NOTES.md'
    $PatchNotesRoot = Join-Path $BuildsDir 'PATCH_NOTES.md'
    $ChecksumsFile = Join-Path $ReleaseDir 'SHA256SUMS.txt'

    New-Item -ItemType Directory -Force -Path $GameDir, $ReleaseDir | Out-Null

    $RunningFromBuilds = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($BuildsDir, [System.StringComparison]::OrdinalIgnoreCase) }
    if ($RunningFromBuilds) {
        throw "Close running World War Pixel before building a patch."
    }

    if (Test-Path $PatchNotesSrc) {
        Copy-Item -Force $PatchNotesSrc $PatchNotesGame
        Copy-Item -Force $PatchNotesSrc $PatchNotesRoot
    }
    Set-Content -Path $VersionOut -Value $TagVersion -Encoding Ascii

    $Artifacts = @()
    if ($Delta) {
        if (-not (Test-Path $PckOut)) {
            throw "Base pack missing at $PckOut; run tools\build_release.ps1 first before building a delta patch."
        }
        $DeltaOut = Join-Path $ReleaseDir "WorldWarPixel-Delta-$TagVersion.pck"
        Write-Host "Exporting tiny delta patch ($TagVersion) -> $DeltaOut"
        & $GodotExe --headless --path $RepoRoot --patches "$PckOut" --export-patch "Windows Desktop" "$DeltaOut"
        if ($LASTEXITCODE -ne 0) {
            throw "Godot delta patch export failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path $DeltaOut)) {
            throw "Expected delta patch missing: $DeltaOut"
        }
        $Artifacts += (Get-Item $DeltaOut)
    } else {
        Write-Host "Exporting fast game pack ($TagVersion) -> $PckOut"
        & $GodotExe --headless --path $RepoRoot --export-pack "Windows Desktop" "$PckOut"
        if ($LASTEXITCODE -ne 0) {
            throw "Godot pack export failed with exit code $LASTEXITCODE"
        }
        if (-not (Test-Path $PckOut)) {
            throw "Expected pack file missing: $PckOut"
        }

        $PatchZip = Join-Path $ReleaseDir 'WorldWarPixel-Patch.zip'
        Remove-Item -Force $PatchZip -ErrorAction SilentlyContinue
        python -c "import zipfile, pathlib, sys
pck_file = pathlib.Path(sys.argv[1])
notes_md = pathlib.Path(sys.argv[2])
patch_zip = pathlib.Path(sys.argv[3])
with zipfile.ZipFile(patch_zip, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    z.write(pck_file, 'WorldWarPixel-Client.pck')
    if notes_md.exists():
        z.write(notes_md, 'PATCH_NOTES.md')
" $PckOut $PatchNotesGame $PatchZip
        if ($LASTEXITCODE -ne 0) {
            throw "Failed packaging WorldWarPixel-Patch.zip"
        }
        $Artifacts += (Get-Item $PckOut)
        $Artifacts += (Get-Item $PatchZip)
    }

    # Update or merge SHA256SUMS.txt
    $SumMap = [ordered]@{}
    if (Test-Path $ChecksumsFile) {
        foreach ($line in (Get-Content $ChecksumsFile)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') {
                $SumMap[$Matches[2].Trim()] = $Matches[1].ToLowerInvariant()
            }
        }
    }
    foreach ($art in $Artifacts) {
        if ($art.DirectoryName -eq $ReleaseDir) {
            $SumMap[$art.Name] = (Get-FileHash -Algorithm SHA256 $art.FullName).Hash.ToLowerInvariant()
        }
    }
    $OutLines = @()
    foreach ($k in $SumMap.Keys) {
        $OutLines += "$($SumMap[$k])  $k"
    }
    Set-Content -Path $ChecksumsFile -Value $OutLines -Encoding Ascii

    Write-Host "Fast patch build complete ($TagVersion):"
    $Artifacts | Select-Object FullName, Length | Format-Table -AutoSize
} finally {
    Pop-Location
}
