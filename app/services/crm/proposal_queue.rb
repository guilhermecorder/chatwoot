# 📄 PARA QUEM É A PROPOSTA (11/11/2026 · LIFE, pedido do Guilherme): a tela do gerador de
# proposta precisa ser fácil — digitar o nome ou o telefone (Crm::PatientSearch já faz) OU ver
# "quem está na coluna do CRM" e clicar. Aqui sai a lista da coluna e os dados do cliente
# escolhido, já com o resumo escrito dele (conta de luz, consumo que vai aumentar…).
#
#   Crm::ProposalQueue.new(account, stage_id: nil, contact_id: nil).call →
#     { stages: [{ id:, name:, color:, count: }], stage_id:, people: [...], selected: {...} | nil }
# Sem stage_id, abre na primeira coluna que tem compromisso e gente (ex.: "Orçamento a fazer").
class Crm::ProposalQueue
  LIMIT = 60

  def initialize(account, stage_id: nil, contact_id: nil)
    @account = account
    @stage_id = stage_id.presence&.to_i
    @contact_id = contact_id.presence&.to_i
  end

  def call
    stage = current_stage
    { stages: stages.map { |s| stage_json(s) }, stage_id: stage&.id, people: stage ? people(stage) : [], selected: selected }
  end

  private

  # o funil principal da conta (o primeiro)
  def pipeline
    @pipeline ||= Crm::Pipeline.where(account: @account).order(:position, :id).first
  end

  def stages
    @stages ||= pipeline ? pipeline.stages.to_a : []
  end

  def counts
    @counts ||= Crm::Contact.where(stage_id: stages.map(&:id)).group(:stage_id).count
  end

  def stage_json(stage)
    { id: stage.id, name: stage.name, color: stage.color, count: counts[stage.id].to_i }
  end

  # a coluna pedida; senão a primeira com compromisso e gente; senão a primeira com gente
  def current_stage
    chosen = stages.find { |s| s.id == @stage_id }
    return chosen if chosen

    busy = stages.select { |s| counts[s.id].to_i.positive? }
    busy.find { |s| Crm::StageDeadline.config(s)&.dig('tarefa').present? } || busy.first
  end

  def people(stage)
    cards = Crm::Contact.where(stage_id: stage.id).includes(:contact)
                        .order(Arel.sql('crm_contacts.stage_moved_at ASC NULLS LAST, crm_contacts.id ASC')).limit(LIMIT)
    cfg = Crm::StageDeadline.config(stage)
    cards.filter_map { |card| card.contact && person(card.contact, card, stage, cfg) }
  end

  def selected
    contact = @contact_id && @account.contacts.find_by(id: @contact_id)
    return nil if contact.nil?

    card = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, contact_id: contact.id)
                       .order(Arel.sql('crm_contacts.stage_moved_at DESC NULLS LAST')).first
    stage = card&.stage
    person(contact, card, stage, stage && Crm::StageDeadline.config(stage))
  end

  def person(contact, card, stage, cfg)
    {
      contact_id: contact.id, name: contact.name, phone: contact.phone_number, card_id: card&.id,
      stage: stage && { id: stage.id, name: stage.name, color: stage.color },
      stage_due_at: card && Crm::StageDeadline.due_at(cfg, card.stage_moved_at),
      summary: Crm::ClientSummary.lines(contact, fields: summary_fields)
    }
  end

  def summary_fields
    @summary_fields ||= Crm::ClientSummary.fields(@account)
  end
end
