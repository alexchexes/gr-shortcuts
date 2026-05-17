param(
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $powershell = (Get-Process -Id $PID).Path
    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        "`"$PSCommandPath`"",
        '-Elevated'
    )

    try {
        $process = Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -Wait -PassThru
        exit $process.ExitCode
    }
    catch {
        Write-Error "Could not start elevated PowerShell: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host 'Restarting Windows MIDI Service...'
Restart-Service -Name 'midisrv' -ErrorAction Stop
Write-Host 'Windows MIDI Service restarted.'
