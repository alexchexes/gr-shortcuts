param(
    [string]$Repo = 'alexchexes/gr-shortcuts'
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

if (-not (Test-Path -LiteralPath $VersionPath)) {
    throw "VERSION file was not found: $VersionPath"
}

$currentText = (Get-Content -LiteralPath $VersionPath -Raw).Trim()
$currentVersion = Convert-ReleaseVersion -Value $currentText
$apiUrl = "https://api.github.com/repos/$Repo/releases/latest"

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{
        'User-Agent' = 'gr-shortcuts-update-check'
    }
}
catch {
    Write-Host ''
    Write-Host "Could not check for updates from $Repo."
    Write-Host 'Make sure you are online and try again.'
    Write-Host ''
    Write-Host 'If this keeps failing, report it here:'
    Write-Host 'https://github.com/alexchexes/gr-shortcuts/issues'
    Write-Host ''
    Write-Host "Error: $($_.Exception.Message)"
    exit 1
}

$latestVersion = Convert-ReleaseVersion -Value $release.tag_name

Write-Host "Current version: $currentVersion"
Write-Host "Latest version:  $latestVersion"

if ($latestVersion -le $currentVersion) {
    Write-Host ''
    Write-Host 'You already have the latest version.'
    exit 0
}

Write-Host ''
Write-Host 'A newer version is available.'
Write-Host "Download it from: $($release.html_url)"
Write-Host 'Or run update.bat to download and install it automatically.'
Write-Host ''
Write-Host 'Manual update steps:'
Write-Host '1. Close Guitar Rig and Guitar Rig Shortcuts.'
Write-Host '2. Download the latest release zip.'
Write-Host '3. Extract it over your existing gr-shortcuts folder.'
Write-Host '4. Run setup.bat again if the release notes ask for it.'
Write-Host ''
Write-Host 'Your config\gr-shortcuts.ini file is user-local and will be preserved.'
