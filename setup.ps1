param(
    [switch]$DryRun,
    [switch]$SkipWinget,
    [switch]$SkipSendMidi
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Invoke-SetupCommand {
    param(
        [string]$Label,
        [scriptblock]$Command
    )

    Write-Step $Label
    if ($DryRun) {
        Write-Host "Dry run: skipped."
        return
    }

    & $Command
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )

    Invoke-SetupCommand "Installing $Name via winget" {
        winget install --id $Id --exact --accept-package-agreements --accept-source-agreements
    }
}

if (-not $SkipWinget) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Install-WingetPackage -Id 'AutoHotkey.AutoHotkey' -Name 'AutoHotkey v2'
        Install-WingetPackage -Id 'TobiasErichsen.loopMIDI' -Name 'loopMIDI'
    }
    else {
        Write-Warning 'winget was not found. Install AutoHotkey v2 and loopMIDI manually, then rerun setup.ps1 -SkipWinget.'
    }
}

if (-not $SkipSendMidi) {
    $sendMidiDir = Join-Path $Root 'tools\sendmidi'
    $sendMidiExe = Join-Path $sendMidiDir 'sendmidi.exe'

    if (Test-Path -LiteralPath $sendMidiExe) {
        Write-Step 'SendMIDI already exists'
        Write-Host $sendMidiExe
    }
    else {
        Invoke-SetupCommand 'Downloading SendMIDI for Windows' {
            $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/gbevin/SendMIDI/releases/latest' -Headers @{
                'User-Agent' = 'gr-shortcuts-setup'
            }
            $asset = $release.assets |
                Where-Object { $_.name -match '^sendmidi-windows-.*\.zip$' } |
                Select-Object -First 1

            if (-not $asset) {
                throw 'Could not find a Windows SendMIDI release asset.'
            }

            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gr-shortcuts-sendmidi-' + [guid]::NewGuid())
            $zipPath = Join-Path $tempRoot $asset.name
            $extractPath = Join-Path $tempRoot 'extract'

            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

            try {
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
                Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

                $downloadedExe = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter 'sendmidi.exe' |
                    Select-Object -First 1

                if (-not $downloadedExe) {
                    throw 'Downloaded SendMIDI archive did not contain sendmidi.exe.'
                }

                New-Item -ItemType Directory -Path $sendMidiDir -Force | Out-Null
                Copy-Item -LiteralPath $downloadedExe.FullName -Destination $sendMidiExe -Force
                Write-Host "Installed $sendMidiExe"
            }
            finally {
                $resolvedTemp = Resolve-Path -LiteralPath $tempRoot -ErrorAction SilentlyContinue
                $systemTemp = [System.IO.Path]::GetTempPath()
                if ($resolvedTemp -and $resolvedTemp.Path.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Remove-Item -LiteralPath $resolvedTemp.Path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

Write-Step 'Manual step still required'
Write-Host 'Open loopMIDI, create a port named "GR7 Control", and leave loopMIDI running.'
Write-Host 'Then edit config\gr-shortcuts.ini if your Guitar Rig path is different.'
Write-Host 'Start with launch-gr-shortcuts.bat.'

