#define MyAppName "HRMS Plaridel"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Municipality of Plaridel"
#define MyAppExeName "hrms_plaridel.exe"

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
; Run `flutter build windows --release` before compiling this installer.
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\HRMS Plaridel"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\HRMS Plaridel"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch HRMS Plaridel"; Flags: nowait postinstall skipifsilent
