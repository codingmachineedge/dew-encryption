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
- Window is 1180x780 logical (1770x1170 physical at 150% DPI). Long status text can clip at that
  height; to enlarge, run SetWindowPos *from the headless desktop* (cross-desktop SetWindowPos and
  `resize_window` fail):
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
