param(
    [string]$Repo = 'alexchexes/gr-shortcuts',
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VersionPath = Join-Path $Root 'VERSION'

function Convert-ReleaseVersion {
    param([string]$Value)

    $normalized = $Value.Trim()
    if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }

    $parsed = $null
    if (-not [version]::TryParse($normalized, [ref]$parsed)) {
        throw "Could not parse version: $Value"
    }

    return $parsed
}

function Test-CanPrompt {
    try {
        return -not [Console]::IsInputRedirected
    }
    catch {
        return $false
    }
}

function Get-ReleaseRoot {
    param([string]$ExtractPath)

    if (Test-Path -LiteralPath (Join-Path $ExtractPath 'setup.bat')) {
        return $ExtractPath
    }

    $children = Get-ChildItem -LiteralPath $ExtractPath -Directory
    foreach ($child in $children) {
        if (Test-Path -LiteralPath (Join-Path $child.FullName 'setup.bat')) {
            return $child.FullName
        }
    }

    throw 'Downloaded release zip does not look like a gr-shortcuts release.'
}

function Test-MapperRunning {
    try {
        $processes = Get-CimInstance Win32_Process |
            Where-Object {
                $_.Name -like 'AutoHotkey*.exe' -and
                $_.CommandLine -match 'gr-shortcuts\.ahk'
            }

        return [bool]$processes
    }
    catch {
        Write-Warning "Could not check whether Guitar Rig Shortcuts is running: $($_.Exception.Message)"
        return $false
    }
}

function Copy-UpdateFiles {
    param(
        [string]$SourceRoot,
        [string]$DestinationRoot
    )

    $skipPatterns = @(
        'config/gr-shortcuts.ini',
        'tools/sendmidi/*'
    )

    $sourcePrefix = $SourceRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

    foreach ($file in Get-ChildItem -LiteralPath $SourceRoot -Recurse -File) {
        $relative = $file.FullName.Substring($sourcePrefix.Length)
        $normalized = $relative -replace '\\', '/'

        $shouldSkip = $false
        foreach ($pattern in $skipPatterns) {
            if ($normalized -like $pattern) {
                $shouldSkip = $true
                break
            }
        }

        if ($shouldSkip) {
            continue
        }

        $destination = Join-Path $DestinationRoot $relative
        $destinationDir = Split-Path -Parent $destination
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }
}

if (-not (Test-Path -LiteralPath $VersionPath)) {
    throw "VERSION file was not found: $VersionPath"
}

$currentText = (Get-Content -LiteralPath $VersionPath -Raw).Trim()
$currentVersion = Convert-ReleaseVersion -Value $currentText
$apiUrl = "https://api.github.com/repos/$Repo/releases/latest"

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{
        'User-Agent' = 'gr-shortcuts-updater'
    }
}
catch {
    Write-Host ''
    Write-Host "Could not check for updates from $Repo."
    Write-Host 'Make sure you are online and try again.'
    Write-Host ''
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}

$latestVersion = Convert-ReleaseVersion -Value $release.tag_name

Write-Host "Current version: $currentVersion"
Write-Host "Latest version:  $latestVersion"

if ($latestVersion -le $currentVersion -and -not $Force) {
    Write-Host ''
    Write-Host 'You already have the latest version.'
    exit 0
}

$assetName = "gr-shortcuts-$($release.tag_name).zip"
$asset = $release.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1

if (-not $asset) {
    Write-Host ''
    Write-Host "The latest release does not include the expected asset: $assetName"
    Write-Host "Download the release manually from: $($release.html_url)"
    exit 1
}

if ($DryRun) {
    Write-Host ''
    Write-Host "Dry run: would download and install $assetName from:"
    Write-Host "  $($asset.browser_download_url)"
    Write-Host ''
    Write-Host 'Dry run: would preserve config\gr-shortcuts.ini and tools\sendmidi.'
    exit 0
}

if (Test-MapperRunning) {
    Write-Host ''
    Write-Host 'Guitar Rig Shortcuts is currently running.'
    Write-Host 'Close it from the tray icon, then run update.bat again.'
    exit 1
}

if (Test-CanPrompt) {
    Write-Host ''
    Write-Host "This will download and install $assetName into:"
    Write-Host "  $Root"
    Write-Host ''
    Write-Host 'The updater preserves config\gr-shortcuts.ini and tools\sendmidi.'
    $answer = Read-Host 'Continue? [y/N]'
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host 'Update cancelled.'
        exit 0
    }
}
else {
    Write-Host ''
    Write-Host 'Input is not interactive, so the update was not applied.'
    Write-Host "Download the release manually from: $($release.html_url)"
    exit 1
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gr-shortcuts-update-' + [guid]::NewGuid())
$zipPath = Join-Path $tempRoot $assetName
$extractPath = Join-Path $tempRoot 'extract'

New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

try {
    Write-Host ''
    Write-Host "Downloading $assetName..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

    Write-Host 'Extracting update...'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    $releaseRoot = Get-ReleaseRoot -ExtractPath $extractPath

    Write-Host 'Installing update...'
    Copy-UpdateFiles -SourceRoot $releaseRoot -DestinationRoot $Root

    Write-Host ''
    Write-Host "Updated to $($release.tag_name)."
    Write-Host 'Your config\gr-shortcuts.ini file was preserved.'
    Write-Host 'Run setup.bat again if the release notes ask for it.'
}
finally {
    $resolvedTemp = Resolve-Path -LiteralPath $tempRoot -ErrorAction SilentlyContinue
    $systemTemp = [System.IO.Path]::GetTempPath()
    if ($resolvedTemp -and $resolvedTemp.Path.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemp.Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}
