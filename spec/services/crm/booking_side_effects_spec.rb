require 'rails_helper'

# 🏷️ item 200: consulta marcada/remarcada/cancelada → etiqueta no paciente e
# na conversa + card na coluna configurada (o robô "roda solto")
RSpec.describe Crm::BookingSideEffects do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_new) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let!(:stage_booked) { pipeline.stages.create!(name: 'Agendamento de Consulta', position: 1) }
  let!(:stage_canceled) { pipeline.stages.create!(name: 'Desmarcou a Consulta', position: 2) }

  def apply(outcome, stage_id: nil)
    described_class.apply(account: account, contact: contact, conversation: conversation, outcome: outcome, stage_id: stage_id)
  end

  it 'sem configuração: etiqueta padrão no paciente e na conversa, card não se move' do
    result = apply(:created)
    expect(result[:labels]).to eq(['consulta_agendada'])
    expect(result[:stage]).to be_nil
    expect(contact.reload.label_list).to include('consulta_agendada')
    expect(conversation.reload.label_list).to include('consulta_agendada')
    expect(account.labels.exists?(title: 'consulta_agendada')).to be(true)
  end

  it 'com coluna configurada na tela Agendamentos: cria o card na coluna certa quando não existe' do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'stage_id' => stage_booked.id } })
    result = apply(:created)
    expect(result[:stage]).to eq('Agendamento de Consulta')
    expect(Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id).stage_id).to eq(stage_booked.id)
  end

  it 'move o card existente e dispara as automações da coluna nova' do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'stage_id' => stage_booked.id } })
    card = Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage_new.id)
    expect(CrmAutomationTriggerService).to receive(:new).with(hash_including(event_type: 'card_entered', new_stage: stage_booked)).and_call_original
    expect(CrmAutomationTriggerService).to receive(:new).with(hash_including(event_type: 'card_left')).and_call_original
    apply(:rescheduled)
    expect(card.reload.stage_id).to eq(stage_booked.id)
    expect(contact.reload.label_list).to include('consulta_reagendada')
  end

  it 'cancelamento: etiqueta de cancelada substitui a de agendada e o card vai para a coluna de cancelamento' do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'stage_id' => stage_booked.id, 'cancel_stage_id' => stage_canceled.id } })
    apply(:created)
    apply(:canceled)
    expect(contact.reload.label_list).to include('consulta_cancelada')
    expect(contact.label_list).not_to include('consulta_agendada')
    expect(Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id).stage_id).to eq(stage_canceled.id)
  end

  it 'sem coluna na tela, vale a "Ao agendar, mover para" do Atendente de Agendamento' do
    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'atendente_agendamento' => { 'after_booking_stage_id' => stage_booked.id } } })
    expect(described_class.booking_stage_id(account)).to eq(stage_booked.id)
    expect(apply(:created)[:stage]).to eq('Agendamento de Consulta')
  end

  it 'etiquetas desligadas: nada de etiqueta, card ainda se move' do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'labels_enabled' => false, 'stage_id' => stage_booked.id } })
    result = apply(:created)
    expect(result[:labels]).to eq([])
    expect(result[:stage]).to eq('Agendamento de Consulta')
  end

  it 'nunca levanta exceção para quem chama' do
    allow(described_class).to receive(:apply_labels).and_raise(StandardError, 'boom')
    expect(apply(:created)).to eq({})
  end

  it 'summary monta o texto da nota' do
    expect(described_class.summary({ labels: ['consulta_agendada'], stage: 'Agendamento de Consulta' }))
      .to eq('🏷️ consulta_agendada · card → Agendamento de Consulta')
    expect(described_class.summary({})).to eq('')
  end
end
