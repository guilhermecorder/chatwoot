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

  describe '16/11: números da proposta na mensagem' do
    let(:proposal) do
      { 'economia' => { 'mensal' => 380 },
        'investimento' => { 'preco_total' => 18_900, 'financiamento' => [{ 'parcelas' => 60, 'valor' => 520 }] } }
    end
    let(:step) do
      { 'delay_value' => 2, 'delay_unit' => 'days',
        'message' => 'Oi, [nome]! Em [financiamento] sai [financiamento_total]; no cartão, 6x de [cartao_6x]. Vale até [validade].' }
    end
    let(:job) { described_class.new }

    it 'preenche com os números da proposta do cliente', :aggregate_failures do
      Crm::Quote.create!(account: account, contact: contact, price: 18_900, kind: 'micro', payload: { 'proposta' => proposal })
      expect(job.send(:missing_quote_numbers, step, conversation)).to eq([])
      expect(job.send(:render_message, step['message'], conversation))
        .to eq("Oi, Ivan! Em 60x de R$ 520 sai R$ 31.200; no cartão, 6x de R$ 3.150. Vale até #{(sent_at + 7.days).strftime('%d/%m')}.")
    end

    it 'sem financiamento na proposta (ou sem orçamento): a etapa diz o que falta para pular', :aggregate_failures do
      expect(job.send(:missing_quote_numbers, step, conversation)).to contain_exactly('financiamento', 'financiamento_total', 'cartao_6x', 'validade')
      Crm::Quote.create!(account: account, contact: contact, price: 18_900, kind: 'micro',
                         payload: { 'proposta' => proposal.merge('investimento' => { 'preco_total' => 18_900 }) })
      expect(job.send(:missing_quote_numbers, step, conversation)).to contain_exactly('financiamento', 'financiamento_total')
    end

    it 'os campos de economia de 12/11 continuam com o texto neutro, sem pular' do
      eco = { 'message' => 'Economia de [economia_mes].' }
      expect(job.send(:missing_quote_numbers, eco, conversation)).to eq([])
      expect(job.send(:render_message, eco['message'], conversation)).to eq('Economia de na sua conta de luz.')
    end
  end
end
