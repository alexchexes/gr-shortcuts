#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
#UseHook

A_IconTip := "Guitar Rig Shortcuts"
ValidateConfigOnly := HasCliArg("--validate-config")

ScriptDir := A_ScriptDir
RootDir := RegExReplace(ScriptDir, "\\src$")
ConfigPath := RootDir "\config\gr-shortcuts.ini"

if !FileExist(ConfigPath) {
    Abort("Missing config file:`n" ConfigPath "`n`nRun setup.bat first.")
}

GuitarRigExe := ResolveConfiguredPath(ReadSetting("App", "GuitarRigExe", ""))
GuitarRigArgs := ReadSetting("App", "GuitarRigArgs", "")
GuitarRigWindow := ReadSetting("App", "GuitarRigWindow", "ahk_exe Guitar Rig 7.exe")
GuitarRigProcess := ReadSetting("App", "GuitarRigProcess", "Guitar Rig 7.exe")
LoopMidiExe := ResolveConfiguredPath(ReadSetting("App", "LoopMidiExe", ""))
ReuseRunningGuitarRig := ReadBoolSetting("App", "ReuseRunningGuitarRig", true)
ActivateGuitarRigOnStart := ReadBoolSetting("App", "ActivateGuitarRigOnStart", true)
CloseMapperWithGuitarRig := ReadBoolSetting("App", "CloseMapperWithGuitarRig", true)
CloseLoopMidiWithMapper := ReadBoolSetting("App", "CloseLoopMidiWithMapper", true)

LoopMidiStartedByMapper := false
LoopMidiPid := 0
OnExit(CleanupBeforeExit)

MidiPort := ReadSetting("MIDI", "Port", "GR7 Control")
SendMidiPath := ResolveConfiguredPath(ReadSetting("MIDI", "SendMidiPath", "tools\sendmidi\sendmidi.exe"))
MidiChannel := ReadNumberSetting("MIDI", "Channel", 1)
PulseMs := ReadNumberSetting("MIDI", "PulseMs", 40)

if !FileExist(SendMidiPath) {
    if !ValidateConfigOnly {
        Abort("Missing SendMIDI executable:`n" SendMidiPath "`n`nRun setup.ps1 first.")
    }
}

if !ValidateConfigOnly {
    StartLoopMidiIfPossible()
}

RegisterMappings()

if ValidateConfigOnly {
    ExitApp
}

guitarRigPid := StartOrReuseGuitarRig()

if CloseMapperWithGuitarRig && guitarRigPid {
    SetTimer(WatchGuitarRig.Bind(guitarRigPid), 1000)
}

WarnIfMidiPortMissing()

TrayTip("Guitar Rig Shortcuts", "Mapper is running for " GuitarRigWindow, 3)

HasCliArg(expected) {
    expected := StrLower(expected)
    for arg in A_Args {
        if StrLower(arg) = expected {
            return true
        }
    }

    return false
}

Abort(message) {
    global ValidateConfigOnly

    if ValidateConfigOnly {
        FileAppend(message "`n", "**")
    }
    else {
        MsgBox(message, "Guitar Rig Shortcuts", "Iconx")
    }

    ExitApp(1)
}

ReadSetting(section, key, defaultValue := "") {
    global ConfigPath
    return IniRead(ConfigPath, section, key, defaultValue)
}

ReadBoolSetting(section, key, defaultValue := false) {
    value := StrLower(Trim(ReadSetting(section, key, defaultValue ? "1" : "0")))
    return value = "1" || value = "true" || value = "yes" || value = "on"
}

ReadNumberSetting(section, key, defaultValue) {
    value := Trim(ReadSetting(section, key, defaultValue))
    return value = "" ? defaultValue : value + 0
}

ReadSection(section) {
    global ConfigPath
    try {
        return IniRead(ConfigPath, section)
    }
    catch {
        return ""
    }
}

ResolveConfiguredPath(path) {
    global RootDir
    path := Trim(path)
    if path = "" {
        return ""
    }

    expanded := ExpandEnvironmentStrings(path)
    if RegExMatch(expanded, "i)^([a-z]:\\|\\\\)") {
        return expanded
    }

    return RootDir "\" expanded
}

ExpandEnvironmentStrings(value) {
    shell := ComObject("WScript.Shell")
    return shell.ExpandEnvironmentStrings(value)
}

StartLoopMidiIfPossible() {
    global LoopMidiExe, LoopMidiStartedByMapper, LoopMidiPid

    if ProcessExist("loopMIDI.exe") {
        return
    }

    if LoopMidiExe != "" && FileExist(LoopMidiExe) {
        Run('"' LoopMidiExe '"', , "Hide", &pid)
        LoopMidiStartedByMapper := pid != 0
        LoopMidiPid := pid
        Sleep 600
        return
    }

    for candidate in LoopMidiCandidates() {
        if FileExist(candidate) {
            Run('"' candidate '"', , "Hide", &pid)
            LoopMidiStartedByMapper := pid != 0
            LoopMidiPid := pid
            Sleep 600
            return
        }
    }
}

CleanupBeforeExit(exitReason, exitCode) {
    global CloseLoopMidiWithMapper, LoopMidiStartedByMapper, LoopMidiPid

    if !CloseLoopMidiWithMapper || !LoopMidiStartedByMapper || !LoopMidiPid {
        return 0
    }

    if !ProcessExist(LoopMidiPid) {
        return 0
    }

    try {
        DetectHiddenWindows(true)
        if WinExist("ahk_pid " LoopMidiPid) {
            WinClose("ahk_pid " LoopMidiPid)
            WinWaitClose("ahk_pid " LoopMidiPid, , 2)
        }

        if ProcessExist(LoopMidiPid) {
            ProcessClose(LoopMidiPid)
        }
    }

    return 0
}

LoopMidiCandidates() {
    candidates := []
    programFiles := EnvGet("ProgramFiles")
    programFilesX86 := EnvGet("ProgramFiles(x86)")

    if programFiles != "" {
        candidates.Push(programFiles "\Tobias Erichsen\loopMIDI\loopMIDI.exe")
    }
    if programFilesX86 != "" {
        candidates.Push(programFilesX86 "\Tobias Erichsen\loopMIDI\loopMIDI.exe")
    }

    return candidates
}

WarnIfMidiPortMissing() {
    global MidiPort

    if !MidiPortIsListed() {
        MsgBox(
            "Guitar Rig is open or starting, but the MIDI port was not found: " MidiPort "`n`n"
            "Keyboard shortcuts will not work until the port is visible to Windows MIDI apps and Guitar Rig is restarted.`n`n"
            "Open loopMIDI and make sure the port exists, then restart Windows or restart the Windows MIDI Service.`n`n"
            "To restart the Windows MIDI Service manually, open PowerShell as administrator and run:`n"
            "Restart-Service midisrv`n`n"
            "You can verify the port with:`n"
            "tools\sendmidi\sendmidi.exe list",
            "Guitar Rig Shortcuts",
            "Icon!"
        )
    }
}

MidiPortIsListed() {
    global SendMidiPath, MidiPort

    outputPath := A_Temp "\gr-shortcuts-sendmidi-list-" A_TickCount ".txt"
    cmd := Format('"{1}" /C ""{2}" list > "{3}" 2>&1"', A_ComSpec, SendMidiPath, outputPath)

    try {
        RunWait(cmd, , "Hide")
        output := FileExist(outputPath) ? FileRead(outputPath) : ""
    }
    finally {
        if FileExist(outputPath) {
            FileDelete(outputPath)
        }
    }

    Loop Parse output, "`n", "`r" {
        if Trim(A_LoopField) = MidiPort {
            return true
        }
    }

    return false
}

RegisterMappings() {
    global GuitarRigWindow

    mappingSection := ReadSection("Mappings")
    if Trim(mappingSection) = "" {
        Abort("No mappings were found in [Mappings].")
    }

    registeredCount := 0
    HotIfWinActive(GuitarRigWindow)

    Loop Parse mappingSection, "`n", "`r" {
        line := Trim(A_LoopField)
        if line = "" || SubStr(line, 1, 1) = ";" {
            continue
        }

        parts := StrSplit(line, "=", , 2)
        if parts.Length < 2 {
            continue
        }

        keyName := Trim(parts[1])
        action := Trim(parts[2])

        if keyName = "" || action = "" {
            continue
        }

        parsed := ParseMappingAction(action)
        if !parsed {
            Abort("Invalid mapping action:`n" keyName "=" action)
        }

        try {
            Hotkey(keyName, HandleMappedKey.Bind(keyName, parsed), "On")
            registeredCount += 1
        }
        catch as error {
            Abort("Could not register hotkey '" keyName "':`n" error.Message)
        }
    }

    HotIfWinActive()

    if registeredCount = 0 {
        Abort("No usable mappings were found in [Mappings].")
    }
}

ParseMappingAction(action) {
    if RegExMatch(action, "i)^cc:(\d{1,3})(?::(\d{1,3}))?$", &match) {
        number := match[1] + 0
        value := match[2] != "" ? match[2] + 0 : 127
        return IsMidi7Bit(number) && IsMidi7Bit(value) ? { kind: "cc", number: number, value: value } : false
    }

    if RegExMatch(action, "i)^pulse:(\d{1,3})$", &match) {
        number := match[1] + 0
        return IsMidi7Bit(number) ? { kind: "pulse", number: number } : false
    }

    if RegExMatch(action, "i)^toggle:(\d{1,3})(?::(\d{1,3}))?$", &match) {
        number := match[1] + 0
        firstValue := match[2] != "" ? match[2] + 0 : 127
        if !IsMidi7Bit(number) || !(firstValue = 0 || firstValue = 127) {
            return false
        }

        nextValue := firstValue
        return { kind: "toggle", number: number, nextValue: nextValue }
    }

    if RegExMatch(action, "i)^pc:(\d{1,3})$", &match) {
        number := match[1] + 0
        return IsMidi7Bit(number) ? { kind: "pc", number: number } : false
    }

    return false
}

IsMidi7Bit(number) {
    return number >= 0 && number <= 127
}

HandleMappedKey(keyName, action, *) {
    waitKey := KeyWaitName(keyName)

    if action.kind = "cc" {
        SendCC(action.number, action.value)
    }
    else if action.kind = "pulse" {
        SendCCPulse(action.number)
    }
    else if action.kind = "toggle" {
        SendCCToggle(action)
    }
    else if action.kind = "pc" {
        SendProgramChange(action.number)
    }

    if waitKey != "" {
        KeyWait(waitKey)
    }
}

KeyWaitName(keyName) {
    keyName := RegExReplace(keyName, "^[~*$]+")
    keyName := RegExReplace(keyName, "^[<>^!+#]+")
    return keyName
}

SendCC(cc, value := 127) {
    SendMidi("cc " cc " " value)
}

SendCCToggle(action) {
    value := action.nextValue
    SendCC(action.number, value)
    action.nextValue := value = 127 ? 0 : 127
}

SendCCPulse(cc) {
    global PulseMs
    SendCC(cc, 127)
    Sleep PulseMs
    SendCC(cc, 0)
}

SendProgramChange(programNumber) {
    SendMidi("pc " programNumber)
}

SendMidi(args) {
    global SendMidiPath, MidiPort, MidiChannel

    cmd := Format('"{1}" dev "{2}" ch {3} {4}', SendMidiPath, MidiPort, MidiChannel, args)
    exitCode := RunWait(cmd, , "Hide")
    if exitCode != 0 {
        TrayTip("Guitar Rig Shortcuts", "Could not send MIDI. Check loopMIDI port: " MidiPort, 5)
    }
}

StartOrReuseGuitarRig() {
    global GuitarRigExe, GuitarRigArgs, GuitarRigWindow, GuitarRigProcess, ReuseRunningGuitarRig, ActivateGuitarRigOnStart

    if ReuseRunningGuitarRig && GuitarRigProcess != "" {
        existingPid := ProcessExist(GuitarRigProcess)
        if existingPid {
            if ActivateGuitarRigOnStart {
                try WinActivate(GuitarRigWindow)
            }
            return existingPid
        }
    }

    if GuitarRigExe = "" || !FileExist(GuitarRigExe) {
        Abort("Guitar Rig executable was not found:`n" GuitarRigExe "`n`nEdit config\gr-shortcuts.ini.")
    }

    target := '"' GuitarRigExe '"'
    if Trim(GuitarRigArgs) != "" {
        target .= " " GuitarRigArgs
    }

    Run(target, , , &pid)
    if !pid {
        Abort("Guitar Rig did not start.")
    }

    return pid
}

WatchGuitarRig(pid) {
    if !ProcessExist(pid) {
        ExitApp
    }
}
