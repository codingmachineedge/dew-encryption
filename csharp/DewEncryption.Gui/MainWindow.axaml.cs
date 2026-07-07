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

    public MainWindow()
    {
        InitializeComponent();
        FilesGrid.ItemsSource = selectedPaths;
        ContainersList.ItemsSource = containers;
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
