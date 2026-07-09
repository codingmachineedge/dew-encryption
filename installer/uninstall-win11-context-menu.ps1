param(
    [switch]$NoExplorerRestart
)

$ErrorActionPreference = "Stop"

Get-AppxPackage -Name "CodingMachineEdge.DewEncryption.ContextMenu" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Get-AppxPackage -AllUsers -Name "CodingMachineEdge.DewEncryption.ContextMenu" -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
        Where-Object DisplayName -eq "CodingMachineEdge.DewEncryption.ContextMenu"
    $provisioned | ForEach-Object {
        Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null
    }
    Remove-Item -Path "HKLM:\Software\DewEncryption\ContextMenu" -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-Item -Path "HKCU:\Software\DewEncryption\ContextMenu" -Recurse -Force -ErrorAction SilentlyContinue

if (-not $NoExplorerRestart) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

Write-Host "Removed Windows 11 Explorer context menu package: Dew Encryption"
