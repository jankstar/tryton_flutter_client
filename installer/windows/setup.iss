; Inno Setup script of the Windows installer (specs/RELEASE.md).
; Built by the release workflow:
;   iscc /DAppVersion=8.0.0 /DAppLabel=v8.0.0-beta.1 installer\windows\setup.iss
; Per-user installation without admin rights; Start menu entry, optional
; desktop icon, uninstaller; LICENSE as licence page, COPYRIGHT installed.

#ifndef AppVersion
  #define AppVersion "8.0.0"
#endif
#ifndef AppLabel
  #define AppLabel "v" + AppVersion
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName "Tryton Flutter Client"
#define AppExe "tryton_flutter_client.exe"
#define AppPublisher "jankstar"
#define AppUrl "https://github.com/jankstar/tryton_flutter_client"

[Setup]
; keep the AppId: Windows identifies installation and updates by it
AppId={{ACE6B0B7-3BA4-4F3E-8508-8D17CD98A377}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppLabel}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
VersionInfoVersion={#AppVersion}
; per user, no admin rights ({autopf} = %LOCALAPPDATA%\Programs)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
InfoBeforeFile=..\..\COPYRIGHT
OutputDir=..\..\build\dist
OutputBaseFilename=TrytonFlutterClient-{#AppLabel}-windows-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\COPYRIGHT"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
