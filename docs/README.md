# Documentação do Money

Índice das features implementadas. Leia o doc relevante **antes** de explorar o
código — eles foram escritos para acelerar sessões futuras e economizar tokens.

## Mapa rápido

| Doc | Tema | Principais arquivos |
|---|---|---|
| [login-autenticacao.md](login-autenticacao.md) | Login/cadastro na abertura, token de admin, seed de usuário padrão | `auth_viewmodel.dart`, `login_page.dart`, `database_service_io.dart` (tabela `USUARIOS`), `app.dart` |
| [clientes-pendentes.md](clientes-pendentes.md) | Campanha com retorno: ouvir Evolution, card "Clientes Pendentes", responder em lote; nome completo na exibição; detecção de colunas da planilha | `pending_clients_viewmodel.dart`, `pending_clients_card.dart`, `auto_reply_service.dart`, `spreadsheet_service.dart`, `template_viewmodel.dart` |
| [chat-modulo.md](chat-modulo.md) | Chat: resolução de `@lid` no envio, listagem com não lidas (selo verde), nome completo, lista-primeiro em telas estreitas, visualizador de imagem + player de áudio embutidos, botão de modelos na barra de digitação | `chat_page.dart`, `auto_reply_service.dart`, `database_service_io.dart` (tabela `CHAT_LEITURA`) |
| [google-docs-modulo.md](google-docs-modulo.md) | Login Google (OAuth desktop), gestão de planilhas do Drive e uso no envio em massa | `google_auth_service.dart`, `google_drive_service.dart`, `google_viewmodel.dart`, `google_docs_page.dart` |

## Ordem de carregamento do app (alto nível)

1. `main.dart` inicializa banco (Firebird), controllers e `MultiProvider`.
2. `app.dart` mostra **LoginPage** se não autenticado; senão **MainLayout**.
3. `MainLayout` tem a navbar: Visão Geral, Campanhas, Chat, **Google**, Conexão,
   Configurações.

## Resumo do que mudou neste ciclo

### 1. Clientes Pendentes (campanha com retorno)
- `AutoReplyService` já faz polling da Evolution e persiste mensagens recebidas
  em `CONVERSAS` (mesmo com auto-reply desligado) — base do recurso.
- `DatabaseService.getPendingResponseClients()` calcula quem respondeu depois do
  nosso último envio (`lastIn > lastOut`).
- Card **"Clientes Pendentes"** na tela inicial → modal de 2 seções: seleção de
  modelo + lista de clientes (seleção manual ou por gênero).

### 2. Filtro de gênero não oculta
- Em **ambos** os pontos (envios e clientes pendentes), escolher
  Homens/Mulheres apenas **marca** os do gênero — todos os nomes seguem
  visíveis, permitindo corrigir classificações erradas.

### 3. Nome completo na exibição, primeiro nome no envio
- `ServerData.nomeCompleto` + capitalização; UI mostra completo, token `{NOME}`
  e gênero usam só o primeiro nome.

### 4. Planilhas: detecção de colunas independente de ordem + benefícios
- `SpreadsheetService` reconhece colunas de valor por nome em qualquer posição,
  incluindo produtos de benefício (`D…VEMCARD - CARTAO BENEFICIO …`).
- Cobertura: `test/data/datasources/spreadsheet_service_test.dart`.

### 5. Módulo Google (Drive/Sheets)
- Nova seção "Google" na navbar; OAuth desktop com persistência de credenciais;
  listagem das planilhas; uso direto no envio em massa
  (`TemplateViewModel.loadFromRows`).

### 6. Login de usuários
- Tela de login na abertura; cadastro com token de administrador; tabela
  `USUARIOS` com hash de senha (salt + SHA-256); seed de usuário/admin padrão
  em toda geração do banco; logout no menu do topo.

### 7. Chat — revisão completa
Detalhes em [chat-modulo.md](chat-modulo.md). Pontos-chave:
- **`@lid` resolvido no envio.** Novo `_extractConversationPhone` /
  `_discoverRealPhoneForConversation` em `auto_reply_service.dart` —
  conversas passam a ser indexadas pelo telefone real, e o envio manual
  descobre o número autoritativo via `findChats` mesmo para conversas antigas
  gravadas com chave-LID. Corrige "envio para número errado" e
  "destinatário não encontrado".
- **Não lidas (estilo WhatsApp).** Nova tabela `CHAT_LEITURA` + coluna
  `NAO_LIDAS` em `getChatContacts` + selo verde `_UnreadBadge` no card.
- **Nome completo no contato.** `getChatContacts` agora cruza `CONVERSAS`,
  `ENVIOS` e `CLIENTES` e escolhe o nome com mais palavras
  (`_pickFullerName`).
- **`getChatContacts` lista também conversas sem mensagem recebida** (chat
  passa a mostrar o que enviamos pelo sistema **ou** pelo próprio WhatsApp,
  já sincronizado como `enviada_manual`).
- **Pendentes voltam a listar.** `getPendingResponseClients` casa o nosso
  último envio por `RIGHT(…, 8)` para absorver diferenças de 9º
  dígito/DDI entre `ENVIOS.TELEFONE_COMPLETO` e `CONVERSAS.TELEFONE`.
- **Tela estreita abre na lista de contatos** (flag
  `_viewingConversation`).
- **Mídia tocando no app.** `_AudioMessagePlayer` (audioplayers + arquivo
  temporário via path_provider) e visualizador de imagem em tela cheia com
  `InteractiveViewer`.
- **Botão de modelos (papel)** ao lado da digitação: carrega templates
  pré-definidos + `MODELOS_MENSAGEM`, renderiza tokens com o nome do contato
  e insere no campo para revisão antes do envio.

## Dependências adicionadas no ciclo

`googleapis`, `googleapis_auth`, `http`, `url_launcher`, `crypto`,
`audioplayers`, `path_provider`.

## Avisos para quem continuar

- **Desktop-first:** Firebird e OAuth loopback não funcionam na web.
- **Verificação:** features que dependem de Firebird/OAuth/WhatsApp foram
  validadas por `flutter analyze` + testes de unidade do parser, não em runtime.
- **Gênero é heurístico:** nunca ocultar por gênero; sempre permitir override.
