# Campanha com Retorno — "Clientes Pendentes"

> Documentação da feature de **resposta a disparos**: ouvir a Evolution, detectar
> clientes que responderam e respondê-los em lote pela tela inicial.
> Escrita para acelerar sessões futuras e economizar tokens — leia esta seção
> antes de explorar o código.

## 1. Visão geral do produto

Fluxo de campanha:

1. O usuário importa uma planilha e dispara mensagens em massa (aba **Campanhas → Disparo em Massa**).
2. O sistema **fica ouvindo a Evolution** para saber se algum cliente respondeu.
3. Quem responde (e ainda não foi respondido por nós) vira um **cliente pendente**.
4. Na **tela inicial (Visão Geral)** aparece o card **"Clientes Pendentes"**.
5. O botão **"Ver"** abre um modal com **2 seções**:
   - **Seção 1 — Modelo de envio:** escolha de qual modelo será disparado agora.
   - **Seção 2 — Clientes que responderam:** lista com seleção manual ou por gênero (Homens/Mulheres/Todos).
6. Ao confirmar, o modelo escolhido é enviado para os selecionados. Eles saem da lista automaticamente assim que respondidos.

### Regra de gênero (importante)

Em **ambos** os pontos de seleção por gênero (filtro da aba de envios **e** seção
de clientes pendentes), escolher *Homens* ou *Mulheres* **não oculta** os demais.
Todos os nomes continuam visíveis; apenas os do gênero escolhido ficam **marcados**.
Motivo: a inferência de gênero é heurística (por terminação do nome) e pode errar —
o usuário precisa enxergar todos para corrigir manualmente os checkboxes.

## 2. Arquitetura (MVVM + Provider)

- **Camada de dados:** `EvolutionApiService` (HTTP via Dio) + `DatabaseService` (Firebird, `database_service_io.dart`; stub web em `database_service_web.dart`).
- **Listening:** `AutoReplyService` (`lib/data/datasources/auto_reply_service.dart`) já faz polling da Evolution a cada 15s em `_checkNewMessages()`, persistindo mensagens recebidas na tabela `CONVERSAS` com `DIRECAO='recebida'`. **Isso roda mesmo com o auto-reply desligado** (a persistência ocorre antes do chece de `_autoReplyEnabled`). É a fonte de "ouvir a Evolution".
- **ViewModels:** `ChangeNotifier` registrados em `lib/main.dart` via `MultiProvider`.
- **UI:** páginas em `lib/presentation/views/`, widgets em `lib/presentation/widgets/`.

## 3. Como o "pendente" é calculado

Tabelas relevantes (Firebird):

- `ENVIOS` — tentativas de disparo (`TELEFONE_COMPLETO`, `SUCESSO`, `TIPO`, `ENVIADO_EM`, `NOME_CLIENTE`).
- `CONVERSAS` — timeline de mensagens (`TELEFONE`, `DIRECAO` ∈ {`recebida`, `enviada_manual`, `enviada_auto`}, `CONTEUDO`, `DESTINO_ENVIO`, `REGISTRADO_EM`).

Método: `DatabaseService.getPendingResponseClients()` (em `database_service_io.dart`).

Critério de pendência (avaliado em Dart sobre o resultado agrupado por telefone):

```
lastIn  = max(REGISTRADO_EM) onde DIRECAO = 'recebida'
lastOut = max(
            max(REGISTRADO_EM) em CONVERSAS onde DIRECAO in ('enviada_manual','enviada_auto'),
            max(ENVIADO_EM)    em ENVIOS    onde SUCESSO = 1
          )

pendente  ⇔  lastOut != null  E  lastIn > lastOut
```

- `lastOut != null` garante que houve um envio nosso (é resposta a campanha, não contato espontâneo).
- `lastIn > lastOut` garante que a última palavra foi do cliente (a bola está com a gente).
- Depois que respondemos (via `enviada_manual`), `lastOut` passa a ser mais recente → o cliente **sai da lista** no próximo carregamento. Não há flag de "respondido" para manter.

O gênero **não** vem do banco nesse SELECT (o telefone normalizado de `CONVERSAS`
não casa trivialmente com `CLIENTES.TELEFONE`+`DDD`). Ele é derivado do nome via
`GenderUtils.fromName()` na ViewModel — consistente com o resto do app.

## 4. Arquivos criados

| Arquivo | Papel |
|---|---|
| `lib/core/utils/gender_utils.dart` | Heurística de gênero compartilhada (`resolve`, `fromName`). Centraliza lógica antes duplicada. |
| `lib/data/models/pending_client.dart` | Modelo `PendingClient` (phone, sendTarget, name, genero, lastMessage, lastReceivedAt, isSelected). |
| `lib/presentation/viewmodels/pending_clients_viewmodel.dart` | `PendingClientsViewModel` + `MessageModelOption`. Carrega pendentes e modelos, seleção por gênero, envio em lote. |
| `lib/presentation/widgets/pending_clients_card.dart` | `PendingClientsCard` (card da Visão Geral) + modal interno de 2 seções. |
| `docs/clientes-pendentes.md` | Este documento. |

## 5. Arquivos alterados

| Arquivo | Mudança |
|---|---|
| `lib/data/datasources/database_service_io.dart` | Novo método `getPendingResponseClients({visibleFrom})`. |
| `lib/data/datasources/database_service_web.dart` | Stub do mesmo método (retorna `[]`). |
| `lib/data/datasources/spreadsheet_service.dart` | `_resolveGenero` agora delega para `GenderUtils.resolve`. |
| `lib/presentation/viewmodels/template_viewmodel.dart` | Gênero deixou de ocultar em `_applyFilters`; `setGenderFilter` virou **seleção** (marca o gênero escolhido, mantém todos visíveis). |
| `lib/main.dart` | Registro do `PendingClientsViewModel` no `MultiProvider`. |
| `lib/presentation/views/overview_page.dart` | `PendingClientsCard` inserido no topo da Visão Geral. |

## 6. Fluxo de envio da resposta

`PendingClientsViewModel.sendToSelected()`:

1. Resolve o `MessageModelOption` selecionado (modelos vêm de `db.listarModelos()` + `predefinedTemplatesList`).
2. Para cada cliente marcado, renderiza cada mensagem não-vazia com `TemplateEngine.render` usando `TemplateVariableData(nome, banco)` (token `{BANCO}` opcional via campo no modal; `{PARC*}` ficam vazios pois não há contexto de parcelas na resposta).
3. Envia via `AutoReplyService.sendManualChatMessage(...)`, que:
   - resolve o destino (usa `sendTarget` salvo ou descobre pelo chat),
   - dispara presença "digitando", envia o texto, persiste como `enviada_manual`,
   - chama `markAsManuallyAnswered` (remove da fila de auto-reply).
4. Mensagens encadeadas do mesmo contato têm ~700ms de respiro entre si.
5. Ao final, recarrega a lista de pendentes (respondidos somem).

## 7. Pontos de atenção / decisões

- **Sem nova flag de estado:** "respondido" é inferido pela timeline, evitando dessincronização. Não criar coluna `RESPONDIDO`.
- **Gênero heurístico:** nunca tratar como verdade absoluta. UI sempre permite override manual. Não filtrar/ocultar por gênero em lugar nenhum.
- **Refresh:** o card carrega na montagem e ao abrir o modal; dentro do modal há botão de atualizar. Não há auto-refresh enquanto aberto (mantido simples).
- **Web:** Firebird indisponível → `getPendingResponseClients` retorna `[]`. A feature é efetivamente desktop.
- **Reuso:** preferir `AutoReplyService.sendManualChatMessage` para qualquer envio de resposta — ele já cuida de presença, destino e persistência.

## 7.1. Nome completo na exibição (envio mantém 1º nome)

Regra: a interface mostra o **nome completo** dos clientes (gestão), mas a
**mensagem enviada usa apenas o primeiro nome** (token `{NOME}`).

- `ServerData` ganhou o campo `nomeCompleto` (capitalizado palavra a palavra
  por `SpreadsheetService._formatFullName`). `nome` continua sendo só o primeiro
  nome — fonte do token `{NOME}` e da inferência de gênero.
- A lista de contatos (`campaigns_page._ContactRow`) e o avatar usam `nomeCompleto`.
- Persistência de gestão: `upsertCliente` (CLIENTES.NOME) e `registrarEnvio`
  (ENVIOS.NOME_CLIENTE) gravam `nomeCompleto`. O conteúdo da mensagem (`renderedMsgs`)
  continua vindo de `payloadData.nome` = primeiro nome.
- Clientes pendentes: `getPendingResponseClients` escolhe o nome **mais completo**
  entre o pushName das conversas e o NOME_CLIENTE do envio (`_pickFullerName`).
  No `PendingClientsViewModel`, gênero e token usam `_firstName(name)` — o
  sobrenome distorceria a heurística por terminação (ex.: "João Silva" → 'a').

## 7.2. Detecção de colunas da planilha (ordem-independente)

`SpreadsheetService.parseRows` localiza colunas **pelo nome do cabeçalho**, então
a **ordem das colunas não importa**. Acentos são normalizados antes da comparação.

Colunas de identificação reconhecidas: `DDD`, `TELEFONE`/`TELEFONE 2`/`CELULAR`/
`WHATSAPP`, `CPF`, `NOME SERVIDOR`, `CARGO PRINCIPAL` (ou `VÍNCULO PRINCIPAL`),
`MUNICÍPIO LOTAÇÃO`, `IDADE` (ou `DATA NASCIMENTO`), `SEXO`.

Colunas de **valor** (parcelas/produtos) — duas estratégias combinadas:

1. **Layout largo** (`_findWideLoanColumns` → `_isLoanProductHeader`): uma coluna por
   produto. Reconhece, em qualquer posição:
   - código de produto no início do cabeçalho: regex `^[A-Z]?\d{3,}[A-Z]`
     (ex.: `D900685VEMCARD - CARTAO BENEFICIO - SAQUE - LEI 22.449`);
   - palavras-chave: `EMPRESTIMO`/`EMPREST`, `CONSIGN`, `REFIN`, `PORTABIL`, `VEMCARD`.

   Por ser específico, **não** aplica a exclusão genérica de `_isNeverLoanValueHeader`
   (que descartaria "CARTAO BENEFICIO"). A letra final exigida no regex evita
   capturar colunas puramente numéricas (ex.: um ano "2024").

2. **Layout linha** (`_findRowLoanValueColumns`): uma linha por produto, valor em
   colunas genéricas `TOTAL`/`VALOR`/`VLR`/`PARCELA`, com a coluna `PRODUTO`
   validando a linha (`_isLoanProductRow`). Colunas já contadas no layout largo
   são removidas para não duplicar valores.

De cada contato, os valores `> 100` são ordenados decrescente e os **5 maiores**
viram as parcelas (`{PARC1}`..`{PARC5}`). Contato sem nenhum valor válido é pulado.

> Mudança importante: antes, o layout largo só procurava colunas **depois** dos
> telefones e só reconhecia o termo `EMPREST`. Agora a detecção é por nome
> (qualquer posição) e inclui produtos de benefício (VEMCARD/código de produto).
> Cobertura em `test/data/datasources/spreadsheet_service_test.dart`.

## 8. Como verificar

1. Importar planilha e disparar para alguns números reais.
2. Responder de um WhatsApp cliente. Em até ~15s, `AutoReplyService` persiste `recebida`.
3. Tela inicial: card "Clientes Pendentes" mostra a contagem; "Ver" abre o modal.
4. Escolher modelo, selecionar por gênero (confirmar que todos seguem visíveis) e responder.
5. O cliente respondido some da lista após o envio.
