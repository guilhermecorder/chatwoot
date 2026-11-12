require 'rails_helper'

# ☀️ Cotador de kits (LIFE): a tela cota, guarda os acessos dos fornecedores
# (que entram e nunca voltam) e respeita o nó crm.cotador.
RSpec.describe 'Cotador de kits — rota do CRM', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/kit_quote" }
  let(:bluesun_api) { 'https://api.bluesundobrasil.com.br' }
  let(:bluesun_session) do
    { token: 'segredo-bluesun', expires_at: 1.hour.from_now.to_i, refresh_token: 'chave-de-refresh', refresh_expires_at: 6.days.from_now.to_i,
      user: { cpf: '000.000.000-00', nome: 'Alguém' } }.to_json
  end

  before { Current.reset }

  def stub_bluesun
    stub_request(:get, "#{bluesun_api}/v1/orcamentos/geracao/servicos/seguro_engenharia").to_return(status: 200, body: [{ id: 's1' }].to_json)
    kit = { tipo_inversor: 'inversor_ongrid', potencia_total_sistema: 5.04, quantidade_painel: 8, potencia_painel: 630,
            valor_final: 6764.81, seguro: true, frete: { valor_cobrado: 169.45 },
            lista_itens: [{ categoria: 'painel', descricao: 'Painel 630Wp' }, { categoria: 'inversor', descricao: 'Leapton 4kW' }] }
    stub_request(:post, "#{bluesun_api}/v1/orcamentos/geracao/simulacao").to_return(status: 200, body: { data: [kit] }.to_json)
  end

  it 'mostra o estado dos acessos sem nenhum fornecedor ligado' do
    get base, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('cidade' => 'Piracicaba/SP', 'max_opcoes' => 7)
    expect(response.parsed_body['acesso']).to include(
      'avt' => a_hash_including('sessao' => 'sem', 'token' => false, 'id_cliente' => false),
      'bluesun' => a_hash_including('sessao' => 'sem')
    )
  end

  it 'guarda a sessão colada e nunca devolve o segredo nem os dados pessoais', :aggregate_failures do
    post "#{base}/update_access", params: { fornecedor: 'bluesun', sessao: bluesun_session }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('acesso', 'bluesun')).to include('sessao' => 'ok')
    expect(response.body).not_to include('segredo-bluesun', 'chave-de-refresh')

    saved = CrmSetting.find_by(account: account).ai_config.dig('kit_quote', 'bluesun_sessao')
    expect(saved).to include('token' => 'segredo-bluesun', 'refresh_token' => 'chave-de-refresh')
    expect(saved).not_to include('user')

    get base, headers: admin.create_new_auth_token, as: :json
    expect(response.body).not_to include('segredo-bluesun')
  end

  it 'recusa um texto que não é a sessão do portal' do
    post "#{base}/update_access", params: { fornecedor: 'bluesun', sessao: 'qualquer coisa' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Cole o texto inteiro')
  end

  it 'guarda o token e o código do cliente da AVT', :aggregate_failures do
    post "#{base}/update_access", params: { avt_token: ' abc12345 ' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('acesso', 'avt')).to include('token' => true)
    expect(response.body).not_to include('abc12345')

    post "#{base}/update_access", params: { avt_id_cliente: '16118' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('acesso', 'avt')).to include('id_cliente' => true)
    expect(Crm::KitQuote::Store.new(account).config.dig('avt', 'id_cliente')).to eq(16_118)
    expect(Crm::KitQuote::Store.new(account).secrets['avt_token']).to eq('abc12345')
  end

  it 'guarda o usuário e a senha da AVT sem nunca devolver a senha', :aggregate_failures do
    post "#{base}/update_access", params: { avt_email: 'life@exemplo.com', avt_senha: 'senha-do-portal' },
                                  headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('acesso', 'avt')).to include('login' => true)
    expect(response.body).not_to include('senha-do-portal')
    expect(Crm::KitQuote::Store.new(account).secrets['avt_login']).to eq('email' => 'life@exemplo.com', 'senha' => 'senha-do-portal')

    get base, headers: admin.create_new_auth_token, as: :json
    expect(response.body).not_to include('senha-do-portal')
  end

  it 'cota com o que está ligado e explica o que falta no outro fornecedor', :aggregate_failures do
    stub_bluesun
    post "#{base}/update_access", params: { fornecedor: 'bluesun', sessao: bluesun_session }, headers: admin.create_new_auth_token, as: :json

    post base, params: { consumo: '600', rede: 'bifasico' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['potencia_necessaria_kwp']).to eq(5.09)
    expect(body['opcoes']).to contain_exactly(a_hash_including('fornecedor' => 'Bluesun', 'preco' => 6764.81, 'tipo' => 'string'))
    avt = body['fornecedores'].find { |f| f['fornecedor'] == 'AVT' }
    expect(avt).to include('ok' => false)
    expect(avt['motivo']).to include('sem token', 'sem sessão')
    expect(response.body).not_to include('segredo-bluesun')
  end

  it 'devolve o DRE padrão (25%) com a adequação da tabela e recalcula com o preço ajustado na mão', :aggregate_failures do
    kits = [{ fornecedor: 'Bluesun', valor: 7178.80 }, { fornecedor: 'AVT', valor: 6500, entra_na_media: false }]
    post "#{base}/dre", params: { kits: kits, placas: 7, tipo: 'micro' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('valor_projeto' => 12_880.0, 'lucro' => 3220.48, 'na_faixa' => true, 'custo_kit' => 7178.8)
    expect(response.parsed_body['adequacao']).to eq('valor' => 550.0, 'faixa' => 'micro inversor, 4 a 8 placas', 'manual' => false)

    post "#{base}/dre", params: { kits: kits, placas: 7, tipo: 'micro', valor: '11.000,00' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('valor_projeto' => 11_000.0, 'na_faixa' => false, 'padrao' => 12_880)

    post "#{base}/dre", params: { kits: kits, placas: 7, tipo: 'micro', margem: 0.3 }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('valor_projeto' => 13_990.0)

    post "#{base}/dre", params: { kits: [], placas: 7, tipo: 'micro' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'pede o valor manual da adequação quando a tabela não tem faixa, e aceita o valor informado', :aggregate_failures do
    kits = [{ fornecedor: 'Bluesun', valor: 30_000 }]
    post "#{base}/dre", params: { kits: kits, placas: 40, tipo: 'micro' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('precisa_adequacao' => true)
    expect(response.parsed_body['error']).to include('40 placas com micro inversor')

    post "#{base}/dre", params: { kits: kits, placas: 40, tipo: 'micro', adequacao: '1.900,00' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['adequacao']).to include('valor' => 1900.0, 'manual' => true)
  end

  it 'cota com a estrutura do telhado quando o telhado é informado' do
    stub_bluesun
    post "#{base}/update_access", params: { fornecedor: 'bluesun', sessao: bluesun_session }, headers: admin.create_new_auth_token, as: :json

    post base, params: { consumo: '490', rede: 'bifasico', telhado: 'ceramica' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['telhado']).to eq('chave' => 'ceramica', 'nome' => 'Telha cerâmica')
    expect(response.parsed_body['opcoes'].first).to include('completa' => true, 'total' => 6934.26)
    expect(response.parsed_body.dig('medias', 'string', 'media')).to eq(6934.26)
  end

  describe 'documentos do orçamento (proposta + justificativa)' do
    let(:contact) { create(:contact, account: account, name: 'Adriana Souza') }
    let(:payload) do
      {
        cliente: { contact_id: contact.id }, telhado: 'ceramica', tipo: 'micro', placas: 7,
        conta: { hoje: 300, acrescimos: [{ rotulo: '2 ares-condicionados', valor: 200 }], consumo_kwh: 490 },
        opcao: { fornecedor: 'Bluesun', tipo: 'micro', potencia_kwp: 4.41, placas: 7, preco: 7020.71, frete: 158.09, total: 7178.8,
                 completa: true, paineis: '7 × Painel 630Wp Helius', inversor: '2 × Micro Inversor Growatt 2,50kW',
                 equipamento: { placa: { quantidade: 7, marca: 'Helius', potencia_w: 630 },
                                inversores: [{ quantidade: 2, marca: 'Growatt', potencia_kw: 2.5 }], peso_kg: 260.7 } },
        kits: [{ fornecedor: 'Bluesun', valor: 7178.80, detalhe: 'kit R$ 7.020,71 + frete R$ 158,09, com estrutura', entra_na_media: true }]
      }
    end

    it 'monta os dados dos dois documentos com os números do DRE e avisa quando o gerador de PDF não está ligado', :aggregate_failures do
      post "#{base}/documents", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['dre']).to include('valor_projeto' => 12_880.0, 'lucro' => 3220.48)
      expect(body.dig('proposta', 'cliente', 'nome')).to eq('Adriana Souza')
      expect(body.dig('proposta', 'investimento', 'preco_total')).to eq(12_880.0)
      expect(body.dig('justificativa', 'resumo')).to include('valor_projeto' => 12_880.0, 'custo_total' => 9659.52, 'lucro' => 3220.48)
      expect(body['arquivos']).to eq([])
      expect(body['aviso']).to include('gerador de PDF ainda não está ligado')
    end

    it 'devolve os PDFs quando o gerador de PDF está ligado', :aggregate_failures do
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'kit_quote') { |c| (c || {}).merge('config' => { 'gerador_pdf' => { 'url' => 'http://gerador.test:3041/' } }) }
      stub_request(:post, 'http://gerador.test:3041/gerar').to_return(
        status: 200, body: { arquivos: [{ nome: 'Proposta-Adriana.pdf', tipo: 'application/pdf', base64: 'JVBERi0=' },
                                        { nome: 'Justificativa-Adriana.pdf', tipo: 'application/pdf', base64: 'JVBERi0=' }], avisos: [] }.to_json
      )

      post "#{base}/documents", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(WebMock).to(have_requested(:post, 'http://gerador.test:3041/gerar').with do |req|
        sent = JSON.parse(req.body)
        sent.dig('proposta', 'investimento', 'preco_total').to_i == 12_880 && sent.dig('justificativa', 'adequacao', 'valor').to_i == 550
      end)
      expect(response.parsed_body['arquivos'].pluck('nome')).to eq(%w[Proposta-Adriana.pdf Justificativa-Adriana.pdf])
      expect(response.parsed_body['aviso']).to be_nil
    end

    it 'não perde os números quando o gerador de PDF falha' do
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'kit_quote') { |c| (c || {}).merge('config' => { 'gerador_pdf' => { 'url' => 'http://gerador.test:3041' } }) }
      stub_request(:post, 'http://gerador.test:3041/gerar').to_return(status: 500, body: { erro: 'Falta o campo "telhado.tipo"' }.to_json)

      post "#{base}/documents", params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('arquivos' => [], 'aviso' => a_string_including('telhado.tipo'))
      expect(response.parsed_body.dig('dre', 'valor_projeto')).to eq(12_880.0)
    end

    it 'pede o que falta: cliente, conta, opção e cotação completa', :aggregate_failures do
      [[{ cliente: { nome: '' } }, 'Escolha o cliente'], [{ conta: { hoje: 0 } }, 'conta de luz de hoje'], [{ opcao: {} }, 'opção de kit'],
       [{ kits: [{ fornecedor: 'AVT', valor: 7000, entra_na_media: false }] }, 'cotação completa']].each do |change, message|
        post "#{base}/documents", params: payload.merge(change), headers: admin.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include(message)
      end
    end

    it 'guarda o orçamento no cliente, com os PDFs, e lista do mais novo ao mais antigo', :aggregate_failures do
      Cevico::SettingMerge.merge_key!(account, :ai_config, 'kit_quote') { |c| (c || {}).merge('config' => { 'gerador_pdf' => { 'url' => 'http://gerador.test:3041' } }) }
      stub_request(:post, 'http://gerador.test:3041/gerar').to_return(
        status: 200, body: { arquivos: [{ nome: 'Proposta-Adriana.pdf', tipo: 'application/pdf', base64: Base64.strict_encode64('%PDF-1') }],
                             avisos: [] }.to_json
      )

      post "#{base}/documents", params: payload, headers: admin.create_new_auth_token, as: :json
      post "#{base}/documents", params: payload.merge(valor: '11.000,00'), headers: admin.create_new_auth_token, as: :json

      saved = response.parsed_body['orcamento']
      expect(saved).to include('valor' => 11_000.0, 'tipo' => 'micro', 'na_faixa' => false, 'enviado_em' => nil, 'por' => admin.name)
      expect(saved['arquivos'].first).to include('nome' => 'Proposta-Adriana.pdf', 'tipo' => 'application/pdf')
      expect(saved['arquivos'].first['url']).to include('/rails/active_storage/')

      quotes = Crm::Quote.where(contact: contact).recent
      expect(quotes.map { |q| q.price.to_f }).to eq([11_000.0, 12_880.0])
      expect(quotes.first.payload.dig('dre', 'adequacao', 'valor')).to eq(550.0)
      expect(quotes.first.payload.dig('conta', 'hoje')).to eq(300.0)
      expect(quotes.first.files.first.download).to eq('%PDF-1')

      get "#{base}/history", params: { contact_id: contact.id }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['orcamentos'].pluck('valor')).to eq([11_000.0, 12_880.0])
    end

    it 'guarda os números mesmo sem o gerador de PDF e não guarda cliente fora da base', :aggregate_failures do
      post "#{base}/documents", params: payload, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['orcamento']).to include('valor' => 12_880.0, 'arquivos' => [])

      post "#{base}/documents", params: payload.merge(cliente: { nome: 'Cliente de balcão' }), headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['orcamento']).to be_nil
      expect(Crm::Quote.count).to eq(1)
    end

    it 'marca a proposta como enviada: grava a data e põe a etiqueta orcamento-enviado no cliente', :aggregate_failures do
      post "#{base}/documents", params: payload, headers: admin.create_new_auth_token, as: :json
      id = response.parsed_body.dig('orcamento', 'id')

      post "#{base}/sent", params: { id: id }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('orcamento', 'enviado_em')).to be_present
      expect(contact.reload.label_list).to include('orcamento-enviado')
      expect(Crm::Quote.find(id)).to be_sent

      post "#{base}/sent", params: { id: 0 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'não mostra nem marca orçamento de outra conta', :aggregate_failures do
      other = create(:account)
      quote = Crm::Quote.create!(account: other, contact: create(:contact, account: other), price: 9000, kind: 'micro')

      post "#{base}/sent", params: { id: quote.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(quote.reload).not_to be_sent

      get "#{base}/history", params: { contact_id: quote.contact_id }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['orcamentos']).to eq([])
    end

    it 'atendente sem o nó crm.cotador não gera documentos' do
      post "#{base}/documents", params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'orçamentos gerados (caixas do topo) e exclusão' do
    let(:ana) { create(:contact, account: account, name: 'Ana Souza') }
    let(:bia) { create(:contact, account: account, name: 'Bia Lima') }

    def quote(contact, created_at:, user: admin, sent_at: nil)
      Crm::Quote.create!(account: account, contact: contact, user: user, price: 12_000, kind: 'micro', created_at: created_at, sent_at: sent_at,
                         payload: { 'proposta' => { 'validade_dias' => 7 } })
    end

    it 'sem cliente lista os da conta toda, com o nome do cliente e a validade de 7 dias', :aggregate_failures do
      novo = quote(ana, created_at: 1.day.ago)
      velho = quote(bia, created_at: 10.days.ago, sent_at: 9.days.ago)

      get "#{base}/history", headers: admin.create_new_auth_token, as: :json

      lista = response.parsed_body['orcamentos']
      expect(lista.pluck('id')).to eq([novo.id, velho.id])
      expect(lista.first).to include('valido' => true, 'cliente' => { 'id' => ana.id, 'nome' => 'Ana Souza' })
      expect(lista.last).to include('valido' => false)
      expect(lista.last['enviado_em']).to be_present
    end

    it 'exclui o orçamento (administrador ou quem gerou) e nega para os outros', :aggregate_failures do
      do_admin = quote(ana, created_at: 1.day.ago)
      do_atendente = quote(bia, created_at: 1.day.ago, user: agent)

      post "#{base}/discard", params: { id: do_admin.id }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(Crm::Quote.exists?(do_admin.id)).to be(false)

      post "#{base}/discard", params: { id: 0 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)

      post "#{base}/discard", params: { id: do_atendente.id }, headers: admin.create_new_auth_token, as: :json
      expect(Crm::Quote.exists?(do_atendente.id)).to be(false)
    end
  end

  describe 'botão "Gerar orçamento" da conversa' do
    let(:contact) { create(:contact, account: account, name: 'Ivan Coral') }

    def ready
      get "#{base}/ready", params: { contact_id: contact.id }, headers: admin.create_new_auth_token, as: :json
      response.parsed_body
    end

    it 'fica travado enquanto o cliente não mandou a conta nem os dados' do
      expect(ready).to eq('liberado' => false, 'falta' => 'Libera quando o cliente enviar a conta de luz ou os dados.')
    end

    it 'libera quando a conta de luz está anotada no resumo do cliente' do
      contact.update!(additional_attributes: { 'ficha_cliente' => { 'conta' => { 'valor' => 'R$ 300 por mês' } } })

      expect(ready).to eq('liberado' => true, 'motivo' => 'Conta de luz anotada: R$ 300 por mês')
    end

    it 'libera quando o cartão chega na coluna do orçamento (a primeira com compromisso) ou passa dela', :aggregate_failures do
      pipeline = Crm::Pipeline.create!(account: account, name: 'Funil')
      novos = Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos', position: 1)
      a_fazer = Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento a fazer', position: 2,
                                   settings: { 'prazo' => { 'modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Montar e enviar o orçamento' } })
      enviado = Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 3)
      card = Crm::Contact.create!(pipeline: pipeline, stage: novos, contact: contact)
      expect(ready['liberado']).to be(false)

      card.update!(stage: a_fazer)
      expect(ready).to eq('liberado' => true, 'motivo' => 'Cartão na coluna «Orçamento a fazer»')

      card.update!(stage: enviado)
      expect(ready).to include('liberado' => true, 'motivo' => 'Cartão na coluna «Orçamento Enviado»')
    end

    it 'cliente que não existe (ou de outra conta) fica travado' do
      get "#{base}/ready", params: { contact_id: create(:contact).id }, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['liberado']).to be(false)
    end
  end

  it 'pede o consumo quando ele não veio' do
    post base, params: { consumo: '' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('consumo médio')
  end

  # 🧭 O Fernando é administrador em triagem (vê só o essencial): o gerador vem junto com o CRM.
  it 'administrador em triagem com o pacote essencial abre o gerador, calcula e gera', :aggregate_failures do
    socio = create(:user, account: account, role: :administrator)
    CrmSetting.find_or_create_by!(account: account).update!(
      agent_permissions: { 'owner_ids' => [admin.id],
                           'admin_limits' => { socio.id.to_s => { 'liberados' => %w[inicio conversas crm tarefas agenda pacientes],
                                                                  'escondidos' => %w[crm.funis crm.campanhas crm.jornada crm.formularios
                                                                                     crm.fontes] } } }
    )
    expect(Cevico::Access.for(account, socio).level('crm.cotador')).to eq('edit')

    get base, headers: socio.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)

    post "#{base}/dre", params: { kits: [{ fornecedor: 'Bluesun', valor: 7178.80 }], placas: 7, tipo: 'micro' },
                        headers: socio.create_new_auth_token, as: :json
    expect(response.parsed_body).to include('valor_projeto' => 12_880.0)

    # os acessos dos fornecedores ele também salva: é administrador
    post "#{base}/update_access", params: { avt_id_cliente: '16118' }, headers: socio.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'atendente sem o nó crm.cotador não abre, não cota e não mexe nos acessos', :aggregate_failures do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post base, params: { consumo: '600' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{base}/update_access", params: { avt_token: 'x' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(CrmSetting.find_by(account: account)&.ai_config&.dig('kit_quote')).to be_blank
  end
end
