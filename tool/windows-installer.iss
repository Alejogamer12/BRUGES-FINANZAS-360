#define ProductName "BRUGES FINANZAS 360"
#define ProductVersion "1.3.0"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{0A7A2BA5-DF4A-4CF9-A8DF-8C532E360360}
AppName={#ProductName}
AppVersion={#ProductVersion}
AppPublisher=BRUGES
DefaultDirName={localappdata}\Programs\Bruges\Finanzas360
DefaultGroupName={#ProductName}
OutputDir=..\BRUGES-FINANZAS-360-INSTALADORES
OutputBaseFilename=BRUGES-FINANZAS-360-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\bruges_finanzas_360.exe

[Tasks]
Name: "desktopicon"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#ProductName}"; Filename: "{app}\bruges_finanzas_360.exe"
Name: "{autodesktop}\{#ProductName}"; Filename: "{app}\bruges_finanzas_360.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\bruges_finanzas_360.exe"; Description: "Iniciar {#ProductName}"; Flags: postinstall nowait skipifsilent
