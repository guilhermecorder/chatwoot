# 🗂️ Estado e registro de atividade de um agente (rodada 195), no MESMO
# formato que os atendentes do WhatsApp usam (Crm::ResponderAgentJob):
#   ai_config["#{agent_key}_state"] = { 'events' => [...100], ...outras chaves }
# O card do agente no hub lê os eventos (últimos 30) e o que mais o agente
# guardar ali (ex.: a lista "ligaria hoje" do Agente de Ligação em 'shadow').
# Tudo é feito sob lock da linha de CrmSetting, relendo a config fresca —
# dois jobs ao mesmo tempo nunca sobrescrevem um ao outro.
module Crm::AgentState
  LOG_CAP = 100
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  module_function

  def key(agent_key)
    "#{agent_key}_state"
  end

  def read(account, agent_key)
    CrmSetting.find_by(account: account)&.ai_config&.dig(key(agent_key)) || {}
  end

  # mexe SÓ na chave de estado do agente; o bloco recebe uma cópia e devolve a nova
  def update(account, agent_key)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    settings.with_lock do
      cfg = settings.ai_config || {}
      state = yield((cfg[key(agent_key)] || {}).deep_dup)
      cfg[key(agent_key)] = state
      settings.update!(ai_config: cfg)
    end
  rescue StandardError => e
    Rails.logger.warn "[Crm::AgentState##{agent_key}] estado: #{e.message}"
  end

  # registro de atividade (visível no card): type curto + nota humana;
  # contact/conversation_id opcionais; once_per_day evita repetir o mesmo aviso
  def log(account, agent_key, type, note, contact: nil, conversation_id: nil, once_per_day: false) # rubocop:disable Metrics/ParameterLists
    update(account, agent_key) do |state|
      events = Array(state['events'])
      today = TZ.now.to_date.to_s
      next state if once_per_day && events.any? { |e| e['type'] == type && e['at'].to_s.start_with?(today) }

      events.unshift({ 'at' => Time.current.iso8601, 'type' => type, 'conversation_id' => conversation_id,
                       'contact' => contact.to_s.truncate(40).presence, 'note' => note.to_s.truncate(220) }.compact)
      state['events'] = events.first(LOG_CAP)
      state
    end
  end
end
