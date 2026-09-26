# 📊 Pesquisa de satisfação pós-cirurgia (item 256) — passos reais de
# app/services/crm/nps_survey.rb (envio + leitura da resposta) e do
# Atendente de Pós-operatório (continua a conversa).
class Crm::FlowMap::Flows::NpsSurvey
  FLOW = Crm::FlowMap::Flow.define(:nps_survey) do # rubocop:disable Metrics/BlockLength
    name 'Pesquisa de satisfação (NPS)'
    group 'Atendimento ao paciente'
    icon 'i-lucide-smile-plus'
    color '#7C3AED'
    what 'manda a pesquisa N dias depois da cirurgia (por tipo), lê a nota e aciona a equipe nas notas baixas'
    config tab: 'agentes', anchor: 'nps_survey'
    trigger :cron, 'A cada 15 min (só age na hora configurada)'
    jobs 'Crm::NpsSurveySendJob'

    node :ligada, 'Pesquisa ligada e é a hora?', kind: :decision
    node :regras, 'Para cada tipo de cirurgia (dias depois)', kind: :loop
    node :cirurgias, 'Cirurgias daquele dia na Agenda'
    node :filtro, 'Realizada, sem cerca, sem pesquisa recente?', kind: :decision
    node :pula, 'Pula e registra o motivo'
    node :modo, 'Sombra ou ao vivo?', kind: :decision
    node :lista, 'Só lista quem receberia', kind: :output
    node :envia, 'Envia o modelo da Meta com os botões', kind: :external
    node :resposta, 'Paciente toca na nota'
    node :grava, 'Etiqueta nps-*, grava a nota e nota interna', kind: :output
    node :baixa, 'Nota de 1 a 6?', kind: :decision
    node :tarefa, 'Tarefa no Meu Painel (1–4 urgente)', kind: :output
    node :agente, 'Atendente de Pós-operatório continua a conversa', kind: :ai
    node :fim, 'Fim', kind: :end

    edge :trigger, :ligada
    edge :ligada, :fim, 'não'
    edge :ligada, :regras, 'sim'
    edge :regras, :cirurgias
    edge :cirurgias, :filtro
    edge :filtro, :pula, 'não'
    edge :pula, :fim
    edge :filtro, :modo, 'sim'
    edge :modo, :lista, 'sombra'
    edge :lista, :fim
    edge :modo, :envia, 'ao vivo'
    edge :envia, :resposta
    edge :resposta, :grava
    edge :grava, :baixa
    edge :baixa, :tarefa, 'sim'
    edge :tarefa, :agente
    edge :baixa, :agente, 'não'
    edge :agente, :fim

    live do |account|
      cfg = agenda(account)['nps_survey'] || {}
      state = agenda(account)['nps_survey_state'] || {}
      answers = Array(state['answers'])
      {
        enabled: cfg['enabled'] == true,
        last_run_at: state['last_run_at'],
        counters: {
          'modo' => cfg['mode'] == 'live' ? 'ao vivo' : 'sombra',
          'tipos de cirurgia' => Array(cfg['rules']).size,
          'na última rodada' => Array(state['sent']).size,
          'respostas (últimas)' => answers.size
        }
      }
    end
  end

  def self.flow
    FLOW
  end
end
