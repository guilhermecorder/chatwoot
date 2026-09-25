require 'rails_helper'

# 💰 item 236 (25/09): a clínica manda um valor → card anda para "Envio de Orçamento"
RSpec.describe Crm::BudgetSideEffects do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Envio de Orçamento', color: '#000', position: 1)
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 2)
    end
  end
  let(:stages) { pipeline.stages.order(:position).to_a }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990001') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let!(:card) { Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages[0]) }

  def outgoing(text, private: false)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: text, private: private)
  end

  it 'reconhece valor em reais nos formatos comuns', :aggregate_failures do
    expect(described_class.price_message?(outgoing('A cirurgia fica R$ 5.700 por olho'))).to be true
    expect(described_class.price_message?(outgoing('fica em 5.700 reais'))).to be true
    expect(described_class.price_message?(outgoing('Oi, pode falar?'))).to be false
    expect(described_class.price_message?(outgoing('R$ 5.700', private: true))).to be false
    expect(described_class.price_message?(create(:message, account: account, inbox: inbox, conversation: conversation,
                                                           message_type: :incoming, content: 'R$ 5.700 é caro'))).to be false
  end

  it 'move o card para Envio de Orçamento (só pra frente) e nunca volta', :aggregate_failures do
    expect(described_class.apply(account: account, contact: contact, message: outgoing('Fica R$ 5.700'))).to eq('Envio de Orçamento')
    expect(card.reload.stage_id).to eq(stages[1].id)
    expect(Crm::StageLog.where(crm_contact_id: card.id, stage_id: stages[1].id)).to exist

    card.update!(stage_id: stages[2].id)
    expect(described_class.apply(account: account, contact: contact, message: outgoing('Lembrando: R$ 5.700'))).to be_nil
    expect(card.reload.stage_id).to eq(stages[2].id)
  end

  it 'pelo listener: mensagem enviada com valor move o card; mensagem sem valor não' do
    listener = CrmListener.instance
    m = outgoing('Segue o valor: R$ 4.200')
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: m))
    expect(card.reload.stage_id).to eq(stages[1].id)
  end

  it 'usa a coluna configurada em Agendamentos → Ajustes quando existe' do
    CrmSetting.create!(account: account, agenda_config: { 'booking' => { 'budget_stage_id' => stages[2].id } })
    expect(described_class.stage(account).name).to eq('Agendamento de Consulta')
  end
end
