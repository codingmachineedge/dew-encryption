param(
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$EscapedRoot = $ProjectRoot.Replace("'", "''")
$EscapedPython = $Python.Replace("'", "''")
$Command = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption '%1' }`""
$FolderCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption '%V' }`""
$WatchCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; Start-Process -WindowStyle Hidden -FilePath '$EscapedPython' -ArgumentList @('-m','dew_encryption','watch','%1') }`""
$WatchBackgroundCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; Start-Process -WindowStyle Hidden -FilePath '$EscapedPython' -ArgumentList @('-m','dew_encryption','watch','%V') }`""
$ManagerCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption.gui '%1' --history }`""
$ManagerBackgroundCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption.gui '%V' --history }`""

$keys = @(
    @{ Path = "HKCU:\Software\Classes\*\shell\dew-encryption"; Verb = "dew encryption"; Command = $Command },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption"; Verb = "dew encryption"; Command = $Command },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption"; Verb = "dew encryption"; Command = $FolderCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption-watch"; Verb = "dew encryption start file history"; Command = $WatchCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-watch"; Verb = "dew encryption start file history"; Command = $WatchBackgroundCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption-manager"; Verb = "dew encryption file history manager"; Command = $ManagerCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-manager"; Verb = "dew encryption file history manager"; Command = $ManagerBackgroundCommand }
)

foreach ($item in $keys) {
    New-Item -Path $item.Path -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "MUIVerb" -Value $item.Verb -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "Icon" -Value "imageres.dll,-102" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "AppliesTo" -Value "" -PropertyType String -Force | Out-Null
    $commandKey = Join-Path $item.Path "command"
    New-Item -Path $commandKey -Force | Out-Null
    Set-Item -Path $commandKey -Value $item.Command
}

Write-Host "Installed Explorer right-click menu entry: dew encryption"
