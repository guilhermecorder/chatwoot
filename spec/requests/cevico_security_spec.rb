require 'rails_helper'

# 🔐 Rodada 171 — endurecimento no código: CSP "só relatar" + sem iframe
# nas páginas públicas, links com validade, cadeado do acesso clínico.
RSpec.describe 'CEVICO segurança (rodada 171)', type: :request do
  let(:account) { create(:account) }

  describe 'páginas públicas' do
    let!(:page) do
      CevicoPage.create!(account: account, title: 'Catarata', slug: 'catarata-teste', status: 'published',
                         body: 'Olá **mundo**', ab_variants: {}, daily_stats: {}, sections: [], team_comments: [])
    end

    it 'manda CSP só-relatar com nonce, sem iframe e sem vazar referer' do
      get "/p/#{page.slug}"
      expect(response).to have_http_status(:success)
      csp = response.headers['Content-Security-Policy-Report-Only']
      expect(csp).to include("script-src 'self' https://www.googletagmanager.com").and include("'nonce-")
      expect(csp).to include('report-uri /webhooks/cevico/csp_report')
      expect(response.headers['Content-Security-Policy']).to be_nil
      expect(response.headers['X-Frame-Options']).to eq('DENY')
      expect(response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
      expect(response.body).to include('nonce="')
    end

    it 'aceita o relatório de violação sem gravar nada' do
      post '/webhooks/cevico/csp_report', params: { 'csp-report' => { 'violated-directive' => 'script-src' } }.to_json,
                                          headers: { 'CONTENT_TYPE' => 'application/csp-report' }
      expect(response).to have_http_status(:no_content)
    end

    # rubocop:disable Rails/DynamicFindBy -- find_by_preview_token é método nosso, não dinâmico
    it 'link de prévia vence em 30 dias e o de retoque em 7' do
      preview = page.preview_token
      edit = page.edit_token
      expect(CevicoPage.find_by_preview_token(preview)).to eq(page)
      expect(page.valid_edit_token?(edit)).to be(true)
      travel_to 8.days.from_now do
        expect(page.valid_edit_token?(edit)).to be(false)
        expect(CevicoPage.find_by_preview_token(preview)).to eq(page)
      end
      travel_to 31.days.from_now do
        expect(CevicoPage.find_by_preview_token(preview)).to be_nil
      end
      # token de prévia não serve para retocar (finalidades separadas)
      expect(page.valid_edit_token?(preview)).to be(false)
    end
    # rubocop:enable Rails/DynamicFindBy
  end

  describe 'link do formulário' do
    let(:form) { Crm::Form.create!(account: account, name: 'Pré-avaliação', questions: [], funnel_stats: {}, ai_insight: {}) }
    let(:contact) { create(:contact, account: account) }

    it 'vale 90 dias e ainda aceita links antigos (sem validade) enviados antes desta rodada' do
      link = form.public_link_for(contact)
      token = CGI.unescape(link.split('/').last)
      expect(Crm::Form.verify_token(token)).to include(form_id: form.id, contact_id: contact.id)
      travel_to 91.days.from_now do
        expect(Crm::Form.verify_token(token)).to be_nil
      end
      legacy = Rails.application.message_verifier(:cevico_form).generate({ form_id: form.id, account_id: account.id, contact_id: nil })
      expect(Crm::Form.verify_token(legacy)).to include(form_id: form.id)
      expect(Crm::Form.verify_token('lixo')).to be_nil
    end
  end

  describe 'acesso clínico' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:admin) { create(:user, account: account, role: :administrator) }

    before { CrmSetting.create!(account: account, agent_permissions: { 'grants' => { agent.id.to_s => ['settings'] } }) }

    it 'atendente com a área "settings" NÃO consegue se incluir entre os médicos' do
      post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
           params: { clinical_access: { doctor_user_ids: [agent.id], team_view: true } },
           headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(CrmSetting.find_by!(account: account).agenda_config.to_h['clinical_access']).to be_nil
    end

    it 'admin continua conseguindo' do
      post "/api/v1/accounts/#{account.id}/crm/settings/update_agenda",
           params: { clinical_access: { doctor_user_ids: [admin.id], team_view: false } },
           headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(CrmSetting.find_by!(account: account).agenda_config['clinical_access']['doctor_user_ids']).to eq([admin.id])
    end
  end

  # 🔐 Rodada 2 da auditoria (12/10): as portas do crm/settings
  describe 'portas do crm/settings (Rodada 2)' do
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:base) { "/api/v1/accounts/#{account.id}/crm/settings" }
    # as ÚNICAS ações que a equipe toda pode chamar: a leitura (que vem enxuta,
    # por papel) e fechar/reabrir dias, horários e médicos da Agenda (itens 267 e 366)
    let(:open_to_team) { %w[show update_blocked_days update_agenda_locks] }

    before do
      # o atendente aqui só VÊ a ficha do paciente: quem edita o orçamento recebe a tabela de preços (decisão R2-G4)
      CrmSetting.create!(account: account, agent_permissions: { 'tree' => { agent.id.to_s => { 'pacientes' => 'view' } } },
                         ai_config: { 'script' => { 'persona' => 'Você é a Clara.' },
                                      'agents' => { 'comments' => { 'prompt' => 'PROMPT PUBLICADO' } } },
                         agenda_config: { 'price_table' => { 'items' => [{ 'group' => 'Cirurgias', 'name' => 'Catarata', 'price' => 9000 }] },
                                          'column_presets' => [] })
    end

    it 'atendente sem concessão leva 403 em TODAS as rotas de settings (menos as duas abertas à equipe)', :aggregate_failures do
      routes = Rails.application.routes.routes.select { |r| r.defaults[:controller] == 'api/v1/accounts/crm/settings' }
      expect(routes.size).to be > 60 # se a lista encolher, alguém apagou rota — olhar
      seen = []
      routes.each do |route|
        action = route.defaults[:action]
        next if open_to_team.include?(action)

        verb = route.verb.to_s.split('|').first.downcase
        path = route.path.spec.to_s.sub('(.:format)', '').sub(':account_id', account.id.to_s)
        send(verb, path, params: { full: true, user_id: agent.id }, headers: agent.create_new_auth_token, as: :json)
        expect(response).to have_http_status(:forbidden), "#{verb.upcase} #{path} (#{action}) devolveu #{response.status}"
        seen << action
      end
      expect(seen).to include('sync_oftalmofacil', 'test_oftalmofacil', 'ai_usage', 'update_ai', 'update', 'update_oftalmofacil')
    end

    it 'show sem concessão não traz Roteiro, prompts, concessões nem preços — e segue com o que a tela usa', :aggregate_failures do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json.keys).not_to include('agent_permissions', 'price_table', 'scheduler_log', 'appointment_reminders_state', 'nps_survey_state')
      expect(json['ai'].keys).not_to include('script', 'script_v2', 'responder_events')
      expect(json.dig('ai', 'agents', 'comments').keys).not_to include('prompt', 'draft', 'default_prompt')
      expect(response.body).not_to include('Clara', 'PROMPT PUBLICADO', '9000')
      expect(json).to include('column_presets', 'person_colors', 'list_clean_mode', 'calls', 'access', 'kpi_layout', 'agenda_windows')
    end
  end
end
