require 'rails_helper'

# 👋 08/11 (LIFE): lead do formulário do Meta → mensagem modelo no WhatsApp na
# hora (nome, cidade, valor da conta) e a conversa fica pronta para a IA.
RSpec.describe Crm::MetaLeadWelcome do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) do
    channel.update_columns(message_templates: [{ 'name' => 'life_lead_formulario', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                                 'category' => 'UTILITY', 'components' => [] }])
    channel.inbox
  end
  let(:preview) do
    "Oi, {{1}}! Aqui é o Fernando, da Life Energia Solar.\n\nRecebi o seu pedido de orçamento. Vi que você é de {{2}} " \
      "e gasta mais ou menos {{3}} de luz por mês.\n\nPosso te fazer umas perguntas rápidas por aqui pra montar o seu orçamento certinho?"
  end
  let(:welcome_cfg) do
    { 'enabled' => true, 'template_name' => 'life_lead_formulario', 'language' => 'pt_BR', 'inbox_id' => inbox.id, 'preview' => preview }
  end
  let(:lead) do
    { 'id' => '111', 'form_id' => '900', 'created_time' => 5.minutes.ago.iso8601, 'ad_name' => 'LF-040 conta 1000',
      'field_data' => [
        { 'name' => 'full_name', 'values' => ['maria aparecida souza'] },
        { 'name' => 'phone_number', 'values' => ['19 99888-7766'] },
        { 'name' => 'city', 'values' => ['santa barbara d oeste'] },
        { 'name' => 'qual_o_valor_médio_da_sua_conta_de_luz?', 'values' => ['r$_500_a_r$_800'] }
      ] }
  end

  before do
    create(:user, account: account, role: :administrator) # a tarefa precisa de quem a criou (na LIFE, o Fernando)
    stub_request(:get, %r{graph\.facebook\.com/.*/900}).to_return(status: 200, body: { name: 'FORM INST' }.to_json,
                                                                    headers: { 'Content-Type' => 'application/json' })
    CrmSetting.find_or_create_by!(account: account).update!(
      meta_ads_config: { 'page_id' => '42', 'page_access_token' => 'tok', 'lead_welcome' => welcome_cfg }
    )
  end

  def ingest(data = lead)
    Crm::MetaLeadIngestService.new(account: account).ingest(data['id'], prefetched: data)
  end

  it 'lead novo recebe a mensagem modelo com nome, cidade e valor, e a conversa fica com as respostas', :aggregate_failures do
    expect(ingest).to eq(:imported)

    contact = account.contacts.last
    expect(contact.phone_number).to eq('+5519998887766') # sem o 55 no formulário → ganha o 55
    message = account.messages.outgoing.last
    expect(message.inbox).to eq(inbox)
    expect(message.additional_attributes['template_params']).to include('name' => 'life_lead_formulario', 'language' => 'pt_BR')
    expect(message.additional_attributes.dig('template_params', 'processed_params', 'body'))
      .to eq('1' => 'Maria', '2' => "Santa Barbara D Oeste", '3' => 'R$ 500 a R$ 800')
    expect(message.content).to start_with('Oi, Maria! Aqui é o Fernando').and include('gasta mais ou menos R$ 500 a R$ 800')
    expect(message.additional_attributes['cevico_auto']).to be_present # robô: não pausa a IA
    note = message.conversation.messages.where(private: true).last
    expect(note.content).to include('Lead do formulário do Meta').and include('LF-040 conta 1000')
    expect(message.conversation.additional_attributes['meta_lead_id']).to eq('111')
  end

  it 'o mesmo lead (webhook + busca de 5 min) não ganha duas boas-vindas' do
    ingest
    expect(ingest).to eq(:duplicate)
    expect(account.messages.outgoing.count).to eq(1)
  end

  it 'sem cidade ou valor no formulário: não manda e abre tarefa para a equipe chamar', :aggregate_failures do
    data = lead.merge('id' => '222', 'field_data' => lead['field_data'].first(2))
    expect(ingest(data)).to eq(:imported)
    expect(account.messages.outgoing.count).to eq(0)
    task = account.tasks.last
    expect(task.title).to include('Chamar lead do formulário do Meta').and include('cidade, valor')
  end

  it 'lead velho (importação retroativa) entra no sistema mas não recebe a mensagem' do
    expect(ingest(lead.merge('id' => '333', 'created_time' => 3.days.ago.iso8601))).to eq(:imported)
    expect(account.messages.outgoing.count).to eq(0)
  end

  it 'quem já está conversando na caixa ganha só a nota, sem a mensagem modelo', :aggregate_failures do
    contact = create(:contact, account: account, name: 'Maria', phone_number: '+5519998887766')
    ci = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5519998887766')
    conv = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci)
    create(:message, conversation: conv, account: account, inbox: inbox, message_type: :incoming, content: 'oi')

    ingest
    expect(account.messages.outgoing.count).to eq(0)
    expect(conv.messages.where(private: true).last.content).to include('também preencheu o formulário')
  end

  it 'modelo ainda não aprovado pelo Meta: não tenta mandar, abre tarefa', :aggregate_failures do
    channel.update_columns(message_templates: [], message_templates_last_updated: 1.minute.ago)
    expect(ingest).to eq(:imported)
    expect(account.messages.outgoing.count).to eq(0)
    expect(account.tasks.last.title).to include('ainda não foi aprovada')
  end

  it 'boas-vindas desligada: segue o jeito antigo (sem mensagem modelo)' do
    CrmSetting.find_by(account: account).update!(meta_ads_config: { 'page_id' => '42', 'page_access_token' => 'tok' })
    expect(ingest).to eq(:imported)
    expect(account.messages.outgoing.count).to eq(0)
  end

  it 'a Meta recusou a mensagem: a checagem abre tarefa para a equipe', :aggregate_failures do
    ingest
    message = account.messages.outgoing.last
    message.update!(status: :failed, external_error: '131026 número sem WhatsApp')
    Crm::MetaLeadWelcomeCheckJob.perform_now(message.id, '111')
    expect(account.tasks.last.title).to include('a Meta recusou a mensagem de boas-vindas')
  end

  it 'a busca de 5 min chama a importação só para contas com página e token' do
    other = create(:account)
    CrmSetting.find_or_create_by!(account: other).update!(meta_ads_config: { 'pixel_id' => '1' })
    expect { Crm::MetaLeadPollJob.perform_now }.to have_enqueued_job(Crm::MetaLeadImportJob).with(account.id, kind_of(Integer)).exactly(:once)
  end

  it 'sanitize_config limpa o que vem da tela' do
    cfg = described_class.sanitize_config('enabled' => '1', 'template_name' => 'Life Lead-Formulario!', 'inbox_id' => '7')
    expect(cfg).to include('enabled' => true, 'template_name' => 'lifeleadformulario', 'language' => 'pt_BR', 'inbox_id' => 7,
                           'max_age_hours' => 24)
  end
end
