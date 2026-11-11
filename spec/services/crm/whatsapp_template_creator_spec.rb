require 'rails_helper'

# 📨 item 391: criar mensagem modelo e pedir a aprovação à Meta daqui do sistema
RSpec.describe Crm::WhatsappTemplateCreator do
  let(:account) { create(:account) }
  let(:inbox) { whatsapp_inbox('111') }
  let(:spec) do
    { name: 'retorno_combinado', category: 'marketing', header: 'Combinado é combinado',
      body: 'Oi, {{1}}! Aqui é o Guilherme, da CEVICO. Fiquei de te chamar de volta.', footer: 'CEVICO',
      buttons: ['Ver horários', 'Agora não'], examples: ['Maria'] }
  end
  let(:meta_url) { %r{graph\.facebook\.com/v[\d.]+/\d+/message_templates} }

  def whatsapp_inbox(waba)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    channel.update_column(:provider_config, channel.provider_config.merge('business_account_id' => waba)) # rubocop:disable Rails/SkipsModelValidations
    channel.inbox.reload
  end

  before do
    stub_request(:get, meta_url).to_return(status: 200, body: { data: [{ name: 'retorno_combinado', status: 'PENDING' }] }.to_json,
                                           headers: { 'Content-Type' => 'application/json' })
  end

  it 'pede a aprovação à Meta no formato dela e devolve "em análise"' do
    create_call = stub_request(:post, 'https://graph.facebook.com/v22.0/111/message_templates')
                  .to_return(status: 200, body: { id: '987', status: 'PENDING', category: 'MARKETING' }.to_json,
                             headers: { 'Content-Type' => 'application/json' })

    result = described_class.new(account, spec).call([inbox])

    expect(result).to include(ok: true, errors: [])
    expect(result[:results]).to contain_exactly(include(inbox_id: inbox.id, ok: true, status: 'PENDING', template_id: '987'))
    expect(create_call.with(headers: { 'Authorization' => 'Bearer test_key' }) do |req|
      body = JSON.parse(req.body)
      body['name'] == 'retorno_combinado' && body['language'] == 'pt_BR' && body['category'] == 'MARKETING' &&
        body['components'] == [
          { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Combinado é combinado' },
          { 'type' => 'BODY', 'text' => spec[:body], 'example' => { 'body_text' => [['Maria']] } },
          { 'type' => 'FOOTER', 'text' => 'CEVICO' },
          { 'type' => 'BUTTONS',
            'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ver horários' }, { 'type' => 'QUICK_REPLY', 'text' => 'Agora não' }] }
        ]
    end).to have_been_made.once
    expect(inbox.channel.reload.message_templates).to eq([{ 'name' => 'retorno_combinado', 'status' => 'PENDING' }])
  end

  it 'pede uma vez só para números da mesma conta do WhatsApp e uma vez por conta diferente' do
    same = whatsapp_inbox('111')
    other = whatsapp_inbox('222')
    stub_request(:post, meta_url)
      .to_return(status: 200, body: { id: '1', status: 'PENDING' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = described_class.new(account, spec).call([inbox, same, other])

    expect(result[:results].pluck(:inbox_id)).to contain_exactly(inbox.id, same.id, other.id)
    expect(a_request(:post, 'https://graph.facebook.com/v22.0/111/message_templates')).to have_been_made.once
    expect(a_request(:post, 'https://graph.facebook.com/v22.0/222/message_templates')).to have_been_made.once
  end

  it 'devolve a explicação da Meta quando ela recusa (e segue nos outros números)' do
    other = whatsapp_inbox('222')
    stub_request(:post, 'https://graph.facebook.com/v22.0/111/message_templates')
      .to_return(status: 400, headers: { 'Content-Type' => 'application/json' },
                 body: { error: { message: 'Invalid parameter', error_user_title: 'Já existe conteúdo neste idioma',
                                  error_user_msg: 'Já existe um modelo com esse nome em Portuguese (BR).' } }.to_json)
    stub_request(:post, 'https://graph.facebook.com/v22.0/222/message_templates')
      .to_return(status: 200, body: { id: '2', status: 'PENDING' }.to_json, headers: { 'Content-Type' => 'application/json' })

    result = described_class.new(account, spec).call([inbox, other])

    expect(result[:ok]).to be(false)
    refused = result[:results].find { |row| row[:inbox_id] == inbox.id }
    expect(refused).to include(ok: false, error: 'Já existe conteúdo neste idioma: Já existe um modelo com esse nome em Portuguese (BR).')
    expect(result[:results].find { |row| row[:inbox_id] == other.id }).to include(ok: true)
  end

  it 'não chama a Meta quando o modelo está errado e explica em português' do
    bad = spec.merge(name: 'Retorno Combinado', body: '{{1}}, tudo bem? Veja {{3}}', buttons: ['a' * 26, 'x', 'x', 'y'], header: "Olá\n*você*")

    result = described_class.new(account, bad).call([inbox])

    expect(result[:ok]).to be(false)
    expect(result[:errors].join(' ')).to include('letras minúsculas', 'título', 'começar nem terminar', 'no máximo 3 botões')
    expect(a_request(:post, meta_url)).not_to have_been_made
  end

  it 'cobra exemplo para cada campo e a ordem 1, 2, 3' do
    expect(described_class.new(account, spec.merge(examples: [])).call([inbox])[:errors].first).to include('exemplo para cada campo')
    expect(described_class.new(account, spec.merge(body: 'Oi {{2}}, tudo bem?')).call([inbox])[:errors].first).to include('em ordem')
  end

  it 'só aceita número ligado direto à Meta' do
    web = create(:inbox, account: account)

    result = described_class.new(account, spec).call([web])

    expect(result[:errors]).to include('Escolha pelo menos um número de WhatsApp ligado direto à Meta.')
  end

  it 'não devolve erro técnico nem token quando a Meta está fora do ar' do
    stub_request(:post, meta_url).to_raise(Net::ReadTimeout)

    result = described_class.new(account, spec).call([inbox])

    expect(result[:results].first).to include(ok: false, error: 'Não consegui falar com a Meta agora. Tente de novo em alguns minutos.')
  end
end
