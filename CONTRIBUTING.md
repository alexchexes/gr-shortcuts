# Contributing

## Checks

Before opening a PR, run the smoke suite:

```powershell
.\test.ps1
```

If you only changed your local key mappings and want a quick key-name check, run:

```powershell
.\validate-config.bat
```

If you change [gr-shortcuts.example.ini](/config/gr-shortcuts.example.ini), keep the example CC numbers unique so users can uncomment keys without searching for a free number.

## Manual Release Check

To create a zip:

```powershell
git archive --format=zip --output dist/gr-shortcuts-v0.X.0.zip HEAD
```

Before publishing a release:

1. Run setup from a release zip.
2. Confirm that the loopMIDI port appears in Guitar Rig.
3. Confirm that `cc`, `toggle`, and `pulse` mappings work with Guitar Rig MIDI Learn.
4. Confirm that the main Guitar Rig window captures mapped keys.
5. Confirm that Guitar Rig Save As and file dialogs do not capture `Left`/`Right`.
6. Confirm that an existing loopMIDI process is not closed when the mapper did not start it.
7. Check `check-update.bat` and `update.bat` against a real release.
