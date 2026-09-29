require 'rails_helper'

# 🔗 Item 287: link SÓ DE LEITURA da análise de um criativo (token assinado, 30 dias).
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Link de leitura da análise de criativo', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:since_date) { Date.current - 29 }
  let(:until_date) { Date.current }
  let(:link) { Crm::CreativeShareLink.generate(account: account, ad_id: '2301', since_date: since_date, until_date: until_date) }
  let(:finance_link) do
    Crm::CreativeShareLink.generate(account: account, ad_id: '2301', since_date: since_date, until_date: until_date, finance: true)
  end
  let(:finance_keys) { /"(spend|cost_[a-z_]+|cpm|cpc|roas|revenue)"/ }
  let(:path) { "/criativos/analise/#{link[:token]}" }

  before do
    CrmSetting.create!(account: account, meta_ads_config: { 'access_token' => 'simulate', 'ad_account_id' => 'act_1' })
    Crm::AdInsightsSyncService.new(account: account).call
    Crm::AdVideoTranscriptionService.new(Crm::AdCreative.find_by!(account: account, ad_id: '2301')).perform
    Rails.cache.clear
  end

  it 'token válido devolve a análise daquele anúncio naquele período (JSON e página)' do
    get "#{path}.json"
    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json['ad']['name']).to include('Enxergar sem óculos')
    expect(json['period']).to include('since' => since_date.iso8601, 'until' => until_date.iso8601, 'days' => 30)
    expect(json['transcript']['text']).to include('WhatsApp')
    expect(json['transcript']['segments'].size).to eq(3)
    expect(json['texts']['button']).to be_present
    expect(json['retention']).to include('source' => 'meta_curve', 'axis' => 'seconds')
    expect(json['retention']['clicks']['marks'].size).to eq(6)
    expect(json['blocks'].pluck('key')).to include('leitura', 'numeros', 'indicadores', 'jornada', 'retencao', 'quedas', 'cliques',
                                                   'transcricao', 'textos')
    expect(json['text']).to include('ANÁLISE DO CRIATIVO', 'TRANSCRIÇÃO DO VÍDEO', 'TEXTOS DO ANÚNCIO NA META')
    expect(json['expires_at']).to be_present

    get path
    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Robots-Tag']).to include('noindex')
    expect(response.body).to include('noindex', 'Copiar tudo', 'Este link vale até', 'Curva de retenção', 'Enxergar sem óculos')
  end

  it 'token vencido ou adulterado é recusado com a página "link vencido"' do
    token = link[:token]
    get "/criativos/analise/#{token[0..-6]}AAAAA"
    expect(response).to have_http_status(:gone)
    expect(response.body).to include('Este link venceu')

    get '/criativos/analise/qualquer-coisa.json'
    expect(response).to have_http_status(:gone)
    expect(response.parsed_body).to eq('error' => 'link vencido')

    # token de outro propósito (assinado pelo sistema, mas não é de análise) não abre
    payload = [account.id, '2301', since_date.iso8601, until_date.iso8601, 30.days.from_now.to_i]
    other = Crm::CreativeShareLink.verifier.encrypt_and_sign(payload, purpose: :outro)
    get "/criativos/analise/#{other}"
    expect(response).to have_http_status(:gone)

    travel_to(31.days.from_now) do
      get path
      expect(response).to have_http_status(:gone)
      expect(response.body).not_to include('Enxergar sem óculos')
    end
  end

  it 'não mostra nome, telefone nem qualquer dado de paciente, nem ids e chaves da Meta' do
    creator = create(:user, account: account)
    patient = create(:contact, account: account, name: 'Marinalva Paciente Teste', phone_number: '+5511977776666',
                               email: 'marinalva@paciente.test',
                               additional_attributes: { 'meta_ads' => { 'source_id' => '2301', 'captured_at' => 2.days.ago.iso8601 } })
    account.tasks.create!(title: 'consulta da Marinalva', task_type: 'consulta', contact_id: patient.id, creator: creator)

    [path, "#{path}.json"].each do |url|
      Rails.cache.clear
      get url
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).not_to include('Marinalva')
      expect(body).not_to include('977776666')
      expect(body).not_to include('paciente.test')
      expect(body).not_to include('simulate') # chave da Meta
      expect(body).not_to include('act_1')
      expect(body).not_to match(/"(ad_id|video_id|campaign_id|account_id|contact_id)"/)
    end
    get "#{path}.json"
    expect(response.parsed_body['journey'].find { |n| n['label'] == 'Leads' }['value']).to eq('1')
  end

  it 'rodada 2: a versão SEM dados financeiros (padrão) não traz nenhum valor em R$ nem chave financeira' do
    expect(link[:finance]).to be(false)
    get "#{path}.json"
    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json['finance']).to be(false)
    expect(json['finance_label']).to eq('Sem dados financeiros')
    expect(response.body).not_to include('R$')
    expect(response.body).not_to match(finance_keys)
    expect(response.body).not_to match(/ROAS|Investido|Custo por/i)
    labels = json['numbers'].pluck('label') + json['journey'].pluck('label') + json['indicators'].pluck('label')
    expect(labels).to include('Impressões', 'CTR de link', 'Leads', 'Cirurgias', '% de agendamento', 'Gancho')
    expect(labels).not_to include('Investido', 'Custo por conversa', 'Custo por consulta', 'Custo por cirurgia', 'Retorno (ROAS)')
    expect(json['daily'].first.keys).to include('conversations', 'hook_rate')
    expect(json['text']).to include('JORNADA NO ATENDIMENTO', 'MAIORES QUEDAS DO VÍDEO', 'TRANSCRIÇÃO DO VÍDEO')

    get path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Sem dados financeiros', 'Jornada no atendimento', 'maiores quedas do vídeo')
    expect(response.body).not_to include('R$')
    expect(response.body).not_to match(/ROAS|Investido|Custo por|O que vale dinheiro/i)
  end

  it 'rodada 2: a versão COM dados financeiros mostra investimento, custos e ROAS' do
    get "/criativos/analise/#{finance_link[:token]}.json"
    json = response.parsed_body
    expect(json['finance']).to be(true)
    expect(json['numbers'].pluck('label')).to include('Investido', 'Custo por conversa')
    expect(json['journey'].pluck('label')).to include('Custo por cirurgia', 'Retorno (ROAS)')
    expect(json['placements']['rows'].first).to include('spend_text')
    expect(json['text']).to include('O QUE VALE DINHEIRO', 'R$')

    get "/criativos/analise/#{finance_link[:token]}"
    expect(response.body).to include('Com dados financeiros', 'O que vale dinheiro', 'R$')
  end

  it 'rodada 2: mexer no endereço não libera o financeiro (a escolha mora dentro do token)' do
    get "#{path}.json", params: { finance: 1 }
    expect(response.parsed_body['finance']).to be(false)
    expect(response.body).not_to include('R$')

    get "#{path}?finance=true&com_financeiro=1"
    expect(response.body).not_to include('R$')
    expect(response.body).to include('Sem dados financeiros')

    # trocar pedaços do token sem financeiro pelos do token com financeiro quebra a assinatura
    open_parts = link[:token].split('--')
    paid_parts = finance_link[:token].split('--')
    [[paid_parts[0], open_parts[1], open_parts[2]], [open_parts[0], paid_parts[1], paid_parts[2]]].each do |parts|
      get "/criativos/analise/#{parts.join('--')}"
      expect(response).to have_http_status(:gone)
      expect(response.body).not_to include('R$')
    end

    # link antigo (sem a marca de versão) abre como SEM financeiro
    old = Crm::CreativeShareLink.verifier.encrypt_and_sign(
      [account.id, '2301', since_date.iso8601, until_date.iso8601, 30.days.from_now.to_i], purpose: Crm::CreativeShareLink::PURPOSE
    )
    get "/criativos/analise/#{old}.json"
    expect(response.parsed_body['finance']).to be(false)
  end

  it 'rodada 3: página pública fala de média e recorde, aponta os mais e os menos e não tem mais o "bom" nem as barras por dia' do
    [path, "/criativos/analise/#{finance_link[:token]}"].each do |url|
      get url
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('Média da conta', 'Recorde da conta', 'Onde apareceu: os mais e os menos', 'Quem viu: os mais e os menos',
                              'mais conversas', 'cliques a cada 100 exibições', 'conversas a cada 100 cliques')
      expect(body).not_to match(/Bom a partir de|Bom até|parâmetro bom/i)
      expect(body).not_to include('cv-bars', 'conversas, dia a dia')
    end

    get "#{path}.json"
    json = response.parsed_body
    expect(response.body).not_to include('R$')
    expect(response.body).not_to match(/bom a partir|bom até|bom é|"good"\s*:|"spend/i)
    expect(json['reading']).to match(/média da conta/)
    expect(json['reading']).not_to match(/parâmetro|verde|zona de atenção/i)
    expect(json['indicators'].first).to include('verdict', 'verdict_label', 'record_text', 'record_phrase', 'is_record')
    expect(json['placements']['summary']).to include('rende mais em')
    expect(json['placements']['rows'].first['badges'].pluck('label')).to include('mais conversas')
    expect(json['placements']['rows'].first.keys).not_to include('spend_text', 'cost_text', 'key')
    expect(json['audience']['no_difference']).to be(true)
    expect(json['audience']['rows'].flat_map { |r| r['badges'] }).to be_empty
    expect(json['text']).to include('ONDE APARECEU: OS MAIS E OS MENOS', 'recorde da conta')
    expect(json['text']).not_to match(/dia a dia|bom a partir/i)
  end

  it 'rodada 2: a leitura que cita custo vira frase neutra na versão sem financeiro' do
    detail = { diagnosis: { text: 'custo por conversa passou do parâmetro (R$ 30,00, bom é ≤ R$ 10,00)' }, rates: {}, totals: {}, funnel: {} }
    open_version = Crm::CreativeSharePayload.new(detail, since_date: since_date, until_date: until_date).call
    expect(open_version[:reading]).to eq(Crm::CreativeSharePayload::NEUTRAL_READING)
    expect(open_version.to_json).not_to include('R$')
    paid = Crm::CreativeSharePayload.new(detail, since_date: since_date, until_date: until_date, finance: true).call
    expect(paid[:reading]).to include('R$ 30,00')
  end

  it 'anúncio de outra conta não abre, mesmo com token bem assinado' do
    other = create(:account)
    foreign = Crm::CreativeShareLink.generate(account: other, ad_id: '2301', since_date: since_date, until_date: until_date)
    get "/criativos/analise/#{foreign[:token]}"
    expect(response).to have_http_status(:gone)
  end

  it 'a tela interna gera o link com a validade (precisa estar logado)' do
    post "/api/v1/accounts/#{account.id}/crm/creatives/2301/share", params: { from: since_date.iso8601, to: until_date.iso8601 }
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/accounts/#{account.id}/crm/creatives/2301/share", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    json = response.parsed_body
    expect(json['url']).to include('/criativos/analise/')
    expect(json['expires_label']).to eq(30.days.from_now.in_time_zone('America/Sao_Paulo').strftime('%d/%m/%Y'))
    data = Crm::CreativeShareLink.verify(json['url'].split('/').last)
    expect(data).to include(account_id: account.id, ad_id: '2301')
    expect(json['url'].split('/').last).not_to match(/2301|#{Base64.urlsafe_encode64('2301', padding: false)}/) # ids não aparecem no endereço

    expect(json).to include('finance' => false, 'finance_label' => 'Sem dados financeiros')
    expect(data[:finance]).to be(false)

    post "/api/v1/accounts/#{account.id}/crm/creatives/2301/share", params: { finance: 1 }, headers: admin.create_new_auth_token, as: :json
    paid = response.parsed_body
    expect(paid).to include('finance' => true, 'finance_label' => 'Com dados financeiros')
    expect(Crm::CreativeShareLink.verify(paid['url'].split('/').last)[:finance]).to be(true)

    post "/api/v1/accounts/#{account.id}/crm/creatives/nao-existe/share", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
# rubocop:enable RSpec/MultipleExpectations
