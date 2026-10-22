require 'rails_helper'

# 📅 Item 364 (22/10): entradas das cargas em massa voltam a contar no dia real,
# só nas colunas em que a prova é a própria coisa (1ª mensagem, orçamento, cirurgia).
RSpec.describe Crm::StageLogRedate do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:load_at) { tz.parse('2026-07-10 01:00') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0) }
  let!(:novos) { pipeline.stages.create!(name: 'Novos Contatos', color: '#000', position: 0) }
  let!(:orcamento) { pipeline.stages.create!(name: 'Envio de Orçamento', color: '#000', position: 1) }
  let!(:agendamento) { pipeline.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 2) }

  # a carga: 30 cards na mesma coluna no mesmo minuto
  def load!(stage, count: 30)
    travel_to(load_at) do
      Array.new(count) do |i|
        contact = create(:contact, account: account, name: "Pessoa #{stage.name} #{i}")
        Crm::Contact.create!(contact_id: contact.id, pipeline_id: pipeline.id, stage_id: stage.id)
        contact
      end
    end
  end

  def talk!(contact, at, content: 'Oi', type: :incoming)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, content: content, message_type: type, created_at: at)
  end

  def entry(contact, stage)
    Crm::StageLog.joins(:crm_contact).find_by(crm_contacts: { contact_id: contact.id }, stage_id: stage.id)
  end

  it 'Novos Contatos e Envio de Orçamento voltam no dia real; agendamento e quem não tem prova ficam fora', :aggregate_failures do
    leads = load!(novos)
    budgets = load!(orcamento)
    booked = load!(agendamento)
    talk!(leads[0], tz.parse('2026-04-15 09:00'))
    talk!(leads[1], tz.parse('2026-07-10 00:30')) # mesmo dia da carga: não prova
    talk!(budgets[0], tz.parse('2026-03-01 09:00'))
    talk!(budgets[0], tz.parse('2026-03-02 10:00'), content: 'O investimento é R$ 4.900 por olho', type: :outgoing)
    talk!(budgets[1], tz.parse('2026-03-02 10:00'), content: 'Taxa de R$ 5', type: :outgoing) # valor irrisório não é orçamento
    talk!(booked[0], tz.parse('2026-02-01 09:00'))

    plans = described_class.plan(account)
    expect(described_class.apply!(plans)).to eq(2)

    expect(entry(leads[0], novos).entered_at).to eq(tz.parse('2026-04-15 09:00'))
    expect(entry(leads[0], novos).event_type).to eq('entered')
    expect(entry(budgets[0], orcamento).entered_at).to eq(tz.parse('2026-03-02 10:00'))
    expect(entry(leads[1], novos).entered_at).to eq(load_at)
    expect(entry(budgets[1], orcamento).entered_at).to eq(load_at)
    expect(entry(booked[0], agendamento).entered_at).to eq(load_at)
    expect(plans.find { |p| p.stage_name == 'Agendamento de Consulta' }.skip).to eq('coluna sem data confiável')
  end

  it 'desfaz: a entrada re-datada volta para a hora da carga, fora dos indicadores', :aggregate_failures do
    leads = load!(novos)
    talk!(leads[0], tz.parse('2026-04-15 09:00'))
    described_class.apply!(described_class.plan(account))

    expect(described_class.undo!(account)).to eq(1)
    log = entry(leads[0], novos)
    expect(log.entered_at).to eq(load_at)
    expect(log.event_type).to eq('bulk')
  end

  it 'já marcada como carga pelo item 309 também é re-datada' do
    leads = load!(novos)
    talk!(leads[0], tz.parse('2026-05-20 09:00'))
    Crm::StageLogBulk.mark!(account)

    described_class.apply!(described_class.plan(account))
    expect(entry(leads[0], novos).event_type).to eq('entered')
  end
end
