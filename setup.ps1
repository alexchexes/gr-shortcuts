param(
    [switch]$DryRun,
    [switch]$SkipWinget,
    [switch]$SkipSendMidi,
    [switch]$CreateDesktopShortcut,
    [switch]$NoDesktopShortcut,
    [switch]$SkipMidiPortCheck
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root 'config\gr-shortcuts.ini'
$SendMidiDir = Join-Path $Root 'tools\sendmidi'
$SendMidiExe = Join-Path $SendMidiDir 'sendmidi.exe'
$SendMidiVersion = '1.3.1'
$SendMidiAssetName = "sendmidi-windows-$SendMidiVersion.zip"
$SendMidiDownloadUrl = "https://github.com/gbevin/SendMIDI/releases/download/$SendMidiVersion/$SendMidiAssetName"
$SendMidiZipSha256 = '9FA5904014E7E1243392AFFD525244A304E12F6399E1012E5AEE5739B8E4B0E3'
$RestartMidiServiceScript = Join-Path $Root 'scripts\restart-midi-service.ps1'

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

function Get-ConfigValue {
    param(
        [string]$Section,
        [string]$Key,
        [string]$DefaultValue
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $DefaultValue
    }

    $currentSection = ''
    foreach ($line in Get-Content -LiteralPath $ConfigPath) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            continue
        }

        if ($currentSection -eq $Section -and $trimmed -match ('^{0}\s*=\s*(.*)$' -f [regex]::Escape($Key))) {
            return $matches[1].Trim()
        }
    }

    return $DefaultValue
}

function Resolve-ConfiguredPath {
    param([string]$Path)

    $trimmed = $Path.Trim()
    if (-not $trimmed) {
        return ''
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($trimmed)
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return $expanded
    }

    return Join-Path $Root $expanded
}

function Get-GuitarRigExePath {
    $configuredPath = Get-ConfigValue `
        -Section 'App' `
        -Key 'GuitarRigExe' `
        -DefaultValue '%ProgramFiles%\Native Instruments\Guitar Rig 7\Guitar Rig 7.exe'

    return Resolve-ConfiguredPath -Path $configuredPath
}

function Get-GuitarRigProcessName {
    $configuredProcess = Get-ConfigValue `
        -Section 'App' `
        -Key 'GuitarRigProcess' `
        -DefaultValue 'Guitar Rig 7.exe'

    return [System.IO.Path]::GetFileNameWithoutExtension($configuredProcess.Trim())
}

function Test-GuitarRigRunning {
    $processName = Get-GuitarRigProcessName
    if (-not $processName) {
        return $false
    }

    return [bool](Get-Process -Name $processName -ErrorAction SilentlyContinue)
}

function Get-LoopMidiPath {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Tobias Erichsen\loopMIDI\loopMIDI.exe'),
        (Join-Path $env:ProgramFiles 'Tobias Erichsen\loopMIDI\loopMIDI.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Start-LoopMidiIfPossible {
    if (Get-Process -Name 'loopMIDI' -ErrorAction SilentlyContinue) {
        return 'running'
    }

    $loopMidiPath = Get-LoopMidiPath
    if ($loopMidiPath) {
        Start-Process -FilePath $loopMidiPath | Out-Null
        Start-Sleep -Milliseconds 500
        return 'started'
    }

    return 'not-found'
}

function Get-SendMidiDeviceList {
    if (-not (Test-Path -LiteralPath $SendMidiExe)) {
        throw "SendMIDI was not found: $SendMidiExe"
    }

    $output = & $SendMidiExe list 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SendMIDI list failed: $output"
    }

    return @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
}

function Test-MidiPortVisible {
    param([string]$MidiPortName)

    $devices = Get-SendMidiDeviceList
    return $devices -contains $MidiPortName
}

function Invoke-MidiServiceRestart {
    if (-not (Test-Path -LiteralPath $RestartMidiServiceScript)) {
        throw "MIDI service restart helper was not found: $RestartMidiServiceScript"
    }

    $powershell = (Get-Process -Id $PID).Path
    $process = Start-Process -FilePath $powershell -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $RestartMidiServiceScript
    ) -WindowStyle Hidden -Wait -PassThru

    return $process.ExitCode -eq 0
}

function Wait-ForMidiPort {
    param([string]$MidiPortName)

    Write-Step 'Configure loopMIDI'

    if ($DryRun) {
        Write-Host "Dry run: would ask user to create and verify loopMIDI port '$MidiPortName'."
        return
    }

    if (-not (Test-CanPrompt)) {
        Write-Host "Create a loopMIDI port named '$MidiPortName'."
        Write-Host "Then check it with: tools\sendmidi\sendmidi.exe list"
        return
    }

    if (Test-GuitarRigRunning) {
        Write-Host '1. Close Guitar Rig before continuing.'
        Write-Host '   Setup detected that Guitar Rig is running. It may not see new MIDI ports until restarted.'
    }
    else {
        Write-Host '1. Close Guitar Rig if it is open.'
        Write-Host '   Guitar Rig may need to be restarted before it sees new MIDI ports.'
    }
    Write-Host '2. Start loopMIDI if it is not already running.'
    $loopMidiStatus = Start-LoopMidiIfPossible
    if ($loopMidiStatus -eq 'running') {
        Write-Host '   OK: loopMIDI is already running. Do not close it.'
    }
    elseif ($loopMidiStatus -eq 'started') {
        Write-Host '   OK: setup started loopMIDI. Do not close it.'
    }
    else {
        Write-Host '   Setup could not find loopMIDI automatically. Open loopMIDI from the Start menu.'
    }
    Write-Host "3. In loopMIDI, type '$MidiPortName' in the 'New port-name' field, press '+', and leave loopMIDI running."
    Read-Host 'Press Enter here after creating the port'

    $attempt = 1
    while ($true) {
        if (Test-MidiPortVisible -MidiPortName $MidiPortName) {
            Write-Host "SendMIDI can see '$MidiPortName'."
            return
        }

        Write-Warning "Attempt ${attempt}: SendMIDI cannot see '$MidiPortName' yet."
        Write-Host 'This can happen on recent Windows 11 versions until the Windows MIDI Service is restarted.'
        $answer = Read-Host 'Restart the Windows MIDI Service now? Admin prompt required. [Y/n]'

        if ($answer -notmatch '^(n|no)$') {
            if (Invoke-MidiServiceRestart) {
                Start-Sleep -Seconds 2
                if (Test-MidiPortVisible -MidiPortName $MidiPortName) {
                    Write-Host "SendMIDI can see '$MidiPortName'."
                    return
                }

                Write-Warning "The service restart finished, but '$MidiPortName' is still not visible."
            }
            else {
                Write-Warning 'The Windows MIDI Service restart did not complete.'
            }
        }

        Write-Host ''
        Write-Host 'You can restart it manually from an elevated PowerShell:'
        Write-Host '  Restart-Service midisrv'
        Write-Host 'Or reboot Windows.'
        Read-Host 'After restarting the service manually, press Enter to check again. Press Ctrl+C to stop setup'
        $attempt += 1
    }
}

function Test-CanPrompt {
    try {
        return -not [Console]::IsInputRedirected
    }
    catch {
        return $false
    }
}

function New-DesktopShortcut {
    $targetPath = Join-Path $Root 'launch-gr-shortcuts.bat'
    $desktopPath = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktopPath 'Guitar Rig Shortcuts.lnk'
    $guitarRigExe = Get-GuitarRigExePath

    Invoke-SetupCommand 'Creating desktop shortcut' {
        if (-not (Test-Path -LiteralPath $targetPath)) {
            throw "Launcher was not found: $targetPath"
        }

        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $targetPath
        $shortcut.WorkingDirectory = $Root
        $shortcut.Description = 'Launch Guitar Rig with keyboard-to-MIDI shortcuts'

        if ($guitarRigExe -and (Test-Path -LiteralPath $guitarRigExe)) {
            $shortcut.IconLocation = "$guitarRigExe,0"
        }

        $shortcut.Save()

        Write-Host "Created $shortcutPath"
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
    if (Test-Path -LiteralPath $SendMidiExe) {
        Write-Step 'SendMIDI already exists'
        Write-Host $SendMidiExe
    }
    else {
        Invoke-SetupCommand "Downloading SendMIDI $SendMidiVersion for Windows" {
            $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gr-shortcuts-sendmidi-' + [guid]::NewGuid())
            $zipPath = Join-Path $tempRoot $SendMidiAssetName
            $extractPath = Join-Path $tempRoot 'extract'

            New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

            try {
                Invoke-WebRequest -Uri $SendMidiDownloadUrl -OutFile $zipPath

                $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath).Hash
                if ($actualHash -ne $SendMidiZipSha256) {
                    throw "Downloaded SendMIDI archive SHA256 mismatch. Expected $SendMidiZipSha256 but got $actualHash."
                }

                Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

                $downloadedExe = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter 'sendmidi.exe' |
                    Select-Object -First 1

                if (-not $downloadedExe) {
                    throw 'Downloaded SendMIDI archive did not contain sendmidi.exe.'
                }

                New-Item -ItemType Directory -Path $SendMidiDir -Force | Out-Null
                Copy-Item -LiteralPath $downloadedExe.FullName -Destination $SendMidiExe -Force
                Write-Host "Installed $SendMidiExe"
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

if (-not $SkipMidiPortCheck) {
    $midiPortName = Get-ConfigValue -Section 'MIDI' -Key 'Port' -DefaultValue 'GR7 Control'
    Wait-ForMidiPort -MidiPortName $midiPortName
}

if ($NoDesktopShortcut) {
    Write-Step 'Desktop shortcut skipped'
}
elseif ($CreateDesktopShortcut) {
    New-DesktopShortcut
}
elseif (-not $DryRun -and (Test-CanPrompt)) {
    Write-Host ''
    $answer = Read-Host 'Create a desktop shortcut for Guitar Rig Shortcuts? [y/N]'
    if ($answer -match '^(y|yes)$') {
        New-DesktopShortcut
    }
}

$guitarRigExe = Get-GuitarRigExePath

Write-Step 'Setup finished'
if ($guitarRigExe -and (Test-Path -LiteralPath $guitarRigExe)) {
    Write-Host "Guitar Rig path OK: $guitarRigExe"
}
else {
    Write-Host 'Guitar Rig executable was not found at:'
    Write-Host "  $guitarRigExe"
    Write-Host 'Before using the launcher, edit this setting:'
    Write-Host "  $ConfigPath"
    Write-Host '  [App] GuitarRigExe=...'
}

Write-Host ''
Write-Host 'Next steps:'
Write-Host '1. Start Guitar Rig normally once and enable "GR7 Control" in Preferences -> MIDI.'
Write-Host '   If the checkbox glitches or does not stay enabled, close and reopen Guitar Rig.'
Write-Host '2. Edit keyboard mappings and MIDI action types later in:'
Write-Host "   $ConfigPath"
Write-Host '3. Start with launch-gr-shortcuts.bat, or use the desktop shortcut if you created one.'
