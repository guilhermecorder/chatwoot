require 'rails_helper'

# 🪝 item 397: Banco de Ganchos (gancho → história → oferta)
RSpec.describe 'CRM copy bank', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/copy_bank" }
  let(:headers) { admin.create_new_auth_token }

  before { CrmSetting.create!(account: account, ai_config: {}) }

  it 'enche o banco na 1ª abertura, uma vez só', :aggregate_failures do
    get base, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    kinds = response.parsed_body['blocks'].group_by { |b| b['kind'] }.transform_values(&:size)
    expect(kinds['gancho']).to be > 900
    expect(kinds).to include('historia' => 8, 'oferta' => 8, 'regancho' => 19)
    gancho = response.parsed_body['blocks'].find { |b| b['kind'] == 'gancho' }
    expect(gancho['referencia']).to start_with('https://')
    expect(gancho['original']).to be_present

    expect { get base, headers: headers, as: :json }.not_to(change { account.cevico_copy_blocks.count })
  end

  it 'cria peça com as lacunas lidas do texto, marca uso e favorito', :aggregate_failures do
    post "#{base}/blocks", params: { block: { kind: 'gancho', categoria: 'cevico', texto: 'Você [ação] há [tempo]? Então [ação].' } },
                           headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body).to include('lacunas' => %w[ação tempo], 'fonte' => 'manual')

    post "#{base}/blocks/#{id}/use", headers: headers, as: :json
    expect(response.parsed_body['usos']).to eq(1)

    patch "#{base}/blocks/#{id}", params: { block: { favorito: true } }, headers: headers, as: :json
    expect(response.parsed_body['favorito']).to be(true)

    delete "#{base}/blocks/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
  end

  it 'salva, lista e muda o status de uma criação', :aggregate_failures do
    post "#{base}/drafts", params: { draft: { titulo: 'Teste', tema: 'refrativa', formato: 'reels', texto_final: 'G\n\nH\n\nO',
                                              partes: { gancho: { texto: 'G', block_id: 1 }, historia: { texto: 'H' } } } },
                           headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body['id']
    expect(response.parsed_body.dig('partes', 'gancho', 'texto')).to eq('G')

    patch "#{base}/drafts/#{id}", params: { draft: { status: 'aprovado' } }, headers: headers, as: :json
    expect(response.parsed_body['status']).to eq('aprovado')

    get "#{base}/drafts", headers: headers, as: :json
    expect(response.parsed_body['drafts'].pluck('id')).to eq([id])
  end

  it 'IA desligada devolve aviso claro, sem chamar a API' do
    post "#{base}/generate_copy", params: { gancho: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('IA não configurada')
  end

  it 'lista formulários com respostas e conta os números sem IA', :aggregate_failures do
    form = Crm::Form.create!(account: account, name: 'Antes da consulta',
                             questions: [{ 'id' => 'q1', 'label' => 'Usa óculos há quanto tempo?', 'type' => 'choice',
                                           'options' => ['Mais de 10 anos', 'Menos'] }])
    3.times do |i|
      answer = { 'id' => 'q1', 'label' => 'Usa óculos há quanto tempo?', 'type' => 'choice', 'value' => i < 2 ? 'Mais de 10 anos' : 'Menos' }
      Crm::FormResponse.create!(account: account, crm_form_id: form.id, completed_at: Time.current, answers: [answer])
    end

    get "#{base}/forms", headers: headers, as: :json
    expect(response.parsed_body['forms']).to include(include('id' => form.id, 'respostas' => 3, 'brief' => nil))

    top = Crm::FormCopyBriefService.new(form: form).numeros.first['top'].first
    expect(top).to eq('opcao' => 'Mais de 10 anos', 'pessoas' => 2, 'pct' => 67)

    post "#{base}/forms/#{form.id}/brief", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity) # IA não configurada no teste
  end

  it 'fora da clínica: sem exemplo da CEVICO, sem selo de saúde e convites gerais', :aggregate_failures do
    CrmSetting.find_by(account: account).update!(agenda_config: { Cevico::Company::KEY => { 'name' => 'LIFE', 'segment' => 'outro' } })
    get base, headers: headers, as: :json
    blocks = response.parsed_body['blocks']
    ganchos = blocks.select { |b| b['kind'] == 'gancho' }
    expect(ganchos.pluck('exemplo').compact).to be_empty
    expect(ganchos.pluck('saude').uniq).to eq(['pronto'])
    expect(blocks.select { |b| b['kind'] == 'oferta' }.pluck('texto').join).not_to include('150 reais')
    expect(response.parsed_body['empresa']).to include('clinica' => false, 'temas' => [])
  end

  # 🏆 18/11: ranking real — criação ligada a anúncio (à mão ou pelo código no nome)
  it 'liga a criação aos anúncios e soma o resultado por tipo de gancho', :aggregate_failures do
    bloco = account.cevico_copy_blocks.create!(kind: 'gancho', categoria: 'autoridade', texto: 'Como [profissão] há anos', usos: 2)
    post "#{base}/drafts", params: { draft: { titulo: 'Teste', texto_final: 'x',
                                              partes: { gancho: { block_id: bloco.id, tipo: 'autoridade' } } } },
                           headers: headers, as: :json
    id = response.parsed_body['id']
    expect(response.parsed_body['codigo']).to eq("CRI-#{id}")

    Crm::AdCreative.create!(account: account, ad_id: 'a1', ad_name: 'Vídeo do doutor')
    Crm::AdCreative.create!(account: account, ad_id: 'a2', ad_name: "CRI-#{id} · gancho autoridade")
    Crm::AdInsight.create!(account: account, ad_id: 'a1', date: Date.current,
                           metrics: { impressions: 1000, plays_3s: 300, conversations: 10, spend: 50 })
    Crm::AdInsight.create!(account: account, ad_id: 'a2', date: Date.current,
                           metrics: { impressions: 1000, plays_3s: 500, conversations: 30, spend: 50 })

    patch "#{base}/drafts/#{id}/ads", params: { ad_ids: %w[a1 nao-existe] }, headers: headers, as: :json
    expect(response.parsed_body['partes']['ad_ids']).to eq(['a1'])
    expect(response.parsed_body['anuncios'].pluck('ad_id')).to contain_exactly('a1', 'a2')

    # salvar o texto de novo não desliga o anúncio
    patch "#{base}/drafts/#{id}", params: { draft: { texto_final: 'y', partes: { gancho: { block_id: bloco.id, tipo: 'autoridade' } } } },
                                  headers: headers, as: :json
    expect(response.parsed_body['partes']['ad_ids']).to eq(['a1'])

    get "#{base}/ranking", headers: headers, as: :json
    tipo = response.parsed_body['tipos'].find { |t| t['tipo'] == 'autoridade' }
    expect(tipo).to include('usos' => 2, 'criacoes' => 1, 'anuncios' => 2, 'impressoes' => 2000, 'conversas' => 40,
                            'gancho_pct' => 40.0, 'conversas_mil' => 20.0, 'custo_conversa' => 2.5)
    expect(response.parsed_body['ganchos'].first).to include('block_id' => bloco.id, 'conversas_mil' => 20.0)
    expect(response.parsed_body['resumo']).to include('criacoes' => 1, 'ligadas' => 1)

    get "#{base}/ads", params: { q: 'doutor' }, headers: headers
    expect(response.parsed_body['ads'].pluck('ad_id')).to eq(['a1'])
  end
end
