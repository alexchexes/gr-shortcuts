#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
#UseHook

A_IconTip := "Guitar Rig Shortcuts"

ScriptDir := A_ScriptDir
RootDir := RegExReplace(ScriptDir, "\\src$")
ConfigPath := RootDir "\config\gr-shortcuts.ini"

if !FileExist(ConfigPath) {
    MsgBox("Missing config file:`n" ConfigPath, "Guitar Rig Shortcuts", "Iconx")
    ExitApp
}

GuitarRigExe := ResolveConfiguredPath(ReadSetting("App", "GuitarRigExe", ""))
GuitarRigArgs := ReadSetting("App", "GuitarRigArgs", "")
GuitarRigWindow := ReadSetting("App", "GuitarRigWindow", "ahk_exe Guitar Rig 7.exe")
GuitarRigProcess := ReadSetting("App", "GuitarRigProcess", "Guitar Rig 7.exe")
LoopMidiExe := ResolveConfiguredPath(ReadSetting("App", "LoopMidiExe", ""))
ReuseRunningGuitarRig := ReadBoolSetting("App", "ReuseRunningGuitarRig", true)
ActivateGuitarRigOnStart := ReadBoolSetting("App", "ActivateGuitarRigOnStart", true)
CloseMapperWithGuitarRig := ReadBoolSetting("App", "CloseMapperWithGuitarRig", true)

MidiPort := ReadSetting("MIDI", "Port", "GR7 Control")
SendMidiPath := ResolveConfiguredPath(ReadSetting("MIDI", "SendMidiPath", "tools\sendmidi\sendmidi.exe"))
MidiChannel := ReadNumberSetting("MIDI", "Channel", 1)
PulseMs := ReadNumberSetting("MIDI", "PulseMs", 40)

if !FileExist(SendMidiPath) {
    MsgBox("Missing SendMIDI executable:`n" SendMidiPath "`n`nRun setup.ps1 first.", "Guitar Rig Shortcuts", "Iconx")
    ExitApp
}

StartLoopMidiIfPossible()
RegisterMappings()
guitarRigPid := StartOrReuseGuitarRig()

if CloseMapperWithGuitarRig && guitarRigPid {
    SetTimer(WatchGuitarRig.Bind(guitarRigPid), 1000)
}

TrayTip("Guitar Rig Shortcuts", "Mapper is running for " GuitarRigWindow, 3)

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
    global LoopMidiExe

    if ProcessExist("loopMIDI.exe") {
        return
    }

    if LoopMidiExe != "" && FileExist(LoopMidiExe) {
        Run('"' LoopMidiExe '"', , "Hide")
        Sleep 600
        return
    }

    for candidate in LoopMidiCandidates() {
        if FileExist(candidate) {
            Run('"' candidate '"', , "Hide")
            Sleep 600
            return
        }
    }
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

RegisterMappings() {
    global GuitarRigWindow

    mappingSection := ReadSection("Mappings")
    if Trim(mappingSection) = "" {
        MsgBox("No mappings were found in [Mappings].", "Guitar Rig Shortcuts", "Iconx")
        ExitApp
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
            MsgBox("Invalid mapping action:`n" keyName "=" action, "Guitar Rig Shortcuts", "Iconx")
            ExitApp
        }

        try {
            Hotkey(keyName, HandleMappedKey.Bind(keyName, parsed.kind, parsed.number), "On")
            registeredCount += 1
        }
        catch as error {
            MsgBox("Could not register hotkey '" keyName "':`n" error.Message, "Guitar Rig Shortcuts", "Iconx")
            ExitApp
        }
    }

    HotIfWinActive()

    if registeredCount = 0 {
        MsgBox("No usable mappings were found in [Mappings].", "Guitar Rig Shortcuts", "Iconx")
        ExitApp
    }
}

ParseMappingAction(action) {
    if RegExMatch(action, "i)^cc:(\d{1,3})$", &match) {
        number := match[1] + 0
        return IsMidi7Bit(number) ? { kind: "cc", number: number } : false
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

HandleMappedKey(keyName, kind, number, *) {
    waitKey := KeyWaitName(keyName)

    if kind = "cc" {
        SendCCPulse(number)
    }
    else if kind = "pc" {
        SendProgramChange(number)
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

SendCCPulse(cc) {
    global PulseMs
    SendMidi("cc " cc " 127")
    Sleep PulseMs
    SendMidi("cc " cc " 0")
}

SendProgramChange(programNumber) {
    SendMidi("pc " programNumber)
}

SendMidi(args) {
    global SendMidiPath, MidiPort, MidiChannel

    cmd := Format('"{1}" dev "{2}" ch {3} {4}', SendMidiPath, MidiPort, MidiChannel, args)
    exitCode := RunWait(cmd, , "Hide")
    if exitCode != 0 {
        TrayTip("Guitar Rig Shortcuts", "SendMIDI failed. Check loopMIDI port: " MidiPort, 5)
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
        MsgBox("Guitar Rig executable was not found:`n" GuitarRigExe "`n`nEdit config\gr-shortcuts.ini.", "Guitar Rig Shortcuts", "Iconx")
        ExitApp
    }

    target := '"' GuitarRigExe '"'
    if Trim(GuitarRigArgs) != "" {
        target .= " " GuitarRigArgs
    }

    Run(target, , , &pid)
    if !pid {
        MsgBox("Guitar Rig did not start.", "Guitar Rig Shortcuts", "Iconx")
        ExitApp
    }

    return pid
}

WatchGuitarRig(pid) {
    if !ProcessExist(pid) {
        ExitApp
    }
}
