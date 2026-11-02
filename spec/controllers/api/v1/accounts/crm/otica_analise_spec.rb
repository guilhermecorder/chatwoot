require 'rails_helper'

# 📊 SUA ÓTICA — ANÁLISE DA LOJA (02/11/2026): a página do SavWin dentro do sistema.
#   · POST reports (token de acesso do usuário ou login): só administrador da conta ótica;
#   · GET reports / latest / :id/html: quem tem o nó otica.analise (padrão: todo mundo da
#     conta ótica); a clínica não tem o nó, então nem vê;
#   · o HTML sai como text/html, sem cache e com noindex; a versão mais nova é a que abre.
RSpec.describe 'Sua Ótica — análise da loja', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/otica" }
  let(:html) { "<!DOCTYPE html>\n<html lang=\"pt-BR\"><head><title>Raio-X</title></head><body><h1>Análise ótica</h1></body></html>" }
  let(:tmp) do
    f = Tempfile.new(['index', '.html'])
    f.binmode
    f.write(html)
    f.rewind
    f
  end
  let(:upload) { Rack::Test::UploadedFile.new(tmp.path, 'text/html', original_filename: 'index.html') }

  before do
    Current.reset
    CrmSetting.create!(account: account, agenda_config: { 'company' => { 'segment' => 'otica' } })
  end

  after { tmp.close! }

  def attach_report(content = html, acc = account, **attrs)
    report = acc.otica_reports.new({ created_by: admin }.merge(attrs))
    report.file.attach(io: StringIO.new(content), filename: 'index.html', content_type: 'text/html')
    report.save!
    report
  end

  describe 'POST reports (enviar uma versão)' do
    it 'admin envia pela API com o token de acesso do usuário (o --enviar do savwin.py)', :aggregate_failures do
      post "#{base}/reports", params: { file: upload, title: 'Raio-X', note: 'leitura de 22/10' },
                              headers: { api_access_token: admin.access_token.token }
      expect(response).to have_http_status(:success)
      body = response.parsed_body['report']
      expect(body['title']).to eq('Raio-X')
      expect(body['note']).to eq('leitura de 22/10')
      expect(body['size_bytes']).to eq(html.bytesize)
      expect(body.dig('created_by', 'id')).to eq(admin.id)
      expect(account.otica_reports.latest.html).to include('Análise ótica')
    end

    it 'admin envia pela tela (login normal) e o título fica com o padrão' do
      post "#{base}/reports", params: { file: upload }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('report', 'title')).to eq('Análise da loja')
    end

    it 'quem não é administrador não envia' do
      post "#{base}/reports", params: { file: upload }, headers: { api_access_token: agent.access_token.token }
      expect(response).to have_http_status(:forbidden)
      expect(account.otica_reports.count).to eq(0)
    end

    it 'sem login não entra' do
      post "#{base}/reports", params: { file: upload }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'sem arquivo ou com arquivo que não é HTML responde 422', :aggregate_failures do
      post "#{base}/reports", params: { title: 'x' }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      csv = Tempfile.new(['dados', '.csv'])
      csv.binmode
      csv.write('codigo,grife')
      csv.rewind
      post "#{base}/reports", params: { file: Rack::Test::UploadedFile.new(csv.path, 'text/csv') }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('HTML')
      csv.close!
    end

    it 'a clínica não tem esta tela: nem o administrador envia' do
      clinic = create(:account)
      clinic_admin = create(:user, account: clinic, role: :administrator)
      post "/api/v1/accounts/#{clinic.id}/crm/otica/reports",
           params: { file: upload }, headers: { api_access_token: clinic_admin.access_token.token }
      expect(response).to have_http_status(:forbidden)
      expect(Otica::Report.count).to eq(0)
    end
  end

  describe 'GET reports, latest e :id/html (ler)' do
    let!(:old) do
      r = attach_report('<html><body>antiga</body></html>', title: 'v1')
      r.update_column(:created_at, 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
      r
    end
    let!(:new) { attach_report(html, title: 'v2', note: 'nova') }

    it 'lista as versões, a mais nova primeiro, e diz qual é a mais nova', :aggregate_failures do
      get "#{base}/reports", headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(response.parsed_body['reports'].pluck('title')).to eq(%w[v2 v1])
      expect(response.parsed_body['latest_id']).to eq(new.id)
    end

    it 'latest serve o HTML da versão mais nova sem cache e sem robô', :aggregate_failures do
      get "#{base}/reports/latest", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq('text/html')
      expect(response.headers['Cache-Control']).to eq('no-store')
      expect(response.headers['X-Robots-Tag']).to include('noindex')
      expect(response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
      expect(response.body).to include('Análise ótica')
      expect(response.body).not_to include('antiga')
    end

    it ':id/html serve uma versão específica' do
      get "#{base}/reports/#{old.id}/html", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.body).to include('antiga')
    end

    it 'não serve versão de outra conta' do
      other = attach_report(html, create(:account))
      get "#{base}/reports/#{other.id}/html", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'latest sem nenhuma versão responde 404' do
      Otica::Report.destroy_all
      get "#{base}/reports/latest", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end

    it 'a clínica não vê (o nó otica.analise não existe no ramo clínica)' do
      clinic = create(:account)
      clinic_admin = create(:user, account: clinic, role: :administrator)
      get "/api/v1/accounts/#{clinic.id}/crm/otica/reports", headers: clinic_admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'quem teve o nó tirado (marcação própria em Configurações → Acessos) não vê' do
      CrmSetting.find_by(account: account).update!(agent_permissions: { 'tree' => { agent.id.to_s => { 'otica.analise' => 'none' } } })
      get "#{base}/reports/latest", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end
end
