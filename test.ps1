param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-TestStep {
    param([string]$Message)

    Write-Host ''
    Write-Host "==> $Message"
}

function Get-AutoHotkeyPath {
    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
        $candidates += Join-Path $env:ProgramFiles 'AutoHotkey\AutoHotkey64.exe'
    }

    if ($env:LocalAppData) {
        $candidates += Join-Path $env:LocalAppData 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw 'AutoHotkey v2 was not found. Run setup.bat first, or install AutoHotkey v2 manually.'
}

function Assert-NativeCommandPassed {
    param([string]$Label)

    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE."
    }
}

Write-TestStep 'Parsing PowerShell scripts'
$powerShellScripts = @()
$powerShellScripts += Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File
$powerShellScripts += Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File

foreach ($script in $powerShellScripts) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$null,
        [ref]$parseErrors
    ) | Out-Null

    if ($parseErrors) {
        $messages = $parseErrors | ForEach-Object { "$($script.Name):$($_.Extent.StartLineNumber): $($_.Message)" }
        throw ($messages -join [Environment]::NewLine)
    }

    Write-Host "Parsed $($script.Name)"
}

Write-TestStep 'Checking VERSION'
$versionPath = Join-Path $Root 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "VERSION file was not found: $versionPath"
}

$versionText = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($versionText -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must use numeric major.minor.patch form without a prefix: $versionText"
}

$parsedVersion = $null
if (-not [version]::TryParse($versionText, [ref]$parsedVersion)) {
    throw "VERSION could not be parsed: $versionText"
}

Write-Host "VERSION is $versionText"

Write-TestStep 'Checking updater release asset contract'
$updatePath = Join-Path $Root 'scripts\update.ps1'
$updateText = Get-Content -LiteralPath $updatePath -Raw
$expectedAssetLine = '$assetName = "gr-shortcuts-$($release.tag_name).zip"'
if (-not $updateText.Contains($expectedAssetLine)) {
    throw "update.ps1 must derive the release zip name from the GitHub release tag: $expectedAssetLine"
}

Write-Host 'Updater expects release assets named gr-shortcuts-<tag>.zip.'

Write-TestStep 'Running setup dry run'
$setupPath = Join-Path $Root 'setup.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupPath -DryRun -NoDesktopShortcut -SkipMidiPortCheck
Assert-NativeCommandPassed 'setup.ps1 dry run'

Write-TestStep 'Validating tracked example config with AutoHotkey'
$autoHotkeyPath = Get-AutoHotkeyPath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gr-shortcuts-test-' + [guid]::NewGuid())

try {
    $tempScriptDir = Join-Path $tempRoot 'src'
    $tempConfigDir = Join-Path $tempRoot 'config'
    $tempScriptPath = Join-Path $tempScriptDir 'gr-shortcuts.ahk'
    $tempConfigPath = Join-Path $tempConfigDir 'gr-shortcuts.ini'

    New-Item -ItemType Directory -Path $tempScriptDir -Force | Out-Null
    New-Item -ItemType Directory -Path $tempConfigDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root 'src\gr-shortcuts.ahk') -Destination $tempScriptPath
    Copy-Item -LiteralPath (Join-Path $Root 'config\gr-shortcuts.example.ini') -Destination $tempConfigPath

    $autoHotkeyProcess = Start-Process -FilePath $autoHotkeyPath -ArgumentList @(
        "`"$tempScriptPath`"",
        'validate-config'
    ) -Wait -PassThru

    if ($autoHotkeyProcess.ExitCode -ne 0) {
        throw "AutoHotkey example config validation failed with exit code $($autoHotkeyProcess.ExitCode)."
    }
}
finally {
    $resolvedTemp = Resolve-Path -LiteralPath $tempRoot -ErrorAction SilentlyContinue
    $systemTemp = [System.IO.Path]::GetTempPath()

    if ($resolvedTemp -and $resolvedTemp.Path.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTemp.Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host 'All smoke tests passed.'
