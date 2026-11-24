require 'rails_helper'

# 🛡️ 24/11/2026 (LIFE): vigia dos orçamentos — "precisamos enviar 100% dos orçamentos, a não ser os que a gente não faz".
RSpec.describe Crm::KitQuoteWatchdogJob do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { tz.parse('2026-11-24 10:40') }
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account, name: 'Cássio Lima', phone_number: '+5519999990001') }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  before do
    travel_to now
    campos = %w[conta telhado].map { |k| { 'chave' => k, 'rotulo' => k } }
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: {
                                                              'agents' => { 'atendente_agendamento' => { 'orcamento_automatico' => true } },
                                                              'ficha_cliente' => { 'campos' => campos }
                                                            })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'É casa, minha mesma', created_at: now - 3.hours)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content: 'O imóvel é seu, alugado ou financiado?', created_at: now - 3.hours + 1.minute)
  end

  def ficha(values)
    Crm::ClientSummary.write!(contact, values, by: 'Atendente')
  end

  def plan
    described_class.plan(account, now).map { |action, conv, _motivo| [action, conv.id] }
  end

  def waiting_quote(created:, asked:)
    Crm::Quote.create!(account: account, contact: contact, price: 12_000, kind: 'micro', created_at: created,
                       payload: { Crm::KitQuote::Delivery::WAITING_KEY => asked.iso8601 })
  end

  it 'conta + telhado na ficha e nenhum orçamento: monta e envia', :aggregate_failures do
    ficha('conta' => 'R$ 300 por mês', 'telhado' => 'fibrocimento (Eternit)')
    expect(plan).to eq([[:montar, conversation.id]])

    expect { described_class.new.perform(now) }.to have_enqueued_job(Crm::KitQuoteAutoJob)
    expect(conversation.reload.additional_attributes.dig('cevico_orcamento_auto', 'origem')).to eq('vigia')
    expect(conversation.additional_attributes.dig('cevico_orcamento_vigia', 'tentativas')).to eq(1)
  end

  it 'sem a conta na ficha, nada' do
    ficha('telhado' => 'cerâmica')
    expect(plan).to be_empty
  end

  it 'caso especial com tarefa aberta (bateria, Mauro) fica com a equipe' do
    ficha('conta' => 'R$ 300 por mês', 'telhado' => 'cerâmica')
    Task.create!(account: account, creator: create(:user, account: account), contact_id: contact.id,
                 title: '🙋 Atendimento · Cássio — Cliente quer sistema com bateria')
    expect(plan).to be_empty
  end

  it 'Sem Interesse ou perda_* fica de fora', :aggregate_failures do
    ficha('conta' => 'R$ 300 por mês', 'telhado' => 'cerâmica')
    contact.add_labels(['perda_sem_interesse'])
    expect(plan).to be_empty
  end

  it 'conversa acontecendo (mensagem há menos de 2 h): espera' do
    ficha('conta' => 'R$ 300 por mês', 'telhado' => 'cerâmica')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contact,
                     content: 'Um minuto', created_at: now - 5.minutes)
    expect(plan).to be_empty
  end

  it 'no máximo 2 tentativas por dia' do
    ficha('conta' => 'R$ 300 por mês', 'telhado' => 'cerâmica')
    conversation.update!(additional_attributes: { 'cevico_orcamento_vigia' => { 'dia' => '2026-11-24', 'tentativas' => 2 } })
    expect(plan).to be_empty
  end

  describe 'orçamento preso no "me avisa que eu te mando"' do
    before { ficha('conta' => 'R$ 300 por mês', 'telhado' => 'cerâmica') }

    it 'há mais de 20 h e com o modelo do PDF aprovado: envia o PDF' do
      channel.update_columns(message_templates: [{ 'name' => 'life_orcamento_pdf', 'status' => 'APPROVED', 'language' => 'pt_BR' }]) # rubocop:disable Rails/SkipsModelValidations
      waiting_quote(created: now - 2.days, asked: now - 26.hours)
      expect(plan).to eq([[:enviar_pdf, conversation.id]])
    end

    it 'sem o modelo aprovado e com a janela fechada: não insiste no "pronto"' do
      waiting_quote(created: now - 2.days, asked: now - 26.hours)
      allow_any_instance_of(Conversation).to receive(:can_reply?).and_return(false) # rubocop:disable RSpec/AnyInstance
      expect(plan).to be_empty
    end

    it 'há menos de 20 h: ainda espera o cliente' do
      waiting_quote(created: now - 1.day, asked: now - 10.hours)
      expect(plan).to be_empty
    end

    it 'com mais de 5 dias: refaz com o preço de hoje' do
      waiting_quote(created: now - 6.days, asked: now - 6.days)
      expect(plan).to eq([[:refazer, conversation.id]])
    end
  end

  it 'fora do horário (antes das 8h ou depois das 20h) não faz nada' do
    ficha('conta' => 'R$ 300 por mês', 'telhado' => 'cerâmica')
    expect { described_class.new.perform(tz.parse('2026-11-24 22:40')) }.not_to have_enqueued_job(Crm::KitQuoteAutoJob)
  end
end
