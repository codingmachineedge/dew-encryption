[CmdletBinding()]
param(
    [string]$LogPath = "$env:TEMP\DewEncryption-dependencies.log",
    [string]$WingetPath = "",
    [string]$RestartMarkerPath = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$script:RestartRequired = $false

function Write-DependencyLog {
    param([string]$Message)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] $Message"
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Test-Dependency {
    param(
        [string]$Command,
        [string[]]$Paths
    )

    if (Get-Command $Command -ErrorAction SilentlyContinue) {
        return $true
    }

    return [bool]($Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)
}

function Wait-Dependency {
    param(
        [string]$Command,
        [string[]]$Paths,
        [int]$Attempts = 10,
        [int]$DelayMilliseconds = 500
    )

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        if (Test-Dependency -Command $Command -Paths $Paths) {
            return $true
        }
        if ($attempt -lt $Attempts) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }
    return $false
}

function Set-InstallerExitState {
    param(
        [string]$Name,
        [int]$ExitCode
    )

    if ($ExitCode -notin @(0, 1641, 3010)) {
        throw "$Name installer failed with exit code $ExitCode."
    }

    if ($ExitCode -in @(1641, 3010)) {
        $script:RestartRequired = $true
        Write-DependencyLog "$Name requested a Windows restart. Setup will finish configuring Dew Encryption first."
    }
}

function Install-VerifiedPackage {
    param([pscustomobject]$Dependency)

    $downloadDirectory = Join-Path $env:TEMP "DewEncryption-dependencies"
    New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
    $installerPath = Join-Path $downloadDirectory $Dependency.FileName

    Write-DependencyLog "Downloading $($Dependency.Name) from its pinned vendor release."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $Dependency.Url -OutFile $installerPath

    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $Dependency.Sha256) {
        Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
        throw "$($Dependency.Name) download failed SHA-256 verification. Expected $($Dependency.Sha256); received $actualHash."
    }

    Write-DependencyLog "Installing verified $($Dependency.Name) package."
    if ($Dependency.InstallerType -eq "exe") {
        $process = Start-Process -FilePath $installerPath -ArgumentList $Dependency.Arguments -Wait -PassThru
    }
    else {
        $arguments = "/i `"$installerPath`" $($Dependency.Arguments)"
        $process = Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
    }

    Set-InstallerExitState -Name $Dependency.Name -ExitCode $process.ExitCode
    Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
}

$logDirectory = Split-Path -Parent $LogPath
if ($logDirectory) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}
Set-Content -LiteralPath $LogPath -Value "" -Encoding UTF8

$programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
$localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)

$dependencies = @(
    [pscustomobject]@{
        Name = "Git"
        Id = "Git.Git"
        Command = "git.exe"
        Paths = @(
            (Join-Path $programFiles "Git\cmd\git.exe"),
            (Join-Path $programFilesX86 "Git\cmd\git.exe"),
            (Join-Path $localAppData "Programs\Git\cmd\git.exe")
        )
        Url = "https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.2/Git-2.55.0.2-64-bit.exe"
        Sha256 = "74300da8dfe0d844c5449ffb809662f8eeac47916f83730c879c4084890c6c0e"
        FileName = "Git-2.55.0.2-64-bit.exe"
        InstallerType = "exe"
        Arguments = "/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES /o:PathOption=Cmd"
    },
    [pscustomobject]@{
        Name = "7-Zip"
        Id = "7zip.7zip"
        Command = "7z.exe"
        Paths = @(
            (Join-Path $programFiles "7-Zip\7z.exe"),
            (Join-Path $programFilesX86 "7-Zip\7z.exe")
        )
        Url = "https://github.com/ip7z/7zip/releases/download/26.02/7z2602-x64.msi"
        Sha256 = "db407a4f6d4999e5c7bc00ce8a882be94717b56e7fa68140fe3f12605d91643e"
        FileName = "7z2602-x64.msi"
        InstallerType = "msi"
        Arguments = "/qn /norestart"
    },
    [pscustomobject]@{
        Name = "VeraCrypt"
        Id = "IDRIX.VeraCrypt"
        Command = "VeraCrypt.exe"
        Paths = @(
            (Join-Path $programFiles "VeraCrypt\VeraCrypt.exe"),
            (Join-Path $programFilesX86 "VeraCrypt\VeraCrypt.exe")
        )
        Url = "https://launchpad.net/veracrypt/trunk/1.26.29/+download/VeraCrypt_Setup_x64_1.26.29.msi"
        Sha256 = "5ba6426983123cfb92bc1f09bd888fdbc0f53f300d0d9c5da52ce3aee8d474f0"
        FileName = "VeraCrypt_Setup_x64_1.26.29.msi"
        InstallerType = "msi"
        Arguments = "/qn /norestart ACCEPTLICENSE=YES REBOOT=ReallySuppress MSIRESTARTMANAGERCONTROL=Disable"
    }
)

try {
    if ($RestartMarkerPath) {
        Remove-Item -LiteralPath $RestartMarkerPath -Force -ErrorAction SilentlyContinue
    }

    $missing = @($dependencies | Where-Object { -not (Test-Dependency -Command $_.Command -Paths $_.Paths) })
    if ($missing.Count -eq 0) {
        Write-DependencyLog "All required dependencies are already installed."
        exit 0
    }

    $wingetCandidates = @($WingetPath)
    $wingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($wingetCommand) {
        $wingetCandidates += $wingetCommand.Source
    }
    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1
    if ($appInstaller) {
        $wingetCandidates += Join-Path $appInstaller.InstallLocation "winget.exe"
    }
    $winget = $wingetCandidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } |
        Select-Object -First 1
    $installationErrors = [System.Collections.Generic.List[string]]::new()
    foreach ($dependency in $missing) {
        try {
            $installed = $false
            if ($winget) {
                Write-DependencyLog "Installing $($dependency.Name) with winget package $($dependency.Id)."
                & $winget install `
                    --exact `
                    --id $dependency.Id `
                    --source winget `
                    --silent `
                    --accept-source-agreements `
                    --accept-package-agreements `
                    --disable-interactivity

                $wingetExitCode = $LASTEXITCODE
                if ($wingetExitCode -in @(0, 1641, 3010)) {
                    if ($wingetExitCode -in @(1641, 3010)) {
                        $script:RestartRequired = $true
                    }
                    $installed = Wait-Dependency -Command $dependency.Command -Paths $dependency.Paths
                }

                if (-not $installed) {
                    Write-DependencyLog "winget did not complete $($dependency.Name) installation (exit $wingetExitCode); using the verified direct fallback."
                }
            }
            else {
                Write-DependencyLog "winget is unavailable; using the verified direct fallback for $($dependency.Name)."
            }

            if (-not $installed) {
                Install-VerifiedPackage -Dependency $dependency
                $installed = Wait-Dependency -Command $dependency.Command -Paths $dependency.Paths
            }

            if (-not $installed) {
                throw "$($dependency.Name) is still missing after its installer completed."
            }

            Write-DependencyLog "$($dependency.Name) is installed."
        }
        catch {
            $message = "$($dependency.Name): $($_.Exception.Message)"
            $installationErrors.Add($message)
            Write-DependencyLog "ERROR: $message Continuing with the remaining dependencies."
        }
    }

    if ($script:RestartRequired -and $RestartMarkerPath) {
        Set-Content -LiteralPath $RestartMarkerPath -Value "restart-required" -Encoding ASCII
    }

    $stillMissing = @($dependencies | Where-Object { -not (Test-Dependency -Command $_.Command -Paths $_.Paths) })
    if ($stillMissing.Count -gt 0) {
        $missingNames = ($stillMissing | ForEach-Object Name) -join ", "
        Write-DependencyLog "WARNING: Setup will continue, but these dependencies are still missing: $missingNames."
        if ($installationErrors.Count -gt 0) {
            Write-DependencyLog "Dependency errors: $($installationErrors -join ' | ')"
        }
        exit 1
    }

    Write-DependencyLog "All required dependencies are installed."
    exit 0
}
catch {
    Write-DependencyLog "ERROR: $($_.Exception.Message)"
    exit 1
}
