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
$QuickCreateCommand = "powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption container-quick-create '%1' %*; Read-Host 'Press Enter to close' }`""
$QuickCreateFolderCommand = $QuickCreateCommand
$VeraCryptEncryptCommand = "powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption veracrypt-encrypt '%1' %*; Read-Host 'Press Enter to close' }`""
$VeraCryptFolderEncryptCommand = "powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption veracrypt-encrypt '%1' %*; Read-Host 'Press Enter to close' }`""
$VeraCryptDecryptCommand = "powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command `"& { Set-Location -LiteralPath '$EscapedRoot'; & '$EscapedPython' -m dew_encryption veracrypt-decrypt '%1' %*; Read-Host 'Press Enter to close' }`""
$CreateTasksCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$EscapedRoot\installer\create-elevated-tasks.ps1`" -Python `"$EscapedPython`"' }`""
$RemoveTasksCommand = "powershell -NoProfile -ExecutionPolicy Bypass -Command `"& { Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$EscapedRoot\installer\remove-elevated-tasks.ps1`"' }`""

$keys = @(
    @{ Path = "HKCU:\Software\Classes\*\shell\dew-encryption"; Verb = "dew encryption"; Command = $Command },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption"; Verb = "dew encryption"; Command = $Command },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption"; Verb = "dew encryption"; Command = $FolderCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption-watch"; Verb = "dew encryption start file history"; Command = $WatchCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-watch"; Verb = "dew encryption start file history"; Command = $WatchBackgroundCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption-manager"; Verb = "dew encryption file history manager"; Command = $ManagerCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-manager"; Verb = "dew encryption file history manager"; Command = $ManagerBackgroundCommand },
    @{ Path = "HKCU:\Software\Classes\*\shell\dew-encryption-quick-create"; Verb = "dew encryption quick create container"; Command = $QuickCreateCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption-quick-create"; Verb = "dew encryption quick create container"; Command = $QuickCreateFolderCommand },
    @{ Path = "HKCU:\Software\Classes\*\shell\dew-encryption-veracrypt-encrypt"; Verb = "dew encryption VeraCrypt encrypt"; Command = $VeraCryptEncryptCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\shell\dew-encryption-veracrypt-encrypt"; Verb = "dew encryption VeraCrypt encrypt"; Command = $VeraCryptFolderEncryptCommand },
    @{ Path = "HKCU:\Software\Classes\.hc\shell\dew-encryption-veracrypt-decrypt"; Verb = "dew encryption VeraCrypt decrypt"; Command = $VeraCryptDecryptCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-create-elevated-tasks"; Verb = "dew encryption create elevated tasks"; Command = $CreateTasksCommand },
    @{ Path = "HKCU:\Software\Classes\Directory\Background\shell\dew-encryption-remove-elevated-tasks"; Verb = "dew encryption remove elevated tasks"; Command = $RemoveTasksCommand }
)

foreach ($item in $keys) {
    New-Item -Path $item.Path -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "MUIVerb" -Value $item.Verb -PropertyType String -Force | Out-Null
    if ($item.Path -like "*veracrypt*" -or $item.Path -like "*quick-create*") {
        New-ItemProperty -Path $item.Path -Name "MultiSelectModel" -Value "Player" -PropertyType String -Force | Out-Null
    }
    $icon = "imageres.dll,-102"
    if ($item.Path -like "*dew-encryption-watch") {
        $icon = Join-Path $ProjectRoot "assets\icons\dew-watch.ico"
    } elseif ($item.Path -like "*dew-encryption-manager") {
        $icon = Join-Path $ProjectRoot "assets\icons\dew-history.ico"
    } elseif ($item.Path -like "*quick-create*") {
        $icon = Join-Path $ProjectRoot "assets\icons\dew-veracrypt-encrypt.ico"
    } elseif ($item.Path -like "*veracrypt-encrypt") {
        $icon = Join-Path $ProjectRoot "assets\icons\dew-veracrypt-encrypt.ico"
    } elseif ($item.Path -like "*veracrypt-decrypt") {
        $icon = Join-Path $ProjectRoot "assets\icons\dew-veracrypt-decrypt.ico"
    } elseif ($item.Path -like "*dew-encryption") {
        $icon = Join-Path $ProjectRoot "assets\icons\dew-archive.ico"
    }
    New-ItemProperty -Path $item.Path -Name "Icon" -Value $icon -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $item.Path -Name "AppliesTo" -Value "" -PropertyType String -Force | Out-Null
    $commandKey = Join-Path $item.Path "command"
    New-Item -Path $commandKey -Force | Out-Null
    Set-Item -Path $commandKey -Value $item.Command
}

Write-Host "Installed Explorer right-click menu entry: dew encryption"
