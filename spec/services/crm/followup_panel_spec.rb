require 'rails_helper'

# 📬 22/11/2026 (LIFE): o follow-up da venda no Meu Painel — envios dos robôs por momento e por mensagem,
# quem leu, quem respondeu (até 48 h) e quem andou no funil (até 7 dias).
RSpec.describe Crm::FollowupPanel do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let(:conta) { Crm::Stage.create!(pipeline: pipeline, name: 'Solicitação da Conta', position: 1) }
  let(:enviado) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 4) }
  let(:vistoria) { Crm::Stage.create!(pipeline: pipeline, name: 'Vistoria Técnica Agendada', position: 6) }
  let(:now) { tz.parse('2026-11-20 10:00') }
  let(:orcamento) do
    steps = [
      { 'delay_value' => 3, 'delay_unit' => 'days', 'delay_from' => 'stage_entry', 'message' => 'Oi, [nome]! Resumo da proposta.' },
      { 'delay_value' => 1, 'delay_unit' => 'days', 'delay_from' => 'stage_entry', 'message' => 'Saudações, [nome]! É possível?' }
    ]
    Crm::FollowupBot.create!(account: account, name: 'LIFE · Orçamento sem resposta (1 e 3 dias)', sender: admin, steps: steps,
                             stage_id: enviado.id, stage_ids: [enviado.id])
  end
  let(:pendente) do
    Crm::FollowupBot.create!(account: account, name: 'LIFE · Conta pendente (2 dias)', sender: admin, active: false,
                             steps: [{ 'delay_value' => 2, 'delay_unit' => 'days', 'message' => 'Oi, [nome]! Falta o valor.' }],
                             stage_id: conta.id, stage_ids: [conta.id])
  end

  before { travel_to now }

  def person(name)
    contact = create(:contact, account: account, name: name)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: enviado)
    [contact, conversation, card]
  end

  def nudge(conversation, bot, step, at, status: :sent, stage: enviado) # rubocop:disable Metrics/ParameterLists
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin,
                     content: 'cutucada', created_at: at, status: status,
                     additional_attributes: { cevico_followup_bot_id: bot.id, cevico_followup_step: step,
                                              cevico_followup_stage_id: stage.id })
  end

  def reply(conversation, at)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     sender: conversation.contact, content: 'Oi, pode mandar', created_at: at)
  end

  def report(since: now - 7.days)
    described_class.new(account, since: since, until_at: now).call
  end

  it 'conta envios, lidas, falhas, respostas em 48 h e quem andou no funil, por momento e por mensagem', :aggregate_failures do
    pendente
    _, ana, ana_card = person('Ana Souza')
    _, bia, = person('Bia Lima')
    nudge(ana, orcamento, 1, now - 3.days, status: :read)
    reply(ana, now - 3.days + 5.hours)
    Crm::StageLog.create!(crm_contact: ana_card, stage_id: vistoria.id, stage_name: vistoria.name, entered_at: now - 2.days)
    nudge(bia, orcamento, 1, now - 3.days, status: :failed)
    nudge(bia, orcamento, 0, now - 1.day, status: :delivered)
    reply(bia, now - 1.day + 3.days) # depois das 48 h: não conta

    result = report
    moment = result[:moments].find { |m| m[:name] == 'Orçamento sem resposta' }
    expect(moment).to include(sent: 3, people: 2, read: 1, failed: 1, replied: 1, moved: 1, where: 'Orçamento Enviado', active: true)
    expect(moment[:steps].map { |s| [s[:when], s[:sent], s[:replied]] })
      .to eq([['1 dia do envio', 2, 1], ['3 dias do envio', 1, 0]])
    expect(moment[:steps].first[:text]).to eq('Saudações, Fulano! É possível?')
    expect(result[:total]).to include(sent: 3, people: 2, replied: 1, moved: 1, failed: 1)
    expect(result[:daily].sum { |d| d[:sent] }).to eq(3)
  end

  it 'mostra o robô desligado só se mandou algo no período; a retomada aparece sempre', :aggregate_failures do
    pendente
    orcamento
    names = report[:moments].map { |m| m[:name] }
    expect(names).to eq(['Orçamento sem resposta', 'Retomada combinada'])

    _, carla, = person('Carla Dias')
    nudge(carla, pendente, 0, now - 1.day, stage: conta)
    moment = report[:moments].find { |m| m[:name] == 'Conta pendente' }
    expect(moment).to include(sent: 1, active: false, where: 'Solicitação da Conta')
    expect(report[:moments].first[:name]).to eq('Conta pendente') # mais cedo no funil vem antes
  end

  it 'mensagem fora do período não entra' do
    orcamento
    _, dani, = person('Dani Rocha')
    nudge(dani, orcamento, 0, now - 20.days)
    expect(report[:total][:sent]).to eq(0)
  end
end
