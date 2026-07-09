param(
    [string]$GuiExecutable = "dew-encryption-gui",
    [string]$CliExecutable = "dew-encryption",
    [string]$Python = ""
)

$ErrorActionPreference = "Stop"

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 12)

if ($Python) {
    # Retain source-checkout support for install-context-menu.ps1, where the
    # package is intentionally launched as Python modules.
    $guiTaskExecutable = $Python
    $guiTaskArguments = "-m dew_encryption.gui"
    $cliTaskExecutable = $Python
    $cliTaskArgumentPrefix = "-m dew_encryption "
} else {
    # The packaged installer supplies two standalone executables. The Avalonia
    # executable is the default GUI and CLI arguments go directly to the CLI.
    $guiTaskExecutable = $GuiExecutable
    $guiTaskArguments = ""
    $cliTaskExecutable = $CliExecutable
    $cliTaskArgumentPrefix = ""
}

$tasks = @(
    @{
        Name = "DewEncryption.GUI.Elevated"
        Description = "Launch Dew Encryption GUI with normal Windows administrator approval."
        Execute = $guiTaskExecutable
        Argument = $guiTaskArguments
    },
    @{
        Name = "DewEncryption.CLI.Help.Elevated"
        Description = "Launch Dew Encryption CLI help with normal Windows administrator approval."
        Execute = $cliTaskExecutable
        Argument = "${cliTaskArgumentPrefix}--help"
    },
    @{
        Name = "DewEncryption.VeraCrypt.Settings.Elevated"
        Description = "Show Dew Encryption VeraCrypt settings with normal Windows administrator approval."
        Execute = $cliTaskExecutable
        Argument = "${cliTaskArgumentPrefix}veracrypt-settings --show"
    }
)

foreach ($task in $tasks) {
    $actionParameters = @{ Execute = $task.Execute }
    if ($task.Argument) {
        $actionParameters.Argument = $task.Argument
    }
    $action = New-ScheduledTaskAction @actionParameters
    Register-ScheduledTask `
        -TaskName $task.Name `
        -Action $action `
        -Principal $principal `
        -Settings $settings `
        -Description $task.Description `
        -Force | Out-Null
}

Write-Host "Created Dew Encryption elevated scheduled tasks."
Write-Host "These tasks require normal Windows administrator approval to create and are removable with remove-elevated-tasks.ps1."
