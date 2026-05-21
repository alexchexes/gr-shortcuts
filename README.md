# Guitar Rig PC Keyboard Shortcuts

A simple utility that solves a pain for Guitar Rig users who do not have a MIDI device.

Guitar Rig does not allow custom keybindings for a regular PC keyboard. It only allows MIDI controls to be mapped via the "Learn MIDI" feature.

This tool lets you work around that limitation in a simple way. After setting it up once, you can start Guitar Rig and this tool from a normal desktop shortcut and use it right away.

## How it works

In simple terms: it makes Guitar Rig think that when you press a key on your PC keyboard, you are pressing a control on a MIDI device, such as a synthesizer.

When you press a configured key, Guitar Rig receives a MIDI message that can be used to bind a certain action/knob for that message through "Learn MIDI".

It uses three small pieces:

- [AutoHotkey v2](https://www.autohotkey.com/) - to capture configured keyboard keys while Guitar Rig is focused.
- [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html) - to create a virtual MIDI port that Guitar Rig can receive.
- [SendMIDI](https://github.com/gbevin/SendMIDI) - to send MIDI CC messages to that virtual MIDI port.

The mapper only captures configured keys while the Guitar Rig 7 standalone app is focused. Outside Guitar Rig, those keys behave normally.

```text
keyboard key -> AutoHotkey focus filter -> SendMIDI -> loopMIDI port -> Guitar Rig MIDI Learn
```

## Limitations

- Tested only with Guitar Rig 7.
- Windows only for now. Let me know via an issue or PR if you need support for macOS.
- It cannot bind actions that Guitar Rig does not expose through "Learn MIDI".
  For example, you cannot bind "load a specific preset when I press F1/F2/F3" because Guitar Rig does not provide Learn MIDI for specific presets.
  > However, you can bind `←`/`→` to switch presets from the currently visible filtered list in the Browser.

## Setup

1. Download the release zip from the [latest release](https://github.com/alexchexes/gr-shortcuts/releases/latest) and extract it somewhere, for example to `C:\Tools\gr-shortcuts`.

2. Close Guitar Rig if it is open, then run `setup.bat` in the extracted folder.

   Setup will install AutoHotkey v2 and loopMIDI through `winget`, download `sendmidi.exe`, create `config\gr-shortcuts.ini` from [gr-shortcuts.example.ini](/config/gr-shortcuts.example.ini) if needed, check the configured Guitar Rig path, and offer to create a desktop shortcut that starts Guitar Rig and this tool at the same time.

3. When setup asks, create a loopMIDI port named `GR7 Control`, leave loopMIDI running, then return to setup and press Enter.

   Setup checks whether SendMIDI can see the port. If Windows does not expose the port yet, setup offers to restart the Windows MIDI Service with an admin prompt. You can also restart the service manually or reboot Windows.

4. If setup says it cannot find Guitar Rig, adjust `GuitarRigExe=` in `config\gr-shortcuts.ini`. The default uses `%ProgramFiles%\Native Instruments\Guitar Rig 7\Guitar Rig 7.exe`.

5. Start Guitar Rig normally once (without `launch-gr-shortcuts.bat`). In Guitar Rig, open `Preferences -> MIDI` and enable the `GR7 Control` input.

   If the checkbox does not stay enabled, close and reopen Guitar Rig.

6. After that, start Guitar Rig and this tool at the same time by using either the `Guitar Rig Shortcuts` desktop shortcut, if you opted in during setup, or by running `launch-gr-shortcuts.bat`. The launcher starts the mapper, the mapper starts loopMIDI if needed, and then Guitar Rig starts. The mapper exits when Guitar Rig exits. If the mapper started loopMIDI, it closes loopMIDI too. If loopMIDI was already running, it leaves it alone.

## Updating

To check for updates, run:

```bat
.\check-update.bat
```

If a newer version exists:

1. Close Guitar Rig and Guitar Rig Shortcuts.
2. Download the latest release zip from the [latest release](https://github.com/alexchexes/gr-shortcuts/releases/latest).
3. Extract it over your existing `gr-shortcuts` folder.
4. Run `setup.bat` again if the release notes ask for it.

Your `config\gr-shortcuts.ini` file is user-local and is not included in the release zip. Setup creates it from [gr-shortcuts.example.ini](/config/gr-shortcuts.example.ini) only if the file is missing.

## Startup Behavior

By default, the launcher cleans up the helper processes it starts:

- `CloseMapperWithGuitarRig=1` closes the AutoHotkey mapper when Guitar Rig closes.
- `CloseLoopMidiWithMapper=1` closes loopMIDI only if this mapper started it. If loopMIDI was already running, it is left alone.

This keeps the session tidy, but the next launch may be slower than starting Guitar Rig directly because the launcher may need to start AutoHotkey and loopMIDI first. The MIDI port check runs after Guitar Rig starts; if the port is missing, you will see a warning.

For faster repeated Guitar Rig starts, edit `config\gr-shortcuts.ini` and use:

```ini
CloseMapperWithGuitarRig=0
CloseLoopMidiWithMapper=0
```

Then start Guitar Rig Shortcuts once and leave it running. The mapper only captures keys while Guitar Rig is focused, so it can stay open in the background. For the fastest repeated starts, open Guitar Rig normally after the mapper is already running. The launcher still works, but it starts a new mapper process.

## Manual Setup

If `setup.bat` cannot install the dependencies automatically, install them manually:

1. Install AutoHotkey v2: <https://www.autohotkey.com/>
2. Install loopMIDI: <https://www.tobias-erichsen.de/software/loopmidi.html>
3. Download SendMIDI for Windows `1.3.1`: <https://github.com/gbevin/SendMIDI/releases/tag/1.3.1>
4. Extract `sendmidi.exe` to `tools\sendmidi\sendmidi.exe`.

Then run `setup.bat` again, or continue from the loopMIDI port step above.

## Troubleshooting

If `GR7 Control` exists in loopMIDI but does not appear in Guitar Rig, first check whether Windows MIDI clients can see it:

```bat
tools\sendmidi\sendmidi.exe list
```

If the list does not include `GR7 Control`, close Guitar Rig and restart Windows. Advanced users can instead restart the Windows MIDI Service from an elevated PowerShell:

```powershell
Restart-Service midisrv
```

Then reopen loopMIDI, confirm the `GR7 Control` port still exists, and start Guitar Rig again.

Microsoft tracks this as a Windows MIDI Services issue where dynamic ports such as loopMIDI / teVirtualMIDI ports are not always visible: <https://devblogs.microsoft.com/windows-music-dev/windows-midi-services-rollout-known-issues-and-workarounds/>

## Mapping Keys

As mentioned above, this works by mapping PC keyboard keys to MIDI signals for Guitar Rig.
By default, only a limited set of keys is enabled to avoid making the whole keyboard unusable while Guitar Rig is running.
Enabled keys and MIDI mappings are configured in `config\gr-shortcuts.ini`. The default template is [gr-shortcuts.example.ini](/config/gr-shortcuts.example.ini).

The default enabled keys are meant to work as a small numpad-first control surface:

| Key                | Mapping                                                         | Suggested use                              |
| ------------------ | --------------------------------------------------------------- | ------------------------------------------ |
| `←`                | `cc:21`                                                         | Previous preset/control                    |
| `→`                | `cc:22`                                                         | Next preset/control                        |
| `Numpad Enter`     | `toggle:53`                                                     | Tapedeck Play/Pause, or any on/off control |
| `Numpad .`         | `pulse:51`                                                      | Tapedeck Stop, or another momentary action |
| `Numpad +`         | `cc:52`                                                         | Extra one-shot control                     |
| `Numpad -`         | `cc:19`                                                         | Extra one-shot control                     |
| `Numpad 0`         | `toggle:50`                                                     | Main macro/effect toggle                   |
| `Numpad 1-5`       | `toggle:54`, `toggle:55`, `toggle:56`, `toggle:11`, `toggle:12` | Macros or effect bypass buttons            |
| Backtick/grave key | `cc:49`                                                         | Extra easy-to-reach control                |

You can reassign any of these to any MIDI-learnable Guitar Rig control.

There are a few mapping types:

- `cc:N` sends CC `N` with value `127`, which is the maximum MIDI CC value. Use this for simple one-shot actions.
- `cc:N:V` sends CC `N` with a specific value `V`, where `V` can be `0-127`. For example, `cc:20:64` sends a roughly "50%" value.
- `toggle:N` alternates between `127` and `0`. This is the better choice for Play/Pause or bypass-style controls.
- `pulse:N` sends `127`, then `0`. This is useful for momentary controls such as Stop.
- `pc:N` sends MIDI Program Change `N`. Use this only for MIDI targets that support Program Change; normal Guitar Rig Learn MIDI controls usually use CC.

For knobs and other continuous parameters, Guitar Rig uses absolute MIDI CC values. A keyboard key can set one fixed value with `cc:N:V`, or switch between two values with `toggle:N`. Gradual increase/decrease by repeated keypresses is not implemented yet.

If a `cc:N` mapping works only once, the control probably expects changing values. Try `toggle:N` for on/off controls or `pulse:N` for momentary controls.

The example CC numbers in the config are unique, so you can usually just uncomment keys. Change CC numbers when you want two keys to trigger the same Guitar Rig action, or when you need to avoid conflicts with another MIDI controller.

Some useful keys are disabled by default because Guitar Rig already uses them as normal keyboard shortcuts. For example, Guitar Rig uses `Space`, `↑`, `↓`, `Enter`, `Escape`, `Tab`, and `Delete` in its browser and dialogs. You can still uncomment and map them if you want MIDI behavior to take over.

Left/right modifiers are available in the config, but disabled by default because they can interfere with normal Windows shortcuts. If you need them, use `LControl`, `RControl`, `LAlt`, `RAlt`, `LShift`, `RShift`. Generic modifiers such as `Control`, `Alt`, and `Shift` catch either side.

Key combinations also work. AutoHotkey uses `^` for Ctrl, `!` for Alt, `+` for Shift, and `#` for the Windows key, for example `^1=cc:36` means `Ctrl+1`. The config contains commented-out examples. Be careful with `Alt` and Windows-key combinations because they may interfere with normal Windows shortcuts.

Enabled keys are captured while Guitar Rig is focused. For example, if you enable `Alt`, `Alt+Tab` may stop working while Guitar Rig is focused.

Guitar Rig keyboard shortcuts manual: <https://www.native-instruments.com/ni-tech-manuals/guitar-rig-manual/en/keyboard-shortcuts>

## Guitar Rig MIDI Learn

1. Start `launch-gr-shortcuts.bat`.
2. In Guitar Rig, right-click a MIDI-learnable control.
3. Choose `Learn MIDI Control`.
4. Press the mapped keyboard key.

Good candidates are Tapedeck play/stop if it is MIDI-learnable, previous/next preset if exposed by Guitar Rig, Macros, and component bypass buttons.

Guitar Rig MIDI Learn manual: <https://www.native-instruments.com/ni-tech-manuals/guitar-rig-manual/en/automation-and-midi-control>

## Validate Config

Run this after editing mappings if you want a quick key-name check:

```powershell
.\validate-config.bat
```

## Contributor Notes

Before opening a PR, run the config check:

```powershell
.\validate-config.bat
```

If you change [gr-shortcuts.example.ini](/config/gr-shortcuts.example.ini), keep the example CC numbers unique so users can uncomment keys without searching for a free number.

## License

MIT. See [LICENSE](/LICENSE).

## TODO

- Add a small GUI for editing key mappings without opening the config file manually.
- Consider adding `inc:N:STEP` and `dec:N:STEP` mappings for keyboard-controlled gradual changes.