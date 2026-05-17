# Guitar Rig keyboard MIDI shortcuts

Minimal Windows setup for using normal keyboard keys as MIDI controls in Guitar Rig 7.

The runtime path is:

keyboard key -> AutoHotkey focus filter -> `SendMIDI` -> `loopMIDI` port -> Guitar Rig "Learn MIDI Control" on the desired controls.

The mapper only captures configured keys while Guitar Rig 7 standalone app is focused.

## Setup

1. Run setup:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   This installs AutoHotkey v2 and loopMIDI through `winget`, then downloads `sendmidi.exe` into `tools\sendmidi`.

2. Open loopMIDI and create a port named:

   ```text
   GR7 Control
   ```

   Leave loopMIDI running. Creating the port is manual because loopMIDI does not provide a documented port-creation command line.

3. The default Guitar Rig exe path is `C:\Program Files\Native Instruments\Guitar Rig 7\Guitar Rig 7.exe`. Edit [config/gr-shortcuts.ini `GuitarRigExe=`](/config/gr-shortcuts.ini#L5) if your Guitar Rig path is different.

4. In Guitar Rig, open `Preferences -> MIDI` and enable the `GR7 Control` input.

5. Start the shortcut launcher:

   ```bat
   .\launch-gr-shortcuts.bat
   ```

The launcher starts the mapper and Guitar Rig. The mapper exits when the Guitar Rig process exits.

### Manual fallback

If setup cannot install everything automatically:

1. Install AutoHotkey v2: <https://www.autohotkey.com/>
2. Install loopMIDI: <https://www.tobias-erichsen.de/software/loopmidi.html>
3. Download SendMIDI for Windows: <https://github.com/gbevin/SendMIDI/releases/latest>
4. Extract `sendmidi.exe` to `tools\sendmidi\sendmidi.exe`.

Then continue from the loopMIDI port step above.

## Mapping keys

Mappings live in [config/gr-shortcuts.ini:22](/config/gr-shortcuts.ini#L22):

```ini
Space=cc:20
Left=cc:21
Right=cc:22
1=cc:31
2=cc:32
```

Each `cc:N` mapping sends a short MIDI CC pulse: value `127`, then value `0`. Guitar Rig MIDI Learn should see the CC when you press the key while Guitar Rig is focused.

Program Change is also supported:

```ini
F1=pc:1
F2=pc:2
```

MIDI CC and Program Change numbers must be between `0` and `127`.

## Optional single exe

After the script works, compile it with AutoHotkey's Ahk2Exe and put the output in the repo root:

```powershell
& "$env:ProgramFiles\AutoHotkey\Compiler\Ahk2Exe.exe" /in .\src\gr-shortcuts.ahk /out .\gr-shortcuts.exe
```

The compiled exe still reads [config/gr-shortcuts.ini:1](/config/gr-shortcuts.ini#L1), so mappings can be edited without recompiling.

## Guitar Rig binding workflow

1. Start `launch-gr-shortcuts.bat`.
2. In Guitar Rig, right-click a MIDI-learnable control.
3. Choose MIDI Learn.
4. Press the mapped keyboard key.

Good UX candidates are Tapedeck play/stop if it is MIDI-learnable, previous/next preset if exposed by Guitar Rig, Macros, and component bypass buttons.
