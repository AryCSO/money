# Módulo Google (Drive / Planilhas)

> Login OAuth com o Google, gestão das planilhas do usuário e uso dessas
> planilhas diretamente no envio em massa — sem baixar arquivos manualmente.
> Documento para acelerar sessões futuras e economizar tokens.

## 1. Visão geral do produto

1. Nova seção **"Google"** na navbar (entre *Chat* e *Conexão*).
2. Na primeira vez, o usuário cola as credenciais OAuth (Client ID/Secret de um
   cliente "App para computador" do Google Cloud). Ficam salvas no computador.
3. Botão **"Conectar com Google"** abre o navegador para consentimento OAuth.
4. Após o login, a página lista **todas as planilhas** do Drive do usuário
   (Google Sheets nativas + arquivos `.xlsx`).
5. Na aba **Campanhas → Disparo em Massa**, a seção de seleção de planilha passa
   a listar também as planilhas do Google. Tocar em uma carrega seus dados no
   mesmo pipeline do upload local (parser + filtros + anti-repetição).

## 2. Pré-requisitos (Google Cloud Console)

Para o login funcionar, o usuário precisa, uma única vez:

1. Criar um projeto no Google Cloud Console.
2. Habilitar **Google Drive API** e **Google Sheets API**.
3. Criar credenciais **OAuth client ID** do tipo **"App para computador"**
   (Desktop app). Isso gera Client ID + Client Secret.
4. Na tela de consentimento OAuth, adicionar o usuário como *test user* (ou
   publicar o app) e os escopos de leitura do Drive/Sheets.
5. Colar Client ID/Secret na seção "Google" do app.

O fluxo usa **loopback** (`http://localhost:<porta>`), aceito automaticamente
por clientes do tipo Desktop — não é preciso registrar redirect URI.

## 3. Arquitetura

| Camada | Arquivo | Papel |
|---|---|---|
| Config | `lib/core/config/google_config_controller.dart` | Persiste Client ID/Secret (SharedPreferences). |
| Serviço (auth) | `lib/data/datasources/google_auth_service.dart` | OAuth desktop (`googleapis_auth`): `signIn`/`restore`/`signOut`; persiste `AccessCredentials` (inclui refresh token). |
| Serviço (dados) | `lib/data/datasources/google_drive_service.dart` | Lista planilhas (Drive API) e lê linhas (Sheets API ou decode de `.xlsx`). |
| Modelo | `lib/data/models/google_spreadsheet_file.dart` | `GoogleSpreadsheetFile` (id, name, isNativeSheet, modifiedTime). |
| ViewModel | `lib/presentation/viewmodels/google_viewmodel.dart` | Estado: conectado, e-mail, lista de arquivos, busy/erro; `connect`/`disconnect`/`refreshFiles`/`fetchRows`. |
| UI | `lib/presentation/views/google_docs_page.dart` | Login + configuração de credenciais + gestão de planilhas. |
| UI (integração) | `campaigns_page.dart` → `_GoogleSheetsPicker` | Lista as planilhas do Google na seleção do envio em massa. |

### Dependências adicionadas (`pubspec.yaml`)

`googleapis`, `googleapis_auth`, `http`, `url_launcher`.

### Escopos OAuth (`GoogleAuthService.scopes`)

- `email`
- `DriveApi.driveReadonlyScope`
- `SheetsApi.spreadsheetsReadonlyScope`

## 4. Fluxo de autenticação

- **Login** (`signIn`): `clientViaUserConsent(ClientId, scopes, prompt)` sobe o
  servidor de loopback e chama `prompt(url)`, que abre o navegador via
  `launchUrl(..., LaunchMode.externalApplication)`. Ao consentir, recebemos um
  `AutoRefreshingAuthClient`; persistimos `client.credentials` e ouvimos
  `client.credentialUpdates` para regravar a cada refresh.
- **Restore** (`restore`): na inicialização, se há credenciais salvas com
  `refreshToken`, reconstruímos via `autoRefreshingClient(ClientId, creds, http.Client())`.
  Não abre navegador.
- **Persistência**: `AccessCredentials` serializado como JSON em
  SharedPreferences (`google.credentials`): type/data/expiry do `AccessToken`,
  `refreshToken`, `idToken`, `scopes`. O `expiry` é restaurado em UTC
  (exigência do `AccessToken`).

## 5. Leitura das planilhas

`GoogleDriveService.fetchRows(file)` retorna `List<List<dynamic>>` no formato que
`SpreadsheetService.parseRows` já consome:

- **Google Sheets nativo**: `spreadsheets.get` para descobrir o título da 1ª aba,
  depois `spreadsheets.values.get(spreadsheetId, titulo)`.
- **`.xlsx` no Drive**: download via `files.get(..., downloadOptions: fullMedia)`,
  bytes decodificados com `SpreadsheetDecoder` (mesma lib do upload local).

## 6. Integração no envio em massa

- `TemplateViewModel.loadFromRows(rows, fileName)` (novo) ingere linhas já lidas,
  reaproveitando o parser em isolate (`_parseRowsInIsolate`) e o
  pós-processamento comum extraído para `_finalizeLoadedSpreadsheet` (cidades,
  reset de filtros, marcação de já-enviados, `_applyFilters`, feedback).
  O upload local (`pickAndLoadSpreadsheet`) agora também usa esse finalize.
- `_GoogleSheetsPicker` (em `campaigns_page.dart`) faz
  `googleVm.fetchRows(file)` → `templateVm.loadFromRows(rows, file.name)`.
  A partir daí o fluxo (filtros de idade/cidade/gênero, seleção, disparo,
  anti-ban, clientes pendentes) é idêntico ao de uma planilha local.

## 7. Navegação

`NavSection.googleDocs` adicionado ao enum em `app_sidebar.dart` (item "Google",
ícone `cloud_rounded`), com título/subtítulo e `case` no `_buildPage` de
`main_layout.dart`. Providers (`GoogleConfigController`, `GoogleViewModel`)
registrados em `main.dart`; `GoogleViewModel.initialize()` tenta reconectar no
arranque.

## 8. Pontos de atenção

- **Desktop-first**: o fluxo loopback é para Windows/macOS/Linux. Em web seria
  necessário o fluxo implícito do `google_identity_services_web` (não implementado).
- **Credenciais do usuário**: não há Client ID/Secret embutido no app — cada
  usuário usa o seu projeto Google Cloud. Isso evita segredos hardcoded e limites
  de quota compartilhados.
- **Somente leitura**: escopos `*.readonly`. O app não modifica planilhas.
- **Reuso do parser**: planilhas do Google passam exatamente pelo mesmo
  `SpreadsheetService` — inclusive a detecção de colunas independente de ordem e
  os produtos de benefício (VEMCARD etc.) documentados em
  `clientes-pendentes.md` (seção 7.2).
- **Não testável offline**: o OAuth real exige credenciais e navegador; a
  verificação aqui foi por análise estática + testes de unidade do parser.

## 9. Como verificar

1. Criar credenciais OAuth Desktop no Google Cloud (seção 2) e colá-las em "Google".
2. "Conectar com Google" → consentir no navegador → a página lista as planilhas.
3. Em Campanhas → Disparo em Massa, abrir "Planilhas do Google", tocar numa
   planilha e confirmar que os contatos carregam com os filtros normais.
