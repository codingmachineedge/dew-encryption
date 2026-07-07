# Dew Encryption C# GUI

This folder contains the C# GUI target for Dew Encryption. It is an Avalonia-based desktop shell intended to run on Windows and Linux while reusing the existing `dew-encryption` Python CLI for the encryption, Git history, VeraCrypt, and hook execution workflows.

## Build

Install the .NET 8 SDK, then run:

```bash
dotnet restore csharp/DewEncryption.Gui/DewEncryption.Gui.csproj
dotnet build csharp/DewEncryption.Gui/DewEncryption.Gui.csproj
```

## Current scope

- Files tab: add files/folders and run the existing `dew-encryption` CLI.
- History tab: call the CLI history and snapshot flows, or launch the existing Python history manager while the C# history UI matures.
- Containers tab: draft container registration details, snapshot container file history, and test open/close hooks through the CLI.

The C# GUI is deliberately a shell over the mature CLI so Windows and Linux behavior stays aligned with the existing automation.
