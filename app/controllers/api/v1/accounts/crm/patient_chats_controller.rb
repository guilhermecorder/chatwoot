# 💬 item 298 (30/09, "do Espaço do Paciente precisa ter um ambiente pra abrir
# a conversa; da Agenda também; opção Abrir conversa no botão direito"): a
# conversa mais recente de um paciente, no formato que o popup de conversa do
# CRM já entende (o mesmo card do quadro). Acha o paciente pelo contact_id ou,
# sem ele, pelo telefone (agendamento antigo sem cadastro ligado). Só olha as
# caixas que a pessoa logada pode ver.
class Api::V1::Accounts::Crm::PatientChatsController < Api::V1::Accounts::BaseController
  # GET /crm/patient_chat?contact_id=12 | ?phone=+5511999990000
  def show
    contact = find_contact
    return render json: { found: false, reason: 'Paciente sem cadastro ligado.' } unless contact

    conversation = last_conversation(contact)
    card = main_card(contact)
    render json: { found: true, has_conversation: conversation.present?, card: card_json(contact, card, conversation),
                   stages: stages_json(card) }
  end

  private

  def find_contact
    found = Current.account.contacts.find_by(id: params[:contact_id]) if params[:contact_id].present?
    found || Task.match_contact(Current.account, params[:phone])
  end

  def last_conversation(contact)
    Current.account.conversations.where(contact_id: contact.id, inbox_id: Current.user.assigned_inboxes.select(:id))
           .order(Arel.sql('last_activity_at DESC NULLS LAST')).includes(:inbox).first
  end

  # o card que se mexeu por último (o popup usa para mover de coluna)
  def main_card(contact)
    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: Current.account.id }, contact_id: contact.id)
                .order(Arel.sql('crm_contacts.stage_moved_at DESC NULLS LAST')).first
  end

  def card_json(contact, card, conversation)
    { id: card&.id, contact_id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email,
      avatar_url: contact.avatar_url, stage_id: card&.stage_id, pipeline_id: card&.pipeline_id, value: card&.value,
      labels: contact.label_list, last_activity_at: contact.last_activity_at,
      last_conversation_id: conversation&.id, last_conversation: conversation_json(conversation) }
  end

  def conversation_json(conversation) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless conversation

    last = conversation.messages.where(private: false, message_type: %i[incoming outgoing]).order(:id).last
    waiting = (last&.incoming? && conversation.open?) || false
    { id: conversation.id, display_id: conversation.display_id, status: conversation.status, inbox_id: conversation.inbox_id,
      inbox_name: conversation.inbox&.name, channel_type: conversation.inbox&.channel_type,
      last_message: last&.content&.slice(0, 120), last_message_at: last&.created_at, last_message_type: last&.message_type,
      unread_count: 0, awaiting_reply: waiting, waiting_since: waiting ? last.created_at : nil }
  end

  def stages_json(card)
    return [] unless card

    card.pipeline.stages.map { |s| { id: s.id, name: s.name, color: s.color, position: s.position } }
  end
end
