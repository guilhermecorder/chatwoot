# 🏥 FUNIL DO OFTALMOFÁCIL para CONSULTAS (item 300, 30/09). Até aqui o funil
# dos parceiros só recebia cirurgia (o sync do hub). Pedido do Guilherme: o
# paciente do Oftalmofácil que tem consulta marcada e recebe o lembrete de
# confirmação precisa ter o card "no CRM da Oftalmofácil" — nunca no da CEVICO.
#
# As colunas "Consulta Agendada" e "Consulta Confirmada" são achadas pelo NOME
# dentro do funil dos parceiros (agenda_config.oftalmofacil.partner_pipeline_id);
# se ainda não existem, nascem no começo do funil. Card deste funil NUNCA
# dispara automação (cerca dos parceiros, item 231) e nunca volta para trás.
module Crm::PartnerFunnel
  module_function

  STAGES = {
    booked: { name: 'Consulta Agendada', like: 'consulta agendada', color: '#2563EB' },
    confirmed: { name: 'Consulta Confirmada', like: 'consulta confirmada', color: '#16A34A' }
  }.freeze

  def pipeline(account)
    id = Crm::PartnerGuard.partner_pipeline_id(account)
    id && account.crm_pipelines.find_by(id: id)
  end

  def stage!(account, key)
    funnel = pipeline(account)
    spec = STAGES[key]
    return nil if funnel.nil? || spec.nil?

    funnel.stages.where('crm_stages.name ILIKE ?', "%#{spec[:like]}%").order(:position).first || create_stage(funnel, key)
  end

  # põe (ou anda) o card do paciente na coluna pedida; devolve o nome da
  # coluna quando mexeu, nil quando não precisou
  def place!(account, contact, key) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if contact.blank?

    stage = stage!(account, key)
    return nil if stage.nil?

    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    return nil if card.persisted? && (card.stage_id == stage.id || card.stage&.position.to_i > stage.position.to_i)

    card.origin ||= 'oftalmofacil'
    card.stage_id = stage.id
    card.save!
    Crm::PartnerGuard.forget!(account)
    stage.name
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
    Rails.logger.warn "[Crm::PartnerFunnel] contato #{contact&.id}: #{e.message}"
    nil
  end

  # colunas novas entram ANTES das de cirurgia, na ordem agendada → confirmada
  def create_stage(funnel, key)
    spec = STAGES[key]
    booked = key == :confirmed && funnel.stages.where('crm_stages.name ILIKE ?', "%#{STAGES[:booked][:like]}%").order(:position).first
    if booked
      # logo depois da "Consulta Agendada": abre espaço empurrando as seguintes
      funnel.stages.where('position > ?', booked.position).update_all('position = position + 1') # rubocop:disable Rails/SkipsModelValidations
      return funnel.stages.create!(name: spec[:name], color: spec[:color], position: booked.position + 1)
    end

    first = funnel.stages.minimum(:position).to_i
    funnel.stages.create!(name: spec[:name], color: spec[:color], position: first - 1)
  end
end
