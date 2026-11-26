; ReveriePaint Windows 安装包（Inno Setup 6）
; 用法：iscc reveriepaint.iss
; 前置：先跑 04-stage-portable.ps1 生成 ..\dist\ReveriePaint

#define MyAppName "ReveriePaint"
#define MyAppVersion "1.9.0-win1"
#define MyAppPublisher "ReveriePaint"
#define MyAppExeName "bin\krita.exe"
#ifndef DistDir
  ; 默认认为 dist 与 installer 同级（windows\dist\ReveriePaint）；
  ; CI 或本地可用 iscc /DDistDir=C:\krita-dev\dist\ReveriePaint 覆盖
  #define DistDir "..\dist\ReveriePaint"
#endif

[Setup]
AppId={{8C1C7A52-6B4E-4E5C-9C0B-1A2B3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\out
OutputBaseFilename=ReveriePaint-{#MyAppVersion}-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\..\LICENSE
; 覆盖安装时不要动用户资源目录（%APPDATA%\krita）

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务"
Name: "associatekra"; Description: "关联 .kra 文件"; GroupDescription: "附加任务"; Flags: unchecked

[Files]
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\ReveriePaint.cmd"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\ReveriePaint.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\ReveriePaint.Document"; ValueType: string; ValueName: ""; ValueData: "Krita 文档"; Flags: uninsdeletekey; Tasks: associatekra
Root: HKA; Subkey: "Software\Classes\ReveriePaint.Document\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\bin\krita.exe,0"; Tasks: associatekra
Root: HKA; Subkey: "Software\Classes\ReveriePaint.Document\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\bin\krita.exe"" ""%1"""; Tasks: associatekra
Root: HKA; Subkey: "Software\Classes\.kra"; ValueType: string; ValueName: ""; ValueData: "ReveriePaint.Document"; Flags: uninsdeletevalue; Tasks: associatekra

[Run]
Filename: "{app}\ReveriePaint.cmd"; Description: "立即启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
