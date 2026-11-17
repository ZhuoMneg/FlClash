[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}
CloseApplications=yes
RestartApplications=no

[Code]
const
  SYNCHRONIZE = $00100000;
  WAIT_OBJECT_0 = 0;
  ERROR_INVALID_PARAMETER = 87;
  GENERIC_WRITE = $40000000;
  OPEN_EXISTING = 3;
  ServiceKey = 'SYSTEM\CurrentControlSet\Services\FlClashHelperService';

function OpenProcess(dwDesiredAccess: DWORD; bInheritHandle: BOOL; dwProcessId: DWORD): THandle;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(hHandle: THandle; dwMilliseconds: DWORD): DWORD;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(hObject: THandle): BOOL;
  external 'CloseHandle@kernel32.dll stdcall';
function GetLastError: DWORD;
  external 'GetLastError@kernel32.dll stdcall';
function CreateFile(lpFileName: String; dwDesiredAccess, dwShareMode: DWORD;
  lpSecurityAttributes: LongWord; dwCreationDisposition, dwFlagsAndAttributes: DWORD;
  hTemplateFile: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';

// The app passes /updatefrom=<pid> (windowsUpdateArguments in lib/common)
// and exits on its own, stopping the Core and clearing the system proxy.
function UpdatingAppPid: Integer;
begin
  Result := StrToIntDef(ExpandConstant('{param:updatefrom|0}'), 0);
end;

function IsAppUpdate: Boolean;
begin
  Result := UpdatingAppPid > 0;
end;

function WaitForUpdatingApp: Boolean;
var
  Handle: THandle;
begin
  Result := True;
  if not IsAppUpdate then
    Exit;
  Handle := OpenProcess(SYNCHRONIZE, False, UpdatingAppPid);
  if Handle = 0 then
  begin
    Result := GetLastError = ERROR_INVALID_PARAMETER;
    Exit;
  end;
  Result := WaitForSingleObject(Handle, 15000) = WAIT_OBJECT_0;
  CloseHandle(Handle);
end;

function UnregisterHelperService: Boolean;
var
  HelperPath, ImagePath: String;
  ResultCode: Integer;
begin
  Result := True;
  if not RegKeyExists(HKLM, ServiceKey) then Exit;
  if not RegQueryStringValue(HKLM, ServiceKey, 'ImagePath', ImagePath) then
  begin
    Result := False;
    Exit;
  end;
  HelperPath := ExpandConstant('{app}\FlClashHelperService.exe');
  ImagePath := Lowercase(Trim(ImagePath));
  HelperPath := Lowercase(HelperPath);
  if (Pos('"' + HelperPath + '"', ImagePath) <> 1) and
     (ImagePath <> HelperPath) and (Pos(HelperPath + ' ', ImagePath) <> 1) then Exit;
  Result := FileExists(HelperPath) and
    Exec(HelperPath, 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if Result then Result := ResultCode = 0;
end;

function InstalledAppClosed: Boolean;
var
  AppPath: String;
  Handle: THandle;
begin
  AppPath := ExpandConstant('{app}\{{EXECUTABLE_NAME}}');
  Result := not FileExists(AppPath);
  if Result then Exit;
  Handle := CreateFile(AppPath, GENERIC_WRITE, 0, 0, OPEN_EXISTING, 0, 0);
  Result := Handle <> THandle(-1);
  if Result then CloseHandle(Handle);
end;

procedure ClearStaleProxy;
var
  AppPath: String;
  ResultCode: Integer;
begin
  AppPath := ExpandConstant('{app}\\{{EXECUTABLE_NAME}}');
  if FileExists(AppPath) then
  begin
    Exec(AppPath, '--clear-stale-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function PointsIntoApp(Value: String): Boolean;
begin
  Result := Pos(Lowercase(AddBackslash(ExpandConstant('{app}'))), Lowercase(Value)) > 0;
end;

// The value name is appName and the schemes are protocolSchemes, both in
// lib/common.
procedure RemoveUserRegistrations;
var
  Schemes: TArrayOfString;
  Value: String;
  i: Integer;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{{APP_NAME}}', Value) and PointsIntoApp(Value) then
  begin
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{{APP_NAME}}');
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', '{{APP_NAME}}');
  end;

  Schemes := ['clash', 'clashmeta', 'flclash'];
  for i := 0 to GetArrayLength(Schemes)-1 do
  begin
    if RegQueryStringValue(HKCU, 'Software\Classes\' + Schemes[i] + '\shell\open\command', '', Value) and PointsIntoApp(Value) then
    begin
      RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\' + Schemes[i]);
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not WaitForUpdatingApp then
    Result := CustomMessage('UpdateAppStillRunning');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    if not InstalledAppClosed then
      RaiseException(CustomMessage('CloseAppFirst'));
    if not UnregisterHelperService then
      RaiseException(CustomMessage('HelperStopFailed'));
  end;
  if CurStep = ssPostInstall then
  begin
    ClearStaleProxy;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := InstalledAppClosed;
  if not Result then
    MsgBox(CustomMessage('CloseAppFirst'), mbError, MB_OK)
  else begin
    Result := UnregisterHelperService;
    if not Result then
      MsgBox(CustomMessage('HelperStopFailed'), mbError, MB_OK)
    else
      ClearStaleProxy;
  end;
end;

// path_provider names these folders after CompanyName and ProductName in
// windows/runner/Runner.rc.
procedure RemoveUserData;
begin
  DelTree(ExpandConstant('{userappdata}\com.follow\clash'), True, True, True);
  DelTree(ExpandConstant('{localappdata}\com.follow\clash'), True, True, True);
  RemoveDir(ExpandConstant('{userappdata}\com.follow'));
  RemoveDir(ExpandConstant('{localappdata}\com.follow'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveUserRegistrations;
    if not UninstallSilent and (MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
    begin
      RemoveUserData;
    end;
  end;
end;

[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[CustomMessages]
english.RemoveUserData=Also delete your profiles and settings?
english.UpdateAppStillRunning=FlClash did not exit. Close it and try again.
chineseSimplified.UpdateAppStillRunning=FlClash 尚未退出。请关闭后重试。
english.CloseAppFirst=Close FlClash and try again.
chineseSimplified.CloseAppFirst=请关闭 FlClash 后重试。
english.HelperStopFailed=Could not stop the FlClash helper service.
chineseSimplified.HelperStopFailed=无法停止 FlClash 辅助服务。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait; Check: IsAppUpdate
