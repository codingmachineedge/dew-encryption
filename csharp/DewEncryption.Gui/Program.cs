using Avalonia;

namespace DewEncryption.Gui;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Any(arg => string.Equals(arg, "--auto-sync-worker", StringComparison.OrdinalIgnoreCase)))
        {
            return DewEncryption.Core.DewAutoSyncWorker.RunSingletonAsync().GetAwaiter().GetResult();
        }

        BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        return 0;
    }

    public static AppBuilder BuildAvaloniaApp()
    {
        return AppBuilder.Configure<App>()
            .UsePlatformDetect()
            .WithInterFont()
            .LogToTrace();
    }
}
