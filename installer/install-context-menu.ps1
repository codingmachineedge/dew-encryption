param(
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EscapedRoot = $ProjectRoot.Replace("'", "''")
$EscapedPython = $Python.Replace("'", "''")
$Command = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption '%1' }`""
$FolderCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption '%V' }`""

$keys = @(
    @{ Path = "HKCU:\Software\Classes\*\shell\dew-encryption"; Command = $Command },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption"; Command = $Command },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption"; Command = $FolderCommand }
)

foreach ($item in $keys) {
    New-Item -Path $item.Path -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "MUIVerb" -Value "dew encryption" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "Icon" -Value "imageres.dll,-102" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "AppliesTo" -Value "" -PropertyType String -Force | Out-Null
    $commandKey = Join-Path $item.Path "command"
    New-Item -Path $commandKey -Force | Out-Null
    Set-Item -Path $commandKey -Value $item.Command
}

Write-Host "Installed Explorer right-click menu entry: dew encryption"
