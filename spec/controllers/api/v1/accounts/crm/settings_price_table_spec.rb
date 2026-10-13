require 'rails_helper'

# 🔢 Rodada 5 da auditoria — "Números certos" (achado #401): salvar a Tabela
# de preços com um procedimento sem preço gravava R$ 0, que ia direto para o
# prompt do Atendente IA ({{TABELA_DE_PRECOS}}) e para o Espaço do Paciente.
RSpec.describe 'POST settings/update_price_table (Tabela de preços)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/settings/update_price_table" }

  before { CrmSetting.create!(account: account, agenda_config: {}, ai_config: {}) }

  def saved_items
    CrmSetting.find_by!(account: account).agenda_config.dig('price_table', 'items')
  end

  def post_items(items)
    post url, params: { items: items }, headers: admin.create_new_auth_token, as: :json
  end

  it 'recusa procedimento sem preço (cenário do achado) e não grava nada', :aggregate_failures do
    post_items([{ group: 'Exames', name: 'Topografia', price: nil },
                { group: 'Exames', name: 'Paquimetria', price: 250, unit: 'unico' }])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Topografia')
    expect(saved_items).to be_nil
    expect(Cevico::PriceList.prompt_block(account)).not_to include('R$ 0')
  end

  it 'recusa preço R$ 0 ou negativo' do
    post_items([{ name: 'Topografia', price: 0 }, { name: 'Outro', price: -10 }])

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'recusa linha sem unidade e grupo × unidade em contradição, sem gravar nada', :aggregate_failures do
    post_items([{ group: 'Outros', name: 'Consulta', price: 400 },
                { group: 'Catarata (por olho)', name: 'Trifocal', price: 8490, unit: 'dois_olhos' }])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('Consulta: escolha a unidade')
    expect(response.parsed_body['error']).to include('Trifocal: o grupo diz "por olho"')
    expect(saved_items).to be_nil
  end

  it 'grava promoção R$ 0 como "sem promoção" e a unidade como campo', :aggregate_failures do
    post_items([{ group: 'Catarata', name: 'Trifocal', price: 8490, promo_price: 0, unit: 'por_olho' },
                { group: 'Refrativa', name: 'Lasik', price: 5700, promo_price: 5200, unit: 'dois_olhos' }])

    expect(response).to have_http_status(:ok)
    expect(saved_items).to eq([
                                { 'group' => 'Catarata', 'name' => 'Trifocal', 'price' => 8490.0, 'unit' => 'por_olho' },
                                { 'group' => 'Refrativa', 'name' => 'Lasik', 'price' => 5700.0, 'promo_price' => 5200.0,
                                  'unit' => 'dois_olhos' }
                              ])
    block = Cevico::PriceList.prompt_block(account)
    expect(block).to include('Trifocal R$ 8.490 por olho')
    expect(block).to include('Lasik R$ 5.200 pelos dois olhos (promoção; preço normal R$ 5.700 pelos dois olhos)')
  end

  it 'lente fácica (Artisan) fica por olho mesmo se a tela mandar "dois olhos"' do
    post_items([{ group: 'Lentes', name: 'Artisan', price: 11_900, unit: 'dois_olhos' }])

    expect(saved_items.first['unit']).to eq('por_olho')
  end

  it 'continua ignorando linha sem nome' do
    post_items([{ name: '', price: nil }, { name: 'Consulta', price: 400, unit: 'unico' }])

    expect(response).to have_http_status(:ok)
    expect(saved_items.pluck('name')).to eq(['Consulta'])
  end
end
