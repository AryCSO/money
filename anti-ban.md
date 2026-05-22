# Guia Anti-Ban — Disparo em Massa com Evolution API / Baileys

> Pesquisa consolidada (maio/2026) sobre práticas para reduzir risco de banimento
> em automações de WhatsApp via APIs **não-oficiais** (Evolution API + Baileys).
> O foco é o stack deste projeto (`money`) — Flutter + Evolution API v2 — mas a maior
> parte das recomendações vale para qualquer cliente Baileys.

---

## 1. Por que o WhatsApp bane

O WhatsApp usa **Machine Learning + heurísticas** para detectar não-humanos. Os sinais
mais fortes que disparam ban são, em ordem de gravidade:

| Sinal | Peso | Como o WhatsApp detecta |
|---|---|---|
| **Reports / blocks dos destinatários** | ★★★★★ | Mais de ~5% bloqueando = quase certo o ban |
| **Mensagens idênticas em massa** | ★★★★★ | Fingerprint/hash do conteúdo |
| **Envio para números fora da agenda (não-salvos)** | ★★★★☆ | Sinaliza "número estranho" |
| **Razão envio/recebimento desbalanceada** | ★★★★☆ | 1000 enviadas e 0 respostas = spam |
| **Volume súbito (chip novo subindo rápido)** | ★★★★☆ | Volume vs. idade da conta |
| **Janelas de envio 24h** | ★★★☆☆ | Humano dorme |
| **Intervalos uniformes (delay fixo)** | ★★★☆☆ | Sem variação = bot |
| **Login frequente / troca de IP/proxy** | ★★★☆☆ | Sessão instável |
| **Links e mídia logo na 1ª mensagem** | ★★★☆☆ | Padrão de phishing |
| **Sem foto / nome / status no perfil** | ★★☆☆☆ | Conta "vazia" parece descartável |
| **`checkWhatsApp` em loop** | ★★☆☆☆ | Validar muitos números rápido = scraping |

> **Regra de ouro:** o bot precisa parecer um humano com 50+ contatos, perfil completo,
> que conversa de verdade. Tudo abaixo é instrumental para essa ilusão.

---

## 2. Warm-up de chip novo (obrigatório)

Chip novo **NUNCA** deve disparar em massa. Plano mínimo de 10 dias antes do
primeiro disparo real (compilação das fontes whapi.cloud, green-api, wadesk,
wasenderapi):

### Dia 0 — Setup
- SIM real (não eSIM virtual, evitar VoIP/Twilio descartáveis)
- Aguardar **24 h** após registrar antes de conectar à API
- Foto de perfil real, nome humano, "sobre", status com texto
- Adicionar **20–50 contatos reais** na agenda do telefone (e ser adicionado por eles)
- Enviar 1–2 mensagens manuais pelo celular para contatos conhecidos

### Dias 1–3 — Conversas humanas
- 3–6 conversas privadas iniciadas **pelo celular**, não pela API
- Pela API: enviar **poucas mensagens variadas** para contatos salvos que respondem
- Troca de figurinhas/imagens/áudios para diversificar payload
- Receber tantas mensagens quanto envia (razão ~1:1)

### Dias 4–7 — Rampa lenta
- **1 mensagem a cada 2 horas** (regra green-api)
- Subir de ~12 para ~50 mensagens/dia gradualmente
- Entrar em 1–2 grupos ativos
- Manter < **2 mensagens por minuto**, < **6 horas/dia**, **não 3 dias seguidos** sem pausa

### Dias 8–14 — Consolidação
- Subir 20% a cada 2 dias até ~100–150 mensagens/dia
- Continuar variando conteúdo
- Manter taxa de resposta ≥ 30–50%

### Dias 15–30
- Mantém volume estável
- A partir do dia 25–30 o WhatsApp considera o número "estabelecido"

> **Bandeira vermelha:** se a conta ficou amarela/vermelha no warm-up, **PARE**
> imediatamente o outbound por 24–48 h e diminua o volume pela metade ao reiniciar.

---

## 3. Limites de volume (conta já estabelecida)

| Período | Conservador | Moderado | Agressivo (alto risco) |
|---|---|---|---|
| Por hora | 20–30 | 50–80 | 150+ |
| Por dia | 80–200 | 300–500 | 800+ |
| Por minuto | 1 | 2 | 4 |

**Recomendação para este projeto:** comece em **conservador** e ajuste conforme a
taxa de resposta. A regra do green-api (200/dia, mínimo 500 ms entre mensagens) é
um teto seguro para chip não-verificado.

### Pausas estruturais
- A cada **50 mensagens**: pausa de **10–15 min** (simula "café")
- Não enviar das **22h às 8h** (fuso do destinatário)
- 1 dia da semana com volume reduzido a 30%
- Evitar disparos em finais de semana inteiros sem nenhuma atividade humana

---

## 4. Padrão de delays (jitter)

**Delay fixo é fingerprint de bot.** Use **jitter** (variação randômica).

| Tipo | Mínimo | Máximo | Distribuição |
|---|---|---|---|
| Entre mensagens do MESMO destinatário | 800 ms | 2500 ms | uniforme |
| Entre destinatários consecutivos | **15 s** | **45 s** | uniforme ou normal |
| "Pausa café" a cada 50 envios | 10 min | 15 min | uniforme |
| Erro de rede / 429 / 5xx | exponencial | — | 2^n com cap em 5 min |

> O código atual em [template_viewmodel.dart:686-695](lib/presentation/viewmodels/template_viewmodel.dart#L686-L695)
> já faz isso: `safeMin + Random().nextInt(...)` + `Random().nextInt(1000)` em ms.
> **Bom.** Sugestão: garantir que `minIntervalController` default seja **≥ 15 s**.

### Presence (digitando…) antes de enviar
Humano não envia 100 ms depois de "abrir" o chat. Fluxo correto:

```
1. sendPresence(composing)        // já existe em EvolutionApiService.sendPresence
2. delay aleatório 1.5–4 s        // simula digitação proporcional ao tamanho do texto
3. sendText(...)                  // envia
4. sendPresence(paused/available) // opcional, mas mais realista
```

Regra de ouro para o delay de digitação: **~50–80 ms por caractere**, com mínimo
de 1.5 s e máximo de 8 s. Para uma mensagem de 200 chars: ~10–16 s digitando.

> ⚠️ Não chame `sendPresence` mais de **1× a cada 5–10 s** por chat — chamadas em
> loop a cada 100 ms são marcadas como "Abusive Behavior" pelo Baileys.
> A "composing" expira sozinha após ~10 s.

---

## 5. Variação de conteúdo (anti-fingerprint)

Mensagens **idênticas para 500 pessoas = ban garantido**. O WhatsApp gera hash do
conteúdo e cruza com volume de reports.

### Técnicas

#### 5.1 Personalização obrigatória
Sempre incluir pelo menos 2 variáveis dinâmicas: `{{nome}}`, `{{banco}}`, `{{cargo}}`,
`{{parcelas}}`. Este projeto já tem `TemplateEngine` — **use sempre**.

#### 5.2 Spintax
Em vez de uma única mensagem, defina variações entre chaves:

```
{Olá|Oi|Bom dia} {{nome}}, {tudo bem?|como vai?|tudo certo?}
{Tenho|Posso te enviar} uma {proposta|condição especial} {pra você|que pode interessar}.
```

A cada envio, escolher uma combinação aleatória. Com 3 opções em 4 pontos,
são 81 variantes — virtualmente impossível dois destinatários receberem o mesmo
texto.

> Esse projeto já permite **múltiplos templates** (`templateControllers` em
> [template_viewmodel.dart](lib/presentation/viewmodels/template_viewmodel.dart)).
> **Próximo passo:** adicionar suporte a spintax dentro de cada template no
> `TemplateEngine`.

#### 5.3 Variar metadados invisíveis
- Espaços não-quebráveis intercalados
- Trocar entre `:)` / `🙂` / `:-)`
- Pontuação variável (`.` vs `!` vs nada)
- Reordenar parágrafos quando o sentido permitir

#### 5.4 Quebra de mensagem
Em vez de 1 mensagem longa, mandar 2–3 curtas em sequência (com delay entre elas).
É o que humanos fazem.

#### 5.5 Mídia
Anexar imagem **com hash único** (re-comprimir/redimensionar levemente cada vez)
ajuda a evitar batch detection. Cuidado: mídia na **1ª** mensagem é red flag —
mande texto primeiro, mídia só após resposta.

---

## 6. Configurações da Evolution API (Baileys)

Ao chamar `POST /instance/create` ou `POST /settings/set/{instance}`, configurar:

```json
{
  "rejectCall": true,
  "msgCall": "Olá, no momento não consigo atender. Pode mandar mensagem aqui mesmo?",
  "groupsIgnore": true,
  "alwaysOnline": false,
  "readMessages": true,
  "readStatus": false,
  "syncFullHistory": false
}
```

### Justificativa por flag

| Flag | Valor | Por quê |
|---|---|---|
| `rejectCall` | `true` | Robôs não atendem chamadas. Receber sem responder é flag. Rejeitar com `msgCall` simula humano "ocupado" |
| `groupsIgnore` | `true` | Você não quer processar/responder grupos sem querer (spam de auto-reply em grupo = ban) |
| `alwaysOnline` | `false` | Ficar online 24/7 é **anti-humano**. Deixe Baileys gerenciar presença naturalmente |
| `readMessages` | `true` | Marcar como lido sinaliza engajamento mútuo |
| `readStatus` | `false` | Não visualizar status alheio em massa (parece scraper) |
| `syncFullHistory` | `false` | Sincronizar histórico antigo gera tráfego anômalo na conexão |

### Onde aplicar no projeto
Modifique [evolution_api_service.dart:21-29](lib/data/datasources/evolution_api_service.dart#L21-L29)
no `createMoneyInstance()` para já enviar os settings junto, ou adicione um método
`applyAntiBanSettings()` que chame `POST /settings/set/{instance}` após o pareamento.

---

## 7. Comportamentos do código atual a melhorar

Checklist concreto para este repositório:

### ✅ Já implementado
- [x] Delay aleatório entre destinatários (`Random().nextInt`) em [template_viewmodel.dart:690](lib/presentation/viewmodels/template_viewmodel.dart#L690)
- [x] Presence `composing` em [evolution_api_service.dart:127](lib/data/datasources/evolution_api_service.dart#L127)
- [x] `linkPreview: false` em `sendText` ([evolution_api_service.dart:178](lib/data/datasources/evolution_api_service.dart#L178)) — bom, link preview é assinatura de bot
- [x] `defaultPresenceDelayMs: 1200` em `app_constants.dart`
- [x] Guarda anti-duplicidade (`enforceDuplicateGuard: true`)
- [x] Múltiplos templates por campanha

### ⚠️ A ajustar
- [ ] **Aumentar default do `minIntervalController`** de "1" para **15 s** (atual valida `< 1`, mas precisa ser confortável por padrão)
- [ ] **Aplicar `applyAntiBanSettings()`** logo após `createMoneyInstance()` setando `rejectCall=true`, `groupsIgnore=true`
- [ ] **Implementar spintax** no `TemplateEngine` (parser de `{a|b|c}`)
- [ ] **Pausa-café automática:** a cada 50 envios, dormir 10–15 min (random)
- [ ] **Janela horária:** bloquear envio fora do horário 8h–22h do fuso local; opção UI para forçar
- [ ] **Delay de digitação proporcional:** `delayDigitando = clamp(textoChars * 60ms, 1500, 8000)` em vez do fixo `1200`
- [ ] **Detector de "queda de qualidade":** monitorar % de erros/`statusCode` 4xx em uma janela móvel; se > 10%, pausar automaticamente
- [ ] **Backoff exponencial** em `sendText` ao receber 429/5xx (hoje propaga direto)
- [ ] **Não usar `findChats` com `limit: 2000`** ([evolution_api_service.dart:361](lib/data/datasources/evolution_api_service.dart#L361)) durante disparos ativos — gera tráfego suspeito; paginar em lotes de 100–200

### 🚀 Recursos novos sugeridos
1. **Modo "warm-up"** na UI: força volume diário máximo configurável (50, 80, 150, 300)
2. **Painel de saúde** que mostra:
   - Taxa de resposta dos últimos 7 dias
   - Razão envio/recebimento
   - % de erros recentes
   - Sugestão automática: "REDUZA" / "OK" / "PODE SUBIR"
3. **Lista de números "queimados"** — se um destinatário gerou erro de bloqueio, não tentar de novo
4. **Modo "trabalho" vs "pausa"** com auto-resume respeitando horário comercial
5. **Diversificador automático**: se >70% das mensagens da fila são similares (Levenshtein), avisar o usuário e forçar variação

---

## 8. Regras de conteúdo (texto da mensagem)

Mesmo com técnica perfeita, se o conteúdo é "spammy", banem. Evitar:

- ❌ **Tudo CAIXA ALTA**
- ❌ Muitas chamadas a ação ("CLIQUE AGORA!!! ÚLTIMA CHANCE!!!")
- ❌ Encurtadores (bit.ly, encurtador.com.br) — preferir URL inteira de domínio próprio
- ❌ Múltiplos `!` ou `?` seguidos
- ❌ Emojis em excesso (>5 por mensagem)
- ❌ Mensagem só com link, sem contexto
- ❌ Palavras-gatilho de fraude: "grátis", "ganhou", "premiação", "urgente", "selecionado", "pix imediato"
- ❌ Anexar imagem antes de qualquer interação

### ✅ Boas práticas de texto
- Cumprimento personalizado com nome
- Apresentação ("Sou X da empresa Y")
- Frase de contexto/permissão ("Vi que você buscava Z")
- **Opt-out claro**: "Responda PARAR para não receber mais"
- CTA sutil em forma de pergunta ("Posso te explicar mais?")
- Total 200–500 caracteres (não muito curto, não muito longo)

---

## 9. Sinais de monitoramento (alerta precoce)

Antes do ban, geralmente há pistas. Detectá-las e parar **salva o número**:

| Sintoma | Significado | Ação |
|---|---|---|
| Status passa a "yellow" no Business Manager | Reports começando | Parar marketing outbound 24h |
| Status "red" | Pré-ban | PARAR TUDO 48h+ |
| Erro 429 da Evolution API | Rate limit do próprio servidor | Backoff exponencial |
| Mensagens ficam "pending" / não entregues | Possível shadowban | Pausar 12h |
| Pareamento (QR) começa a falhar | Conta marcada | Não tentar reconectar em loop — espera 24h |
| Taxa de erro > 10% em 30 envios | Lista ruim ou conta marcada | Pausar e revisar lista |

> **Implementar** um listener desses sintomas em `EvolutionApiService` e expor para
> o `OverviewViewModel` mostrar no dashboard.

---

## 10. Higiene de lista

Lista ruim = ban rápido. Antes de importar a planilha:

- Remover números obviamente inválidos (menos de 10 dígitos sem DDI)
- **Não comprar listas** — 15–40% são números mortos, garantia de ban
- Conferir DDI/DDD coerentes com a região do chip (chip BR enviando p/ DDIs aleatórios = suspeito)
- Antes do disparo, opcionalmente validar `checkWhatsApp` em **lote pequeno e devagar** (não 1000 em 1 minuto)
- Pular automaticamente quem já recebeu nas últimas 24h (já existe `enforceDuplicateGuard`)

---

## 11. Infraestrutura

- **IP/proxy estável:** não trocar de IP entre sessões; se usar proxy residencial, fixe um por chip
- **VPS consistente:** chip usado de SP não pode logar de Singapura
- **Não rodar múltiplas instâncias do mesmo chip simultaneamente**
- **Sessão persistente:** evitar login/logout — guardar `creds.json` corretamente (já é responsabilidade da Evolution API)
- **1 chip = 1 finalidade:** não misturar marketing + atendimento + grupos no mesmo número

---

## 12. Plano de ação prioritário para este projeto

Ordem recomendada para implementar (do mais barato/maior impacto):

1. **Setar `rejectCall`/`groupsIgnore` após criar instância** — 15 min, alto impacto
2. **Aumentar default de `minInterval`/`maxInterval` para 15–45 s na UI** — 5 min
3. **Pausa-café a cada 50 envios** — 30 min em [template_viewmodel.dart](lib/presentation/viewmodels/template_viewmodel.dart)
4. **Janela horária 8h–22h** com toggle — 30 min
5. **Spintax no `TemplateEngine`** — 1–2 h
6. **Delay de digitação proporcional ao tamanho do texto** — 20 min
7. **Backoff exponencial em `sendText`** ao receber 429/5xx — 30 min
8. **Painel de saúde** (taxa de resposta, % erros) — 2–3 h
9. **Modo warm-up com teto diário configurável** — 1 h

---

## Fontes

Pesquisa baseada nos seguintes recursos (maio/2026):

- [WhatsApp Messaging Limits 2026 — Chatarmin](https://chatarmin.com/en/blog/whats-app-messaging-limits)
- [Protect Your Number from Ban — GREEN API](https://green-api.com/en/docs/faq/how-to-protect-number-from-ban/)
- [Warming Up New Phone Numbers for WhatsApp API — Whapi.cloud](https://support.whapi.cloud/help-desk/blocking/warming-up-new-phone-numbers-for-whatsapp-api)
- [WhatsApp Anti-Ban Strategy for Unofficial APIs — WasenderAPI](https://wasenderapi.com/blog/stop-getting-banned-the-ultimate-whatsapp-anti-ban-strategy-for-unofficial-apis-in-2025)
- [Avoid Banned WhatsApp Number — Hypersender](https://hypersender.com/en/blog/avoid-banned-whatsapp-number)
- [Presence and Receipts — Baileys Wiki](https://baileys.wiki/docs/socket/presence-receipts/)
- [Evolution API — Create Instance Reference](https://doc.evolution-api.com/v2/api-reference/instance-controller/create-instance-basic)
- [COMPILADO Melhores práticas ANTI-BAN — Issue #1946 Evolution API](https://github.com/EvolutionAPI/evolution-api/issues/1946)
- [WhatsApp Business Policy](https://business.whatsapp.com/policy)
- [About account bans — WhatsApp FAQ](https://faq.whatsapp.com/465883178708358)
