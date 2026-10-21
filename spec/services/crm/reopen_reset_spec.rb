require 'rails_helper'

# 🔁 item 348: conversa única por caixa — paciente reabre = pausas da IA zeradas
RSpec.describe Crm::ReopenReset do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:wa_key) { Crm::ResponderAgentJob::STATE_KEY }
  let(:paused) { { 'paused' => true, 'reason' => 'humano_assumiu', 'by' => 'Vaneide' } }

  def pause!(attrs)
    Cevico::AttributeMerge.merge!(conversation) { |current| current.merge(attrs) }
  end

  def patient_writes!
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     sender: contact, content: 'Oi, voltei')
  end

  def reset_notes
    conversation.messages.where(message_type: :activity).where('content LIKE ?', '🔁%')
  end

  it 'zera as pausas da IA (WhatsApp e Instagram) quando o paciente reabre uma conversa resolvida' do
    pause!(wa_key => paused, 'cevico_atendente_ia' => paused, 'cevico_followup' => { 'x' => 1 })
    conversation.resolved!

    patient_writes!

    conversation.reload
    expect(conversation).to be_open
    expect(conversation.additional_attributes).not_to have_key(wa_key)
    expect(conversation.additional_attributes).not_to have_key('cevico_atendente_ia')
    expect(conversation.additional_attributes['cevico_followup']).to eq('x' => 1) # o resto fica
    expect(reset_notes.count).to eq(1)
  end

  it 'não mexe em conversa que já estava aberta (a pausa de quem assumiu continua)' do
    pause!(wa_key => paused)

    patient_writes!

    expect(conversation.reload.additional_attributes[wa_key]).to include('paused' => true)
    expect(reset_notes).to be_empty
  end

  it 'reabertura pela equipe (tela) não zera a pausa' do
    pause!(wa_key => paused)
    conversation.resolved!

    conversation.open!

    expect(conversation.reload.additional_attributes[wa_key]).to include('paused' => true)
  end

  it 'sem pausa, reabre sem nota' do
    conversation.resolved!

    patient_writes!

    expect(conversation.reload).to be_open
    expect(reset_notes).to be_empty
  end

  it 'mensagem da equipe numa conversa resolvida não reabre nem zera' do
    pause!(wa_key => paused)
    conversation.resolved!

    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Lembrete')

    conversation.reload
    expect(conversation).to be_resolved
    expect(conversation.additional_attributes[wa_key]).to include('paused' => true)
  end
end
