[Setup]
AppId={{A7B3C9E2-F4D1-4E6A-8A9F-B2C8D4E6F0A1}
AppName=LexoPlayer
AppVersion=1.0.0-beta.1
AppPublisher=Erfan Hooman
DefaultDirName={autopf}\LexoPlayer
DefaultGroupName=LexoPlayer
; Where to drop the finished single installation wizard .exe
OutputDir=C:\src\LexoPlayer\build\windows\installer
OutputBaseFilename=LexoPlayer-Setup-x64
; High-efficiency LZMA2 compression configurations
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

; --- FORCE LOGO ON THE INSTALLER WIZARD FILE ---
SetupIconFile=C:\src\LexoPlayer\windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 1. Main execution binary mapped directly to the x64 build Release directory
Source: "C:\src\LexoPlayer\build\windows\x64\runner\Release\lexo_player.exe"; DestDir: "{app}"; Flags: ignoreversion

; 2. All companion .dll links and asset data folders bundled right alongside it
Source: "C:\src\LexoPlayer\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; --- FORCE LOGO ON START MENU AND DESKTOP SHORTCUTS ---
Name: "{group}\LexoPlayer"; Filename: "{app}\lexo_player.exe"; IconFilename: "{app}\windows\runner\resources\app_icon.ico"
Name: "{autodesktop}\LexoPlayer"; Filename: "{app}\lexo_player.exe"; Tasks: desktopicon; IconFilename: "{app}\windows\runner\resources\app_icon.ico"

[Run]
Filename: "{app}\lexo_player.exe"; Description: "{cm:LaunchProgram,LexoPlayer}"; Flags: nowait postinstall skipifsilent