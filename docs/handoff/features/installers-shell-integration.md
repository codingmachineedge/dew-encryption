# Feature Handoff: Installers and Shell Integration

## Purpose

Installer and shell integration files expose the CLI and GUI through Windows Explorer, Linux desktop launchers, Nautilus scripts, and optional elevated scheduled-task setup.

## Windows components

- `installer/install.ps1`: automated dependency/repo/package/context-menu setup.
- `installer/install-context-menu.ps1`: HKCU Explorer menu registration.
- `installer/uninstall-context-menu.ps1`: removes Explorer actions.
- `installer/create-elevated-tasks.ps1` and `remove-elevated-tasks.ps1`: explicit admin-consented scheduled task setup/removal.
- `installer/DewEncryption.iss`: Inno Setup script for the fully configured x64 Windows installer. It requires Git, 7-Zip, and VeraCrypt and invokes one elevated dependency helper that uses winget or pinned, hash-verified vendor installers when any are missing.
- `installer/install-dependencies.ps1`: installs and verifies required system dependencies.
- `scripts/build-windows-installer.ps1`: builds the Python CLI/history GUI, publishes the self-contained C# GUI, and compiles the installer.

## Linux components

- `linux/install.sh`: user install, desktop file, icon, Nautilus scripts.
- `linux/uninstall.sh`: user uninstall.
- `linux/dew-encryption.desktop`: desktop launcher.
- `linux/nautilus-scripts/*`: right-click script actions.

## Change checklist

- Any CLI subcommand rename must be propagated to all shell scripts and installer command strings.
- Explorer registrations are HKCU and non-admin by design.
- The main app remains a per-user install; only the required system dependency helper requests normal UAC elevation.
- Start Menu, postinstall launch, and startup use the C# GUI. History-manager verbs intentionally use the Python GUI until native history parity is complete.
- Elevated tasks should remain explicit and UAC-consented; do not silently bypass UAC.
