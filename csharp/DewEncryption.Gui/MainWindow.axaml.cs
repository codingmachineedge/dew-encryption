using System.Collections.ObjectModel;
using System.Diagnostics;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;

namespace DewEncryption.Gui;

public sealed partial class MainWindow : Window
{
    private readonly ObservableCollection<DewPathItem> selectedPaths = [];
    private readonly ObservableCollection<string> containers = [];
    private readonly ObservableCollection<string> driveProfiles = [];

    public MainWindow()
    {
        InitializeComponent();
        FilesGrid.ItemsSource = selectedPaths;
        ContainersList.ItemsSource = containers;
        DriveProfilesList.ItemsSource = driveProfiles;
        Log("Ready. Select files, folders, or containers to drive the dew-encryption CLI.");
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
        foreach (DewPathItem item in items)
        {
            selectedPaths.Remove(item);
        }
    }

    private async void RunSelected_Click(object? sender, RoutedEventArgs e)
    {
        if (selectedPaths.Count == 0)
        {
            Log("Add at least one file or folder before running Dew Encryption.");
            return;
        }

        await RunCliAsync(selectedPaths.Select(item => item.Path).ToArray());
    }

    private async void OpenHelp_Click(object? sender, RoutedEventArgs e)
    {
        await RunCliAsync("--help");
    }

    private async void RefreshHistory_Click(object? sender, RoutedEventArgs e)
    {
        DewPathItem? first = selectedPaths.FirstOrDefault();
        if (first is null)
        {
            Log("Select a file or folder before refreshing history.");
            return;
        }

        await RunCliAsync("history", first.Path);
    }

    private async void SnapshotHistory_Click(object? sender, RoutedEventArgs e)
    {
        DewPathItem? first = selectedPaths.FirstOrDefault();
        if (first is null)
        {
            Log("Select a file or folder before snapshotting history.");
            return;
        }

        await RunCliAsync(first.Path);
    }

    private async void OpenPythonHistoryGui_Click(object? sender, RoutedEventArgs e)
    {
        DewPathItem? first = selectedPaths.FirstOrDefault();
        if (first is null)
        {
            Log("Select a file or folder before opening the history manager.");
            return;
        }

        await RunProcessAsync("dew-encryption-gui", first.Path, "--history");
    }

    private void RegisterContainer_Click(object? sender, RoutedEventArgs e)
    {
        string name = string.IsNullOrWhiteSpace(ContainerNameBox.Text) ? "Container" : ContainerNameBox.Text.Trim();
        string path = ContainerPathBox.Text?.Trim() ?? string.Empty;
        string mountPath = MountPathBox.Text?.Trim() ?? string.Empty;
        string label = string.IsNullOrWhiteSpace(path) ? name : $"{name} — {path}";
        if (!string.IsNullOrWhiteSpace(mountPath))
        {
            label = $"{label} mounted at {mountPath}";
        }

        containers.Add(label);
        Log($"Registered container draft: {label}");
    }

    private async void SnapshotContainer_Click(object? sender, RoutedEventArgs e)
    {
        string path = ContainerPathBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            Log("Enter a container path before snapshotting container history.");
            return;
        }

        await RunCliAsync("container-history", path, "--snapshot");
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
        string path = ContainerPathBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(path))
        {
            Log($"Enter a container path before testing {eventName} hooks.");
            return;
        }

        List<string> args = ["container-hooks", eventName, path];
        string mountPath = MountPathBox.Text?.Trim() ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(mountPath))
        {
            args.Add("--mount-path");
            args.Add(mountPath);
        }

        await RunCliAsync(args.ToArray());
    }


    private void NewDrive_Click(object? sender, RoutedEventArgs e)
    {
        string name = string.IsNullOrWhiteSpace(DriveNameBox.Text) ? "Dew Drive" : DriveNameBox.Text.Trim();
        string folder = DriveFolderBox.Text?.Trim() ?? string.Empty;
        string registry = DriveRegistryImageBox.Text?.Trim() ?? string.Empty;
        string label = string.IsNullOrWhiteSpace(folder) ? name : $"{name} — {folder}";
        if (!string.IsNullOrWhiteSpace(registry))
        {
            label = $"{label} ⇄ {registry}";
        }

        driveProfiles.Add(label);
        Log($"Registered Dew Drive draft: {label}");
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
            Title = "Add files to Dew Drive",
            AllowMultiple = true,
        });

        AppendDriveItems(files.Select(file => file.Path.LocalPath));
    }

    private async void AddDriveFolder_Click(object? sender, RoutedEventArgs e)
    {
        IReadOnlyList<IStorageFolder> folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions
        {
            Title = "Add folder to Dew Drive",
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
        foreach (string path in paths.Where(path => !string.IsNullOrWhiteSpace(path)))
        {
            DriveItemsBox.Text += $"{path}{Environment.NewLine}";
            Log($"Added to Dew Drive staging list: {path}");
        }
    }

    private async Task RunDewDriveAsync(string command, bool push)
    {
        string folder = DriveFolderBox.Text?.Trim() ?? string.Empty;
        if (string.IsNullOrWhiteSpace(folder))
        {
            Log("Choose a local Dew Drive folder before running a drive command.");
            return;
        }

        List<string> args = ["dew-drive", command, "--folder", folder];
        string registryImage = DriveRegistryImageBox.Text?.Trim() ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(registryImage))
        {
            args.Add("--registry-image");
            args.Add(registryImage);
        }

        if (command == "sync")
        {
            args.Add("--mode");
            args.Add(SelectedDriveMode());
            AddPatternArgs(args, "--include", DriveIncludePatternsBox.Text);
            AddPatternArgs(args, "--exclude", DriveExcludePatternsBox.Text);
            if (push)
            {
                args.Add("--push");
            }
        }

        await RunCliAsync(args.ToArray());
    }

    private string SelectedDriveMode()
    {
        return (DriveEncryptionModeBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "standard";
    }

    private static void AddPatternArgs(List<string> args, string option, string? value)
    {
        foreach (string pattern in (value ?? string.Empty).Split([Environment.NewLine, ",", ";"], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            args.Add(option);
            args.Add(pattern);
        }
    }

    private void AddPath(string path, string kind)
    {
        if (selectedPaths.Any(item => string.Equals(item.Path, path, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        selectedPaths.Add(new DewPathItem(path, kind));
        Log($"Added {kind.ToLowerInvariant()}: {path}");
    }

    private Task RunCliAsync(params string[] arguments)
    {
        return RunProcessAsync("dew-encryption", arguments);
    }

    private async Task RunProcessAsync(string fileName, params string[] arguments)
    {
        Log($"> {fileName} {string.Join(' ', arguments.Select(QuoteForLog))}");
        ProcessStartInfo startInfo = new()
        {
            FileName = fileName,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };

        foreach (string argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using Process process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Unable to start {fileName}.");
        string output = await process.StandardOutput.ReadToEndAsync();
        string error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        if (!string.IsNullOrWhiteSpace(output))
        {
            Log(output.TrimEnd());
        }

        if (!string.IsNullOrWhiteSpace(error))
        {
            Log(error.TrimEnd());
        }

        Log($"Exit code: {process.ExitCode}");
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

public sealed record DewPathItem(string Path, string Kind);
