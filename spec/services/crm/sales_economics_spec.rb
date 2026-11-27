require 'rails_helper'

# 📊 27/11/2026 (LIFE): custos e retorno no Meu Painel — custos lançados (rateados) × medidos, retorno das vendas,
# ROAS, custo por etapa e tempos; e a equipe no horário comercial (só mensagem escrita por gente).
RSpec.describe Crm::SalesEconomics do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { tz.parse('2026-11-27 17:00') } # sexta
  let(:account) { create(:account) }
  let!(:fernando) { create(:user, account: account, role: :administrator, name: 'Fernando Srair') }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life', position: 0) }
  let!(:stages) do
    ['Novos Contatos', 'Solicitação da Conta', 'Orçamento a fazer', 'Orçamento Enviado', 'Negociação',
     'Contrato Assinado'].each_with_index.to_h { |name, i| [name, Crm::Stage.create!(pipeline: pipeline, name: name, position: i)] }
  end
  let(:costs) { Crm::SalesCosts.new(account) }

  before do
    travel_to now
    allow(Crm::UsdRateService).to receive_messages(rates_for: {}, last_known: { rate: 5.0 })
  end

  def report(since: tz.parse('2026-11-01 00:00'), until_at: now)
    described_class.new(account, since: since, until_at: until_at).call
  end

  describe 'custos' do
    it 'rateia o lançado pelos dias e o lançado vence o medido', :aggregate_failures do
      costs.create!(category: 'trafego', amount: '3.000,00', date: '2026-11-15', span: 'mes')
      costs.create!(category: 'ia', amount: '700', date: '2026-11-23', span: 'semana', note: 'Anthropic')
      Crm::AiUsage.create!(account: account, agent_key: 'atendente', model: 'x', cost_usd: 10, created_at: now - 1.day)

      week = report(since: tz.parse('2026-11-23 00:00'), until_at: tz.parse('2026-11-29 23:59'))[:costs]
      rows = week[:rows].index_by { |r| r[:key] }
      expect(rows['trafego'][:valor]).to eq(700.0) # 3.000 ÷ 30 dias × 7
      expect(rows['trafego'][:fonte]).to eq('lancado')
      expect(rows['ia'][:valor]).to eq(700.0)
      expect(rows['ia'][:medido]).to be_positive
      expect(week[:total]).to eq(rows.values.sum { |r| r[:valor].to_f }.round(2))
    end

    it 'sem lançamento cobrindo o período, usa o medido' do
      Crm::AiUsage.create!(account: account, agent_key: 'atendente', model: 'x', cost_usd: 2, created_at: now - 1.day)
      row = report[:costs][:rows].find { |r| r[:key] == 'ia' }
      expect(row).to include(fonte: 'medido')
      expect(row[:valor]).to be_positive
    end

    it 'recusa categoria ou período desconhecido' do
      expect { costs.create!(category: 'aluguel', amount: 10, date: '2026-11-01', span: 'mes') }.to raise_error(ArgumentError)
      expect { costs.create!(category: 'ia', amount: 10, date: '2026-11-01', span: 'ano') }.to raise_error(ArgumentError)
    end
  end

  describe 'retorno e ROAS' do
    it 'conta a venda quando o cartão entra em Contrato Assinado no período, uma vez só', :aggregate_failures do
      costs.create!(category: 'trafego', amount: '1000', date: '2026-11-01', span: 'mes')
      contact = create(:contact, account: account, name: 'Paulo')
      card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages['Novos Contatos'], created_at: now - 10.days)
      card.update!(value: 15_000)
      card.update!(stage: stages['Contrato Assinado'])
      card.update!(stage: stages['Negociação'])
      card.update!(stage: stages['Contrato Assinado'])

      out = report
      expect(out[:revenue]).to include(total: 15_000.0, sales: 1)
      expect(out[:roas]).to eq((15_000.0 / out[:costs][:total]).round(2))
      expect(out[:times][:ate_fechar][:n]).to eq(1)
    end

    it 'sem valor no cartão, usa o último orçamento enviado' do
      contact = create(:contact, account: account, name: 'Rita')
      Crm::Quote.create!(account: account, contact: contact, price: 12_340, sent_at: now - 3.days, payload: {})
      card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages['Orçamento Enviado'])
      card.update!(stage: stages['Contrato Assinado'])
      expect(report[:revenue][:total]).to eq(12_340.0)
    end
  end

  describe 'equipe (Crm::TeamResponse)' do
    let(:contact) { create(:contact, account: account, name: 'Cliente') }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    def msg(at, type: :outgoing, sender: fernando, attrs: {}, content: 'oi')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type,
                       sender: type == :incoming ? contact : sender, content: content, created_at: at,
                       additional_attributes: attrs)
    end

    it 'ignora o que o robô manda em nome do Fernando e mede resposta e intervalos', :aggregate_failures do
      Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stages['Orçamento Enviado'], assignee: fernando)
      msg(tz.parse('2026-11-27 08:00'), attrs: { 'cevico_followup_bot_id' => 1 }, content: 'Bom dia! robô')
      msg(tz.parse('2026-11-27 09:00'), type: :incoming)
      msg(tz.parse('2026-11-27 10:30'), attrs: { 'cevico_wa_billing' => { 'pricing_type' => 'regular' } })
      msg(tz.parse('2026-11-27 14:00'))

      team = described_class.new(account, since: tz.parse('2026-11-27 00:00'), until_at: now).call[:team]
      person = team[:people].find { |p| p[:name] == 'Fernando Srair' }
      expect(person[:messages]).to eq(2)
      expect(person[:owner]).to be(true)
      expect(person[:reply][:mediana_min]).to eq(90)
      expect(person[:gaps].first).to include(from: '10:30', to: '14:00', minutes: 210)
      expect(person[:presence].find { |s| s[:hour] == 8 }[:days]).to eq(0)
      expect(person[:days_absent]).to eq(0)
    end

    it 'mede o pedido de atendimento humano em horário comercial e lista quem espera', :aggregate_failures do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                       content: '🙋 Atendente pediu ATENDIMENTO HUMANO nesta conversa (preço)', created_at: tz.parse('2026-11-26 17:30'))
      msg(tz.parse('2026-11-27 08:30'))
      other = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account, name: 'Zé'))
      create(:message, account: account, inbox: inbox, conversation: other, message_type: :activity,
                       content: '🙋 Atendente pediu ATENDIMENTO HUMANO nesta conversa (CPF)', created_at: tz.parse('2026-11-27 15:00'))

      req = described_class.new(account, since: tz.parse('2026-11-26 00:00'), until_at: now).call[:team][:human_requests]
      expect(req).to include(total: 2, answered: 1, mediana_min: 60, sem_resposta: 1) # 17h30–18h + 8h–8h30
      expect(req[:sem_resposta_lista].first).to include(name: 'Zé', minutes: 120)
    end
  end

  it 'minutos comerciais pulam a noite, o domingo e os feriados', :aggregate_failures do
    expect(Crm::TeamResponse.business_minutes(tz.parse('2026-11-28 11:00'), tz.parse('2026-11-30 09:00'))).to eq(120)
    expect(Crm::TeamResponse.window(Date.new(2026, 11, 20))).to be_nil # Consciência Negra
  end
end
