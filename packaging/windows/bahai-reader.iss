; Windows installer (Inno Setup 6). Built in CI: iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=dist
; Installs for the current user only (no administrator prompt). Unsigned, so Windows SmartScreen may warn on first run.
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{6C1C6A5E-3B0F-4E7A-9D57-B4E1A2F0C919}
AppName=Bahá’í Reader
AppVersion={#AppVersion}
AppVerName=Bahá’í Reader {#AppVersion}
AppPublisher=Nine Point Labs
AppPublisherURL=https://bahaireader.org/
AppSupportURL=https://github.com/ninepointlabs/bahai-reader/issues
AppUpdatesURL=https://github.com/ninepointlabs/bahai-reader/releases/latest
DefaultDirName={localappdata}\Programs\Bahai Reader
DefaultGroupName=Bahá’í Reader
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=bahai-reader-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bahai-reader.exe
LicenseFile=..\..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\DATA-NOTICE.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Bahá’í Reader"; Filename: "{app}\bahai-reader.exe"
Name: "{autodesktop}\Bahá’í Reader"; Filename: "{app}\bahai-reader.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\bahai-reader.exe"; Description: "{cm:LaunchProgram,Bahá’í Reader}"; Flags: nowait postinstall skipifsilent
