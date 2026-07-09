# Step Handoff: Install, Build, and Release

## Windows manual install

1. Clone the repo.
2. Install the Python package in editable mode.
3. Run `installer/install-context-menu.ps1`.
4. Verify Explorer actions appear under files, folders, and folder background menus.

## Windows automated/full installer

1. Use `installer/install.ps1` for automated local install.
2. Use `scripts/build-windows-installer.ps1` to build the Python CLI/history GUI, self-contained C# default GUI, and Inno Setup installer.
3. Verify setup automatically installs missing Git, 7-Zip, and VeraCrypt before it copies the app or registers integrations.
4. Verify Start Menu, postinstall launch, and startup use the C# GUI while history-manager verbs use the Python fallback.
5. Every branch push runs the installer workflow and publishes a commit-specific GitHub prerelease with installer and checksum release assets.
6. Use the release workflow for manual builds and tagged release artifacts.

## Linux install

1. Clone the repo.
2. Run `bash linux/install.sh`.
3. Confirm `dew-encryption` and `dew-encryption-gui` are available.
4. Confirm desktop launcher/icon and Nautilus scripts are installed.

## CI/release maintenance

1. Keep CI compile and smoke tests aligned with supported commands.
2. Validate Windows PowerShell scripts with parser checks.
3. Validate Linux scripts with `bash -n`.
4. Update GitHub Pages docs when feature surfaces change.
