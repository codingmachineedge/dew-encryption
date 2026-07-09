namespace DewEncryption.Core;

public sealed class DewAutoSyncWorker : IDisposable
{
    private const string SemaphoreName = @"Local\DewEncryption.AutoSyncWorker";
    private static readonly TimeSpan ReconcileInterval = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan SyncDebounce = TimeSpan.FromSeconds(3);

    private readonly SettingsService settingsService;
    private readonly DewSecretService secretService;
    private readonly DewCliService cliService;
    private readonly Dictionary<string, ProfileWatcher> watchers = new(StringComparer.OrdinalIgnoreCase);
    private readonly string logPath;
    private readonly object logGate = new();

    public DewAutoSyncWorker(
        SettingsService? settingsService = null,
        DewSecretService? secretService = null,
        DewCliService? cliService = null)
    {
        this.settingsService = settingsService ?? new SettingsService();
        this.secretService = secretService ?? new DewSecretService();
        this.cliService = cliService ?? new DewCliService();
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        logPath = Path.Combine(localAppData, "DewEncryption", "Logs", "auto-sync.log");
    }

    public static async Task<int> RunSingletonAsync(CancellationToken cancellationToken = default)
    {
        using Semaphore semaphore = new(1, 1, SemaphoreName);
        if (!semaphore.WaitOne(0))
        {
            return 0;
        }

        try
        {
            using DewAutoSyncWorker worker = new();
            await worker.RunAsync(cancellationToken).ConfigureAwait(false);
            return 0;
        }
        finally
        {
            semaphore.Release();
        }
    }

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        WriteLog("Background auto-sync worker started.");
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    ReconcileProfiles(cancellationToken);
                }
                catch (Exception ex)
                {
                    WriteLog($"Profile reconciliation failed: {ex.Message}");
                }

                await Task.Delay(ReconcileInterval, cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        finally
        {
            WriteLog("Background auto-sync worker stopped.");
        }
    }

    private void ReconcileProfiles(CancellationToken cancellationToken)
    {
        AppSettings settings = settingsService.Load();
        Dictionary<string, DewDriveProfile> desired = (settings.DewDrives?.Drives ?? [])
            .Where(IsUsableAutoPushProfile)
            .GroupBy(profile => profile.Name, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.Last())
            .ToDictionary(profile => profile.Name, StringComparer.OrdinalIgnoreCase);

        foreach (string removedName in watchers.Keys.Except(desired.Keys, StringComparer.OrdinalIgnoreCase).ToList())
        {
            watchers[removedName].Dispose();
            watchers.Remove(removedName);
            WriteLog($"Stopped watching profile '{removedName}'.");
        }

        foreach ((string name, DewDriveProfile profile) in desired)
        {
            if (watchers.TryGetValue(name, out ProfileWatcher? current) && current.Matches(profile))
            {
                continue;
            }

            current?.Dispose();
            string folder = ProfileFolder(profile);
            Directory.CreateDirectory(folder);
            watchers[name] = new ProfileWatcher(profile, SyncDebounce, cancellationToken, SyncProfileAsync, WriteLog);
            WriteLog($"Watching profile '{name}' at '{folder}'.");
        }
    }

    private bool IsUsableAutoPushProfile(DewDriveProfile profile)
    {
        if (!profile.AutoPush || string.IsNullOrWhiteSpace(profile.Name) ||
            string.IsNullOrWhiteSpace(ProfileFolder(profile)) || string.IsNullOrWhiteSpace(ProfileRegistry(profile)))
        {
            return false;
        }

        string password = secretService.UnprotectForCurrentUser(profile.ProtectedPassword);
        if (string.IsNullOrEmpty(password))
        {
            WriteLog($"Profile '{profile.Name}' is not watched because it has no saved password for this Windows user.");
            return false;
        }
        return true;
    }

    private async Task SyncProfileAsync(DewDriveProfile profile, CancellationToken cancellationToken)
    {
        string password = secretService.UnprotectForCurrentUser(profile.ProtectedPassword);
        if (string.IsNullOrEmpty(password))
        {
            WriteLog($"Skipped '{profile.Name}': its saved password is unavailable.");
            return;
        }

        WriteLog($"Syncing profile '{profile.Name}' to '{ProfileRegistry(profile)}'.");
        try
        {
            DewCommandResult result = await cliService.SyncDewDriveProfileAsync(
                profile.Name,
                ProfileRegistry(profile),
                push: true,
                password,
                cancellationToken).ConfigureAwait(false);
            if (result.Succeeded)
            {
                WriteLog($"Profile '{profile.Name}' synced successfully.");
            }
            else
            {
                string error = string.IsNullOrWhiteSpace(result.StandardError) ? result.StandardOutput : result.StandardError;
                WriteLog($"Profile '{profile.Name}' sync failed with exit code {result.ExitCode}: {error.Trim()}");
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            WriteLog($"Profile '{profile.Name}' sync failed: {ex.Message}");
        }
    }

    private void WriteLog(string message)
    {
        string line = $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}] {message}";
        lock (logGate)
        {
            string? directory = Path.GetDirectoryName(logPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }
            File.AppendAllText(logPath, line + Environment.NewLine);
        }
    }

    public void Dispose()
    {
        foreach (ProfileWatcher watcher in watchers.Values)
        {
            watcher.Dispose();
        }
        watchers.Clear();
    }

    private static string ProfileFolder(DewDriveProfile profile) =>
        string.IsNullOrWhiteSpace(profile.LocalPath) ? profile.Folder : profile.LocalPath;

    private static string ProfileRegistry(DewDriveProfile profile) =>
        string.IsNullOrWhiteSpace(profile.RegistryRef) ? profile.RegistryImage : profile.RegistryRef;

    private sealed class ProfileWatcher : IDisposable
    {
        private readonly DewDriveProfile profile;
        private readonly TimeSpan debounceDelay;
        private readonly CancellationToken workerToken;
        private readonly Func<DewDriveProfile, CancellationToken, Task> sync;
        private readonly Action<string> log;
        private readonly FileSystemWatcher watcher;
        private readonly object gate = new();
        private CancellationTokenSource? debounceCancellation;
        private bool syncRunning;
        private bool dirty;
        private bool disposed;

        public ProfileWatcher(
            DewDriveProfile profile,
            TimeSpan debounceDelay,
            CancellationToken workerToken,
            Func<DewDriveProfile, CancellationToken, Task> sync,
            Action<string> log)
        {
            this.profile = profile;
            this.debounceDelay = debounceDelay;
            this.workerToken = workerToken;
            this.sync = sync;
            this.log = log;
            watcher = new FileSystemWatcher(ProfileFolder(profile))
            {
                IncludeSubdirectories = true,
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size,
                EnableRaisingEvents = true,
            };
            watcher.Changed += OnChanged;
            watcher.Created += OnChanged;
            watcher.Deleted += OnChanged;
            watcher.Renamed += OnChanged;
            watcher.Error += OnError;
        }

        public bool Matches(DewDriveProfile candidate) =>
            string.Equals(profile.Name, candidate.Name, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(ProfileFolder(profile), ProfileFolder(candidate), StringComparison.OrdinalIgnoreCase) &&
            string.Equals(ProfileRegistry(profile), ProfileRegistry(candidate), StringComparison.OrdinalIgnoreCase) &&
            string.Equals(profile.EncryptionMode, candidate.EncryptionMode, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(profile.ProtectedPassword, candidate.ProtectedPassword, StringComparison.Ordinal);

        private void OnChanged(object sender, FileSystemEventArgs e)
        {
            if (ShouldIgnorePath(e.FullPath))
            {
                return;
            }

            CancellationToken token;
            lock (gate)
            {
                if (disposed)
                {
                    return;
                }
                dirty = true;
                if (syncRunning)
                {
                    return;
                }
                debounceCancellation?.Cancel();
                debounceCancellation?.Dispose();
                debounceCancellation = CancellationTokenSource.CreateLinkedTokenSource(workerToken);
                token = debounceCancellation.Token;
            }
            _ = DebounceAndSyncAsync(token);
        }

        private void OnError(object sender, ErrorEventArgs e)
        {
            log($"Watcher error for profile '{profile.Name}': {e.GetException().Message}");
        }

        private async Task DebounceAndSyncAsync(CancellationToken cancellationToken)
        {
            try
            {
                await Task.Delay(debounceDelay, cancellationToken).ConfigureAwait(false);
                lock (gate)
                {
                    if (disposed || syncRunning)
                    {
                        return;
                    }
                    syncRunning = true;
                    dirty = false;
                }

                while (!cancellationToken.IsCancellationRequested)
                {
                    await sync(profile, workerToken).ConfigureAwait(false);
                    lock (gate)
                    {
                        if (!dirty || disposed)
                        {
                            syncRunning = false;
                            return;
                        }
                        dirty = false;
                    }
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
            }
            finally
            {
                lock (gate)
                {
                    if (cancellationToken == debounceCancellation?.Token && !dirty)
                    {
                        syncRunning = false;
                    }
                }
            }
        }

        public void Dispose()
        {
            lock (gate)
            {
                if (disposed)
                {
                    return;
                }
                disposed = true;
                debounceCancellation?.Cancel();
                debounceCancellation?.Dispose();
                debounceCancellation = null;
            }
            watcher.EnableRaisingEvents = false;
            watcher.Dispose();
        }

        private static bool ShouldIgnorePath(string path) =>
            path.Contains(DewPathService.ArchiveDirName, StringComparison.OrdinalIgnoreCase) ||
            path.Contains($"{Path.DirectorySeparatorChar}.git{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase);
    }
}
