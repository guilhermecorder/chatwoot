require 'rails_helper'

# 📅 item 321 (03/10): a MESMA régua de período em todos os ambientes — hoje,
# ontem, 7 dias, semana passada, mês, mês passado, 90 dias, ano, personalizado
RSpec.describe 'CEVICO régua de período padrão', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  before { travel_to tz.parse('2026-10-03 15:00') }

  describe 'gasto dos agentes de IA' do
    before do
      { '2026-10-03 09:00' => 1, '2026-10-02 09:00' => 2, '2026-08-10 09:00' => 4, '2026-05-01 09:00' => 8 }.each do |at, cost|
        Crm::AiUsage.create!(account: account, agent_key: 'atendente', model: 'x', cost_usd: cost, created_at: tz.parse(at))
      end
    end

    it 'devolve o total e a quebra por agente do período da régua', :aggregate_failures do
      costs = %w[today yesterday last7 last90 year].index_with do |preset|
        get "#{base}/settings/ai_usage", params: { preset: preset }, headers: headers, as: :json
        response.parsed_body.dig('period', 'totals', 'cost_usd')
      end
      expect(costs).to eq('today' => 1.0, 'yesterday' => 2.0, 'last7' => 3.0, 'last90' => 7.0, 'year' => 15.0)

      get "#{base}/settings/ai_usage", params: { preset: 'custom', from: '2026-08-01', to: '2026-08-31' }, headers: headers, as: :json
      expect(response.parsed_body['period']).to include('from' => '2026-08-01', 'to' => '2026-08-31')
      expect(response.parsed_body.dig('period', 'by_agent', 0)).to include('key' => 'atendente', 'cost_usd' => 4.0)
    end

    it 'sem preset continua como era (caixas fixas e 30 dias por agente)', :aggregate_failures do
      get "#{base}/settings/ai_usage", headers: headers, as: :json
      expect(response.parsed_body['period']).to be_nil
      expect(response.parsed_body.dig('periods', 'all', 'cost_usd')).to eq(15.0)
    end
  end

  describe 'Auditor de Conversas' do
    before do
      days = { '2026-10-02' => { 'n' => 2, 'sum' => 16.0, 'gaps' => { 'sem_cta' => 1 } },
               '2026-09-10' => { 'n' => 1, 'sum' => 5.0, 'gaps' => {} },
               '2026-07-20' => { 'n' => 4, 'sum' => 20.0, 'gaps' => {} } }
      CrmSetting.create!(account: account, ai_config: { 'auditor_state' => { 'agents' => { admin.id.to_s => days } } })
    end

    it 'soma só os dias dentro do período da régua', :aggregate_failures do
      totals = %w[last7 last_month last90].index_with do |preset|
        get "#{base}/settings/auditor_summary", params: { preset: preset }, headers: headers, as: :json
        response.parsed_body['audited_total']
      end
      expect(totals).to eq('last7' => 2, 'last_month' => 1, 'last90' => 7)

      get "#{base}/settings/auditor_summary", params: { days: 30 }, headers: headers, as: :json # legado
      expect(response.parsed_body['audited_total']).to eq(3)
    end
  end

  describe 'Meu Painel com 90 dias' do
    it 'a meta vale ~3 meses e o total de 90 dias não vira "recorde do dia"', :aggregate_failures do
      settings = CrmSetting.create!(account: account, agenda_config: {})
      3.times { |i| create(:contact, account: account, created_at: tz.parse('2026-08-15 10:00') + i.days) }

      get "#{base}/home", params: { preset: 'last90' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('goals', 'factor')).to be_within(0.01).of(90 / 31.0)
      expect(response.parsed_body.dig('goals', 'records')).to eq({})
      expect(settings.reload.agenda_config['panel_records']).to be_nil
    end
  end
end
