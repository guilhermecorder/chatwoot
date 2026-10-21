# 🗺️ Mensagens da jornada (item 168) — passos reais de
# app/jobs/crm/journey_run_job.rb (Planner + Dispatcher) e do
# Crm::Journey::ReplyService (resposta do paciente). Substitui o fluxo
# externo do N8N "CONFIRMACAO CIRURGICA - IOP".
class Crm::FlowMap::Flows::Journey
  FLOW = Crm::FlowMap::Flow.define(:journey) do # rubocop:disable Metrics/BlockLength
    name 'Mensagens da jornada'
    group 'Atendimento ao paciente'
    icon 'i-lucide-route'
    color '#0F766E'
    what 'manda a mensagem certa no momento certo da jornada (cirurgia amanhã, consulta hoje, entrou na coluna…) e lê a resposta'
    config route: 'crm_journey'
    trigger :cron, 'A cada 15 min (planeja o dia e envia na hora de cada regra)'
    jobs 'Crm::JourneyRunJob'

    node :regra, 'Para cada mensagem ligada', kind: :loop
    node :eventos, 'Eventos de hoje (cirurgia, consulta, coluna, etiqueta…)'
    node :publico, 'Paciente está no público (etiquetas/colunas)?', kind: :decision
    node :repetido, 'Já existe envio para este paciente × evento?', kind: :decision
    node :aprovacao, 'Regra exige aprovação?', kind: :decision
    node :fila, 'Entra na Fila de hoje (aguardando aprovação)', kind: :output
    node :agenda, 'Entra na fila com a hora da regra'
    node :hora, 'Chegou a hora e está na janela de envio?', kind: :decision
    node :silencio, 'Paciente pediu silêncio (nao_perturbe/perda_*)?', kind: :decision
    node :pula, 'Pula (registra o motivo)'
    node :variaveis, 'Preenche nome/data/hora/unidade/endereço/procedimento'
    node :envia, 'Envia o modelo (ou texto, se a janela de 24h está aberta)', kind: :external
    node :falhou, 'Falhou?', kind: :decision
    node :registra, 'Marca como enviada (prévia + variáveis)', kind: :output
    node :resposta, 'Paciente responde', kind: :decision
    node :confirmou, 'Confirmou: etiqueta + nota ✅', kind: :output
    node :recusou, 'Não vai / remarcar: nota ⚠️ + aviso no Radar', kind: :output
    node :fim, 'Fim', kind: :end

    edge :trigger, :regra
    edge :regra, :eventos
    edge :eventos, :publico
    edge :publico, :fim, 'não'
    edge :publico, :repetido, 'sim'
    edge :repetido, :fim, 'sim'
    edge :repetido, :aprovacao, 'não'
    edge :aprovacao, :fila, 'sim'
    edge :fila, :hora, 'aprovada'
    edge :aprovacao, :agenda, 'não'
    edge :agenda, :hora
    edge :hora, :fim, 'ainda não'
    edge :hora, :silencio, 'sim'
    edge :silencio, :pula, 'sim'
    edge :pula, :fim
    edge :silencio, :variaveis, 'não'
    edge :variaveis, :envia
    edge :envia, :falhou
    edge :falhou, :fim, 'sim (registra o erro)'
    edge :falhou, :registra, 'não'
    edge :registra, :resposta
    edge :resposta, :confirmou, 'sim/confirmo'
    edge :resposta, :recusou, 'não/remarcar'
    edge :confirmou, :fim
    edge :recusou, :fim

    live do |account|
      messages = Crm::JourneyMessage.where(account: account)
      tz = Crm::Journey::Settings::TZ
      today = Crm::JourneySend.where(account: account).for_day(tz.now.to_date, tz).group(:status).count
      {
        enabled: messages.active.exists?,
        last_run_at: Crm::JourneySend.where(account: account).maximum(:sent_at)&.iso8601,
        counters: {
          'mensagens ligadas' => messages.active.count,
          'enviadas hoje' => today['sent'] || 0,
          'aguardando aprovação' => today['pending_review'] || 0,
          'na fila' => today['queued'] || 0
        },
        note: 'substitui o N8N "CONFIRMACAO CIRURGICA - IOP" (cirurgia na véspera às 10h)'
      }
    end
  end

  def self.flow
    FLOW
  end
end
