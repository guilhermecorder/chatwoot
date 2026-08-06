# SISTEMA CORINGA — segmentos de mercado

O sistema deixou de ser "de clínica oftalmológica" e virou um **coringa**:
o conteúdo específico de cada mercado (terminologia, profissionais,
unidades, agenda, preços, prompts dos robôs) mora num **pacote de
segmento** editável — e a **clínica oftalmológica é a pré-seleção de
fábrica**: sem configurar nada, a CEVICO continua exatamente como sempre foi.

## Como funciona

```
config/brands/<marca>.yml  →  segmento: clinica | empresa | <novo>
config/segmentos/<id>.yml  →  o pacote com todo o conteúdo do mercado
lib/segmento.rb            →  Segmento.termo / .profissionais / .prompt ...
window.SEGMENTO            →  o mesmo pacote no navegador (vueapp.html.erb)
helper/segmento.js         →  termo() / frase() / meta() no Vue
```

A escolha do segmento (por prioridade):
1. `SEGMENTO=<id>` no ambiente da VPS (força na mão);
2. `segmento:` no yml da marca (`cevico.yml` → **clinica**, `life.yml` → **empresa**);
3. sem nada → **clinica** (a pré-seleção).

## O que o pacote de segmento controla

| Bloco | O que é | Quem consome |
|---|---|---|
| `termos` / `frases` | paciente→cliente, médico→profissional, "Nova consulta"→"Novo atendimento"… | telas Vue (Agenda, Início, Espaço do Cliente, Sidebar, dashboards) e textos do backend |
| `profissionais` | os "médicos" da casa (nome, apelido, cor, grafias toleradas) | Agenda, filtros, DoctorNames (backend), dashboards |
| `unidades` | agendas paralelas (key + nome + cor) — **key nunca muda depois de ter dados** | Agenda, dashboards, robôs, mensagens de atividade |
| `janelas_padrao` | grade semanal inicial (editável na tela "Janelas dos profissionais") | Agenda (frontend) + AgendaSlots (backend/robôs) |
| `modalidades` / `problemas` / `procedimentos` | tipos de atendimento, motivos e o que se vende | Agenda, conferência do dia, Espaço do Cliente |
| `precos` | tabela de preços de fábrica (editável em Configurações → Tabela de preços) | Espaço do Cliente + prompts (`{{TABELA_DE_PRECOS}}`) |
| `metas` / `paineis` | meta do mês e nomes dos donos dos painéis do Início | Meu Painel |
| `jornada` / `pilares` / `indicadores*` / `*_categorias` | Painel Estratégico, Metas, Financeiro e Estoque | controllers/models |
| `prompts` / `guardrails` / `contexto` | os robôs de IA falando a língua do negócio | todos os agentes (Crm::AiAgentConfig) |

## Prompts dos robôs — ordem de escolha

`prompt custom da conta (UI) > prompt do segmento (yml) > chumbado no serviço`

O chumbado **É** o preset da clínica (por isso `clinica.yml` não tem
`prompts:` — fonte única, sem divergência). O `empresa.yml` traz versões
genéricas de negócio para: conversation_insight, instagram_agent,
appointment_extraction, sales_coach (+ insights), opportunity_radar,
comments_agent, surgery_closing, nps, form_insight, objection_map e
weekly_mentor.

Placeholders disponíveis em qualquer prompt:
- `{{TABELA_DE_PRECOS}}` — tabela oficial da conta (ou padrão do segmento);
- `{{CONTEXTO_DO_NEGOCIO}}` — descrição do negócio (`ai_config['business_context']`
  da conta, senão `contexto:` do segmento);
- `{{NOME_DA_EMPRESA}}` — nome da instalação (pacote de marca).

## Personalização pelo ADMIN (sem código)

**Configurações → Personalização** (menu do admin): edita por conta —
profissionais (nome, apelido, cor, grafias), unidades, motivos do
atendimento, opções de indicação/venda, meta do mês e o **contexto do
negócio** dos robôs. Salvo em `crm_settings.agenda_config['segment']`
(+ `ai_config['business_context']`); resolução em todo lugar:
**conta > segmento > preset clínica**. "Restaurar padrão do segmento"
apaga os ajustes da conta. Também por conta (telas que já existiam):
tabela de preços, janelas da agenda e prompts por agente.

O que ainda é só por segmento (yml): terminologia (termos/frases),
modalidades, jornada/pilares/indicadores/categorias e os prompts padrão.

## Como criar um segmento novo (ex.: energia solar)

1. `cp config/segmentos/empresa.yml config/segmentos/solar.yml`
2. Edite: id/nome, termos ("venda"→"instalação"?), profissionais reais,
   unidades, preços (kits), `contexto:` com a história do negócio e os
   prompts que quiser especializar.
3. No yml da marca: `segmento: solar`.
4. Build + deploy (sem migração de banco; a marca veste na subida).

**Regra das keys**: `key` de unidade/modalidade/categoria é gravada no
banco junto com os dados. Renomear **label** é livre; renomear **key**
com histórico gravado quebra filtros e relatórios.

## Garantia de compatibilidade (CEVICO)

`clinica.yml` guarda **exatamente** os valores que estavam chumbados no
código (3 médicos, Tatuapé/Av. Paulista, 7 janelas, tabela de preços,
metas, jornada). Sem `MARCA`/`SEGMENTO` no ambiente, tudo cai nesse
preset — comportamento idêntico ao de antes, incluindo testes (fallbacks
chumbados permanecem nos helpers para contexto sem pacote).

## O que ainda é clínico (pendências — fase B/C)

- **Copywriter / Construtor de Páginas / Editor**: prompts continuam os da
  CEVICO em qualquer segmento (personalizáveis por conta na UI). O módulo
  de Páginas públicas (`cevico_pages`, portas refrativa/catarata/trifocal,
  formulários públicos e seeds do `cevico_forms.rake`) é da CEVICO.
- **Espaço do Cliente — campos de prontuário** (OD/OE, refração, acuidade,
  PIO, grupos de procedimento): sempre clínicos; num segmento não-clínica
  o espaço funciona, mas a ficha rápida mostra campos de olho.
- **Textos secundários** de telas menores (Academy, AutomationsHub,
  questionário pré-consulta do CrmForms, placeholders do Estoque/Financeiro,
  descrições dos agentes em telas de automação).
- **Terminologia por conta** (paciente→cliente é por segmento/yml; por
  conta exigiria reatividade em todas as telas — fase C se precisar).
- Schemas de saída dos robôs mantêm descrições com vocabulário clínico
  (as CHAVES são neutras; só texto de orientação ao modelo).
