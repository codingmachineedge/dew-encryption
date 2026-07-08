# Dew Encryption C# GUI and Core Library

This folder contains the C# targets for Dew Encryption:

- `DewEncryption.Core`: a .NET 8 class library that centralizes the reusable application model, path selection, container profile data, and process/CLI orchestration for the full app workflows.
- `DewEncryption.Gui`: an Avalonia desktop shell for Windows and Linux that references the core library while reusing the existing `dew-encryption` Python CLI for encryption, Git history, VeraCrypt, and hook execution workflows.

## Build locally

Install the .NET 8 SDK, then run:

```bash
dotnet restore csharp/DewEncryption.sln
dotnet build csharp/DewEncryption.sln
```

## Build with Docker

From the repository root, run:

```bash
docker build -f csharp/Dockerfile .
```

The Docker build restores and compiles both the .NET Core library and Avalonia GUI in Release mode.

## Current scope

- Files tab: add files/folders and run the existing `dew-encryption` CLI through `DewEncryption.Core`.
- History tab: call core library helpers for CLI history and snapshot flows, or launch the existing Python history manager while the C# history UI matures.
- Containers tab: draft container registration details, snapshot container file history, and test open/close hooks through core library helpers.

The C# GUI is deliberately a shell over the mature CLI so Windows and Linux behavior stays aligned with the existing automation while reusable .NET app functionality lives in `DewEncryption.Core`.
