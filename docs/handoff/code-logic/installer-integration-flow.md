# Code Logic Handoff: Installer and Integration Flow

## Full Windows installer flow

1. `PrepareToInstall` detects Git, 7-Zip, and VeraCrypt through `PATH` and standard install locations.
2. If anything is missing, the installer extracts `install-dependencies.ps1` and runs it once with normal UAC elevation.
3. The helper tries winget first and falls back to pinned, SHA-256-verified vendor installers, then verifies every executable and fails setup if the machine remains incomplete.
4. Setup installs the bundled Python CLI, self-contained C# GUI, and Python history GUI.
5. Start Menu, postinstall launch, and optional startup use the C# GUI; specialized history verbs use the Python fallback.

## Windows context menu flow

1. `install-context-menu.ps1` computes project root and Python executable.
2. It builds command strings for files, folders, folder backgrounds, VeraCrypt actions, history manager, watcher, and elevated task setup/removal.
3. It creates HKCU registry keys and command subkeys.
4. It assigns action-specific icons and multi-select behavior for container actions.

## Elevated task flow

- Launcher scripts start PowerShell with `-Verb RunAs` so Windows shows a normal UAC prompt.
- Task scripts create/remove clearly named `DewEncryption.*.Elevated` tasks.

## Linux install flow

1. Validate `python3`, `git`, and `7z`; warn if VeraCrypt is missing.
2. Install the Python package for the current user.
3. Copy desktop launcher, icon, and Nautilus scripts.
4. Update desktop database/icon cache when tools are available.
