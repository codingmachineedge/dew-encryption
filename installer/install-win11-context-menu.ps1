param(
    [string]$Python = "python",
    [string]$Configuration = "Release",
    [ValidateSet("x64")]
    [string]$Platform = "x64",
    [string]$InstallRoot = "",
    [string]$PackagePath = "",
    [switch]$SkipBuild,
    [switch]$NoExplorerRestart,
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = if ($InstallRoot) { [IO.Path]::GetFullPath($InstallRoot) } else { Split-Path -Parent $ScriptRoot }
$LogPath = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) "DewEncryption\Logs\context-menu-install.log"
New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null

function Write-InstallLog {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

trap {
    Write-InstallLog "ERROR: $($_.Exception.Message)"
    throw
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Quote-Literal {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Restart-Elevated {
    $parts = @(
        "&", (Quote-Literal $PSCommandPath),
        "-Elevated",
        "-Python", (Quote-Literal $Python),
        "-Configuration", (Quote-Literal $Configuration),
        "-Platform", (Quote-Literal $Platform),
        "-InstallRoot", (Quote-Literal $ProjectRoot)
    )
    if ($PackagePath) { $parts += @("-PackagePath", (Quote-Literal $PackagePath)) }
    if ($SkipBuild) { $parts += "-SkipBuild" }
    if ($NoExplorerRestart) { $parts += "-NoExplorerRestart" }
    $command = $parts -join " "
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $process = Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-EncodedCommand", $encoded
    )
    if ($process.ExitCode -ne 0) {
        throw "Elevated Windows 11 context menu setup failed with exit code $($process.ExitCode)."
    }
}

if ([Environment]::OSVersion.Version.Build -lt 22000) {
    Write-InstallLog "Windows 11 context menu registration skipped on OS build $([Environment]::OSVersion.Version.Build)."
    return
}

if (-not (Test-Administrator)) {
    if ($Elevated) { throw "Context menu setup still lacks administrator rights after elevation." }
    Restart-Elevated
    return
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [Environment]::GetEnvironmentVariable("Path", "User")
}

function Ensure-DotNet {
    if (Get-Command dotnet.exe -ErrorAction SilentlyContinue) { return }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { throw ".NET 8 SDK and winget are unavailable." }
    & $winget.Source install --exact --id Microsoft.DotNet.SDK.8 --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "winget could not install the .NET 8 SDK (exit $LASTEXITCODE)." }
    Refresh-Path
}

function ConvertTo-RelativePath {
    param([string]$Root, [string]$Path)
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/") + "\"
    $rootUri = [Uri]$rootFull
    $pathUri = [Uri][IO.Path]::GetFullPath($Path)
    return [Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace("/", "\")
}

$contextOutput = Join-Path $ProjectRoot "context-menu"
$dllPath = Join-Path $contextOutput "DewEncryptionExplorerCommand.dll"
if (-not $PackagePath) {
    $PackagePath = Join-Path $contextOutput "DewEncryption.ContextMenu.msix"
}

$packagedGui = Join-Path $ProjectRoot "dew-encryption-gui.exe"
$packagedCli = Join-Path $ProjectRoot "dew-encryption.exe"
$packagedPythonGui = Join-Path $ProjectRoot "dew-encryption-python-gui.exe"
$appExecutable = $packagedGui

if (-not $SkipBuild -and (-not (Test-Path -LiteralPath $dllPath -PathType Leaf) -or -not (Test-Path -LiteralPath $PackagePath -PathType Leaf))) {
    Ensure-DotNet
    $guiProject = Join-Path $ProjectRoot "csharp\DewEncryption.Gui\DewEncryption.Gui.csproj"
    if (-not (Test-Path -LiteralPath $guiProject -PathType Leaf)) {
        throw "Missing C# GUI project: $guiProject"
    }
    & dotnet build $guiProject --configuration $Configuration
    if ($LASTEXITCODE -ne 0) { throw "The C# GUI build failed with exit code $LASTEXITCODE." }
    $appExecutable = Join-Path $ProjectRoot "csharp\DewEncryption.Gui\bin\$Configuration\net8.0\DewEncryption.Gui.exe"
    if (-not (Test-Path -LiteralPath $appExecutable -PathType Leaf)) {
        throw "Missing C# GUI package entry point: $appExecutable"
    }

    $buildScript = Join-Path $ProjectRoot "scripts\build-win11-context-menu.ps1"
    if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) { throw "Missing context menu build script: $buildScript" }
    $packageVersion = "1.0.$([int](Get-Date -Format 'MMdd')).$([int](Get-Date -Format 'HHmm'))"
    & $buildScript -Configuration $Configuration -Platform $Platform -OutputDirectory $contextOutput `
        -AppExecutableRelativePath (ConvertTo-RelativePath -Root $ProjectRoot -Path $appExecutable) `
        -PackageVersion $packageVersion -InstallMissingTools
    if ($LASTEXITCODE -ne 0) { throw "Context menu build failed with exit code $LASTEXITCODE." }
}

if (-not (Test-Path -LiteralPath $dllPath -PathType Leaf)) { throw "Missing context menu DLL: $dllPath" }
if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw "Missing context menu identity package: $PackagePath" }
if (-not (Test-Path -LiteralPath $appExecutable -PathType Leaf)) {
    $appExecutable = Join-Path $ProjectRoot "csharp\DewEncryption.Gui\bin\$Configuration\net8.0\DewEncryption.Gui.exe"
}

$resolvedPython = (Get-Command $Python -ErrorAction SilentlyContinue).Source
if (-not $resolvedPython) { $resolvedPython = $Python }
$iconPath = if (Test-Path (Join-Path $ProjectRoot "icons\dew-main.ico")) {
    Join-Path $ProjectRoot "icons\dew-main.ico"
} else {
    Join-Path $ProjectRoot "assets\icons\dew-main.ico"
}

foreach ($registryRoot in @("HKCU:\Software\DewEncryption\ContextMenu", "HKLM:\Software\DewEncryption\ContextMenu")) {
    New-Item -Path $registryRoot -Force | Out-Null
    New-ItemProperty -Path $registryRoot -Name InstallRoot -Value $ProjectRoot -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryRoot -Name PythonPath -Value $resolvedPython -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryRoot -Name IconPath -Value $iconPath -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryRoot -Name CliPath -Value $(if (Test-Path $packagedCli) { $packagedCli } else { "" }) -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $registryRoot -Name PythonGuiPath -Value $(if (Test-Path $packagedPythonGui) { $packagedPythonGui } else { "" }) -PropertyType String -Force | Out-Null
}

Get-AppxPackage -Name "CodingMachineEdge.DewEncryption.ContextMenu" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
Get-AppxPackage -AllUsers -Name "CodingMachineEdge.DewEncryption.ContextMenu" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }

Write-InstallLog "Registering unsigned Windows 11 sparse identity package at $PackagePath with external root $ProjectRoot."
Add-AppxPackage -Path $PackagePath -ExternalLocation $ProjectRoot -AllowUnsigned -ForceApplicationShutdown
if (-not (Get-AppxPackage -Name "CodingMachineEdge.DewEncryption.ContextMenu" -ErrorAction SilentlyContinue)) {
    throw "Windows did not report the Dew Encryption context menu package after registration."
}

if (-not $NoExplorerRestart) {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

Write-InstallLog "Installed Windows 11 Explorer context menu package: Dew Encryption"
