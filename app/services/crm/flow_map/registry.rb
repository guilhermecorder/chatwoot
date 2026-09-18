# 🗺️ REGISTRO DOS FLUXOS (item 170): lista explícita (ordem determinística,
# sem surpresa de autoload) dos fluxogramas de cada agente/automação.
#
# REGRA DE TRABALHO: toda rodada que cria/muda um agente entrega o
# fluxograma aqui (app/services/crm/flow_map/flows/<chave>.rb) + no
# resumo da rodada. A spec spec/services/crm/flow_map/registry_spec.rb
# falha se um agente do AGENT_META ou um job CEVICO do schedule.yml ficar
# sem fluxo.
module Crm::FlowMap::Registry
  FLOWS = [
    # Atendimento ao paciente
    Crm::FlowMap::Flows::Scheduler,
    Crm::FlowMap::Flows::Instagram,
    Crm::FlowMap::Flows::Comments,
    Crm::FlowMap::Flows::Nps,
    Crm::FlowMap::Flows::Conversation,
    Crm::FlowMap::Flows::Calls,
    Crm::FlowMap::Flows::Voice,
    Crm::FlowMap::Flows::Reminders,
    Crm::FlowMap::Flows::Journey,
    Crm::FlowMap::Flows::FollowupBots,
    # Vendas e fechamento
    Crm::FlowMap::Flows::Sales,
    Crm::FlowMap::Flows::Closing,
    Crm::FlowMap::Flows::Opportunity,
    Crm::FlowMap::Flows::Form,
    Crm::FlowMap::Flows::ColumnAutomations,
    Crm::FlowMap::Flows::Campaigns,
    # Marketing e aquisição
    Crm::FlowMap::Flows::Copywriter,
    Crm::FlowMap::Flows::Pagebuilder,
    Crm::FlowMap::Flows::Creative,
    Crm::FlowMap::Flows::Harvest,
    # Gestão e evolução do time
    Crm::FlowMap::Flows::Manager,
    Crm::FlowMap::Flows::Auditor,
    Crm::FlowMap::Flows::Mentor,
    Crm::FlowMap::Flows::StalledCards,
    # Infraestrutura
    Crm::FlowMap::Flows::Oftalmofacil
  ].freeze

  module_function

  def groups
    Crm::FlowMap::Flow::GROUPS
  end

  # fluxos já validados, na ordem dos grupos (e, dentro do grupo, na ordem da lista)
  def flows
    @flows ||= FLOWS.map { |klass| klass.flow.validate! }
                    .sort_by.with_index { |flow, idx| [groups.index(flow.group) || 99, idx] }
                    .freeze
  end

  def keys
    flows.map(&:key)
  end

  def find_flow(key)
    flows.find { |flow| flow.key == key.to_s }
  end

  # erro num `live` não derruba a lista (o próprio Flow#live_state vira nota)
  def all(account)
    flows.map { |flow| flow.to_h(account) }
  end

  def find(account, key)
    find_flow(key)&.to_h(account)
  end
end
