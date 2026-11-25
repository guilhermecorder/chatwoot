require 'rails_helper'

# 🆚 item 413 — a porta do Comparativo de caixas: mesmo acesso do Dashboard CRM;
# dinheiro só para administrador.
RSpec.describe 'Comparativo de caixas API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/inbox_comparison" }
  let(:inbox) { create(:inbox, account: account, name: 'INSTAGRAM') }

  before do
    travel_to Time.current.in_time_zone('America/Sao_Paulo').change(hour: 12)
    Rails.cache.clear
    CrmSetting.create!(account: account, agenda_config: {})
    contact = create(:contact, account: account, created_at: 1.hour.ago)
    create(:conversation, account: account, inbox: inbox, contact: contact, created_at: 1.hour.ago)
    allow(Crm::MetaInsightsService).to receive(:new).and_return(instance_double(Crm::MetaInsightsService, call: { configured: false }))
  end

  it 'pede login' do
    get url

    expect(response).to have_http_status(:unauthorized)
  end

  it 'devolve o comparativo do período com o dinheiro para o administrador', :aggregate_failures do
    get url, params: { preset: 'today', compare: 'previous' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['financeiro']).to be(true)
    expect(body['meta']).to include('aviso' => 'Meta Ads não configurado em Integrações')
    expect(body['caixas'].first).to include('nome' => 'INSTAGRAM', 'porta' => true)
    expect(body['caixas'].first['funil']).to include('chegaram' => 1)
    expect(body['caixas'].first['custo']).to include('investimento' => 0.0)
    expect(body['comparacao']).to include('modo' => 'previous', 'rotulo' => 'ontem')
  end

  it 'entende o período "Hoje + ontem" (item 418)', :aggregate_failures do
    get url, params: { preset: 'last2' }, headers: admin.create_new_auth_token, as: :json

    sp = Time.current.in_time_zone('America/Sao_Paulo')
    expect(response.parsed_body['periodo']['de']).to start_with(sp.yesterday.strftime('%Y-%m-%d'))
    expect(response.parsed_body['periodo']['ate']).to start_with(sp.strftime('%Y-%m-%d'))
    expect(response.parsed_body['comparacao']).to include('rotulo' => '2 dias anteriores')
  end

  it 'devolve as linhas por caixa, campanha e criativo para quem vê o relatório (item 418)', :aggregate_failures do
    get "#{url}/lines", params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['regime']).to include('balde' => 'dia', 'janela' => 7)
    expect(body['caixas'].first).to include('nome' => 'INSTAGRAM', 'chegaram' => 1)
    expect(body['campanhas'].first).to include('nome' => 'Sem anúncio do Meta carimbado · INSTAGRAM')
  end

  # 📍 item 419 — marcos de teste: a caixa comparada com ela mesma
  describe 'marcos de teste' do
    it 'o administrador anota, lista e apaga um marco com as caixas dele', :aggregate_failures do
      post "#{url}/mark", params: { title: 'INSTAGRAM no Roteiro 2', at: 2.hours.ago.iso8601, inbox_ids: [inbox.id, 999_999], note: 'teste' },
                          headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      marco = response.parsed_body['marcos'].first
      expect(marco).to include('titulo' => 'INSTAGRAM no Roteiro 2', 'inbox_ids' => [inbox.id], 'caixas' => ['INSTAGRAM'], 'nota' => 'teste')
      expect(marco['horas']).to be_within(0.1).of(2.0)
      expect(response.parsed_body['pode_marcar']).to be(true)

      get "#{url}/marks", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['marcos'].size).to eq(1)
      # quem não vê o relatório também não lista os marcos
      get "#{url}/marks", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{url}/unmark", params: { id: marco['id'] }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['marcos']).to eq([])
    end

    it 'recusa marco sem nome, no futuro ou anotado por quem não é administrador', :aggregate_failures do
      post "#{url}/mark", params: { title: ' ' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{url}/mark", params: { title: 'Futuro', at: 2.days.from_now.iso8601 }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{url}/mark", params: { title: 'Agente' }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(Crm::AttendanceMilestones.list(account)).to eq([])
    end

    it 'desde o marco: o período vai do marco até agora e a base é o mesmo tempo logo antes', :aggregate_failures do
      marco = Crm::AttendanceMilestones.add!(account, title: 'Troca', at: 3.hours.ago.iso8601, inbox_ids: [inbox.id])
      antes = create(:contact, account: account, created_at: 4.hours.ago)
      create(:conversation, account: account, inbox: inbox, contact: antes, created_at: 4.hours.ago)

      get url, params: { preset: 'mark', mark: marco['id'], compare: 'month' }, headers: admin.create_new_auth_token, as: :json
      body = response.parsed_body
      expect(Time.zone.parse(body['periodo']['de'])).to be_within(1.second).of(3.hours.ago)
      expect(Time.zone.parse(body['periodo']['ate'])).to be_within(5.minutes).of(Time.current)
      expect(body['comparacao']).to include('modo' => 'previous', 'rotulo' => 'mesmo tempo antes do marco')
      expect(Time.zone.parse(body['comparacao']['de'])).to be_within(5.minutes).of(6.hours.ago)
      caixa = body['caixas'].first
      expect(caixa['funil']).to include('chegaram' => 1)
      expect(caixa['anterior']).to include('chegaram' => 1)

      get "#{url}/lines", params: { preset: 'mark', mark: marco['id'] }, headers: admin.create_new_auth_token, as: :json
      linhas = response.parsed_body
      expect(linhas['regime']).to include('balde' => 'hora')
      expect(linhas['marcos'].first).to include('id' => marco['id'], 'titulo' => 'Troca', 'pos' => 0, 'inbox_ids' => [inbox.id])
    end

    it 'marco que não existe cai na régua de sempre; as linhas do período mostram onde o marco fica', :aggregate_failures do
      get url, params: { preset: 'mark', mark: 'nao-existe' }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)

      Crm::AttendanceMilestones.add!(account, title: 'Ontem', at: 1.day.ago.iso8601)
      get "#{url}/lines", params: { preset: 'last7' }, headers: admin.create_new_auth_token, as: :json
      marcos = response.parsed_body['marcos']
      expect(marcos.size).to eq(1)
      expect(marcos.first).to include('titulo' => 'Ontem', 'pos' => 5, 'inbox_ids' => [])
    end
  end

  it 'as linhas também pedem login' do
    get "#{url}/lines"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'usa a régua padrão de período (mês, quando não vem preset)' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['periodo']['de']).to start_with(Time.current.in_time_zone('America/Sao_Paulo').strftime('%Y-%m-01'))
  end
end
