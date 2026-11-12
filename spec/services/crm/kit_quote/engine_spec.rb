require 'rails_helper'

# ☀️ Cotador de kits (LIFE): do consumo às opções, com AVT e Bluesun.
# As respostas simuladas seguem o formato real visto nos portais em 11/11/2026.
RSpec.describe Crm::KitQuote::Engine do
  let(:config) do
    Crm::KitQuote::DEFAULTS.deep_dup.tap { |c| c['avt']['id_cliente'] = 16_118 }
  end
  let(:avt_base) { 'https://api-d1297.cloud.solaryum.com.br' }
  let(:bluesun_api) { 'https://api.bluesundobrasil.com.br' }
  let(:secrets) do
    {
      'avt_token' => 'abc12345',
      'avt_sessao' => { 'accessToken' => 'sessao-avt', 'expirationDate' => 1.hour.from_now.iso8601, 'urlApi' => avt_base },
      'bluesun_sessao' => { 'token' => 'sessao-bluesun', 'expires_at' => 1.hour.from_now.to_i }
    }
  end

  def stub_avt_official_denied
    stub_request(:get, %r{#{avt_base}/integracaoPlataforma/MontarKits}).to_return(status: 400, body: 'Acesso negado!!!')
  end

  def stub_avt_session
    stub_request(:get, "#{avt_base}/api/Produto/BuscarPaineis?idFornecedor=2")
      .to_return(status: 200, body: [{ idProduto: 45_241, descricao: 'DAH 620W | BIFACIAL', potencia: 620 }].to_json)
    stub_request(:post, "#{avt_base}/api/Pedido/BuscarCombinacoes").to_return do |request|
      # sem dizer que vem do portal, a AVT nega (como no servidor real)
      next { status: 400, body: 'Acesso Negado!!!' } unless request.headers['Origin'] == 'https://portal.avtenergy.com.br'

      micro = JSON.parse(request.body)['buscarMicroinversores']
      kits = if micro
               [{ inversor: 'MICROINVERSOR HYX-M2500D-SW - ', tipoInv: 1, valorTotal: 8426.8, valorFinal: 8945.34 }]
             else
               [{ inversor: 'INVERSOR HYX-S3.6K-S2 - ', tipoInv: 0, valorTotal: 6552, valorFinal: 7033.04 },
                { inversor: 'INVERSOR SOFAR | 4KTL2-G3 - ', tipoInv: 0, valorTotal: 6908, valorFinal: 7396.16 }]
             end
      { status: 200, body: kits.to_json }
    end
  end

  def bluesun_kit(type, kwp, price)
    {
      tipo_inversor: type, potencia_total_sistema: kwp, quantidade_painel: 8, potencia_painel: 630,
      valor_final: price, valor_original: price, seguro: true, frete: { valor_cobrado: 169.45 },
      lista_itens: [
        { categoria: 'painel', descricao: 'Painel Fotovoltaico 630Wp Bifacial Helius', qtde: 8 },
        { categoria: type.start_with?('micro') ? 'micro_inversor' : 'inversor', descricao: 'Inversor Leapton 4kW', quantidade_total: 1 }
      ]
    }
  end

  def stub_bluesun
    stub_request(:get, "#{bluesun_api}/v1/orcamentos/geracao/servicos/seguro_engenharia")
      .to_return(status: 200, body: [{ id: 'seguro-1' }].to_json)
    stub_request(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao")
      .to_return(status: 200, body: { data: [
        bluesun_kit('inversor_ongrid', 5.04, 6764.81), bluesun_kit('inversor_ongrid', 5.04, 6833.37),
        bluesun_kit('micro_inversor_ongrid', 5.04, 6859.89), bluesun_kit('inversor_ongrid', 4.96, 7039.63),
        bluesun_kit('micro_inversor_ongrid', 4.96, 7134.71), bluesun_kit('inversor_ongrid', 5.04, 7120.46)
      ] }.to_json)
  end

  it 'calcula a potência e junta as opções dos dois fornecedores, até 7, da mais barata à mais cara' do
    stub_avt_official_denied
    stub_avt_session
    stub_bluesun

    result = described_class.new(config, secrets).run(kwh_month: 600, grid: 'bifasico')

    expect(result['potencia_necessaria_kwp']).to eq(5.09)
    expect(result['fornecedores']).to contain_exactly(
      a_hash_including('fornecedor' => 'AVT', 'ok' => true, 'caminho' => 'sessão do portal', 'opcoes' => 3),
      a_hash_including('fornecedor' => 'Bluesun', 'ok' => true, 'opcoes' => 6)
    )
    options = result['opcoes']
    expect(options.size).to eq(7)
    expect(options.map { |o| o['preco'] }).to eq(options.map { |o| o['preco'] }.sort)
    expect(options.map { |o| o.values_at('fornecedor', 'tipo') }.uniq)
      .to include(%w[AVT string], %w[AVT micro], %w[Bluesun string], %w[Bluesun micro])
    cheapest_avt = options.find { |o| o['fornecedor'] == 'AVT' }
    expect(cheapest_avt).to include('paineis' => '9 × DAH 620W | BIFACIAL', 'inversor' => 'INVERSOR HYX-S3.6K-S2',
                                    'preco' => 7033.04, 'potencia_kwp' => 5.58,
                                    'obs' => 'rede bifásica cotada como monofásica 220 V')
    expect(options.first).to include('fornecedor' => 'Bluesun', 'preco' => 6764.81, 'frete' => 169.45, 'obs' => 'inclui seguro')
  end

  it 'manda o consumo e a rede para a Bluesun' do
    stub_avt_official_denied
    stub_avt_session
    stub_bluesun

    described_class.new(config, secrets).run(kwh_month: 600, grid: 'trifasico')

    expect(WebMock).to(have_requested(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao").with do |req|
      body = JSON.parse(req.body)
      body['consumo_medio'] == 600 && body['tipo_contrato'] == 'trifasico' && body['valor_perda'] == 20 &&
        body['seguro_engenharia'] == 'seguro-1' && req.headers['Authorization'] == 'Bearer sessao-bluesun'
    end)
  end

  it 'usa a API oficial da AVT quando ela responde' do
    stub_request(:get, %r{#{avt_base}/integracaoPlataforma/MontarKits}).to_return do |request|
      micro = request.uri.query_values['tipoInv'] == '1'
      kit = { potencia: 5.58, precoVenda: micro ? 8900 : 7000, composicao: [
        { categoria: 'Painel', descricao: 'DAH 620W', qtd: 9 },
        { categoria: 'Inversor', descricao: micro ? 'MICRO HYX' : 'HYX S3.6K' }
      ] }
      { status: 200, body: [kit].to_json }
    end
    stub_bluesun

    result = described_class.new(config, secrets).run(kwh_month: 600)

    expect(result['fornecedores'].first).to include('fornecedor' => 'AVT', 'caminho' => 'API oficial', 'opcoes' => 2)
    expect(result['opcoes'].select { |o| o['fornecedor'] == 'AVT' }.map { |o| o['preco'] }).to contain_exactly(7000.0, 8900.0)
    expect(WebMock).not_to have_requested(:post, "#{avt_base}/api/Pedido/BuscarCombinacoes")
  end

  it 'explica o motivo quando um fornecedor está sem acesso e segue com o outro' do
    stub_avt_official_denied
    stub_bluesun
    sem_avt = secrets.merge('avt_sessao' => nil)

    result = described_class.new(config, sem_avt).run(kwh_month: 600)

    avt = result['fornecedores'].find { |f| f['fornecedor'] == 'AVT' }
    expect(avt['ok']).to be(false)
    expect(avt['motivo']).to include('Acesso negado', 'sem sessão do portal')
    expect(result['opcoes']).to all(include('fornecedor' => 'Bluesun'))
  end

  it 'entra sozinho na AVT quando a sessão venceu e há usuário e senha guardados' do
    stub_avt_official_denied
    stub_avt_session
    stub_bluesun
    login = stub_request(:post, "#{avt_base}/api/v2/account/login")
            .with(body: { email: 'life@exemplo.com', senha: 'segredo' }.to_json, headers: { 'Origin' => 'https://portal.avtenergy.com.br' })
            .to_return(status: 200, body: { accessToken: 'sessao-nova', expirationDate: 1.hour.from_now.iso8601 }.to_json)
    store = instance_double(Crm::KitQuote::Store, save_session!: {})
    vencida = secrets.merge('avt_sessao' => { 'accessToken' => 'velha', 'expirationDate' => 1.hour.ago.iso8601 },
                            'avt_login' => { 'email' => 'life@exemplo.com', 'senha' => 'segredo' })

    result = described_class.new(config, vencida, store).run(kwh_month: 600)

    expect(login).to have_been_requested.once
    expect(store).to have_received(:save_session!).with('avt', a_hash_including('accessToken' => 'sessao-nova', 'urlApi' => avt_base))
    expect(result['fornecedores'].find { |f| f['fornecedor'] == 'AVT' }).to include('ok' => true, 'opcoes' => 3)
    expect(WebMock).to(have_requested(:post, "#{avt_base}/api/Pedido/BuscarCombinacoes")
      .with(headers: { 'Authorization' => 'Bearer sessao-nova' }).at_least_once)
  end

  it 'explica quando a AVT não aceita o usuário e a senha guardados' do
    stub_avt_official_denied
    stub_bluesun
    stub_request(:post, "#{avt_base}/api/v2/account/login").to_return(status: 401, body: 'Usuário ou senha inválidos')
    sem_sessao = secrets.merge('avt_sessao' => nil, 'avt_login' => { 'email' => 'life@exemplo.com', 'senha' => 'errada' })

    result = described_class.new(config, sem_sessao).run(kwh_month: 600)

    avt = result['fornecedores'].find { |f| f['fornecedor'] == 'AVT' }
    expect(avt).to include('ok' => false)
    expect(avt['motivo']).to include('não aceitou o usuário e a senha')
  end

  it 'diz que a AVT recusou quando o portal nega todas as consultas de kit' do
    stub_avt_official_denied
    stub_request(:get, "#{avt_base}/api/Produto/BuscarPaineis?idFornecedor=2")
      .to_return(status: 200, body: [{ idProduto: 45_241, descricao: 'DAH 620W', potencia: 620 }].to_json)
    stub_request(:post, "#{avt_base}/api/Pedido/BuscarCombinacoes").to_return(status: 400, body: 'Acesso Negado!!!')
    stub_bluesun

    result = described_class.new(config, secrets).run(kwh_month: 600)

    avt = result['fornecedores'].find { |f| f['fornecedor'] == 'AVT' }
    expect(avt).to include('ok' => false)
    expect(avt['motivo']).to include('recusou a consulta de kits', 'Acesso Negado')
  end

  it 'tenta de novo quando a rede falha de passagem ao achar o endereço' do
    stub_avt_official_denied
    stub_avt_session
    stub_request(:get, "#{bluesun_api}/v1/orcamentos/geracao/servicos/seguro_engenharia")
      .to_raise(SocketError).then.to_return(status: 200, body: [{ id: 'seguro-1' }].to_json)
    stub_request(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao")
      .to_return(status: 200, body: { data: [bluesun_kit('inversor_ongrid', 5.04, 6764.81)] }.to_json)
    allow_any_instance_of(Crm::KitQuote::Http).to receive(:sleep) # rubocop:disable RSpec/AnyInstance

    result = described_class.new(config, secrets).run(kwh_month: 600)

    expect(result['fornecedores'].find { |f| f['fornecedor'] == 'Bluesun' }).to include('ok' => true, 'opcoes' => 1)
  end

  it 'avisa quando a sessão da Bluesun venceu' do
    stub_avt_official_denied
    stub_avt_session
    vencida = secrets.merge('bluesun_sessao' => { 'token' => 'x', 'expires_at' => 1.hour.ago.to_i })

    result = described_class.new(config, vencida).run(kwh_month: 600)

    bluesun = result['fornecedores'].find { |f| f['fornecedor'] == 'Bluesun' }
    expect(bluesun).to include('ok' => false)
    expect(bluesun['motivo']).to include('venceu')
    expect(WebMock).not_to have_requested(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao")
  end

  describe 'cotação completa: estrutura do telhado + frete' do
    it 'pede a estrutura do telhado à Bluesun e marca a cotação como completa', :aggregate_failures do
      stub_avt_official_denied
      stub_avt_session
      stub_bluesun

      result = described_class.new(config, secrets).run(kwh_month: 600, grid: 'bifasico', roof: 'ceramica')

      expect(WebMock).to(have_requested(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao").with do |req|
        body = JSON.parse(req.body)
        body['incluir_estrutura'] == 1 && body['id_tipo_estrutura_telhado'] == 47
      end)
      expect(result['telhado']).to eq('chave' => 'ceramica', 'nome' => 'Telha cerâmica')
      bluesun = result['opcoes'].find { |o| o['fornecedor'] == 'Bluesun' }
      expect(bluesun).to include('estrutura' => true, 'completa' => true, 'falta' => '', 'frete' => 169.45, 'total' => 6934.26)
      avt = result['opcoes'].find { |o| o['fornecedor'] == 'AVT' }
      expect(avt).to include('estrutura' => false, 'completa' => false, 'falta' => 'estrutura do telhado e frete', 'total' => 7033.04)
      expect(result['fornecedores'].find { |f| f['fornecedor'] == 'AVT' }).to include('completas' => 0, 'falta' => 'estrutura do telhado e frete')
    end

    it 'sem o telhado (ou com telhado que não existe) cota sem estrutura e nada entra na média', :aggregate_failures do
      stub_avt_official_denied
      stub_avt_session
      stub_bluesun

      result = described_class.new(config, secrets).run(kwh_month: 600, roof: 'palha')

      expect(WebMock).to(have_requested(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao").with do |req|
        JSON.parse(req.body).values_at('incluir_estrutura', 'id_tipo_estrutura_telhado') == [0, nil]
      end)
      expect(result['telhado']).to be_nil
      expect(result['opcoes']).to all(include('completa' => false))
      expect(result['medias']['string']).to include('fornecedores_na_media' => 0, 'media' => nil)
    end

    it 'faz o preço médio do kit só com quem deu cotação completa, por tipo de inversor', :aggregate_failures do
      stub_avt_official_denied
      stub_avt_session
      stub_bluesun

      medias = described_class.new(config, secrets).run(kwh_month: 600, roof: 'ceramica')['medias']

      # string: Bluesun completa (6.764,81 + frete 169,45) entra; AVT (sem estrutura e sem frete) fica fora
      expect(medias['string']).to include('fornecedores_na_media' => 1, 'media' => 6934.26)
      expect(medias['string']['cotacoes']).to contain_exactly(
        a_hash_including('fornecedor' => 'Bluesun', 'valor' => 6934.26, 'entra_na_media' => true,
                         'detalhe' => 'kit R$ 6.764,81 + frete R$ 169,45, com estrutura'),
        a_hash_including('fornecedor' => 'AVT', 'valor' => 7033.04, 'entra_na_media' => false,
                         'detalhe' => 'kit R$ 7.033,04, sem estrutura do telhado e frete')
      )
      expect(medias['micro']).to include('fornecedores_na_media' => 1, 'media' => 7029.34)
    end

    it 'calcula a média entre dois fornecedores completos' do
      options = [
        Crm::KitQuote.option(supplier: 'Bluesun', type: 'micro', kwp: 4.41, panel_count: 7, price: 7020.71, freight: 158.09, structure: true),
        Crm::KitQuote.option(supplier: 'Bluesun', type: 'micro', kwp: 4.41, panel_count: 7, price: 7500, freight: 158.09, structure: true),
        Crm::KitQuote.option(supplier: 'AVT', type: 'micro', kwp: 4.34, panel_count: 7, price: 6700, freight: 121.20, structure: true)
      ]

      expect(Crm::KitQuote::Average.by_type(options)['micro']).to include('fornecedores_na_media' => 2, 'media' => 7000.0)
    end
  end

  describe 'renovação da sessão da Bluesun' do
    let(:vencida) do
      secrets.merge('bluesun_sessao' => { 'token' => 'velha', 'expires_at' => 1.minute.ago.to_i,
                                          'refresh_token' => 'chave', 'refresh_expires_at' => 5.days.from_now.to_i })
    end

    it 'renova sozinha quando a sessão de 3 h venceu e a chave de renovação ainda vale', :aggregate_failures do
      stub_avt_official_denied
      stub_avt_session
      stub_bluesun
      nova = { token: 'nova', expires_at: 3.hours.from_now.to_i, refresh_token: 'chave-2', refresh_expires_at: 7.days.from_now.to_i,
               user: { nome: 'Alguém' } }
      renew = stub_request(:post, "#{bluesun_api}/v1/validar_token").with(body: { refresh_token: 'chave' }.to_json)
                                                                    .to_return(status: 200, body: nova.to_json)
      store = instance_double(Crm::KitQuote::Store, save_session!: {})

      result = described_class.new(config, vencida, store).run(kwh_month: 600)

      expect(renew).to have_been_requested.once
      expect(store).to have_received(:save_session!).with('bluesun', hash_including('token' => 'nova', 'refresh_token' => 'chave-2'))
      expect(store).not_to have_received(:save_session!).with('bluesun', hash_including('user'))
      expect(result['fornecedores'].find { |f| f['fornecedor'] == 'Bluesun' }).to include('ok' => true)
      expect(WebMock).to(have_requested(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao")
        .with(headers: { 'Authorization' => 'Bearer nova' }))
    end

    it 'avisa que venceu quando o portal não aceita a renovação' do
      stub_avt_official_denied
      stub_avt_session
      stub_request(:post, "#{bluesun_api}/v1/validar_token").to_return(status: 401, body: '{}')

      result = described_class.new(config, vencida).run(kwh_month: 600)

      expect(result['fornecedores'].find { |f| f['fornecedor'] == 'Bluesun' }).to include('ok' => false, 'motivo' => a_string_including('venceu'))
    end

    it 'não pede renovação enquanto a sessão vale' do
      stub_avt_official_denied
      stub_avt_session
      stub_bluesun

      described_class.new(config, secrets.merge('bluesun_sessao' => vencida['bluesun_sessao'].merge('expires_at' => 1.hour.from_now.to_i)))
                     .run(kwh_month: 600)

      expect(WebMock).not_to have_requested(:post, "#{bluesun_api}/v1/validar_token")
    end
  end
end
