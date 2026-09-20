# Conformidade com as regras da Meta e do Google — varredura de 20/09/2026

Pedido do Guilherme: "tudo que existe no nosso sistema respeite as regras do
META e do GOOGLE — faça uma varredura antes de subir". Varredura feita no
código do fork (só leitura, arquivo:linha na sessão), com correções aplicadas
na mesma rodada. Regras citadas pelo nome; onde não há código, está dito.

## Resumo

| Ponto | Situação antes | Agora |
|---|---|---|
| WhatsApp ativo fora de 24 h só com template aprovado | ✅ | ✅ |
| Opt-out ("PARE") | ❌ inexistente; campanha e régua não excluíam `nao_perturbe` | ✅ `Crm::OptOut`: filtro FIXO em campanha, régua (e campanha de ligação, que herda o público) + detector de PARE/SAIR/não quero mais no `CrmListener` (aplica `nao_perturbe` e deixa nota) |
| Categoria do template (marketing × utility) | ⚠️ não validada | ⚠️ pendente (item 180) |
| Teto global de mensagens por paciente/dia | ⚠️ só por motor | ⚠️ pendente (item 180) |
| Calling API: permissão pela API oficial | ✅ | ✅ |
| Calling API: 1 pedido/24 h e 2/7 dias | ❌ sem trava local | ✅ trava no `OutboundService` (histórico no contato) |
| Calling API: horário comercial na ligação manual | ❌ | ✅ `hours_error` no `initiate` |
| Calling API: 4 não atendidas → revogação / 100 chamadas por destinatário | ⚠️ | ⚠️ pendente (item 180) |
| Insights da Meta só da própria conta, agregados | ✅ | ✅ |
| Retenção/expurgo de `cevico_ad_insights`/criativos/miniaturas | ⚠️ sem expurgo | ⚠️ pendente (item 180) |
| Escopo do token documentado (`ads_management` a mais) | ⚠️ | ⚠️ pendente (só `ads_read` basta) |
| CTWA: só dados de referral do próprio negócio | ✅ | ✅ (janela do `ctwa_clid` pendente) |
| Conversions API: SHA-256 + normalização | ✅ | ✅ |
| Conversions API: `test_event_code` em produção | ❌ | ✅ só fora de produção (ou `CEVICO_META_TEST_EVENTS=1`) |
| Conversions API: `event_id` estável / dedup com o Pixel | ⚠️ | ⚠️ pendente |
| GA4 Measurement Protocol com nome e telefone em texto puro | ❌ | ✅ removidos — só o id interno |
| Instagram: respostas via API oficial, sem duplicar | ✅ | ✅ |
| Instagram: agente negava ser IA / persona com nome de pessoa | ❌ | ✅ agora "assistente virtual da CEVICO", responde com honestidade |
| Instagram: teto diário de respostas a comentários | ⚠️ | ⚠️ pendente |
| Google: GA4 Data API só leitura; sem Google Ads API (RMF não se aplica); sem raspagem | ✅ | ✅ |
| Páginas públicas: Pixel/GA4/GTM sem banner de consentimento | ❌ | 🔶 DECISÃO DELE (texto legal + design do banner + Consent Mode v2) |
| Pixel com dado pessoal sem hash | ✅ não envia | ✅ |
| Segredos nas respostas da API / logs | ✅ | ✅ |
| Segredos em texto puro no banco (`CrmSetting`: token da Meta, chave privada da service account do Google, senhas) | ❌ | 🔶 DECISÃO DELE (`encrypts` exige chaves de criptografia no ambiente + backup antes) |
| Token da Meta na query string | ⚠️ | ⚠️ pendente (usar `Authorization: Bearer`) |

## O que foi corrigido nesta rodada (código)

- `app/services/google_ads_conversions_service.rb` — GA4 recebe só `contact_id`.
- `app/services/meta_ads_conversions_service.rb` — `test_event_code` só fora de produção.
- `app/services/crm/opt_out.rb` (novo) + `Crm::Campaign#resolve_audience` +
  `Crm::MessageAutomation#eligible_contacts` + `CrmListener#handle_opt_out`.
  Spec `spec/services/crm/opt_out_spec.rb`.
- `app/services/crm/calls/outbound_service.rb` — limites de pedido de
  permissão (24 h / 7 dias) e horário comercial na ligação manual.
- `app/services/crm/instagram_agent_service.rb` e `comments_agent_service.rb`
  — identificação como assistente virtual.

## Decisões que ficam com o Guilherme

1. **Criptografar os segredos do `CrmSetting`** (token da Meta, `api_secret`,
   `developer_token`, `service_account_json`, `n8n_api_key`, senha do
   Oftalmofácil). Precisa de `ACTIVE_RECORD_ENCRYPTION_*` no EasyPanel e
   backup antes. Enquanto isso: restringir quem acessa o banco/backup.
2. **Banner de consentimento de cookies + Consent Mode v2** nas landings
   (Pixel só depois do aceite). É LGPD + regra do Google para tags; muda a
   experiência das páginas — precisa do texto e do design aprovados.

## Pendências menores (item 180 no BACKLOG)

Categoria do template gravada/validada; teto global por paciente/dia;
`event_id` = Protocolo no servidor e no Pixel; purga de insights/criativos e
janela do `ctwa_clid`; escopo `ads_read` na instrução do token; token no
header; contador de 4 não atendidas; teto diário do respondedor de
comentários (e filtrar o próprio usuário no Instagram); aviso de gravação no
pedido de permissão de ligação; aviso de privacidade nos formulários.
