using System.Diagnostics;

namespace DewEncryption.Core;

public sealed class DewCliService
{
    public string CliFileName { get; }
    public string HistoryGuiFileName { get; }

    public DewCliService(string cliFileName = "dew-encryption", string historyGuiFileName = "dew-encryption-gui")
    {
        CliFileName = cliFileName;
        HistoryGuiFileName = historyGuiFileName;
    }

    public Task<DewCommandResult> RunHelpAsync(CancellationToken cancellationToken = default)
    {
        return RunCliAsync(["--help"], cancellationToken);
    }

    public Task<DewCommandResult> RunSelectedAsync(IEnumerable<string> paths, CancellationToken cancellationToken = default)
    {
        return RunCliAsync(paths, cancellationToken);
    }

    public Task<DewCommandResult> SnapshotHistoryAsync(string path, CancellationToken cancellationToken = default)
    {
        return RunCliAsync([path], cancellationToken);
    }

    public Task<DewCommandResult> RefreshHistoryAsync(string path, CancellationToken cancellationToken = default)
    {
        return RunCliAsync(["history", path], cancellationToken);
    }

    public Task<DewCommandResult> OpenHistoryGuiAsync(string path, CancellationToken cancellationToken = default)
    {
        return RunProcessAsync(HistoryGuiFileName, [path, "--history"], cancellationToken);
    }

    public Task<DewCommandResult> SnapshotContainerHistoryAsync(string containerPath, CancellationToken cancellationToken = default)
    {
        return RunCliAsync(["container-history", containerPath, "--snapshot"], cancellationToken);
    }

    public Task<DewCommandResult> TestContainerHooksAsync(string eventName, string containerPath, string? mountPath = null, CancellationToken cancellationToken = default)
    {
        List<string> args = ["container-hooks", eventName, containerPath];
        if (!string.IsNullOrWhiteSpace(mountPath))
        {
            args.Add("--mount-path");
            args.Add(mountPath);
        }

        return RunCliAsync(args, cancellationToken);
    }

    public Task<DewCommandResult> RunCliAsync(IEnumerable<string> arguments, CancellationToken cancellationToken = default)
    {
        return RunProcessAsync(CliFileName, arguments, cancellationToken);
    }

    public static async Task<DewCommandResult> RunProcessAsync(string fileName, IEnumerable<string> arguments, CancellationToken cancellationToken = default)
    {
        string[] argumentArray = arguments.ToArray();
        ProcessStartInfo startInfo = new()
        {
            FileName = fileName,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        foreach (string argument in argumentArray)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using Process process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Unable to start {fileName}.");
        Task<string> outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        Task<string> errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);

        return new DewCommandResult(fileName, argumentArray, process.ExitCode, await outputTask.ConfigureAwait(false), await errorTask.ConfigureAwait(false));
    }
}
