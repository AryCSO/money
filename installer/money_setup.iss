#ifndef APP_BUILD_DIR
#define APP_BUILD_DIR "..\build\windows\x64\runner\Debug"
#endif

[Setup]
AppId={{F8E9C27D-07B2-4F20-AC26-DA4B15996FD8}
AppName=Money
AppVersion=1.0.0
AppPublisher=Money
DefaultDirName=C:\money
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=Money_Installer
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=..\windows\runner\resources\app_icon.ico

[Languages]
Name: "portuguesebrazilian"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Types]
Name: "completo"; Description: "Instalacao completa (Money + Docker + Evolution + ngrok)"
Name: "personalizado"; Description: "Escolher o que instalar"; Flags: iscustom

[Components]
Name: "money"; Description: "Aplicativo Money"; Types: completo personalizado
Name: "docker"; Description: "Docker Engine + Docker Compose"; Types: completo personalizado
Name: "evolution"; Description: "Evolution API (requer Docker ativo)"; Types: completo personalizado
Name: "ngrok"; Description: "ngrok + tunnel automatico"; Types: completo personalizado

[Files]
Source: "{#APP_BUILD_DIR}\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs ignoreversion; Components: money
Source: "..\setup_money_env.bat"; DestDir: "{app}"; Flags: ignoreversion; Components: docker,evolution,ngrok
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Money"; Filename: "{app}\app\money.exe"; Components: money
Name: "{group}\Configurar Ambiente (Docker + API + ngrok)"; Filename: "{app}\setup_money_env.bat"; Check: ShouldRunInfraSetup
Name: "{autodesktop}\Money"; Filename: "{app}\app\money.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Area de Trabalho"; GroupDescription: "Atalhos:"; Components: money

[Run]
Filename: "{app}\setup_money_env.bat"; Parameters: """{app}"" ""{code:GetNgrokToken}"" ""{code:GetInstallDocker}"" ""{code:GetInstallEvolution}"" ""{code:GetInstallNgrok}"""; Description: "Configurar ambiente selecionado (Docker/Evolution/ngrok)"; Flags: postinstall waituntilterminated; Check: ShouldRunInfraSetup
Filename: "{app}\app\money.exe"; Description: "Abrir o Money agora"; Flags: nowait postinstall skipifsilent; Check: WizardIsComponentSelected('money')

[Code]
var
  NgrokPage: TInputQueryWizardPage;

procedure InitializeWizard;
begin
  NgrokPage :=
    CreateInputQueryPage(
      wpSelectComponents,
      'Credenciais ngrok',
      'Informe seu token ngrok',
      'Cole o authtoken da sua conta ngrok. Se deixar vazio, voce pode configurar depois no setup_money_env.bat.'
    );
  NgrokPage.Add('Ngrok authtoken:', False);
end;

function GetNgrokToken(Value: string): string;
begin
  Result := Trim(NgrokPage.Values[0]);
  if Result = '' then
    Result := 'COLE_SEU_TOKEN_NGROK_AQUI';
end;

function GetInstallDocker(Value: string): string;
begin
  if WizardIsComponentSelected('docker') then
    Result := '1'
  else
    Result := '0';
end;

function GetInstallEvolution(Value: string): string;
begin
  if WizardIsComponentSelected('evolution') then
    Result := '1'
  else
    Result := '0';
end;

function GetInstallNgrok(Value: string): string;
begin
  if WizardIsComponentSelected('ngrok') then
    Result := '1'
  else
    Result := '0';
end;

function ShouldRunInfraSetup: Boolean;
begin
  Result :=
    WizardIsComponentSelected('docker') or
    WizardIsComponentSelected('evolution') or
    WizardIsComponentSelected('ngrok');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;

  if (PageID = NgrokPage.ID) and (not WizardIsComponentSelected('ngrok')) then
    Result := True;
end;
