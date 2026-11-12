require 'rails_helper'

# 🏷️ 11/11/2026 (LIFE): follow-up PÓS-ORÇAMENTO — as mensagens sobre o orçamento contam do dia em que
# o cartão entrou em "Orçamento Enviado" (o cliente recebeu), só saem para quem tem a etiqueta
# `orcamento-enviado` e PARAM quando o cliente responde; as de reativação seguem por silêncio.
RSpec.describe Crm::FollowupBotJob do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ivan Coral') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let(:enviado) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 0) }
  let(:reader) { instance_double(Crm::FollowupConversationReader, call: { situacao: 'aberta', motivo: 'sumiu', fonte: 'ia' }) }
  let(:sent_at) { tz.parse('2026-11-10 10:00') } # terça: o orçamento foi enviado e o cartão entrou na coluna
  let(:bot) do
    steps = [
      { 'delay_value' => 1, 'delay_unit' => 'days', 'delay_from' => 'stage_entry', 'stop_on_reply' => true, 'message' => 'Conseguiu abrir?' },
      { 'delay_value' => 3, 'delay_unit' => 'days', 'delay_from' => 'stage_entry', 'stop_on_reply' => true, 'message' => 'O que achou?' },
      { 'delay_value' => 60, 'delay_unit' => 'days', 'message' => 'Quer que eu atualize?' }
    ]
    Crm::FollowupBot.create!(account: account, name: 'LIFE · Orçamento sem resposta', sender: admin, steps: steps,
                             stage_id: enviado.id, stage_ids: [enviado.id], required_labels: ['orcamento-enviado'])
  end

  before do
    allow(Crm::FollowupConversationReader).to receive(:new).and_return(reader)
    travel_to sent_at
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Segue a conta de luz', created_at: sent_at - 1.day)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin,
                     content: 'Segue o seu orçamento', created_at: sent_at)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: enviado)
  end

  def plan
    described_class.new.send(:plan_for, bot, conversation.reload, bot.ordered_steps)
  end

  def pending_days(the_plan)
    the_plan[:pending].map { |d| d[:step]['delay_value'] }
  end

  it 'sem a etiqueta ninguém é cutucado; com ela, os dias contam de quando o cliente recebeu', :aggregate_failures do
    expect(plan[:reason]).to eq('etiquetas')

    contact.add_labels(['orcamento-enviado'])
    the_plan = plan
    expect(pending_days(the_plan)).to eq([1, 3, 60])
    first = the_plan[:pending].first
    expect(first[:from_stage]).to be(true)
    expect(first[:due_at]).to be_within(2.hours).of(sent_at + 1.day)
  end

  it 'o cliente respondeu: as mensagens sobre o orçamento não saem mais; a de reativação continua na fila', :aggregate_failures do
    contact.add_labels(['orcamento-enviado'])
    travel_to sent_at + 2.days
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Recebi, vou ver com a minha esposa', created_at: sent_at + 26.hours)
    expect(plan[:reason]).to eq('paciente_falou_ultimo') # ele espera resposta: o robô não fala por cima

    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: admin,
                     content: 'Combinado, qualquer dúvida me chama', created_at: sent_at + 27.hours)
    expect(pending_days(plan)).to eq([60])
  end
end
