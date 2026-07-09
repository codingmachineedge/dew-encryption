param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed with exit code $LASTEXITCODE." }
python -m pip install pyinstaller
if ($LASTEXITCODE -ne 0) { throw "PyInstaller installation failed with exit code $LASTEXITCODE." }

Remove-Item -Path .\build, .\dist\app, .\dist\csharp-gui, .\dist\installer, .\dist\dew-encryption.exe, .\dist\dew-encryption-python-gui.exe -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path .\dist\app | Out-Null

python -m PyInstaller --clean --onefile --icon .\assets\icons\dew-main.ico --name dew-encryption .\dew_encryption\__main__.py
if ($LASTEXITCODE -ne 0) { throw "CLI packaging failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath .\dist\dew-encryption.exe -PathType Leaf)) { throw "CLI packaging did not create dist\dew-encryption.exe." }
Copy-Item .\dist\dew-encryption.exe .\dist\app\dew-encryption.exe -Force

python -m PyInstaller --clean --onefile --windowed --icon .\assets\icons\dew-main.ico --name dew-encryption-python-gui .\dew_encryption\gui_main.py
if ($LASTEXITCODE -ne 0) { throw "Python history GUI packaging failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath .\dist\dew-encryption-python-gui.exe -PathType Leaf)) { throw "Python history GUI packaging did not create its executable." }
Copy-Item .\dist\dew-encryption-python-gui.exe .\dist\app\dew-encryption-python-gui.exe -Force

dotnet publish .\csharp\DewEncryption.Gui\DewEncryption.Gui.csproj `
    --configuration $Configuration `
    --runtime win-x64 `
    --self-contained true `
    --output .\dist\csharp-gui `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:DebugType=None `
    -p:DebugSymbols=false
if ($LASTEXITCODE -ne 0) { throw "C# GUI publish failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath .\dist\csharp-gui\DewEncryption.Gui.exe -PathType Leaf)) { throw "C# GUI publish did not create its executable." }
Copy-Item .\dist\csharp-gui\DewEncryption.Gui.exe .\dist\app\dew-encryption-gui.exe -Force

$iscc = Get-Command iscc -ErrorAction SilentlyContinue
if (-not $iscc) {
    throw "Inno Setup Compiler (iscc) was not found. Install Inno Setup, then rerun this script."
}

& $iscc.Source .\installer\DewEncryption.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath .\dist\installer\DewEncryptionSetup.exe -PathType Leaf)) { throw "Inno Setup did not create the installer." }

Write-Host "Installer created at dist\installer\DewEncryptionSetup.exe"
