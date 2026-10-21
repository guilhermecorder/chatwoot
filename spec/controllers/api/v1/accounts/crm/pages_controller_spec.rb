require 'rails_helper'

# 🔐 Auditoria rodada 2 (#20, #150, #169, #399, #428): ambiente Páginas de
# portas fechadas — concessão pelo catálogo (marketing.paginas), página NO AR
# só o admin altera, slug/status só do admin, link do botão dentro da régua,
# geração com IA e upload com limite por pessoa por dia.
RSpec.describe 'CEVICO Páginas (API)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/pages" }
  let(:published) do
    CevicoPage.create!(account: account, title: 'Catarata', slug: 'catarata-no-ar', status: 'published',
                       cta_url: 'https://wa.me/5511999999999', sections: [], ab_variants: [], team_comments: [], daily_stats: {})
  end
  let(:draft) do
    CevicoPage.create!(account: account, title: 'Refrativa', slug: 'refrativa-rascunho', status: 'draft',
                       sections: [], ab_variants: [], team_comments: [], daily_stats: {})
  end

  def perms!(hash)
    CrmSetting.find_or_create_by!(account: account).update!(agent_permissions: hash)
  end

  def auth(user) = user.create_new_auth_token
  def png = fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')

  before do
    Cevico::DailyQuota.reset!(:page_generate, account: account, user: agent)
    Cevico::DailyQuota.reset!(:page_generate, account: account, user: admin)
    Cevico::DailyQuota.reset!(:page_upload, account: account, user: agent)
  end

  describe 'concessão marketing.paginas (#169)' do
    it 'sem concessão nenhuma: nem lista, nem cria, nem gera com IA, nem sobe imagem', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'marketing.paginas' => 'none' } })

      get base, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      post base, params: { title: 'Nova' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{base}/upload_image", params: { image: png }, headers: auth(agent)
      expect(response).to have_http_status(:forbidden)
    end

    it 'quem só VÊ lista sem o link de retoque e não cria nem gera', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'marketing.paginas' => 'view' } })
      draft

      get base, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['pages'].first['builder_url']).to be_nil

      post base, params: { title: 'Nova' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'quem EDITA (padrão do time) recebe o link de retoque e cria só rascunho, mesmo pedindo publicada', :aggregate_failures do
      draft
      get base, headers: auth(agent), as: :json
      expect(response.parsed_body['pages'].first['builder_url']).to include('?edit=')

      post base, params: { title: 'Nova', status: 'published', slug: 'endereco-escolhido' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:created)
      created = CevicoPage.find(response.parsed_body['id'])
      expect(created.status).to eq('draft')
      expect(created.slug).to eq('nova')
    end
  end

  describe 'página NO AR (#20/#150/#399/#428)' do
    it 'atendente não altera nada numa página publicada (403) e o site não muda', :aggregate_failures do
      patch "#{base}/#{published.id}", params: { title: 'Mudou', cta_url: 'https://wa.me/5511888888888' },
                                       headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to include('no ar')
      expect(published.reload.title).to eq('Catarata')
      expect(published.cta_url).to eq('https://wa.me/5511999999999')
    end

    it 'atendente ainda comenta na página publicada' do
      post "#{base}/#{published.id}/add_comment", params: { text: 'Trocar a foto da capa' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(published.reload.team_comments.first['text']).to eq('Trocar a foto da capa')
    end

    it 'quem só VÊ páginas comenta e apaga o próprio comentário, mas não o dos outros', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'marketing.paginas' => 'view' } })
      published.update!(team_comments: [{ 'id' => 'adm1', 'user_id' => admin.id, 'name' => 'Admin', 'text' => 'ok', 'at' => Time.current.iso8601 }])

      post "#{base}/#{published.id}/add_comment", params: { text: 'Sugestão de título' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      mine = response.parsed_body['team_comments'].find { |c| c['text'] == 'Sugestão de título' }

      post "#{base}/#{published.id}/delete_comment", params: { comment_id: mine['id'] }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/#{published.id}/delete_comment", params: { comment_id: 'adm1' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(published.reload.team_comments.pluck('id')).to eq(['adm1'])
    end

    it 'atendente edita o rascunho, mas não troca o endereço nem a etapa', :aggregate_failures do
      patch "#{base}/#{draft.id}", params: { title: 'Refrativa 2', slug: 'outro-endereco', status: 'published' },
                                   headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      draft.reload
      expect(draft.title).to eq('Refrativa 2')
      expect(draft.slug).to eq('refrativa-rascunho')
      expect(draft.status).to eq('draft')
    end

    it 'administrador altera a página publicada, o endereço e a etapa', :aggregate_failures do
      patch "#{base}/#{published.id}", params: { title: 'Catarata hoje', slug: 'catarata-hoje', status: 'draft' },
                                       headers: auth(admin), as: :json
      expect(response).to have_http_status(:success)
      published.reload
      expect(published.title).to eq('Catarata hoje')
      expect(published.slug).to eq('catarata-hoje')
      expect(published.status).to eq('draft')
    end

    it 'IA em segundo plano não reescreve página no ar para quem não é admin', :aggregate_failures do
      post "#{base}/generate_start", params: { briefing: 'x', page_id: published.id }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:forbidden)

      post "#{base}/generate_start", params: { briefing: 'x', page_id: draft.id }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['job_id']).to be_present
    end
  end

  describe 'link do botão (cta_url)' do
    it 'recusa destino fora da régua e aceita WhatsApp', :aggregate_failures do
      patch "#{base}/#{draft.id}", params: { cta_url: 'https://exemplo.com/promocao' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(draft.reload.cta_url).to be_nil

      patch "#{base}/#{draft.id}", params: { cta_url: 'https://api.whatsapp.com/send?phone=5511999999999' },
                                   headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(draft.reload.cta_url).to start_with('https://api.whatsapp.com/')
    end

    it 'grava o link sem espaços nas pontas (espaço quebrava o clique público)' do
      patch "#{base}/#{draft.id}", params: { cta_url: '  https://wa.me/5511999999999  ' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(draft.reload.cta_url).to eq('https://wa.me/5511999999999')
    end
  end

  describe 'link de retoque no relatório de Resultados' do
    it 'quem só vê Resultados não recebe o token de edição; admin recebe', :aggregate_failures do
      perms!('tree' => { agent.id.to_s => { 'marketing.resultados' => 'view', 'marketing.paginas' => 'view' } })
      published
      report = "/api/v1/accounts/#{account.id}/crm/pages_report"

      get report, params: { preset: 'last7' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['pages'].first['builder_url']).to be_nil

      get report, params: { preset: 'last7' }, headers: auth(admin), as: :json
      expect(response.parsed_body['pages'].first['builder_url']).to include('?edit=')
    end
  end

  describe 'limite por pessoa por dia' do
    it 'geração com IA para no limite (429) e cada pessoa tem o seu', :aggregate_failures do
      stub_const('Api::V1::Accounts::Crm::PagesController::GENERATE_PER_DAY', 2)

      2.times do
        post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(agent), as: :json
        expect(response).to have_http_status(:success)
      end
      post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(agent), as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to include('limite de hoje')

      post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:success)
    end

    it 'administrador tem teto 3× maior e a mensagem não manda pedir a um administrador', :aggregate_failures do
      stub_const('Api::V1::Accounts::Crm::PagesController::GENERATE_PER_DAY', 1)

      3.times do
        post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(admin), as: :json
        expect(response).to have_http_status(:success)
      end
      post "#{base}/generate_start", params: { briefing: 'x' }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).not_to include('peça a um administrador')
    end

    it 'a chave do contador usa o dia de São Paulo' do
      travel_to Time.utc(2026, 10, 13, 1, 0) do # 22h de 12/10 em São Paulo
        expect(Cevico::DailyQuota.key(:page_generate, account_id: 1, user_id: 2)).to end_with(':2026-10-12')
      end
    end

    it 'upload de imagem para no limite (429)', :aggregate_failures do
      stub_const('Api::V1::Accounts::Crm::PagesController::UPLOAD_PER_DAY', 1)

      post "#{base}/upload_image", params: { image: png }, headers: auth(agent)
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['url']).to include('/rails/active_storage/')

      post "#{base}/upload_image", params: { image: png }, headers: auth(agent)
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
