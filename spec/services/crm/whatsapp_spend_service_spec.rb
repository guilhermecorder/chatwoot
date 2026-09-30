require 'rails_helper'

# 💸 item 303: Gasto do WhatsApp — atribuição por mensagem + fatura da Meta
RSpec.describe Crm::WhatsappSpendService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent, name: 'Vaneide') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999990000') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:since) { Time.zone.now.beginning_of_day - 2.days }
  let(:until_at) { Time.zone.now.end_of_day }
  let(:result) { described_class.new(account: account, since: since, until_at: until_at).call }
  let(:att) { result[:attributed] }

  # a factory inventa um User para toda mensagem de saída — sem sender = "sistema"
  def outgoing(attrs, at: Time.zone.now, sender: nil, status: :delivered)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                               sender: sender, status: status, created_at: at, additional_attributes: attrs)
    message.update_columns(sender_type: nil, sender_id: nil) if sender.nil? # rubocop:disable Rails/SkipsModelValidations
    message
  end

  def billing(type, category)
    { 'cevico_wa_billing' => { 'billable' => type == 'regular', 'category' => category, 'type' => type, 'model' => 'PMP' } }
  end

  before do
    Rails.cache.clear
    # robô: 3 balões na mesma resposta, grátis na janela de 24h (regra até 30/09)
    3.times do |i|
      outgoing({ 'cevico_ia_agent' => 'atendente_agendamento' }.merge(billing('free_customer_service', 'service')),
               at: Time.zone.now.advance(hours: -1, seconds: i * 3))
    end
    # lembrete (modelo de utilidade) fora da janela: cobrado
    outgoing({ 'cevico_auto' => 'lembrete_consulta' }.merge(billing('regular', 'utility')))
    # follow-up com modelo de marketing: cobrado
    outgoing({ 'cevico_followup_bot_id' => 7, 'cevico_followup_step' => 1 }.merge(billing('regular', 'marketing')))
    # pessoa da equipe respondendo um lead de anúncio: grátis pelas 72h
    outgoing(billing('free_entry_point', 'service'), sender: user)
    # mensagem antiga, sem a marca da Meta
    outgoing({})
    # fora do período: não entra
    outgoing(billing('regular', 'marketing'), at: since - 1.day)
    # falhou: não entra (a Meta não cobra o que não entregou)
    outgoing(billing('regular', 'marketing'), status: :failed)
  end

  it 'conta as mensagens do período por tipo de cobrança' do
    expect(att[:messages]).to eq(7)
    expect(att[:billable]).to eq(2)
    expect(att[:free_window]).to eq(3)
    expect(att[:free_ad]).to eq(1)
    expect(att[:unknown]).to eq(1)
  end

  it 'estima o custo pelas tarifas padrão em reais (marketing + utilidade)' do
    expect(result[:rates]['currency']).to eq('BRL')
    expect(att[:cost]).to eq((0.3217 + 0.035).round(2))
    # regra de outubro: os 3 balões na janela passam a custar serviço (R$ 0,035)
    expect(att[:simulated_october_cost]).to eq((0.3217 + 0.035 + (3 * 0.035)).round(2))
  end

  it 'diz quem gastou, com nome, tipo e cor' do
    by_key = att[:by_who].index_by { |r| r[:key] }
    expect(by_key['ia:atendente_agendamento']).to include(kind: 'robo', messages: 3, free_window: 3, cost: 0.0)
    expect(by_key['auto:lembrete_consulta']).to include(kind: 'automacao', label: 'Lembrete consulta (automático)', billable: 1, cost: 0.04)
    expect(by_key['followup']).to include(kind: 'automacao', cost: 0.32)
    expect(by_key["user:#{user.id}"]).to include(kind: 'equipe', label: 'Vaneide', free_ad: 1)
    expect(by_key['sistema']).to include(unknown: 1)
    # ordenado pelo custo
    expect(att[:by_who].first[:key]).to eq('followup')
  end

  it 'mede os balões por resposta do robô' do
    expect(att[:balloons]).to eq(robot_messages: 3, robot_replies: 1, per_reply: 3.0)
  end

  it 'monta o dia a dia com um ponto por dia do período' do
    expect(att[:daily].size).to eq(3)
    today = att[:daily].last
    expect(today[:messages]).to eq(7)
    expect(today[:cost]).to eq(0.36)
  end

  it 'respeita as tarifas editadas pelo admin' do
    Crm::WhatsappPricing.save(account, 'marketing' => '0,50', 'utility' => 0.1)
    expect(result[:rates]).to include('marketing' => 0.5, 'utility' => 0.1, 'edited' => true)
    expect(att[:cost]).to eq(0.6)
  end

  context 'when a Meta já mandou a fatura' do
    before do
      Crm::WhatsappCharge.create!(account: account, waba_id: 'w1', phone_number: channel.phone_number.delete('^0-9'), day: Time.zone.today,
                                  category: 'marketing', pricing_type: 'regular', volume: 10, cost: 3.217, currency: 'BRL')
      Crm::WhatsappCharge.create!(account: account, waba_id: 'w1', phone_number: channel.phone_number.delete('^0-9'), day: Time.zone.today,
                                  category: 'service', pricing_type: 'free_customer_service', volume: 40, cost: 0, currency: 'BRL')
      Crm::WhatsappCharge.create!(account: account, waba_id: 'w1', phone_number: '', day: 3.months.ago.to_date,
                                  category: 'utility', pricing_type: 'regular', volume: 5, cost: 0.175, currency: 'BRL')
    end

    it 'mostra o valor real e os grátis' do
      meta = result[:meta]
      expect(meta[:synced]).to be(true)
      expect(meta[:currency]).to eq('BRL')
      expect(meta[:cost]).to eq(3.22)
      expect(meta[:billable_volume]).to eq(10)
      expect(meta[:free_window_volume]).to eq(40)
    end

    it 'abre por categoria, por número (com o nome da caixa) e por mês' do
      meta = result[:meta]
      expect(meta[:by_category].first).to include(category: 'marketing', volume: 10)
      expect(meta[:by_phone].first[:inbox]).to eq(inbox.name)
      expect(meta[:months].map { |m| m[:cost] }).to eq([0.18, 3.22])
    end
  end

  it 'sem fatura, avisa que ainda não sincronizou' do
    expect(result[:meta]).to eq(synced: false, synced_at: nil)
  end
end
