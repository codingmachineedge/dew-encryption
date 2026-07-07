# Dew Encryption

Dew Encryption is a small Windows utility that adds a normal Explorer right-click action named `dew encryption`. It snapshots the selected file or folder into a local Git repository, commits the current contents, and compresses that repository into a `.7z` archive.

It also includes a simple GUI file manager for selecting files and running the same workflow without using Explorer.

## Screenshots

![Dew Encryption GUI](docs/screenshots/gui.svg)

![Explorer menu mockup](docs/screenshots/explorer-menu.svg)

## Requirements

- Windows 10 or later
- Python 3.10+
- Git for Windows
- 7-Zip with `7z.exe` available on `PATH`, or installed in the standard `Program Files\7-Zip` location

## Install

Fully automated install, including dependencies when `winget` is available:

```powershell
irm https://raw.githubusercontent.com/codingmachineedge/dew-encryption/main/installer/install.ps1 | iex
```

That command installs or verifies Python, Git, and 7-Zip, clones this repo into `%LOCALAPPDATA%\DewEncryption`, installs the Python package, and registers the Explorer context menu.

Manual install:

```powershell
git clone https://github.com/codingmachineedge/dew-encryption.git
cd dew-encryption
python -m pip install -e .
powershell -ExecutionPolicy Bypass -File .\installer\install-context-menu.ps1
```

The installer writes only to `HKCU`, so it does not require administrator rights. The menu entry is registered for files, folders, and folder background right-clicks, and it does not require holding Shift.

## GitHub Pages

Project page:

https://codingmachineedge.github.io/dew-encryption/

The page is deployed by `.github/workflows/pages.yml` from the `docs/` folder.

## GitHub Actions

- `.github/workflows/ci.yml` compiles the package, parses installer scripts, installs 7-Zip, and runs a real snapshot smoke test on Windows.
- `.github/workflows/release.yml` builds a zip bundle on tag pushes like `v0.1.0` or manual workflow runs.
- `.github/workflows/pages.yml` deploys `docs/` to GitHub Pages.

## Use From Explorer

1. Right-click a file or folder.
2. Choose `dew encryption`.
3. Find the output under `Dew Encryption Archives` beside the selected item.

Each run creates or updates:

- `Dew Encryption Archives\.dew-encryption-repo`
- `Dew Encryption Archives\dew-encryption-YYYYMMDD-HHMMSS.7z`

## Use The GUI

```powershell
dew-encryption-gui
```

or:

```powershell
python -m dew_encryption.gui
```

## Optional Encrypted Archive

The CLI accepts a password for 7-Zip encryption:

```powershell
dew-encryption --password "change-me" C:\Path\To\Folder
```

When a password is supplied, the archive uses 7-Zip header encryption.

## Uninstall Explorer Menu

```powershell
powershell -ExecutionPolicy Bypass -File .\installer\uninstall-context-menu.ps1
```
