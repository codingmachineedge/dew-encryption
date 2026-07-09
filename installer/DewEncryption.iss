#define MyAppName "Dew Encryption"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "codingmachineedge"
#define MyAppURL "https://github.com/codingmachineedge/dew-encryption"
#define MyAppExeName "dew-encryption.exe"
#define MyAppGuiExeName "dew-encryption-gui.exe"
#define MyPythonGuiExeName "dew-encryption-python-gui.exe"

[Setup]
AppId={{9E91A740-2663-4DB2-9C7C-198FC592E3FB}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Dew Encryption
DefaultGroupName=Dew Encryption
DisableProgramGroupPage=yes
OutputDir=..\dist\installer
OutputBaseFilename=DewEncryptionSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\assets\icons\dew-main.ico
UninstallDisplayIcon={app}\{#MyAppGuiExeName}

[Files]
Source: "..\dist\app\dew-encryption.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\app\dew-encryption-gui.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dist\app\dew-encryption-python-gui.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\installer\install-dependencies.ps1"; Flags: dontcopy
Source: "..\dist\context-menu\DewEncryptionExplorerCommand.dll"; DestDir: "{app}\context-menu"; Flags: ignoreversion restartreplace uninsrestartdelete
Source: "..\dist\context-menu\DewEncryption.ContextMenu.msix"; DestDir: "{app}\context-menu"; Flags: ignoreversion
Source: "..\installer\install-win11-context-menu.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "..\installer\uninstall-win11-context-menu.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\installer\create-elevated-tasks.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "..\installer\remove-elevated-tasks.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "..\installer\launch-create-elevated-tasks.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "..\installer\launch-remove-elevated-tasks.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "..\assets\icons\dew-main.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\assets\icons\dew-main.png"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\assets\icons\dew-archive.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\assets\icons\dew-watch.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\assets\icons\dew-history.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\assets\icons\dew-veracrypt-encrypt.ico"; DestDir: "{app}\icons"; Flags: ignoreversion
Source: "..\assets\icons\dew-veracrypt-decrypt.ico"; DestDir: "{app}\icons"; Flags: ignoreversion

[Icons]
Name: "{group}\Dew Encryption"; Filename: "{app}\{#MyAppGuiExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\icons\dew-main.ico"
Name: "{group}\Dew Encryption README"; Filename: "{app}\README.md"

[Tasks]
Name: "startup"; Description: "Start Dew Drive auto-sync at Windows login"; GroupDescription: "Startup:"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\installer\install-win11-context-menu.ps1"" -InstallRoot ""{app}"" -PackagePath ""{app}\context-menu\DewEncryption.ContextMenu.msix"" -SkipBuild"; StatusMsg: "Registering the Windows 11 Explorer context menu..."; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppGuiExeName}"; Description: "Launch Dew Encryption"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""{app}\installer\uninstall-win11-context-menu.ps1"""; Flags: runhidden waituntilterminated; RunOnceId: "RemoveDewWin11ContextMenu"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "DewEncryptionDewDrive"; ValueData: """{app}\{#MyAppGuiExeName}"" --auto-sync-worker"; Flags: uninsdeletevalue; Tasks: startup

Root: HKLM; Subkey: "Software\DewEncryption\ContextMenu"; ValueType: string; ValueName: "InstallRoot"; ValueData: "{app}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\DewEncryption\ContextMenu"; ValueType: string; ValueName: "CliPath"; ValueData: "{app}\{#MyAppExeName}"
Root: HKLM; Subkey: "Software\DewEncryption\ContextMenu"; ValueType: string; ValueName: "PythonGuiPath"; ValueData: "{app}\{#MyPythonGuiExeName}"
Root: HKLM; Subkey: "Software\DewEncryption\ContextMenu"; ValueType: string; ValueName: "IconPath"; ValueData: "{app}\icons\dew-main.ico"

Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --archive-encrypt %*"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --archive-encrypt ""%1"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --archive-encrypt ""%V"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-watch"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption start file history"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-watch"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-watch.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-watch\command"; ValueType: string; ValueName: ""; ValueData: "powershell -NoProfile -ExecutionPolicy Bypass -Command ""Start-Process -WindowStyle Hidden -FilePath '{app}\{#MyAppExeName}' -ArgumentList @('watch','%1')"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-watch"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption start file history"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-watch"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-watch.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-watch\command"; ValueType: string; ValueName: ""; ValueData: "powershell -NoProfile -ExecutionPolicy Bypass -Command ""Start-Process -WindowStyle Hidden -FilePath '{app}\{#MyAppExeName}' -ArgumentList @('watch','%V')"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-manager"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption file history manager"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-manager"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-history.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-manager\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" ""%1"" --history"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-manager"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption file history manager"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-manager"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-history.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-manager\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" ""%V"" --history"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-quick-create"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption quick create container"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-quick-create"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-quick-create"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-veracrypt-encrypt.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-quick-create\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --container-quick-create %*"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-quick-create"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption quick create container"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-quick-create"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-quick-create"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-veracrypt-encrypt.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-quick-create\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --container-quick-create %*"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-veracrypt-encrypt"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption VeraCrypt encrypt"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-veracrypt-encrypt"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-veracrypt-encrypt"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-veracrypt-encrypt.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-veracrypt-encrypt\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --veracrypt-encrypt %*"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-veracrypt-encrypt"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption VeraCrypt encrypt"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-veracrypt-encrypt"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-veracrypt-encrypt"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-veracrypt-encrypt.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-veracrypt-encrypt\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --veracrypt-encrypt %*"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\.hc\shell\dew-encryption-veracrypt-decrypt"; Flags: deletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.hc\shell\dew-encryption-veracrypt-decrypt"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption VeraCrypt decrypt"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.hc\shell\dew-encryption-veracrypt-decrypt"; ValueType: string; ValueName: "MultiSelectModel"; ValueData: "Player"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.hc\shell\dew-encryption-veracrypt-decrypt"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-veracrypt-decrypt.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\SystemFileAssociations\.hc\shell\dew-encryption-veracrypt-decrypt\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --veracrypt-decrypt %*"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-create-elevated-tasks"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption create elevated tasks"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-create-elevated-tasks"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-main.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-create-elevated-tasks\command"; ValueType: string; ValueName: ""; ValueData: "powershell -NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\launch-create-elevated-tasks.ps1"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-remove-elevated-tasks"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption remove elevated tasks"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-remove-elevated-tasks"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-main.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-remove-elevated-tasks\command"; ValueType: string; ValueName: ""; ValueData: "powershell -NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\launch-remove-elevated-tasks.ps1"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-dew-drive-add"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption add to Dew Drive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-dew-drive-add"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-dew-drive-add\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" dew-drive add ""%1"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-dew-drive-add"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption add to Dew Drive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-dew-drive-add"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-dew-drive-add\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" dew-drive add ""%1"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-dew-drive-sync"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption sync Dew Drive"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-dew-drive-sync"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-dew-drive-sync\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" dew-drive sync --push"; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-docker-upload"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption upload to Docker or custom remote"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-docker-upload"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\*\shell\dew-encryption-docker-upload\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --docker-upload ""%1"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-docker-save-here"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption save Docker image here"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-docker-save-here"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-docker-save-here\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyPythonGuiExeName}"" --docker-save-here ""%V"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-git-commit-push"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption commit and push repo"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-git-commit-push"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-git-commit-push"; ValueType: string; ValueName: "AppliesTo"; ValueData: "System.FileName:"".git"" OR System.FileName:""*"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\Background\shell\dew-encryption-git-commit-push\command"; ValueType: string; ValueName: ""; ValueData: "powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command ""& '{app}\{#MyAppExeName}' git-commit-push '%V'; Read-Host 'Press Enter to close'"""; Flags: uninsdeletekey

Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-git-commit-push"; ValueType: string; ValueName: "MUIVerb"; ValueData: "dew encryption commit and push repo"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-git-commit-push"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\icons\dew-archive.ico"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-git-commit-push"; ValueType: string; ValueName: "AppliesTo"; ValueData: "System.FileName:"".git"" OR System.FileName:""*"""; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Directory\shell\dew-encryption-git-commit-push\command"; ValueType: string; ValueName: ""; ValueData: "powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command ""& '{app}\{#MyAppExeName}' git-commit-push '%1'; Read-Host 'Press Enter to close'"""; Flags: uninsdeletekey

[Code]
function CommandExists(Name: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{cmd}'), '/C where ' + Name, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

function GitInstalled(): Boolean;
begin
  Result := CommandExists('git') or
    FileExists(ExpandConstant('{commonpf}\Git\cmd\git.exe')) or
    FileExists(ExpandConstant('{commonpf32}\Git\cmd\git.exe')) or
    FileExists(ExpandConstant('{localappdata}\Programs\Git\cmd\git.exe'));
end;

function SevenZipInstalled(): Boolean;
begin
  Result := CommandExists('7z') or
    FileExists(ExpandConstant('{commonpf}\7-Zip\7z.exe')) or
    FileExists(ExpandConstant('{commonpf32}\7-Zip\7z.exe'));
end;

function VeraCryptInstalled(): Boolean;
begin
  Result := CommandExists('VeraCrypt') or
    FileExists(ExpandConstant('{commonpf}\VeraCrypt\VeraCrypt.exe')) or
    FileExists(ExpandConstant('{commonpf32}\VeraCrypt\VeraCrypt.exe'));
end;

function AllDependenciesInstalled(): Boolean;
begin
  Result := GitInstalled() and SevenZipInstalled() and VeraCryptInstalled();
end;

function MissingDependencyNames(): String;
var
  Missing: String;
begin
  Missing := '';
  if not GitInstalled() then
    Missing := 'Git';
  if not SevenZipInstalled() then begin
    if Missing <> '' then Missing := Missing + ', ';
    Missing := Missing + '7-Zip';
  end;
  if not VeraCryptInstalled() then begin
    if Missing <> '' then Missing := Missing + ', ';
    Missing := Missing + 'VeraCrypt';
  end;
  Result := Missing;
end;

procedure ShowDependencyWarning(LogPath: String);
var
  WarningText: String;
begin
  WarningText := 'Dew Encryption setup will continue, but these components are still missing: ' +
    MissingDependencyNames() + '.' + #13#10#13#10 +
    'Features that use those components will be unavailable until they are installed.' + #13#10 +
    'Log: ' + LogPath;
  Log('WARNING: ' + WarningText);
  if not WizardSilent then
    MsgBox(WarningText, mbInformation, MB_OK);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  DependencyScript: String;
  WingetPath: String;
  LogPath: String;
  RestartMarkerPath: String;
  Parameters: String;
  ResultCode: Integer;
begin
  Result := '';
  ResultCode := -1;
  NeedsRestart := False;
  if AllDependenciesInstalled() then
    Exit;

  ExtractTemporaryFile('install-dependencies.ps1');
  DependencyScript := ExpandConstant('{tmp}\install-dependencies.ps1');
  WingetPath := ExpandConstant('{localappdata}\Microsoft\WindowsApps\winget.exe');
  LogPath := ExpandConstant('{localappdata}\Dew Encryption\Logs\dependency-install.log');
  RestartMarkerPath := ExpandConstant('{tmp}\dew-encryption-restart-required');
  DeleteFile(RestartMarkerPath);
  ForceDirectories(ExtractFileDir(LogPath));
  Parameters := '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' +
    DependencyScript + '" -LogPath "' + LogPath + '" -WingetPath "' + WingetPath +
    '" -RestartMarkerPath "' + RestartMarkerPath + '"';

  WizardForm.StatusLabel.Caption := 'Installing Git, 7-Zip, and VeraCrypt...';
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log('WARNING: The dependency installer could not be started. Setup will continue.')
  else if ResultCode <> 0 then
    Log(Format('WARNING: The dependency installer exited with code %d. Setup will continue.', [ResultCode]));

  if not AllDependenciesInstalled() then
    ShowDependencyWarning(LogPath);

  if FileExists(RestartMarkerPath) then
    NeedsRestart := True;
end;
