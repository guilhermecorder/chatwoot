# 📥 MOTOR POR CAIXA (item 416, 25/11/2026): uma caixa de entrada com motor,
# esforço e Roteiro PRÓPRIOS no mesmo atendente, sem mexer nas outras caixas.
# Pedido do Guilherme: testar a caixa "CONFIRMAÇÃO DE CONSULTA" toda na Luna,
# no esforço alto e no Roteiro 2, enquanto as outras seguem como estão.
#
# A config mora em ai_config['agents'][agente]['inbox_engines']:
#   { '5' => { 'model' => 'gpt-6-luna', 'effort' => 'high', 'script' => 'v2' } }
# Chave = id da caixa (texto). Cada campo é opcional: em branco = vale o de
# sempre (motor = teste A/B / motor por coluna / cartão; esforço = o do cartão;
# Roteiro = o do teste A/B ou o oficial).
#
# Ordem de quem decide o motor da resposta (Crm::ResponderAgentService#model):
# reserva na falha > 🧪 Testar agente > MOTOR DA CAIXA > variante B > coluna > cartão.
# Só conversa REAL (o 🧪 Testar agente tem os seletores dele). Se a chave do
# fornecedor do modelo sumir, a caixa cai no caminho de sempre (nunca fica muda).
module Crm::InboxEngine
  module_function

  CONFIG_KEY = 'inbox_engines'.freeze
  FIELDS = %w[model effort script].freeze

  # { 'id da caixa' => { 'model'?, 'effort'?, 'script'? } } (sempre um Hash)
  def config(agent_config)
    raw = agent_config.is_a?(Hash) ? agent_config[CONFIG_KEY] : nil
    raw.is_a?(Hash) ? raw : {}
  end

  # a escolha da caixa desta conversa (Hash) ou nil
  def entry_for(conversation, agent_config)
    inbox_id = conversation&.inbox_id
    return nil if inbox_id.blank?

    entry = config(agent_config)[inbox_id.to_s]
    entry.is_a?(Hash) && entry.values.any?(&:present?) ? entry : nil
  end

  # limpa o que chegou da tela: só caixas que o agente lê, só modelo
  # reconhecido, esforço da lista e Roteiro v1/v2; caixa sem nada = sai
  def sanitize(raw, agent_config)
    allowed = Array(agent_config['inbox_ids']).map { |id| id.to_i.to_s }
    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    hash.each_with_object({}) do |(inbox_id, choice), clean|
      inbox_id = inbox_id.to_s
      next if allowed.exclude?(inbox_id)

      entry = clean_entry(choice)
      clean[inbox_id] = entry if entry.any?
    end
  end

  def clean_entry(choice)
    choice = choice.respond_to?(:to_unsafe_h) ? choice.to_unsafe_h : choice.to_h
    model = choice['model'].to_s.strip
    effort = choice['effort'].to_s.strip
    script = choice['script'].to_s.strip
    {
      'model' => Crm::LlmCatalog.valid_id?(model) ? model : nil,
      'effort' => Crm::AiAgentConfig::EFFORTS.include?(effort) ? effort : nil,
      'script' => Crm::CevicoScript::VERSIONS.include?(script) ? script : nil
    }.compact
  end
end
