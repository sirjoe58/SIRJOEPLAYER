; Installer di SirJoe Player per Windows (Inno Setup 6)
#define AppVersion GetEnv("APP_VERSION")

[Setup]
AppId={{6E2B7C1A-4F3D-4C55-9B7E-5A1D2F8C9E10}
AppName=SirJoe Player
AppVersion={#AppVersion}
AppPublisher=SirJoe
DefaultDirName={autopf}\SirJoe Player
DefaultGroupName=SirJoe Player
UninstallDisplayIcon={app}\sirjoe_player.exe
OutputDir=..\dist
OutputBaseFilename=SirJoePlayer-Setup-Windows
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
WizardStyle=modern

[Languages]
Name: "italian"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktopicon"; Description: "Crea un'icona sul desktop"; GroupDescription: "Icone:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SirJoe Player"; Filename: "{app}\sirjoe_player.exe"
Name: "{group}\Disinstalla SirJoe Player"; Filename: "{uninstallexe}"
Name: "{autodesktop}\SirJoe Player"; Filename: "{app}\sirjoe_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\sirjoe_player.exe"; Description: "Avvia SirJoe Player"; Flags: nowait postinstall skipifsilent
