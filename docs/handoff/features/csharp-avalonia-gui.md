# Feature Handoff: C# Avalonia GUI

## Purpose

The C# Avalonia project is the default GUI for packaged Windows installs. It is published self-contained and drives the adjacent bundled Python `dew-encryption.exe` CLI while native feature parity continues to expand.

## Current capabilities

- Files tab: add files, add folder, remove selected, run Dew Encryption, log output.
- History tab: refresh history, snapshot now, open Python history manager.
- Containers tab: register draft container labels, snapshot container history, test open hooks, test close hooks.
- Header: open CLI help.

## Code path

- `MainWindow.axaml` declares the UI and click handler names.
- `MainWindow.axaml.cs` stores selected paths in `ObservableCollection<DewPathItem>` and invokes the bundled CLI or `dew-encryption-python-gui` using `ProcessStartInfo.ArgumentList`.
- CLI stdout/stderr and exit code are appended to the log box.

## Change checklist

- Keep CLI calls argument-list based rather than shell-string based.
- As native feature parity grows, decide whether to call Python APIs directly or keep the CLI boundary.
- Keep the self-contained Windows publish and .NET build covered in CI.
