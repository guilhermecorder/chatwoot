require 'rails_helper'

# 📈 item 329 (05/10): Resultados de tráfego — funil com taxas, série para os
# gráficos, período anterior, diagnósticos, coleção de insights e sugestões da IA.
RSpec.describe 'CEVICO Resultados de tráfego', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pages_report" }
  let(:page) do
    CevicoPage.create!(account: account, title: 'Catarata', slug: 'catarata-teste', status: 'published', category: 'captacao',
                       daily_stats: { Date.current.iso8601 => { 'scroll' => { '25' => 50, '50' => 30, '100' => 10 } } })
  end

  before { Rails.cache.clear }

  def traffic(date, source, views, cta, campaign: '')
    CevicoPageTraffic.create!(account: account, cevico_page: page, date: date, source: source, campaign: campaign, views: views, cta_clicks: cta)
  end

  def lead(source, at: Time.current, booked: false)
    person = create(:contact, account: account, additional_attributes: {
                      'page_ads' => { 'page_id' => page.id, 'source' => source, 'captured_at' => at.iso8601 }
                    })
    Task.create!(account: account, creator: admin, title: 'Consulta: Paciente', task_type: 'consulta', contact: person) if booked
    person
  end

  def report(params = { preset: 'last7' })
    get base, params: params, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  it 'entrega totais, período anterior, série por dia e a linha da página com leitura e SEO', :aggregate_failures do
    traffic(Date.current, 'google_ads', 60, 9, campaign: 'catarata-sp')
    traffic(Date.current - 1, 'google_organico', 40, 6)
    traffic(Date.current - 8, 'google_ads', 20, 1) # período anterior
    lead('google_ads', booked: true)
    lead('google_organico')

    body = report
    expect(body['totals']).to include('views' => 100, 'cta' => 15, 'leads' => 2, 'booked' => 1)
    expect(body['previous']['totals']).to include('views' => 20, 'cta' => 1, 'leads' => 0)
    expect(body['series']).to include('granularity' => 'day')
    expect(body['series']['labels'].size).to eq(7)
    expect(body['series']['views'].last(2)).to eq([40, 60])
    expect(body['series']['leads'].sum).to eq(2)
    expect(body['series']['by_source']['google_ads']['views'].last).to eq(60)

    row = body['rows'].first
    expect(row).to include('title' => 'Catarata', 'views' => 100, 'leads' => 2, 'scroll' => { '25' => 50, '50' => 30, '75' => 0, '100' => 10 })
    expect(row['sources']['google_ads']).to include('views' => 60, 'cta' => 9, 'leads' => 1, 'booked' => 1)
    expect(row['campaigns']['catarata-sp']).to include('views' => 60)
    expect(row['spark'].last).to eq([60, 9])
    expect(body['insights'].pluck('rule')).to include('seo_titulo', 'seo_descricao')
    expect(body['pages'].first).to include('id' => page.id)
    expect(body['pages'].first['builder_url']).to include('?edit=')
  end

  it 'períodos longos viram série por semana' do
    traffic(Date.current, 'direto', 5, 1)
    expect(report(preset: 'last90')['series']['granularity']).to eq('week')
  end

  it 'coleção de insights: guarda, aplica (com antes × depois), descarta e apaga', :aggregate_failures do
    traffic(Date.current, 'direto', 40, 8)
    traffic(Date.current - 1, 'direto', 50, 2)
    headers = admin.create_new_auth_token

    post "#{base}/save_insight", params: { key: "p#{page.id}:cta_baixo", page_id: page.id, title: 'Subir o botão', text: 'no topo', origin: 'auto' },
                                 headers: headers, as: :json
    saved = response.parsed_body['collection'].first
    expect(saved).to include('title' => 'Subir o botão', 'status' => 'todo', 'origin' => 'auto', 'created_by' => admin.name)
    expect(saved['result']).to be_nil

    post "#{base}/save_insight", params: { id: saved['id'], status: 'done' }, headers: headers, as: :json
    done = response.parsed_body['collection'].first
    expect(done).to include('status' => 'done', 'applied_at' => Date.current.iso8601)
    expect(done['result']).to include('days' => 1, 'early' => false)
    expect(done['result']['before']).to include('views' => 50, 'click_rate' => 4.0)
    expect(done['result']['after']).to include('views' => 40, 'click_rate' => 20.0)

    post "#{base}/save_insight", params: { id: saved['id'], status: 'dismissed' }, headers: headers, as: :json
    expect(response.parsed_body['collection'].first).to include('status' => 'dismissed', 'applied_at' => nil)
    expect(report['collection'].size).to eq(1)

    post "#{base}/remove_insight", params: { id: saved['id'] }, headers: headers, as: :json
    expect(response.parsed_body['collection']).to be_empty

    post "#{base}/save_insight", params: { text: 'sem título' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'sugestões da IA: manda a página, os números e os diagnósticos; erro da IA volta como aviso', :aggregate_failures do
    traffic(Date.current, 'google_ads', 60, 9)
    result = { diagnostico: 'ok', sugestoes: [{ 'titulo' => 'Subir o botão', 'por_que' => 'x', 'pedido' => 'y' }] }
    allow(Crm::PageOptimizerService).to receive(:new).and_return(instance_double(Crm::PageOptimizerService, call: result))

    post "#{base}/ai_suggestions", params: { preset: 'last7', page_id: page.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['sugestoes'].first['titulo']).to eq('Subir o botão')
    expect(Crm::PageOptimizerService).to have_received(:new)
      .with(hash_including(page: page, row: hash_including(views: 60), period: %r{\d{2}/\d{2} a }))

    allow(Crm::PageOptimizerService).to receive(:new).and_call_original
    post "#{base}/ai_suggestions", params: { preset: 'last7', page_id: page.id }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('IA não configurada')
  end

  it 'barra atendente sem a concessão de Marketing' do
    get base, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
