; Build through tool/build_release.py so versions match pubspec.yaml.
#ifndef AppVersion
  #error AppVersion must be provided by the release builder
#endif
#ifndef AppNumericVersion
  #error AppNumericVersion must be provided by the release builder
#endif
#ifndef BundleDir
  #error BundleDir must point to the complete Flutter Windows release bundle
#endif
#ifndef ProjectDir
  #error ProjectDir must point to the repository root
#endif

[Setup]
AppId={{D0404317-743A-46CE-9394-04B9B81BDDAB}
AppName=PhotoSim
AppVersion={#AppVersion}
AppPublisher=PhotoSim contributors
AppPublisherURL=https://github.com/Alchemist-Aloha/PhotoSim
AppSupportURL=https://github.com/Alchemist-Aloha/PhotoSim/issues
DefaultDirName={localappdata}\Programs\PhotoSim
DefaultGroupName=PhotoSim
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\photosim.exe
LicenseFile={#ProjectDir}\LICENSE
SetupIconFile={#ProjectDir}\windows\runner\resources\app_icon.ico
OutputBaseFilename=PhotoSim-{#AppVersion}-windows-x64-setup
VersionInfoVersion={#AppNumericVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductName=PhotoSim
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#ProjectDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ProjectDir}\docs\windows.md"; DestDir: "{app}"; DestName: "README.md"; Flags: ignoreversion

[Icons]
Name: "{group}\PhotoSim"; Filename: "{app}\photosim.exe"
Name: "{autodesktop}\PhotoSim"; Filename: "{app}\photosim.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\photosim.exe"; Description: "Launch PhotoSim"; Flags: nowait postinstall skipifsilent
