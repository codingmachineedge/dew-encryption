param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\DewEncryption",
    [string]$RepoUrl = "https://github.com/codingmachineedge/dew-encryption.git",
    [switch]$SkipWinget,
    [switch]$NoContextMenu,
    [switch]$SourceInstall,
    [switch]$Elevated
)

$ErrorActionPreference = "Stop"
$CanonicalScriptUrl = "https://raw.githubusercontent.com/codingmachineedge/dew-encryption/main/installer/install.ps1"
$Repository = "codingmachineedge/dew-encryption"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-SingleQuotedLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Start-ElevatedInstallerScript {
    $temporaryScript = ""
    $scriptPath = $PSCommandPath
    try {
        if ([string]::IsNullOrWhiteSpace($scriptPath)) {
            $temporaryScript = Join-Path $env:TEMP ("dew-encryption-install-{0}.ps1" -f [guid]::NewGuid())
            Invoke-WebRequest -UseBasicParsing -Uri $CanonicalScriptUrl -OutFile $temporaryScript
            $scriptPath = $temporaryScript
        }

        $parts = @(
            "&", (ConvertTo-SingleQuotedLiteral $scriptPath),
            "-Elevated",
            "-InstallRoot", (ConvertTo-SingleQuotedLiteral $InstallRoot),
            "-RepoUrl", (ConvertTo-SingleQuotedLiteral $RepoUrl)
        )
        if ($SkipWinget) { $parts += "-SkipWinget" }
        if ($NoContextMenu) { $parts += "-NoContextMenu" }
        if ($SourceInstall) { $parts += "-SourceInstall" }
        $parts += "; if (-not `$?) { exit 1 }"
        $command = $parts -join " "
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        $process = Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-EncodedCommand", $encoded
        )
        if ($process.ExitCode -ne 0) {
            throw "Elevated Dew Encryption installation failed with exit code $($process.ExitCode)."
        }
    }
    finally {
        if ($temporaryScript) {
            Remove-Item -LiteralPath $temporaryScript -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not (Test-Administrator)) {
    if ($Elevated) {
        throw "Dew Encryption installation still lacks administrator rights after elevation."
    }
    Start-ElevatedInstallerScript
    return
}

function Install-ReleasePackage {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ Accept = "application/vnd.github+json"; "User-Agent" = "DewEncryption-Installer" }
    $releases = Invoke-RestMethod -UseBasicParsing -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases?per_page=30"
    $releaseAsset = $null
    $checksumAsset = $null
    foreach ($release in @($releases)) {
        if ($release.draft -or $release.prerelease) { continue }
        $candidate = @($release.assets) | Where-Object {
            $_.name -match '^DewEncryptionSetup(?:-[0-9a-f]{12})?\.exe$'
        } | Select-Object -First 1
        if (-not $candidate) { continue }
        $candidateChecksum = @($release.assets) | Where-Object {
            $_.name -eq "$($candidate.name).sha256" -or $_.name -eq "SHA256SUMS.txt"
        } | Select-Object -First 1
        if ($candidateChecksum) {
            $releaseAsset = $candidate
            $checksumAsset = $candidateChecksum
            break
        }
    }

    if (-not $releaseAsset -or -not $checksumAsset) {
        throw "No published Dew Encryption release contains both the Windows installer and its SHA-256 checksum."
    }

    $temporaryDirectory = Join-Path $env:TEMP ("DewEncryption-release-{0}" -f [guid]::NewGuid())
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    try {
        $installerPath = Join-Path $temporaryDirectory $releaseAsset.name
        $checksumPath = Join-Path $temporaryDirectory $checksumAsset.name
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $releaseAsset.browser_download_url -OutFile $installerPath
        Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $checksumAsset.browser_download_url -OutFile $checksumPath

        $matchingLine = Get-Content -LiteralPath $checksumPath | Where-Object {
            $_ -match [regex]::Escape($releaseAsset.name) + '$'
        } | Select-Object -First 1
        if (-not $matchingLine -or $matchingLine -notmatch '^(?<hash>[0-9a-fA-F]{64})\s+') {
            throw "The release checksum file does not contain a valid SHA-256 entry for $($releaseAsset.name)."
        }
        $expectedHash = $Matches.hash.ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Installer SHA-256 verification failed. Expected $expectedHash; received $actualHash."
        }

        Write-Host "Verified $($releaseAsset.name). Starting elevated setup..."
        $setup = Start-Process -FilePath $installerPath -Wait -PassThru
        if ($setup.ExitCode -ne 0) {
            throw "Dew Encryption setup failed with exit code $($setup.ExitCode)."
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-WingetPackage {
    param([string]$Id)
    if ($SkipWinget) { return }
    if (-not (Test-Command winget)) {
        throw "winget is unavailable. Install the source prerequisites manually or use the default release installer."
    }
    & winget install --exact --id $Id --source winget --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget could not install $Id (exit $LASTEXITCODE); source installation will continue where possible."
    }
}

function Install-SourceCheckout {
    foreach ($dependency in @(
        @{ Command = "python"; Id = "Python.Python.3.12" },
        @{ Command = "git"; Id = "Git.Git" },
        @{ Command = "7z"; Id = "7zip.7zip" },
        @{ Command = "VeraCrypt"; Id = "IDRIX.VeraCrypt" }
    )) {
        if (-not (Test-Command $dependency.Command)) {
            Install-WingetPackage $dependency.Id
        }
    }

    $env:Path = "$env:ProgramFiles\Git\cmd;$env:ProgramFiles\7-Zip;$env:ProgramFiles\VeraCrypt;$env:Path"
    if (-not (Test-Command python) -or -not (Test-Command git)) {
        throw "Python and Git are required to complete a source installation."
    }

    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
    if (Test-Path (Join-Path $InstallRoot ".git")) {
        & git -C $InstallRoot pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "Git pull failed with exit code $LASTEXITCODE." }
    }
    else {
        if ((Get-ChildItem -Path $InstallRoot -Force | Measure-Object).Count -gt 0) {
            throw "InstallRoot is not empty and is not a Git repo: $InstallRoot"
        }
        & git clone $RepoUrl $InstallRoot
        if ($LASTEXITCODE -ne 0) { throw "Git clone failed with exit code $LASTEXITCODE." }
    }

    & python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed with exit code $LASTEXITCODE." }
    & python -m pip install -e $InstallRoot
    if ($LASTEXITCODE -ne 0) { throw "Dew Encryption Python install failed with exit code $LASTEXITCODE." }
    if (-not $NoContextMenu) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallRoot "installer\install-context-menu.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Classic context-menu installation failed with exit code $LASTEXITCODE." }
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallRoot "installer\install-win11-context-menu.ps1")
        if ($LASTEXITCODE -ne 0) { throw "Windows 11 context-menu installation failed with exit code $LASTEXITCODE." }
    }
    Write-Host "Dew Encryption source checkout installed at $InstallRoot."
}

if ($SourceInstall) {
    Install-SourceCheckout
}
else {
    Install-ReleasePackage
}
