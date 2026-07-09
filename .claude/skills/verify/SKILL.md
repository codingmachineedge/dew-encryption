---
name: verify
description: Build and drive the Dew Encryption C# GUI to verify changes end-to-end without touching the user's real settings or visible desktop.
---

# Verifying Dew Encryption changes

## Build

```bash
dotnet build csharp/DewEncryption.sln -c Release --nologo
```

Use Release when a previously launched Debug GUI instance holds a lock on
`csharp/DewEncryption.Gui/bin/Debug/net8.0/DewEncryption.Core.dll` (common; don't kill the
user's instance). The Avalonia XAML compiler runs at build time, so a successful build also
validates `Click="..."` handler wiring.

## Isolate settings

`SettingsService.ResolveConfigFilePath` honors the `DEW_ENCRYPTION_CONFIG` env var. Point it at a
scratch JSON so GUI driving never touches `%APPDATA%\DewEncryption\settings.json`. JSON uses
snake_case keys (e.g. `dew_drives.drives[].last_sync`). Seed profiles directly in the file to skip
form typing.

## Launch off-screen (lowlevel-computer-use MCP)

```
create_headless_desktop {name: "DewVerify"}
launch_on_headless_desktop {name: "DewVerify", command: "cmd.exe /c \"set DEW_ENCRYPTION_CONFIG=<scratch>\\settings.json&& <repo>\\csharp\\DewEncryption.Gui\\bin\\Release\\net8.0\\DewEncryption.Gui.exe\""}
```

Wait ~4s, then `list_headless_windows` → find the "Dew Encryption" window hwnd.

## Drive

- `screenshot {hwnd, client_only: true}` — client pixel coords match background-click client coords.
- `mouse_click {hwnd, x, y}` — background PostMessage clicks work on Avalonia (tabs, buttons, list
  items, textboxes).
- `type_text {hwnd, text}` — WM_CHAR typing works after clicking a TextBox to focus it.
- Window is 1180x840 logical (1770x1260 physical at 150% DPI); the Dew Drive right panel scrolls.
  Background typing into a just-clicked TextBox can race Avalonia focus — if typed text vanishes,
  re-click and retype, or seed values via the settings JSON instead. To enlarge the window, run
  SetWindowPos *from the headless desktop* (cross-desktop SetWindowPos and `resize_window` fail):
  `launch_on_headless_desktop` with a `powershell.exe -NoProfile -Command "Add-Type ... SetWindowPos(...)"` one-liner.
- The GUI's CLI calls fall back to `python -m dew_encryption.core` (repo root) and inherit
  `DEW_ENCRYPTION_CONFIG`; a real `dew-drive sync` on a scratch profile succeeds on this machine
  (7-Zip present), so successful-sync paths are testable for real.

## Clean up

Kill only the GUI you launched: find `DewEncryption.Gui.exe` whose `ParentProcessId` is the cmd PID
returned by `launch_on_headless_desktop`, `Stop-Process` it, then `close_headless_desktop`.

## Gotchas

- The "Startup" checkbox reflects the real HKCU Run registry key even with a scratch config —
  don't toggle it during tests (it writes the user's registry).
- `RefreshDriveList()` reloads settings from disk and resets list selection.

## VeraCrypt testing gotchas

- **Git Bash mangles `/switch` args** (MSYS path conversion) — any direct VeraCrypt/Format run from
  Bash needs `export MSYS2_ARG_CONV_EXCL='*'` or the exe receives garbage and silently no-ops with
  exit 0. Python `subprocess` and the headless launcher pass args verbatim (no mangling).
- Creation uses `"VeraCrypt Format.exe"`; mount/dismount use `VeraCrypt.exe`. Format rejects the
  VeraCrypt.exe-only `/quit` switch ("Error while parsing command line."), and under `/silent` that
  suppressed dialog hangs the process forever.
- VeraCrypt error dialogs render black via PrintWindow; read their text with `list_child_windows`
  (the Static control holds the message).
- `/silent` auto-accepts the short-password (<20 chars) warning; without `/silent` it blocks on a
  Yes/No prompt. exFAT file containers create fine without elevation.
- Kill stray `VeraCrypt Format` processes between experiments — a lingering instance makes new
  launches exit 0 instantly without doing anything.
