using System.Diagnostics;
using System.Reflection;

namespace DewEncryption.Core;

public sealed class DewAutoSyncProcessService
{
    public void EnsureRunning()
    {
        ProcessStartInfo startInfo = BuildStartInfo();
        Process.Start(startInfo)?.Dispose();
    }

    private static ProcessStartInfo BuildStartInfo()
    {
        string executable = Environment.ProcessPath
            ?? throw new InvalidOperationException("Unable to resolve the Dew Encryption executable path.");
        ProcessStartInfo startInfo = new()
        {
            FileName = executable,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = AppContext.BaseDirectory,
        };

        if (string.Equals(Path.GetFileNameWithoutExtension(executable), "dotnet", StringComparison.OrdinalIgnoreCase))
        {
            string assemblyPath = Assembly.GetEntryAssembly()?.Location
                ?? throw new InvalidOperationException("Unable to resolve the Dew Encryption GUI assembly path.");
            startInfo.ArgumentList.Add(assemblyPath);
        }

        startInfo.ArgumentList.Add("--auto-sync-worker");
        return startInfo;
    }
}
