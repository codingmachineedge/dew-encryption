using System.Collections.ObjectModel;
using Avalonia.Controls;
using Avalonia.Interactivity;
using Avalonia.Platform.Storage;
using DewEncryption.Core;

namespace DewEncryption.Gui;

public sealed partial class MainWindow : Window
{
    private readonly DewCliService cliService = new();
    private readonly DewSelectionService selectionService = new();
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
        selectionService.RemovePaths(items);
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
            Log("Select a file or folder before opening the history manager.");
            return;
        }

        await RunAndLogAsync(cliService.OpenHistoryGuiAsync(first.Path));
    }

    private void RegisterContainer_Click(object? sender, RoutedEventArgs e)
    {
        DewContainerProfile profile = ReadContainerProfile();
        containers.Add(profile.DisplayLabel);
        Log($"Registered container draft: {profile.DisplayLabel}");
    }

    private async void SnapshotContainer_Click(object? sender, RoutedEventArgs e)
    {
        DewContainerProfile profile = ReadContainerProfile();
        if (string.IsNullOrWhiteSpace(profile.Path))
        {
            Log("Enter a container path before snapshotting container history.");
            return;
        }

        await RunAndLogAsync(cliService.SnapshotContainerHistoryAsync(profile.Path));
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
            Log($"Enter a container path before testing {eventName} hooks.");
            return;
        }

        await RunAndLogAsync(cliService.TestContainerHooksAsync(eventName, profile.Path, profile.MountPath));
    }

    private DewContainerProfile ReadContainerProfile()
    {
        string name = string.IsNullOrWhiteSpace(ContainerNameBox.Text) ? "Container" : ContainerNameBox.Text.Trim();
        string path = ContainerPathBox.Text?.Trim() ?? string.Empty;
        string mountPath = MountPathBox.Text?.Trim() ?? string.Empty;
        int fontSize = int.TryParse(FontSizeBox.Text, out int parsedFontSize) ? parsedFontSize : 10;
        DewThemeSettings theme = new(
            FontFamilyBox.Text?.Trim() ?? "Segoe UI",
            BackgroundBox.Text?.Trim() ?? "#0f172a",
            ForegroundBox.Text?.Trim() ?? "#e5e7eb",
            AccentBox.Text?.Trim() ?? "#38bdf8",
            fontSize);
        return new DewContainerProfile(name, path, mountPath, theme, HookBox.Text?.Trim() ?? string.Empty);
    }

    private void AddPath(string path, string kind)
    {
        if (!selectionService.AddPath(path, kind))
        {
            return;
        }

        DewPathItem item = selectionService.SelectedPaths[^1];
        selectedPaths.Add(item);
        Log($"Added {kind.ToLowerInvariant()}: {path}");
    }

    private async Task RunAndLogAsync(Task<DewCommandResult> commandTask)
    {
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
        }
        catch (Exception ex)
        {
            Log(ex.Message);
        }
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
