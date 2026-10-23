# 👓 PONTE O.S. → CRM: cada passo da O.S. leva o card do cliente para a
# coluna certa, achada PELO NOME (nunca por id fixo — na VPS da ótica os ids
# são outros). Nomes padrão são os dos funis montados em 21/10 (PLANO.md §8);
# a conta pode trocar em agenda_config['otica']['stages'].
#   aberta       → "Pedido fechado"      (funil Aquisição)
#   em_producao  → "Pedido em produção"  (funil Pós-venda)
#   pronta       → "Pronto para retirar" (dispara a Jornada "óculos pronto")
#   entregue     → "Retirou o óculos"    (dispara a régua 7/30/180/365)
# O movimento em si é o do Crm::AttendanceReflector (reaproveitado).
class Otica::CrmBridge
  DEFAULT_STAGES = {
    'aberta' => 'Pedido fechado',
    'em_producao' => 'Pedido em produção',
    'pronta' => 'Pronto para retirar',
    'entregue' => 'Retirou o óculos'
  }.freeze

  def self.stage_names(account)
    custom = CrmSetting.find_by(account: account)&.agenda_config&.dig('otica', 'stages')
    DEFAULT_STAGES.merge((custom || {}).to_h.transform_keys(&:to_s).compact_blank)
  end

  # a coluna da conta cujo nome COMEÇA com o texto configurado (sem distinção
  # de caixa/acento); se houver mais de uma, a do funil mais à frente
  def self.stage_for(account, status)
    wanted = stage_names(account)[status.to_s].to_s.strip
    return nil if wanted.blank?

    normalized = I18n.transliterate(wanted).downcase
    Crm::Stage.joins(:pipeline)
              .where(crm_pipelines: { account_id: account.id })
              .order('crm_pipelines.position', 'crm_stages.position')
              .detect { |s| I18n.transliterate(s.name.to_s).downcase.start_with?(normalized) }
  end

  # reflete o status atual da O.S. no card; devolve o card movido (ou nil)
  def self.reflect(order)
    stage = stage_for(order.account, order.status)
    return nil if stage.blank?

    card = Crm::AttendanceReflector.move_contact_to_stage(account: order.account, contact: order.contact, new_stage: stage,
                                                          create_if_missing: true)
    order.update_columns(crm_contact_id: card.id) if card # rubocop:disable Rails/SkipsModelValidations
    card
  rescue StandardError => e
    Rails.logger.error "[Otica::CrmBridge] O.S. #{order.id} (#{order.status}): #{e.message}"
    nil
  end

  # onde o card do cliente está hoje (para a tela)
  def self.card_json(order)
    card = Crm::Contact.joins(:pipeline)
                       .where(crm_pipelines: { account_id: order.account_id }, contact_id: order.contact_id)
                       .order(updated_at: :desc).first
    return nil if card.blank?

    { pipeline_name: card.pipeline.name, stage_name: card.stage.name }
  end
end
