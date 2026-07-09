param(
    [string]$Configuration = "Release",
    [ValidateSet("x64")]
    [string]$Platform = "x64",
    [string]$OutputDirectory = "",
    [string]$AppExecutableRelativePath = "dew-encryption-gui.exe",
    [string]$PackageVersion = "1.0.0.0",
    [switch]$InstallMissingTools
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$ContextRoot = Join-Path $Root "windows\context-menu"
$OutputDirectory = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory) } else { Join-Path $Root "dist\context-menu" }
$BuildRoot = Join-Path $Root "build\context-menu\$Platform"
$DllName = "DewEncryptionExplorerCommand.dll"

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
        [Environment]::GetEnvironmentVariable("Path", "User")
}

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Override = ""
    )
    if (-not $InstallMissingTools) {
        throw "$Id is required. Rerun with -InstallMissingTools to install it automatically."
    }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget is required to install missing Windows build tools automatically."
    }
    $arguments = @(
        "install", "--exact", "--id", $Id, "--source", "winget", "--silent",
        "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
    if ($Override) {
        $arguments += @("--override", $Override)
    }
    & $winget.Source @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install $Id (exit $LASTEXITCODE)."
    }
    Refresh-Path
}

function Find-Vswhere {
    $candidates = @(
        (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
        (Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe")
    )
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
}

function Get-VisualStudioBuild {
    $vswhere = Find-Vswhere
    if ($vswhere) {
        $path = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
        if ($path) {
            $version = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion | Select-Object -First 1)
            return [pscustomobject]@{ Path = $path; Version = $version }
        }
    }

    Install-WingetPackage -Id "Microsoft.VisualStudio.2022.BuildTools" -Override "--wait --quiet --norestart --nocache --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    $vswhere = Find-Vswhere
    $path = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
    $version = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion | Select-Object -First 1)
    if (-not $path) {
        throw "Visual Studio C++ build tools are unavailable after automatic installation."
    }
    return [pscustomobject]@{ Path = $path; Version = $version }
}

function Find-CMake {
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $vswhere = Find-Vswhere
    if ($vswhere) {
        foreach ($installation in @(& $vswhere -all -products * -property installationPath)) {
            $candidate = Join-Path $installation "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    $candidate = Join-Path $env:ProgramFiles "CMake\bin\cmake.exe"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    Install-WingetPackage -Id "Kitware.CMake"
    $command = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    throw "CMake is unavailable after automatic installation."
}

function Find-MakeAppx {
    $command = Get-Command makeappx.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    $candidate = Get-ChildItem -LiteralPath $kitsRoot -Filter makeappx.exe -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*\x64\makeappx.exe" } |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if ($candidate) { return $candidate }
    throw "MakeAppx is unavailable. Install the Windows 11 SDK or rerun with -InstallMissingTools."
}

if ($PackageVersion -notmatch '^\d{1,5}\.\d{1,5}\.\d{1,5}\.\d{1,5}$') {
    throw "PackageVersion must contain four numeric components no greater than 65535."
}
foreach ($component in $PackageVersion.Split('.')) {
    if ([int]$component -gt 65535) { throw "PackageVersion components cannot exceed 65535." }
}

$visualStudio = Get-VisualStudioBuild
$majorVersion = [int]($visualStudio.Version.Split('.')[0])
$generator = $env:DEW_CONTEXT_MENU_CMAKE_GENERATOR
if (-not $generator) {
    $generator = if ($majorVersion -ge 18) { "Visual Studio 18 2026" } else { "Visual Studio 17 2022" }
}
$cmake = Find-CMake

& $cmake -S $ContextRoot -B $BuildRoot -G $generator -A $Platform
if ($LASTEXITCODE -ne 0) { throw "Could not configure the Windows 11 context menu DLL." }
& $cmake --build $BuildRoot --config $Configuration --target DewEncryptionExplorerCommand
if ($LASTEXITCODE -ne 0) { throw "Could not build the Windows 11 context menu DLL." }

$builtDll = @(
    (Join-Path $BuildRoot "$Configuration\$DllName"),
    (Join-Path $BuildRoot $DllName)
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $builtDll) { throw "$DllName was not produced under $BuildRoot." }

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputDll = Join-Path $OutputDirectory $DllName
Copy-Item -LiteralPath $builtDll -Destination $outputDll -Force

$stage = Join-Path $Root "build\context-menu-package"
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $stage "icons") -Force | Out-Null
$manifest = Get-Content -LiteralPath (Join-Path $ContextRoot "package\AppxManifest.template.xml") -Raw
$manifest = $manifest.Replace("{{APP_EXECUTABLE}}", $AppExecutableRelativePath)
$manifest = $manifest.Replace("{{DLL_PATH}}", "context-menu\$DllName")
$manifest = $manifest.Replace("{{PACKAGE_VERSION}}", $PackageVersion)
[IO.File]::WriteAllText((Join-Path $stage "AppxManifest.xml"), $manifest, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $Root "assets\icons\dew-main.png") -Destination (Join-Path $stage "icons\dew-main.png") -Force

$makeAppx = Find-MakeAppx
$packagePath = Join-Path $OutputDirectory "DewEncryption.ContextMenu.msix"
& $makeAppx pack /o /nv /d $stage /p $packagePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Could not build the Windows 11 context menu identity package."
}

Write-Host "Windows 11 context menu DLL: $outputDll"
Write-Host "Windows 11 context menu identity package: $packagePath"
