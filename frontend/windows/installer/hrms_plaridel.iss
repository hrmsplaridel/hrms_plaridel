#define MyAppName "HRMS Plaridel"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Municipality of Plaridel"
#define MyAppExeName "hrms_plaridel.exe"
#define VCRedistPath SourcePath + "prerequisites\vc_redist.x64.exe"
#if !FileExists(VCRedistPath)
  #error Run download-prerequisites.ps1 before compiling this installer.
#endif
#define VCRedistVersion GetFileVersion(VCRedistPath)

[Setup]
AppId={{8BB2241D-5999-4E87-90FC-483C47CB3396}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\HRMS Plaridel
DefaultGroupName=HRMS Plaridel
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=HRMS-Plaridel-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; Keep the prerequisite first for efficient extraction with solid compression.
Source: "{#VCRedistPath}"; Flags: dontcopy
; Run `flutter build windows --release` before compiling this installer.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\HRMS Plaridel"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\HRMS Plaridel"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch HRMS Plaridel"; Flags: nowait postinstall skipifsilent; Check: CanLaunchApp

[Code]
var
  RuntimeRestartRequired: Boolean;

function RuntimeVersionSufficient(RootKey: Integer): Boolean;
var
  Installed: Cardinal;
  VersionText: String;
  InstalledVersion, RequiredVersion: Int64;
begin
  Result := False;
  if not RegQueryDWordValue(RootKey,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
    Exit;
  if Installed <> 1 then
    Exit;
  if not RegQueryStringValue(RootKey,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Version', VersionText) then
    Exit;
  if Copy(VersionText, 1, 1) = 'v' then
    Delete(VersionText, 1, 1);
  if not StrToVersion(VersionText, InstalledVersion) then
    Exit;
  if not StrToVersion('{#VCRedistVersion}', RequiredVersion) then
    Exit;
  Result := InstalledVersion >= RequiredVersion;
end;

function HasRequiredRuntime: Boolean;
begin
  Result := RuntimeVersionSufficient(HKLM64) or RuntimeVersionSufficient(HKLM32);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if HasRequiredRuntime then
    Exit;
  ExtractTemporaryFile('vc_redist.x64.exe');
  WizardForm.PreparingLabel.Caption :=
    'Installing Microsoft Visual C++ Runtime. Approve the Windows administrator prompt to continue.';
  if not ShellExec('runas', ExpandConstant('{tmp}\vc_redist.x64.exe'),
    '/install /passive /norestart', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := 'Microsoft Visual C++ Runtime could not start. Administrator approval is required. ' +
      SysErrorMessage(ResultCode);
    Exit;
  end;
  Log(Format('Visual C++ Runtime installer exit code: %d', [ResultCode]));
  if (ResultCode = 3010) or (ResultCode = 1641) then
    RuntimeRestartRequired := True
  else if ResultCode <> 0 then
  begin
    { A concurrent installation may have installed a newer version. }
    if not HasRequiredRuntime then
      Result := Format('Microsoft Visual C++ Runtime installation failed (code %d). ' +
        'Complete the runtime installation, then retry HRMS Setup.', [ResultCode]);
    Exit;
  end;
  if not RuntimeRestartRequired and not HasRequiredRuntime then
    Result := 'Microsoft Visual C++ Runtime could not be verified. Restart Windows and retry HRMS Setup.';
end;

function NeedRestart: Boolean;
begin
  Result := RuntimeRestartRequired;
end;

function CanLaunchApp: Boolean;
begin
  Result := not RuntimeRestartRequired;
end;
