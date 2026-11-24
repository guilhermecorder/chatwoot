# 🔙 PONTO DE VOLTA DO ATENDIMENTO (24/11/2026). Em 24/11 o atendimento por IA
# mudou de uma vez: recepção e sondagem novas no Roteiro 1, ChatGPT nas
# primeiras colunas, prompt novo em teste. Se o resultado piorar, UM comando
# devolve o atendimento ao formato que tinha o histórico de conversão:
#   · Roteiro 1 e Passos do Atendente de Agendamento com o texto EXATO que
#     estava em produção até 23/11 (config/cevico/ponto_de_volta_2026_11_24.yml,
#     tirado da imagem 1b4af7f) — gravados como texto personalizado;
#   · motor por coluna apagado (volta o modelo do cartão, o Sonnet);
#   · teste A/B em andamento encerrado.
# Nada se perde: antes de escrever, tira foto do Roteiro e dos Passos atuais
# (Histórico → "voltar para esta") e guarda o mapa e o teste em
# ai_config['restore_point']['undo'].
module Crm::AttendanceRestorePoint
  module_function

  FILE = Rails.root.join('config/cevico/ponto_de_volta_2026_11_24.yml')
  KEY = 'restore_point'.freeze
  AGENTS = %w[atendente_agendamento atendente_pos atendente_pos_op].freeze
  NOTE = 'antes de voltar ao atendimento de 23/11 (ponto de volta)'.freeze

  def data
    @data ||= YAML.safe_load(File.read(FILE))
  end

  def summary(account)
    state = (CrmSetting.find_by(account: account)&.ai_config || {})[KEY] || {}
    { id: data['id'], label: data['label'], source: data['source'], applied_at: state['applied_at'], applied_by: state['by'] }
  end

  def apply!(account, by: nil)
    Crm::ScriptVersion.snapshot!(account, kind: 'script', note: NOTE, by: by)
    data['stage'].each_key { |agent| Crm::ScriptVersion.snapshot!(account, kind: 'stage', agent_key: agent, note: NOTE, by: by) }
    Crm::ScriptVersion.write_script!(account, data['script'])
    data['stage'].each { |agent, prompt| Crm::ScriptVersion.write_stage_prompt!(account, agent, prompt) }
    reset_engines!(account, by)
    Crm::AttendanceMilestones.add!(account, title: 'Voltou ao atendimento de antes de 24/11',
                                            note: 'Roteiro 1 e Passos do Agendamento com o texto de 23/11, motor por coluna ' \
                                                  'apagado e teste A/B encerrado.',
                                            by: by&.name)
    summary(account)
  end

  # apaga o motor por coluna e encerra o teste A/B dos três atendentes (guardando o que havia)
  def reset_engines!(account, by) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    now = Time.current.iso8601
    Cevico::SettingMerge.merge!(account, :ai_config) do |cfg|
      agents = cfg['agents'] ||= {}
      undo = {}
      AGENTS.each do |key|
        agent = agents[key]
        next unless agent.is_a?(Hash)

        undo[key] = agent.slice(Crm::StageEngine::CONFIG_KEY, Crm::EngineExperiment::CONFIG_KEY).presence
        experiment = agent[Crm::EngineExperiment::CONFIG_KEY]
        if experiment.is_a?(Hash) && experiment['enabled'] && experiment['ended_at'].blank?
          entry = Crm::EngineExperiment.history_entry(experiment, key, agent, by: by&.name, decision: 'a', note: 'encerrado pelo ponto de volta')
          agent[Crm::EngineExperiment::HISTORY_KEY] = Crm::EngineExperiment.push_history(agent, entry)
          agent[Crm::EngineExperiment::CONFIG_KEY] = experiment.merge('enabled' => false, 'ended_at' => entry['ended_at'])
        end
        agent.delete(Crm::StageEngine::CONFIG_KEY)
      end
      cfg[KEY] = { 'id' => data['id'], 'applied_at' => now, 'by' => by&.name, 'undo' => undo.compact }
      cfg
    end
  end
end
