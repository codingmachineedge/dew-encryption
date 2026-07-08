using System.Collections.ObjectModel;
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

    public MainWindow()
    {
        InitializeComponent();
        settings = settingsService.Load();
        FilesGrid.ItemsSource = selectedPaths;
        ContainersList.ItemsSource = containers;
        DriveProfilesList.ItemsSource = driveProfiles;
        RefreshContainerList();
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
        string name = string.IsNullOrWhiteSpace(DriveNameBox.Text) ? "Dew Drive" : DriveNameBox.Text.Trim();
        string folder = DriveFolderBox.Text?.Trim() ?? string.Empty;
        string registry = DriveRegistryImageBox.Text?.Trim() ?? string.Empty;
        string label = string.IsNullOrWhiteSpace(folder) ? name : $"{name} - {folder}";
        if (!string.IsNullOrWhiteSpace(registry))
        {
            label = $"{label} -> {registry}";
        }

        if (!driveProfiles.Contains(label))
        {
            driveProfiles.Add(label);
        }

        DriveStatusText.Text = label;
        Log($"Prepared Dew Drive: {label}");
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
            NewDrive_Click(sender, e);
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
        string folder = DriveFolderBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(folder))
        {
            SetStatus("Drive folder required.");
            Log("Choose a local Dew Drive folder before running a drive command.");
            return;
        }

        string registryImage = DriveRegistryImageBox.Text?.Trim() ?? string.Empty;
        if (command == "sync")
        {
            if (push && string.IsNullOrWhiteSpace(registryImage))
            {
                SetStatus("Remote required.");
                Log("Enter a Git remote or registry image before using Snapshot + Push.");
                return;
            }

            await RunAndLogAsync(cliService.SyncDewDriveFolderAsync(folder, registryImage, push));
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

            await RunAndLogAsync(cliService.PullDewDriveAsync(registryImage, folder));
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

    private async Task RunAndLogAsync(Task<DewCommandResult> commandTask)
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
        }
        catch (Exception ex)
        {
            SetStatus("Command failed.");
            Log(ex.Message);
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
