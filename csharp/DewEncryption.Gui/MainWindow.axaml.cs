using System.Collections.ObjectModel;
using Avalonia.Threading;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using DewEncryption.Core;

namespace DewEncryption.Gui;

public sealed partial class MainWindow : Window
{
    private readonly DewCliService cliService = new();
    private readonly DewDriveService driveService = new();
    private readonly DewSelectionService selectionService = new();
    private readonly SettingsService settingsService = new();
    private readonly ObservableCollection<DewPathItem> selectedPaths = [];
    private readonly ObservableCollection<string> containers = [];
    private readonly ObservableCollection<string> driveProfiles = [];
    private AppSettings settings;
    private FileSystemWatcher? driveWatcher;
    private CancellationTokenSource? driveSyncDebounce;
    private bool driveSyncInProgress;

    public MainWindow()
    {
        InitializeComponent();
        settings = settingsService.Load();
        FilesGrid.ItemsSource = selectedPaths;
        ContainersList.ItemsSource = containers;
        DriveProfilesList.ItemsSource = driveProfiles;
        RefreshContainerList();
        RefreshDriveList();
        LoadVeraCryptSettings();
        UpdateSelectionContext();
        Log("Ready.");
    }

    private async void AddFiles_Click(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Add files to Dew Encryption",
            AllowMultiple = true,
        });

        foreach (IStorageFile file in files)
        {
            AddPath(file.Path.LocalPath, "File");
        }
    }

    private async void AddFolder_Click(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFolder> folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Add a folder to Dew Encryption",
            AllowMultiple = false,
        });

        foreach (IStorageFolder folder in folders)
        {
            AddPath(folder.Path.LocalPath, "Folder");
        }
    }

    private void RemoveSelected_Click(object? sender, RoutedEventArgs e)
    {
        List<DewPathItem> items = FilesGrid.SelectedItems.Cast<DewPathItem>().ToList();
        selectionService.RemovePaths(items);
        foreach (DewPathItem item in items)
        {
            selectedPaths.Remove(item);
        }

        UpdateSelectionContext();
        Log($"Removed {items.Count} selected item(s).");
    }

    private async void RunSelected_Click(object? sender, RoutedEventArgs e)
    {
        if (selectedPaths.Count == 0)
        {
            SetStatus("Nothing selected.");
            Log("Add at least one file or folder before running Dew Encryption.");
            return;
        }

        await RunAndLogAsync(cliService.RunSelectedAsync(selectedPaths.Select(item => item.Path)));
    }

    private async void OpenHelp_Click(object? sender, RoutedEventArgs e)
    {
        await RunAndLogAsync(cliService.RunHelpAsync());
    }

    private async void RefreshHistory_Click(object? sender, RoutedEventArgs e)
    {
        DewPathItem? first = selectedPaths.FirstOrDefault();
        if (first is null)
        {
            SetStatus("Nothing selected.");
            Log("Select a file or folder before refreshing history.");
            return;
        }

        await RunAndLogAsync(cliService.RefreshHistoryAsync(first.Path));
    }

    private async void SnapshotHistory_Click(object? sender, RoutedEventArgs e)
    {
        DewPathItem? first = selectedPaths.FirstOrDefault();
        if (first is null)
        {
            SetStatus("Nothing selected.");
            Log("Select a file or folder before snapshotting history.");
            return;
        }

        await RunAndLogAsync(cliService.SnapshotHistoryAsync(first.Path));
    }

    private async void OpenPythonHistoryGui_Click(object? sender, RoutedEventArgs e)
    {
        DewPathItem? first = selectedPaths.FirstOrDefault();
        if (first is null)
        {
            SetStatus("Nothing selected.");
            Log("Select a file or folder before opening the history manager.");
            return;
        }

        await RunAndLogAsync(cliService.OpenHistoryGuiAsync(first.Path));
    }

    private void RegisterContainer_Click(object? sender, RoutedEventArgs e)
    {
        DewContainerProfile profile = ReadContainerProfile();
        if (string.IsNullOrWhiteSpace(profile.Path))
        {
            SetStatus("Container path required.");
            Log("Enter a container path before saving a container profile.");
            return;
        }

        List<ContainerProfile> profiles = (settings.Containers ?? []).ToList();
        int existingIndex = profiles.FindIndex(item =>
            string.Equals(item.Path, profile.Path, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(item.Name, profile.Name, StringComparison.OrdinalIgnoreCase));

        IReadOnlyList<HookAction>? existingHooks = existingIndex >= 0 ? profiles[existingIndex].Hooks : [];
        ContainerProfile savedProfile = new(profile.Name, profile.Path, profile.MountPath, profile.Theme, existingHooks);
        if (existingIndex >= 0)
        {
            profiles[existingIndex] = savedProfile;
        }
        else
        {
            profiles.Add(savedProfile);
        }

        settings = settings with { Containers = profiles };
        settingsService.Save(settings);
        RefreshContainerList();
        ContainerStatusText.Text = $"Saved: {profile.DisplayLabel}";
        SetStatus("Container saved.");
        Log($"Saved container profile: {profile.DisplayLabel}");
    }

    private async void SnapshotContainer_Click(object? sender, RoutedEventArgs e)
    {
        DewContainerProfile profile = ReadContainerProfile();
        if (string.IsNullOrWhiteSpace(profile.Path))
        {
            SetStatus("Container path required.");
            Log("Enter a container path before snapshotting container history.");
            return;
        }

        await RunAndLogAsync(cliService.SnapshotContainerHistoryAsync(profile.Path));
    }

    private async void ViewContainerHistory_Click(object? sender, RoutedEventArgs e)
    {
        DewContainerProfile profile = ReadContainerProfile();
        if (string.IsNullOrWhiteSpace(profile.Path))
        {
            SetStatus("Container path required.");
            Log("Enter a container path before viewing container history.");
            return;
        }

        await RunAndLogAsync(cliService.ViewContainerHistoryAsync(profile.Path));
    }

    private async void TestOpenHooks_Click(object? sender, RoutedEventArgs e)
    {
        await TestHooksAsync("open");
    }

    private async void TestCloseHooks_Click(object? sender, RoutedEventArgs e)
    {
        await TestHooksAsync("close");
    }

    private async Task TestHooksAsync(string eventName)
    {
        DewContainerProfile profile = ReadContainerProfile();
        if (string.IsNullOrWhiteSpace(profile.Path))
        {
            SetStatus("Container path required.");
            Log($"Enter a container path before testing {eventName} hooks.");
            return;
        }

        await RunAndLogAsync(cliService.TestContainerHooksAsync(eventName, profile.Path, profile.MountPath));
    }

    private void ContainersList_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        int index = ContainersList.SelectedIndex;
        ContainerProfile? profile = index >= 0 ? (settings.Containers ?? []).ElementAtOrDefault(index) : null;
        if (profile is null)
        {
            return;
        }

        DewThemeSettings theme = profile.Theme ?? new DewThemeSettings();
        ContainerNameBox.Text = profile.Name;
        ContainerPathBox.Text = profile.Path;
        MountPathBox.Text = profile.MountPath;
        FontFamilyBox.Text = theme.FontFamily;
        BackgroundBox.Text = theme.Background;
        ForegroundBox.Text = theme.Foreground;
        AccentBox.Text = theme.Accent;
        FontSizeBox.Text = theme.FontSize.ToString();
        ContainerStatusText.Text = profile.Path;
    }

    private DewContainerProfile ReadContainerProfile()
    {
        string name = string.IsNullOrWhiteSpace(ContainerNameBox.Text) ? "Container" : ContainerNameBox.Text.Trim();
        string path = ContainerPathBox.Text?.Trim() ?? string.Empty;
        string mountPath = MountPathBox.Text?.Trim() ?? string.Empty;
        int fontSize = int.TryParse(FontSizeBox.Text, out int parsedFontSize) ? parsedFontSize : 10;
        DewThemeSettings theme = new(
            FontFamilyBox.Text?.Trim() ?? "Segoe UI",
            BackgroundBox.Text?.Trim() ?? "#172033",
            ForegroundBox.Text?.Trim() ?? "#F8FAFC",
            AccentBox.Text?.Trim() ?? "#0F766E",
            fontSize);
        return new DewContainerProfile(name, path, mountPath, theme, HookBox.Text?.Trim() ?? string.Empty);
    }

    private void NewDrive_Click(object? sender, RoutedEventArgs e)
    {
        DewDriveProfile savedProfile = ReadDriveProfile();
        if (string.IsNullOrWhiteSpace(DriveFolder(savedProfile)))
        {
            SetStatus("Stream folder required.");
            Log("Choose a local stream folder before saving a Dew Drive profile.");
            return;
        }

        List<DewDriveProfile> profiles = (settings.DewDrives?.Drives ?? []).ToList();
        int existingIndex = profiles.FindIndex(item =>
            string.Equals(item.Name, savedProfile.Name, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(DriveFolder(item), DriveFolder(savedProfile), StringComparison.OrdinalIgnoreCase));

        if (existingIndex >= 0)
        {
            profiles[existingIndex] = savedProfile;
        }
        else
        {
            profiles.Add(savedProfile);
        }

        DewDriveSettings current = settings.DewDrives ?? new DewDriveSettings(Drives: []);
        settings = settings with { DewDrives = current with { Drives = profiles } };
        settingsService.Save(settings);
        RefreshDriveList();
        DriveStatusText.Text = $"Saved: {DriveLabel(savedProfile)}";
        SetStatus("Dew Drive saved.");
        Log($"Saved Dew Drive profile: {DriveLabel(savedProfile)}");
    }

    private async void PickDriveFolder_Click(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFolder> folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Select local Dew Drive folder",
            AllowMultiple = false,
        });

        IStorageFolder? folder = folders.FirstOrDefault();
        if (folder is not null)
        {
            DriveFolderBox.Text = folder.Path.LocalPath;
            DriveStatusText.Text = folder.Path.LocalPath;
            Log($"Selected stream folder: {folder.Path.LocalPath}");
        }
    }

    private async void AddDriveFiles_Click(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFile> files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = "Copy files into Dew Drive",
            AllowMultiple = true,
        });

        AppendDriveItems(files.Select(file => file.Path.LocalPath));
    }

    private async void AddDriveFolder_Click(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFolder> folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Copy folder into Dew Drive",
            AllowMultiple = false,
        });

        AppendDriveItems(folders.Select(folder => folder.Path.LocalPath));
    }

    private async void SyncDrive_Click(object? sender, RoutedEventArgs e)
    {
        await RunDewDriveAsync("sync", push: false);
    }

    private async void SyncPushDrive_Click(object? sender, RoutedEventArgs e)
    {
        await RunDewDriveAsync("sync", push: true);
    }

    private async void PullDrive_Click(object? sender, RoutedEventArgs e)
    {
        await RunDewDriveAsync("pull", push: false);
    }

    private async void RestoreDrive_Click(object? sender, RoutedEventArgs e)
    {
        await RunDewDriveAsync("restore", push: false);
    }

    private async void InstallVeraCrypt_Click(object? sender, RoutedEventArgs e)
    {
        SetStatus("Installing VeraCrypt...");
        Log("Installing VeraCrypt with winget.");
        await RunAndLogAsync(cliService.InstallVeraCryptAsync());
        string? path = DewDependencyService.FindVeraCryptPath(DriveVeraCryptPathBox.Text?.Trim() ?? string.Empty);
        if (!string.IsNullOrWhiteSpace(path))
        {
            DriveVeraCryptPathBox.Text = path;
            SaveVeraCryptSettingsLocal();
            Log($"VeraCrypt detected: {path}");
        }
        else
        {
            Log("VeraCrypt was not detected after install. Check winget output above.");
        }
    }

    private async void SaveVeraCryptSettings_Click(object? sender, RoutedEventArgs e)
    {
        SaveVeraCryptSettingsLocal();
        await RunAndLogAsync(cliService.SaveVeraCryptSettingsAsync(settings.Veracrypt));
    }

    private async void StartDriveAutoSync_Click(object? sender, RoutedEventArgs e)
    {
        DewDriveProfile profile = SaveDriveProfileFromForm();
        string folder = DriveFolder(profile);
        if (string.IsNullOrWhiteSpace(folder))
        {
            SetStatus("Stream folder required.");
            Log("Choose a local stream folder before starting auto sync.");
            return;
        }

        if (string.IsNullOrWhiteSpace(DriveRegistry(profile)))
        {
            SetStatus("Docker image required.");
            Log("Enter a Docker/OCI image before starting auto sync.");
            return;
        }

        if (!await EnsureEncryptionReadyAsync(profile.EncryptionMode))
        {
            return;
        }

        Directory.CreateDirectory(folder);
        StopDriveAutoSync();
        driveWatcher = new FileSystemWatcher(folder)
        {
            IncludeSubdirectories = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite | NotifyFilters.Size,
            EnableRaisingEvents = true,
        };
        driveWatcher.Changed += DriveWatcher_Changed;
        driveWatcher.Created += DriveWatcher_Changed;
        driveWatcher.Deleted += DriveWatcher_Changed;
        driveWatcher.Renamed += DriveWatcher_Changed;

        DriveStatusText.Text = $"Auto sync running: {folder}";
        SetStatus("Auto sync running.");
        Log($"Auto sync started: {folder}");
    }

    private void StopDriveAutoSync_Click(object? sender, RoutedEventArgs e)
    {
        StopDriveAutoSync();
        SetStatus("Auto sync stopped.");
        Log("Auto sync stopped.");
    }

    private void DriveProfilesList_SelectionChanged(object? sender, SelectionChangedEventArgs e)
    {
        int index = DriveProfilesList.SelectedIndex;
        DewDriveProfile? profile = index >= 0 ? (settings.DewDrives?.Drives ?? []).ElementAtOrDefault(index) : null;
        if (profile is null)
        {
            return;
        }

        DriveNameBox.Text = profile.Name;
        DriveFolderBox.Text = DriveFolder(profile);
        DriveRegistryImageBox.Text = DriveRegistry(profile);
        SetDriveEncryptionMode(profile.EncryptionMode);
        DriveAutoPushBox.IsChecked = profile.AutoPush;
        DriveCommitBox.Text = "HEAD";
        DriveStatusText.Text = DriveLabel(profile);
    }

    private void AppendDriveItems(IEnumerable<string> paths)
    {
        List<string> pathList = paths.Where(path => !string.IsNullOrWhiteSpace(path)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (pathList.Count == 0)
        {
            return;
        }

        string folder = DriveFolderBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(folder))
        {
            foreach (string path in pathList)
            {
                DriveItemsBox.Text += $"{path}{Environment.NewLine}";
                Log($"Staged Dew Drive item: {path}");
            }

            DriveStatusText.Text = "Choose a local folder to copy staged items.";
            return;
        }

        try
        {
            IReadOnlyList<string> copied = driveService.CopyIntoFolder(folder, pathList);
            foreach (string path in copied)
            {
                DriveItemsBox.Text += $"Copied: {path}{Environment.NewLine}";
                Log($"Copied into Dew Drive: {path}");
            }

            DriveStatusText.Text = $"Copied {copied.Count} item(s) into {folder}";
            SetStatus("Dew Drive copy complete.");
        }
        catch (Exception ex)
        {
            SetStatus("Dew Drive copy failed.");
            Log(ex.Message);
        }
    }

    private async Task RunDewDriveAsync(string command, bool push)
    {
        DewDriveProfile profile = SaveDriveProfileFromForm();
        string folder = DriveFolder(profile);
        if (string.IsNullOrWhiteSpace(folder))
        {
            SetStatus("Drive folder required.");
            Log("Choose a local Dew Drive folder before running a drive command.");
            return;
        }

        string registryImage = DriveRegistry(profile);
        string password = DrivePasswordBox.Text?.Trim() ?? string.Empty;
        if (command == "sync")
        {
            if (push && string.IsNullOrWhiteSpace(registryImage))
            {
                SetStatus("Docker image required.");
                Log("Enter a Docker/OCI image before using Sync + Push.");
                return;
            }

            if (string.IsNullOrWhiteSpace(password))
            {
                SetStatus("Password required.");
                Log("Enter an encryption password before syncing a Dew Drive.");
                return;
            }

            if (!await EnsureEncryptionReadyAsync(profile.EncryptionMode))
            {
                return;
            }

            await RunAndLogAsync(cliService.SyncDewDriveProfileAsync(profile.Name, registryImage, push, password));
            return;
        }

        if (command == "pull")
        {
            if (string.IsNullOrWhiteSpace(registryImage))
            {
                SetStatus("Remote required.");
                Log("Enter a registry image before pulling a Dew Drive.");
                return;
            }

            if (string.IsNullOrWhiteSpace(password))
            {
                SetStatus("Password required.");
                Log("Enter the Dew Drive password before pulling a remote image.");
                return;
            }

            await RunAndLogAsync(cliService.PullDewDriveAsync(registryImage, folder, password));
            return;
        }

        if (command == "restore")
        {
            string commit = string.IsNullOrWhiteSpace(DriveCommitBox.Text) ? "HEAD" : DriveCommitBox.Text.Trim();
            await RunAndLogAsync(cliService.RestoreDewDriveFolderAsync(folder, commit));
        }
    }

    private void AddPath(string path, string kind)
    {
        if (!selectionService.AddPath(path, kind))
        {
            SetStatus("Already selected.");
            return;
        }

        DewPathItem item = selectionService.SelectedPaths[^1];
        selectedPaths.Add(item);
        UpdateSelectionContext();
        Log($"Added {kind.ToLowerInvariant()}: {path}");
    }

    private async Task<DewCommandResult?> RunAndLogAsync(Task<DewCommandResult> commandTask)
    {
        SetStatus("Running...");
        try
        {
            DewCommandResult result = await commandTask;
            Log($"> {result.FileName} {string.Join(' ', result.Arguments.Select(QuoteForLog))}");
            if (!string.IsNullOrWhiteSpace(result.StandardOutput))
            {
                Log(result.StandardOutput.TrimEnd());
            }

            if (!string.IsNullOrWhiteSpace(result.StandardError))
            {
                Log(result.StandardError.TrimEnd());
            }

            Log($"Exit code: {result.ExitCode}");
            SetStatus(result.ExitCode == 0 ? "Complete." : $"Exited with code {result.ExitCode}.");
            return result;
        }
        catch (Exception ex)
        {
            SetStatus("Command failed.");
            Log(ex.Message);
            return null;
        }
    }

    private void RefreshContainerList()
    {
        settings = settingsService.Load();
        containers.Clear();
        foreach (ContainerProfile profile in settings.Containers ?? [])
        {
            string label = string.IsNullOrWhiteSpace(profile.Path) ? profile.Name : $"{profile.Name} - {profile.Path}";
            containers.Add(label);
        }

        ContainerStatusText.Text = containers.Count == 0 ? "No saved containers." : $"{containers.Count} saved container(s).";
    }

    private void RefreshDriveList()
    {
        settings = settingsService.Load();
        driveProfiles.Clear();
        foreach (DewDriveProfile profile in settings.DewDrives?.Drives ?? [])
        {
            driveProfiles.Add(DriveLabel(profile));
        }

        DriveStatusText.Text = driveProfiles.Count == 0 ? "No saved Dew Drive profiles." : $"{driveProfiles.Count} saved Dew Drive profile(s).";
    }

    private DewDriveProfile SaveDriveProfileFromForm()
    {
        DewDriveProfile profile = ReadDriveProfile();
        List<DewDriveProfile> profiles = (settings.DewDrives?.Drives ?? []).ToList();
        int existingIndex = profiles.FindIndex(item =>
            string.Equals(item.Name, profile.Name, StringComparison.OrdinalIgnoreCase) ||
            (!string.IsNullOrWhiteSpace(DriveFolder(profile)) && string.Equals(DriveFolder(item), DriveFolder(profile), StringComparison.OrdinalIgnoreCase)));
        if (existingIndex >= 0)
        {
            profiles[existingIndex] = profile;
        }
        else
        {
            profiles.Add(profile);
        }

        DewDriveSettings current = settings.DewDrives ?? new DewDriveSettings(Drives: []);
        settings = settings with { DewDrives = current with { Drives = profiles } };
        settingsService.Save(settings);
        RefreshDriveList();
        return profile;
    }

    private DewDriveProfile ReadDriveProfile()
    {
        string name = string.IsNullOrWhiteSpace(DriveNameBox.Text) ? "Dew Drive" : DriveNameBox.Text.Trim();
        string folder = DriveFolderBox.Text?.Trim() ?? string.Empty;
        string registry = DriveRegistryImageBox.Text?.Trim() ?? string.Empty;
        string mode = SelectedDriveMode();
        return new DewDriveProfile(
            Name: name,
            LocalPath: folder,
            Folder: folder,
            RegistryRef: registry,
            RegistryImage: registry,
            EncryptionMode: mode,
            AutoPush: DriveAutoPushBox.IsChecked == true,
            IncludePatterns: [],
            ExcludePatterns: []);
    }

    private string SelectedDriveMode()
    {
        return (DriveEncryptionModeBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "veracrypt";
    }

    private void SetDriveEncryptionMode(string mode)
    {
        string normalized = string.IsNullOrWhiteSpace(mode) ? "7zip" : mode.Trim().ToLowerInvariant();
        DriveEncryptionModeBox.SelectedIndex = normalized is "7z" or "7zip" or "archive" or "password" or "standard" ? 0 : 1;
    }

    private void LoadVeraCryptSettings()
    {
        VeraCryptSettings vc = settings.Veracrypt;
        DriveVcEncryptionBox.Text = vc.Encryption;
        DriveVcHashBox.Text = vc.Hash;
        DriveVcFilesystemBox.Text = vc.Filesystem;
        DriveVcPimBox.Text = vc.Pim;
        DriveVeraCryptPathBox.Text = DewDependencyService.FindVeraCryptPath(vc.VeraCryptPath) ?? vc.VeraCryptPath;
    }

    private void SaveVeraCryptSettingsLocal()
    {
        VeraCryptSettings existing = settings.Veracrypt;
        settings = settings with
        {
            Veracrypt = existing with
            {
                Encryption = string.IsNullOrWhiteSpace(DriveVcEncryptionBox.Text) ? "AES" : DriveVcEncryptionBox.Text.Trim(),
                Hash = string.IsNullOrWhiteSpace(DriveVcHashBox.Text) ? "SHA-512" : DriveVcHashBox.Text.Trim(),
                Filesystem = string.IsNullOrWhiteSpace(DriveVcFilesystemBox.Text) ? "exFAT" : DriveVcFilesystemBox.Text.Trim(),
                Pim = string.IsNullOrWhiteSpace(DriveVcPimBox.Text) ? "0" : DriveVcPimBox.Text.Trim(),
                VeraCryptPath = DriveVeraCryptPathBox.Text?.Trim() ?? string.Empty,
            },
        };
        settingsService.Save(settings);
        SetStatus("VeraCrypt settings saved.");
        Log("VeraCrypt settings saved.");
    }

    private async Task<bool> EnsureEncryptionReadyAsync(string mode)
    {
        if (!string.Equals(mode, "veracrypt", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        SaveVeraCryptSettingsLocal();
        string? path = DewDependencyService.FindVeraCryptPath(settings.Veracrypt.VeraCryptPath);
        if (!string.IsNullOrWhiteSpace(path))
        {
            DriveVeraCryptPathBox.Text = path;
            return true;
        }

        Log("VeraCrypt is missing; installing with winget.");
        await RunAndLogAsync(cliService.InstallVeraCryptAsync());
        path = DewDependencyService.FindVeraCryptPath(settings.Veracrypt.VeraCryptPath);
        if (string.IsNullOrWhiteSpace(path))
        {
            SetStatus("VeraCrypt missing.");
            Log("VeraCrypt was not detected after install.");
            return false;
        }

        DriveVeraCryptPathBox.Text = path;
        SaveVeraCryptSettingsLocal();
        return true;
    }

    private void DriveWatcher_Changed(object sender, FileSystemEventArgs e)
    {
        if (ShouldIgnoreDrivePath(e.FullPath))
        {
            return;
        }

        driveSyncDebounce?.Cancel();
        driveSyncDebounce = new CancellationTokenSource();
        CancellationToken token = driveSyncDebounce.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(3), token).ConfigureAwait(false);
                await Dispatcher.UIThread.InvokeAsync(async () => await RunDriveAutoSyncAsync(), DispatcherPriority.Background);
            }
            catch (OperationCanceledException)
            {
            }
        }, token);
    }

    private async Task RunDriveAutoSyncAsync()
    {
        if (driveSyncInProgress)
        {
            return;
        }

        driveSyncInProgress = true;
        try
        {
            Log("Auto sync detected changes.");
            await RunDewDriveAsync("sync", push: true);
        }
        finally
        {
            driveSyncInProgress = false;
        }
    }

    private void StopDriveAutoSync()
    {
        driveSyncDebounce?.Cancel();
        driveSyncDebounce?.Dispose();
        driveSyncDebounce = null;
        if (driveWatcher is not null)
        {
            driveWatcher.EnableRaisingEvents = false;
            driveWatcher.Dispose();
            driveWatcher = null;
        }
    }

    private static bool ShouldIgnoreDrivePath(string path)
    {
        return path.Contains(DewPathService.ArchiveDirName, StringComparison.OrdinalIgnoreCase) ||
            path.Contains($"{Path.DirectorySeparatorChar}.git{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase);
    }

    private static string DriveFolder(DewDriveProfile profile)
    {
        return !string.IsNullOrWhiteSpace(profile.LocalPath) ? profile.LocalPath : profile.Folder;
    }

    private static string DriveRegistry(DewDriveProfile profile)
    {
        return !string.IsNullOrWhiteSpace(profile.RegistryRef) ? profile.RegistryRef : profile.RegistryImage;
    }

    private static string DriveLabel(DewDriveProfile profile)
    {
        string folder = DriveFolder(profile);
        string registry = DriveRegistry(profile);
        string label = string.IsNullOrWhiteSpace(folder) ? profile.Name : $"{profile.Name} - {folder}";
        return string.IsNullOrWhiteSpace(registry) ? label : $"{label} -> {registry}";
    }

    private void UpdateSelectionContext()
    {
        SelectionSummaryText.Text = selectedPaths.Count == 0
            ? "No files or folders selected."
            : $"{selectedPaths.Count} selected item(s).";
        DewPathItem? first = selectedPaths.FirstOrDefault();
        HistoryTargetBox.Text = first is null ? string.Empty : DewPathService.RepoForSource(first.Path);
    }

    private void SetStatus(string message)
    {
        StatusText.Text = message;
    }

    private static string QuoteForLog(string value)
    {
        return value.Contains(' ') ? $"\"{value}\"" : value;
    }

    private void Log(string message)
    {
        LogBox.Text += $"[{DateTime.Now:HH:mm:ss}] {message}{Environment.NewLine}";
        LogBox.CaretIndex = LogBox.Text.Length;
    }
}
