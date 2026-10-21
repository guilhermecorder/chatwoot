# Agentes de IA por coluna do CRM — análise e proposta (23/09/2026)

Pedido do Guilherme: "analisar possibilidades de outros agentes nas colunas que
temos, para atendimento". Exemplo dele: fundo de funil — quem já passou em
consulta, recebeu orçamento e disse que precisa de um tempo; o robô de
follow-up cutuca; se a pessoa volta, um agente ajuda a agendar ou faz um
atendimento rápido; sabendo o preço, pode "pré-agendar" a cirurgia — o
agendamento da cirurgia em si fica com humano por enquanto.

## 1. Como está hoje (quem fala em cada coluna)

Regra do sistema: **a coluna do card decide quem responde** (CrmListener →
`responder_owner_for`). Cada coluna tem no máximo um agente dono. Mensagem
enviada por pessoa da equipe pausa o agente; 👍 reativa; robôs, jornada,
lembretes e campanhas são "sistema" e não pausam.

| Coluna do CRM | Quem responde ao paciente hoje | O que mais roda na coluna |
|---|---|---|
| (sem card) | Atendente de Agendamento | — |
| Novos Contatos | Atendente de Agendamento | robôs de follow-up |
| Envio de Orçamento | Atendente de Agendamento | robôs de follow-up |
| Agendamento de Consulta | Atendente Pós-agendamento | lembrete D-1 (Jornada) |
| Desmarcou a Consulta | Atendente Pós-agendamento (se marcado no card) | follow-up |
| Consulta Confirmada | Atendente Pós-agendamento | Jornada |
| Não Foi a Consulta | Atendente Pós-agendamento (se marcado) | follow-up |
| Consulta Realizada | **ninguém** | Analista de Conversas / Monitor de Fechamento (automação) |
| Indicação de Cirurgia | **ninguém** | follow-up, Monitor de Fechamento |
| Sem Indicação Cirúrgica | **ninguém** | — |
| Não Fechou Ainda | **ninguém** | robôs de follow-up (o caso dele) |
| Cirurgia Agendada | **ninguém** | Jornada (véspera), Oftalmofácil |
| Cirurgia Realizada | **ninguém** | NPS (automação) |
| Pós Operatório | **ninguém** | Jornada |

Ou seja: da consulta realizada em diante, quando o paciente escreve (ou
responde a um follow-up), só humano responde. É exatamente o buraco do
exemplo dele: o robô cutuca o "Não Fechou Ainda", a pessoa responde às 21h de
sábado e ninguém continua a conversa.

O que já existe e serve de base para qualquer agente novo (nada disso precisa
ser refeito): motor `Crm::ResponderAgentService` (Roteiro + bloco da etapa +
ferramentas), sombra → fatia → ao vivo (`CEVICO_RESPONDERS_LIVE`, dias/horas),
pausa por humano/👍, chavinha por conversa, Orientações (👎 vira orientação),
🧪 Testar agente, cache do roteiro (213), leitura de áudio/imagem (204),
Agenda viva (`Crm::AgendaSlots`, consultas/teleconsultas/exames/cirurgias),
Tabela de preços da conta, `Crm::AgentAlert` (aviso no Meu Painel),
`Crm::ClinicalNote`, campo "Procedimento de interesse" e valor do card,
etiquetas `procedimento_*`/`objecao_*` (Jornada Disney).

## 2. Proposta — 3 agentes novos, na ordem em que valem dinheiro

### C. Atendente de Retorno (fundo de funil) — o exemplo dele
- **Colunas:** Consulta Realizada · Indicação de Cirurgia · Não Fechou Ainda
  (e, opcional, Sem Indicação Cirúrgica com um bloco próprio de "cuidado
  contínuo": retorno anual, óculos, exames).
- **Quando entra:** o paciente responde ao robô de follow-up ou volta
  sozinho ("oi, estive aí mês passado, ainda tem aquele valor?").
- **O que sabe (contexto montado pelo motor):** data e médico da consulta
  (Task da Agenda), procedimento indicado (campo "Procedimento de interesse"
  + etiquetas `procedimento_*` + notas clínicas), orçamento dado (valor do
  card + Tabela de preços), objeção registrada (`objecao_*`), quem atendeu.
- **O que faz:** responde dúvidas do procedimento (só o que está no Roteiro),
  reforça a equipe cirúrgica/estrutura da CEVICO, apresenta as condições
  (10x, à vista) e conduz ao próximo micro-compromisso — igual ao
  afunilamento do Atendente de Agendamento (item 200).
- **"Pré-agendar" cirurgia (decisão dele: humano fecha):** ferramenta
  `pre_agendar_cirurgia` que grava intenção (procedimento, olho(s), forma de
  pagamento, janela de datas preferida), aplica etiqueta `quer_cirurgia`,
  move o card para "Cirurgia Agendada — a confirmar" (ou mantém e cria
  Tarefa para a responsável), avisa no Meu Painel (`Crm::AgentAlert`) e
  responde ao paciente "a Vaneide te confirma a data até X". Sem sala
  cirúrgica marcada pela IA. Quando ele quiser, a mesma ferramenta passa a
  usar a Agenda de cirurgias (`AgendaSlots`, janelas da sala) — é uma
  chavinha, não uma reconstrução.
- **Também agenda:** retorno/teleconsulta/exame pré-operatório com vagas
  reais (ferramentas já existentes do Pós-agendamento).
- **Modelo:** Sonnet 5, esforço medium (conversa de venda; Haiku para
  a versão "cuidado contínuo").
- **Guardrails extras:** valor só da Tabela de preços; nunca diagnóstico;
  nunca "cirurgia marcada" sem humano; convênio = regra do Roteiro.
- **Como medir:** Não Fechou Ainda → Cirurgia Agendada (taxa e tempo), % de
  respostas fora do horário humano, 👍/👎 na Sombra. Base do item 201.

### D. Atendente Pré-cirúrgico
- **Colunas:** Cirurgia Agendada.
- **Faz:** dúvidas de preparo (jejum, colírios, acompanhante, exames,
  documentos, local/horário), confirma presença, registra pedido de
  remarcação (humano remarca a sala; o agente só grava e avisa), lembra do
  que falta (exame pré-op pendente vira Tarefa).
- **Fonte de verdade:** seção nova do Roteiro "Orientações pré-operatórias
  por procedimento" escrita/aprovada pelos médicos. Fora dela →
  `chamar_humano`.
- **Modelo:** Haiku 4.5 (perguntas curtas e repetidas) — barato.
- **Ganho:** menos ligações no dia anterior; paciente chega preparado (menos
  cirurgia cancelada por preparo errado).

### E. Atendente Pós-operatório
- **Colunas:** Cirurgia Realizada · Pós Operatório.
- **Faz:** o que é esperado × o que é alarme (dor forte, perda súbita de
  visão, secreção, trauma → "procure o pronto atendimento agora" +
  `chamar_humano` + alerta vermelho no Meu Painel), retornos de pós-op com
  vagas reais, reforço de seguir a receita (nunca prescreve nem altera
  colírio), NPS no momento certo (o agente NPS já existe — integra), pedido
  de indicação/avaliação quando o paciente está feliz (etiqueta
  `indicou_amigo`).
- **Risco clínico é o maior de todos:** sombra mais longa, textos de
  sintomas aprovados pelos médicos, `chamar_humano` como padrão em qualquer
  sintoma. Modelo Sonnet 5.

### Por que não um agente por coluna
Cada agente é um prompt + cache + card no hub; agente demais = roteiro
duplicado e mais custo de gravação de cache. O que muda de coluna para
coluna é o **bloco da etapa**, e o motor já suporta um agente cobrindo
várias colunas com passos diferentes por coluna (é assim que o Pós-agendamento
trata Desmarcou/Não Foi). Três agentes cobrem as 7 colunas sem dono.

## 3. Ordem sugerida e esforço
1. **C — Retorno** (1 rodada: bloco da etapa + 2 ferramentas + contexto do
   orçamento/consulta + card no hub + Roteiro seção "Fechamento"; sem
   migration). Sombra na coluna Não Fechou Ainda primeiro.
2. **D — Pré-cirúrgico** (½ rodada: bloco + seção do Roteiro; ferramenta
   "registrar pedido de remarcação").
3. **E — Pós-operatório** (1 rodada + textos médicos aprovados antes).

Complementos pequenos que ajudam os três: (a) no CRM, cabeçalho da coluna
mostrando "🤖 quem responde aqui" (dado já existe em `ai_config.agents.*.stage_ids`);
(b) item 201 (efetividade) para provar cada agente com número; (c) o robô de
follow-up da coluna passa a ser o "gatilho" oficial do agente C — hoje já
funciona por desenho (mensagem de robô não pausa a IA).

## 4. Perguntas para ele decidir antes de construir
1. C também responde em "Sem Indicação Cirúrgica"? (cuidado contínuo)
2. "Pré-agendar" = mover o card para Cirurgia Agendada com etiqueta
   "a confirmar", ou manter na coluna e só criar Tarefa + aviso?
3. Quem recebe o aviso do pré-agendamento (Vaneide / responsável do card)?
4. Textos pré e pós-operatórios: quem escreve/aprova (médicos)?
