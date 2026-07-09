$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script = Join-Path $root "installer\create-elevated-tasks.ps1"
$guiExecutable = Join-Path $root "dew-encryption-gui.exe"
$cliExecutable = Join-Path $root "dew-encryption.exe"

Start-Process powershell -Verb RunAs -ArgumentList @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$script`"",
    "-GuiExecutable", "`"$guiExecutable`"",
    "-CliExecutable", "`"$cliExecutable`""
)
