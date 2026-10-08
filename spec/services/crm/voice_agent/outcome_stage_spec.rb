require 'rails_helper'

# 📇 item 333: o card anda pela coluna escolhida para o RESULTADO da ligação
RSpec.describe Crm::VoiceAgent::OutcomeStage do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:entry) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 0) }
  let!(:lost) { Crm::Stage.create!(pipeline: pipeline, name: 'Perdido', position: 9) }
  let!(:surgery) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Agendada', position: 10) }
  let(:contact) { create(:contact, account: account, name: 'Maria Silva', phone_number: '+5511999990001') }
  let(:settings) { Crm::VoiceAgent::Settings.new(account) }

  before { CrmSetting.create!(account: account, ai_config: { 'voice' => { 'outcome_stages' => { 'sem_interesse' => lost.id } } }) }

  def call_with(outcome)
    Crm::Call.create!(account: account, inbox: inbox, contact: contact, meta_call_id: "el:#{SecureRandom.hex(4)}", provider: 'elevenlabs',
                      handled_by: 'ai', direction: :outbound, status: :completed, outcome: outcome, started_at: Time.current)
  end

  def card
    Crm::Contact.find_by(contact_id: contact.id, pipeline_id: pipeline.id)
  end

  it 'move o card para a coluna do resultado' do
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: entry.id)

    expect(described_class.apply!(call_with('sem_interesse'), settings)).to eq('Perdido')
    expect(card.stage_id).to eq(lost.id)
  end

  it 'resultado sem coluna escolhida não mexe em nada' do
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: entry.id)

    expect(described_class.apply!(call_with('quer_whatsapp'), settings)).to be_nil
    expect(card.stage_id).to eq(entry.id)
  end

  it 'nunca anda para trás (quem já está numa coluna depois fica onde está)' do
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: surgery.id)

    expect(described_class.apply!(call_with('sem_interesse'), settings)).to be_nil
    expect(card.stage_id).to eq(surgery.id)
  end

  it 'quem tem consulta futura marcada não sai do lugar' do
    Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: entry.id)
    account.tasks.create!(title: 'Consulta: Maria Silva', task_type: 'consulta', due_at: 2.days.from_now, status: :todo, contact: contact,
                          phone: contact.phone_number, creator: create(:user, account: account, role: :administrator))

    expect(described_class.apply!(call_with('sem_interesse'), settings)).to be_nil
    expect(card.stage_id).to eq(entry.id)
  end

  it 'paciente de parceiro nunca é mexido' do
    contact.add_labels(['of_clinica_x'])

    expect(described_class.apply!(call_with('sem_interesse'), settings)).to be_nil
    expect(card).to be_nil
  end
end
