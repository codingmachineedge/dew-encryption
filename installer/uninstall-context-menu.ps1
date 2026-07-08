$ErrorActionPreference = "Stop"

$keys = @(
    "HKCU:\Software\Classes\*\shell\dew-encryption",
    "HKCU:\Software\Classes\Directory\shell\dew-encryption",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption",
    "HKCU:\Software\Classes\Directory\shell\dew-encryption-watch",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-watch",
    "HKCU:\Software\Classes\Directory\shell\dew-encryption-manager",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-manager",
    "HKCU:\Software\Classes\*\shell\dew-encryption-veracrypt-encrypt",
    "HKCU:\Software\Classes\Directory\shell\dew-encryption-veracrypt-encrypt",
    "HKCU:\Software\Classes\.hc\shell\dew-encryption-veracrypt-decrypt",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-create-elevated-tasks",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-remove-elevated-tasks",
    "HKCU:\Software\Classes\*\shell\dew-encryption-dew-drive-add",
    "HKCU:\Software\Classes\Directory\shell\dew-encryption-dew-drive-add",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-dew-drive-sync",
    "HKCU:\Software\Classes\*\shell\dew-encryption-docker-upload",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-docker-save-here",
    "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-git-commit-push",
    "HKCU:\Software\Classes\Directory\shell\dew-encryption-git-commit-push"
)

foreach ($key in $keys) {
    if (Test-Path $key) {
        Remove-Item -Path $key -Recurse -Force
    }
}

Write-Host "Removed Explorer right-click menu entry: dew encryption"
