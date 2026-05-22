# Módulo **Chat** — revisão

> Documentação da revisão do módulo Chat do Money: correção do envio errado
> (LID), listagem de não lidas estilo WhatsApp, player de áudio embutido,
> visualizador de imagem, nome completo nos contatos, lista-primeiro em telas
> estreitas e botão de modelos na barra de digitação.
> Leia este doc antes de mexer no chat — economiza tokens em sessões futuras.

## 1. Visão geral

O Chat lê e escreve em `CONVERSAS` (Firebird), sincroniza periodicamente com a
Evolution API via `AutoReplyService` e exibe contatos + timeline numa janela
estilo WhatsApp. O que mudou nesta revisão:

| # | Tema | Onde |
|---|---|---|
| 1 | Envio para o número certo (resolução de `@lid`) | `auto_reply_service.dart` |
| 2 | Reprodução **dentro do app**: áudio + imagem em tela cheia | `chat_page.dart`, `pubspec.yaml` |
| 3 | Resposta só conta **após** o nosso envio | `database_service_io.dart` (já era a regra; foi reforçada e corrigida) |
| 4 | Contatos com **nome completo** importado da planilha | `database_service_io.dart::getChatContacts` |
| 5 | Em **telas estreitas**, módulo abre na lista de contatos | `chat_page.dart` (flag `_viewingConversation`) |
| 6 | Chat mostra também o que **nós enviamos** (sistema ou WhatsApp) | `database_service_io.dart::getChatContacts`, persistência de `fromMe` já existente |
| 7 | **Selo verde** com contagem de não lidas no card do cliente | tabela `CHAT_LEITURA` + `chat_page.dart` |
| 8 | Pendentes voltam a listar respostas | `database_service_io.dart::getPendingResponseClients` |
| 9 | Botão de **modelos** (papel) na barra de digitação | `chat_page.dart` |

## 2. Correção do envio errado — `@lid`

### Sintoma
- Mensagens iam para um **destinatário errado** (estranho com número parecido).
- Ou Evolution respondia **"destinatário não encontrado"**.

### Causa raiz
O WhatsApp passou a usar identificadores **opacos** (`@lid`) como `remoteJid`
em parte das conversas. O código tratava os dígitos do LID como se fossem
telefone:

```dart
final phone = PhoneUtils.normalize(remoteJid.replaceAll(RegExp(r'@.*'), ''));
```

- Quando o LID tinha tamanho de número brasileiro (10–13 dígitos pós-`55`),
  `_looksLikePhoneFallback` aceitava → envio ia para um número aleatório real.
- Quando ficava com 17 dígitos (LID 15-dígitos + `55`), Evolution rejeitava.

Pior: o **LID virava a chave da conversa** (`CONVERSAS.TELEFONE`) e o
**`DESTINO_ENVIO`**, contaminando linhas antigas.

### Correção
1. Novo `_extractConversationPhone(payload, remoteJid)` em
   [auto_reply_service.dart](../lib/data/datasources/auto_reply_service.dart) —
   resolve o telefone **real** numa ordem segura e **nunca** devolve LID:
   1. `remoteJid` que já seja `@s.whatsapp.net` / `@c.us` → telefone direto.
   2. Campos com o telefone real (`senderPn`, `remoteJidAlt`, `participant`…)
      — qualquer `@lid` é descartado por `_normalizeManualTarget`.
   3. `remoteJid` numérico **que não seja LID** e pareça telefone (10–15
      dígitos) → dígitos normalizados.
   4. Caso contrário → string vazia (a conversa **não** é indexada).

2. **Sync passa a indexar pelo telefone real.** Em `syncRecentConversations`
   e `_checkNewMessages`:
   ```dart
   final phone = _extractConversationPhone(chat, remoteJid);
   if (phone.isEmpty) continue;
   ```
   Auto-reply também ganha esse benefício: ele envia para `phone`.

3. **`_resolveSendTarget` usa o mesmo resolvedor**, então `DESTINO_ENVIO`
   nunca mais será um LID em registros novos.

4. **Envio manual prioriza descoberta autoritativa.**
   `_buildManualSendTargets` agora tenta na ordem:
   1. `_discoverRealPhoneForConversation(conversationKey)` — consulta
      `findChats`/`findMessages` ao vivo, casa pelo `remoteJid`/candidatos da
      conversa e devolve o telefone real (mesmo se a chave salva era um LID).
   2. `preferredTarget` (DESTINO_ENVIO salvo).
   3. `conversationKey` (telefone real, em registros novos).
   4. Telefone do cliente da planilha (`findClientPhoneCandidatesByName`).

   Isso corrige **inclusive conversas antigas** já gravadas com chave-LID, sem
   precisar re-sincronizar nem migrar dados.

### Dados antigos
Conversas que já estavam na lista com chave-LID continuam aparecendo como um
card "fantasma" (o card em si não some sozinho), mas o **envio** resolve o
número real via passo 1 acima. Ao chegar uma nova mensagem desse contato, ela
é gravada já indexada pelo telefone correto e a conversa aparece duplicada
(uma com a chave nova). Se isso incomodar no futuro, dá para escrever uma
limpeza única que migra/funde as linhas LID.

## 3. Persistência: tabelas e índices

### `CONVERSAS` (sem mudanças de schema)
A coluna `DIRECAO` tem três valores em uso:
- `recebida` — mensagem do cliente (sync da Evolution).
- `enviada_manual` — envio nosso pelo chat **ou** mensagem `fromMe` do próprio
  WhatsApp (também sincronizada).
- `enviada_auto` — resposta automática do auto-reply.

> Disparos em massa **não** ficam em `CONVERSAS`; vivem em `ENVIOS` (TIPO `massa`).
> A timeline (`getConversationTimeline`) faz `UNION ALL` entre as duas.

### Nova tabela `CHAT_LEITURA`
```sql
CREATE TABLE CHAT_LEITURA (
  TELEFONE VARCHAR(64) PRIMARY KEY,
  LIDA_EM  TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
)
```
Criada automaticamente em `_ensureSchema`. Cada linha guarda o timestamp em
que aquele chat foi aberto pela última vez. Usada para calcular `NAO_LIDAS`.

API: `DatabaseService.markChatRead(telefone)` faz `UPDATE OR INSERT` com `now`.
Chamada em `_ChatPageState._markContactRead` e implicitamente em `_loadMessages`
quando o contato selecionado tem `unreadCount > 0` (cobre auto-seleção no
desktop e toque explícito em telas estreitas).

## 4. `getChatContacts` — nome completo, não lidas, conversas só nossas

Mudanças no [`database_service_io.dart`](../lib/data/datasources/database_service_io.dart):

- **Critério de inclusão.** Antes: `WHERE C.DIRECAO = 'recebida'`. Agora:
  `WHERE 1 = 1` — qualquer conversa em que exista mensagem (recebida **ou**
  enviada por nós, manual/auto). Isso atende ao req 6: chat passa a listar
  também conversas iniciadas por nós (incluindo o que foi enviado pelo
  próprio WhatsApp e sincronizado como `enviada_manual`).
- **Nome completo (req 4).** A query retorna três candidatos:
  - `NOME_CLIENTE` — pushName do WhatsApp (geralmente primeiro nome).
  - `NOME_ENVIO` — `ENVIOS.NOME_CLIENTE` (nome completo da planilha; já era
    salvo em `sendBulkFromSpreadsheet`).
  - `NOME_CLIENTE_PLANILHA` — `CLIENTES.NOME`, casando por `TELEFONE` /
    `DDD || TELEFONE` / `'55' || DDD || TELEFONE`.

  Em Dart, `_pickFullerName` escolhe o que tem **mais palavras**, com fallback
  para o próprio telefone se nenhum nome existe. Resultado vai em `nome_cliente`.
- **Não lidas (req 7).** Coluna `NAO_LIDAS`:
  ```sql
  SELECT COUNT(*)
  FROM CONVERSAS CU
  WHERE CU.TELEFONE = C.TELEFONE
    AND CU.DIRECAO = 'recebida'
    AND CU.REGISTRADO_EM > COALESCE(
      (SELECT FIRST 1 LIDA_EM FROM CHAT_LEITURA WHERE TELEFONE = C.TELEFONE),
      TIMESTAMP '1900-01-01 00:00:00'
    )
    [AND CU.REGISTRADO_EM >= ?]   -- visibleFrom quando aplicável
  ```
  Abrir a conversa zera o selo (`markChatRead`).

## 5. `getPendingResponseClients` — voltou a listar (req 3, 8)

A regra continua sendo `lastIn > lastOut` (resposta posterior ao nosso envio).
O bug era que `LAST_OUT_ENVIO` comparava `E.TELEFONE_COMPLETO = C.TELEFONE`
**exato**, e essas duas colunas vinham de fontes diferentes:

- `ENVIOS.TELEFONE_COMPLETO` = `PhoneUtils.normalize(ddi + ddd + phone)` (vem
  da planilha — geralmente **com** o 9º dígito).
- `CONVERSAS.TELEFONE` = telefone derivado do `remoteJid` do WhatsApp (às
  vezes **sem** o 9º dígito, conforme o número).

Resultado: o último envio nosso "sumia" → `lastOut` ficava null → cliente era
descartado da lista.

**Correção:** o match agora aceita também igualdade de **últimos 8 dígitos**:

```sql
WHERE E.SUCESSO = 1
  AND ( E.TELEFONE_COMPLETO = C.TELEFONE
        OR RIGHT(E.TELEFONE_COMPLETO, 8) = RIGHT(C.TELEFONE, 8) )
```

Aplicado em `LAST_OUT_ENVIO` **e** no subselect `NOME_ENVIO` (para o nome
completo no card). Trade-off aceitável: dois contatos diferentes com mesmos 8
dígitos finais é teoricamente possível, na prática raríssimo e o lastOut só
serve como filtro temporal.

## 6. UI — `chat_page.dart`

### 6.1. Lista-primeiro em telas estreitas (req 5)
Novo `bool _viewingConversation` no estado. No `LayoutBuilder`:

```dart
if (!isDesktop && _selectedContact != null && _viewingConversation) {
  return _buildConversationPane(isDesktop: false);
}
```

- `_selectContact` (toque do usuário) → `_viewingConversation = true`.
- Botão "voltar" → `_viewingConversation = false` + `_selectedContact = null`.
- Auto-seleção do primeiro contato (que existia para o desktop) **não** abre
  conversa em narrow porque `_viewingConversation` permanece `false`.

### 6.2. Selo verde de não lidas (req 7)
- `_ChatContact` ganhou `unreadCount` (lido de `nao_lidas` na query).
- `_UnreadBadge` desenha o círculo verde `#25D366` com a contagem
  (`99+` quando > 99).
- Time da última interação fica verde quando há não lidas.
- Ao abrir a conversa, `_markContactRead` chama `DatabaseService.markChatRead`
  e atualiza a UI local (`copyWithRead`) sem precisar re-buscar do banco.

### 6.3. Visualizador de imagem (parte do req 2)
Imagem no balão fica clicável (`GestureDetector`) — abre `showDialog`
fullscreen com:
- `InteractiveViewer` (zoom + pan, scale 0.8–5×).
- `Image.memory` quando há bytes locais; `Image.network` quando só há
  `mediaUrl`.
- Botão `X` flutuante para fechar.

Sem dependência extra (`InteractiveViewer` é do framework). Os bytes da
imagem recebida já são baixados em `_prepareIncomingPayloadForStorage`.

### 6.4. Player de áudio embutido (parte do req 2)
- Nova widget `_AudioMessagePlayer` (StatefulWidget) usando **`audioplayers`**.
- Resolução da fonte:
  - Se `payload.hasFileBytes` → grava `Uint8List` em arquivo temporário
    (`path_provider.getTemporaryDirectory`) e usa `DeviceFileSource(path)` —
    caminho confiável no Windows.
    Extensão deduzida do `mimetype`/`fileName`; default `.ogg` (formato comum
    do WhatsApp).
  - Senão, se há `mediaUrl` → `UrlSource(url)`.
- UI: play/pause, slider de posição, `mm:ss / mm:ss`, ícone `mic`. Estado
  reage a `onDurationChanged`, `onPositionChanged`, `onPlayerStateChanged`,
  `onPlayerComplete` (resseta posição).
- `dispose` cancela todas as subscriptions e libera o `AudioPlayer`.

### 6.5. Botão de modelos (req 9)
Ícone `Icons.description_rounded` ("papel") foi adicionado **dentro** do mesmo
"InputSurface" arredondado, antes do clipe de anexo. Habilitado quando há
contato selecionado.

`_showTemplatePicker` abre um `showModalBottomSheet` listando os modelos:

- **Pré-definidos:** importa `predefinedTemplatesList` de
  `template_viewmodel.dart` (mesmos templates da aba Campanhas).
- **Salvos no banco:** `DatabaseService.listarModelos()` (tabela
  `MODELOS_MENSAGEM`).

Ao escolher um modelo, `_applyTemplate` renderiza os tokens via
`TemplateEngine.render` com `TemplateVariableData(nome: _firstName(contact.name))`
(token `{NOME}` recebe só o primeiro nome; demais tokens vazios). As mensagens
do modelo são unidas com `\n\n` e **inseridas no campo de digitação** — o
usuário revisa/edita e dispara com o botão de enviar normal. Isso evita
disparar várias mensagens automaticamente "às cegas".

## 7. Envio manual — ordem de tentativa

Em `AutoReplyService.sendManualChatMessage`:

```
markAsManuallyAnswered(phone)   # remove da fila do auto-reply
targets = _buildManualSendTargets(...)
for target in targets:
  sendPresence(composing)
  _sendManualPayload(target, payload)   # text|media|location
  _storeConversationPayload(direcao='enviada_manual')
  return
# se todos falharem → throw lastError → toast no chat_page
```

`_buildManualSendTargets` (já citado em §2):

1. `_discoverRealPhoneForConversation` — autoritativo.
2. `preferredTarget` (DESTINO_ENVIO salvo).
3. `conversationKey` (telefone real após a correção de LID).
4. `findClientPhoneCandidatesByName(contactName)`.

Como o discovery vem primeiro, o caminho comum hoje é uma chamada de rede a
`findChats`. É a contrapartida pela correção de LID (que precisa da view ao
vivo). Se for um problema de performance, dá para cachear o `chats` por
alguns segundos — ainda não foi feito.

## 8. Dependências adicionadas

Em [pubspec.yaml](../pubspec.yaml):

```yaml
audioplayers: ^6.1.0
path_provider: ^2.1.4
```

- `audioplayers` traz `audioplayers_windows` como plugin nativo — é
  registrado automaticamente no próximo `flutter run`/`build` (Windows
  desktop). `flutter pub get` já foi executado.
- `path_provider` é usado só para `getTemporaryDirectory` (gravar o áudio).

## 9. Avisos para quem continuar

- **`@lid` é hostil.** Nunca trate `remoteJid` como número sem antes passar
  por `_extractConversationPhone`. Qualquer novo caminho que envie pra
  Evolution deve usar `_discoverRealPhoneForConversation` ou um campo já
  resolvido (`_resolveSendTarget`).
- **`PhoneUtils.normalize` continua simplista.** Ele só garante prefixo `55`;
  não normaliza 9º dígito. Por isso o match de pendentes usa `RIGHT(…, 8)`.
  Se um dia formos canonicalizar (com/sem 9º), revisitar
  `getPendingResponseClients` e a comparação em `getChatContacts`.
- **CHAT_LEITURA cresce indefinidamente** (uma linha por telefone que já foi
  aberto). É leve, mas se a base ficar gigante, dá para limpar linhas mais
  antigas que `visibleFrom`.
- **Players de mídia precisam de build.** `flutter analyze` não exercita o
  plugin nativo do `audioplayers`. Rode `flutter run -d windows` ao menos uma
  vez após esta mudança.
- **Sync persiste mídia.** `_prepareIncomingPayloadForStorage` baixa os bytes
  de imagens/áudios/documentos recebidos. Isso pode inflar `CONVERSAS.ARQUIVO_DADOS`.
  Hoje é o que viabiliza tocar áudio e ver imagem offline; se virar problema
  de espaço, mover para arquivos no disco e guardar só o path.
