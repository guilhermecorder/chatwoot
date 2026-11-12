# 🔓 O botão "Gerar orçamento" da conversa só libera depois que o cliente mandou a conta de luz
# ou os dados (pedido do Guilherme, 11/11/2026). Vale um dos dois sinais:
#   1. a conta de luz está anotada no resumo do cliente (Crm::ClientSummary, campo 'conta');
#   2. o cartão do cliente já chegou na coluna do orçamento — a primeira coluna do funil que tem
#      compromisso (Crm::StageDeadline; na LIFE, "Orçamento a fazer") — ou passou dela;
#   3. o atendente já abriu a tarefa "Orçamento: conta recebida" para este cliente (12/11: a pessoa mandou
#      a foto da conta, a tarefa #28 abriu e o botão seguiu travado — a ficha não tinha o valor e o cartão
#      não tinha mudado de coluna). Mesmo sinal da Jornada do orçamento (Crm::QuoteJourney::BILL_TASK).
class Crm::KitQuote::Ready
  BILL_FIELD = 'conta'.freeze
  WAITING = 'Libera quando o cliente enviar a conta de luz ou os dados.'.freeze

  def initialize(account, contact)
    @account = account
    @contact = contact
  end

  # { 'liberado' => true, 'motivo' => 'Conta de luz anotada: R$ 300' } ou { 'liberado' => false, 'falta' => '...' }
  def call
    reason = @contact && (bill_reason || task_reason || stage_reason)
    reason ? { 'liberado' => true, 'motivo' => reason } : { 'liberado' => false, 'falta' => WAITING }
  end

  private

  def bill_reason
    value = (@contact.additional_attributes || {}).dig(Crm::ClientSummary::ATTR_KEY, BILL_FIELD, 'valor')
    "Conta de luz anotada: #{value}" if value.present?
  end

  def task_reason
    task = @account.tasks.where(contact_id: @contact.id).where('tasks.title LIKE ?', "%#{Crm::QuoteJourney::BILL_TASK}%")
                   .order(id: :desc).first
    "Conta recebida (tarefa ##{task.id})" if task
  end

  def stage_reason
    card = Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, contact_id: @contact.id)
                       .order(Arel.sql('crm_contacts.stage_moved_at DESC NULLS LAST, crm_contacts.id DESC')).first
    return nil unless card&.stage

    stages = card.pipeline.stages.to_a
    quote_column = stages.index { |s| Crm::StageDeadline.config(s)&.dig('tarefa').present? }
    current = stages.index { |s| s.id == card.stage_id }
    "Cartão na coluna «#{card.stage.name}»" if quote_column && current && current >= quote_column
  end
end
