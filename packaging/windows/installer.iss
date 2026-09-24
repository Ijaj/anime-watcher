; Inno Setup script for Anime Watcher.
; Built by .github/workflows/release-windows.yml on windows-latest:
;   flutter build windows --release
;   iscc packaging\windows\installer.iss
; Produces dist\anime-watcher-setup_x64.exe.
;
; To build locally: install Flutter + Inno Setup 6 (https://jrsoftware.org/isinfo.php),
; run `flutter build windows --release` from the repo root, download
; https://aka.ms/vs/17/release/vc_redist.x64.exe into this folder, then run
; `iscc installer.iss` from packaging\windows.

#define AppName "Anime Watcher"
#define AppExeName "anime_watcher.exe"
#define AppVersion GetEnv("ANIME_WATCHER_VERSION")
#if AppVersion == ""
  #define AppVersion "1.0.0"
#endif
#define ReleaseDir "..\..\build\windows\x64\runner\Release"

[Setup]
; Fixed GUID so upgrades replace the previous install instead of side-by-side installing.
AppId={{9F2B6C2E-2F7B-4B7E-9C7C-8B0C7B9B5D31}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Anime Watcher
DefaultDirName={autopf}\Anime Watcher
DefaultGroupName=Anime Watcher
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=anime-watcher-setup_x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"

[Files]
; The whole flutter build output: exe, data\ (assets + engine), and the
; plugin DLLs (media_kit/mpv, sqlite3, etc. are already bundled here by
; their respective Flutter plugins at build time).
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

; Bundled only if present (downloaded by CI before ISCC runs); not required
; for a local build without it — the postinstall step below just skips.
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: dontcopy skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; Post-install: the Flutter Windows engine needs the VC++ runtime. Most
; up-to-date Windows 10/11 machines already have it; install it silently
; only if it's missing.
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing Microsoft Visual C++ Runtime..."; \
    Check: VCRedistNeedsInstall; Flags: waituntilterminated
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
function VCRedistNeedsInstall: Boolean;
var
  Installed: Cardinal;
begin
  // The VC++ 2015-2022 x64 runtime (all share major version 14) sets this
  // registry value once installed.
  Result := not (RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64', 'Installed', Installed) and (Installed = 1));
end;
