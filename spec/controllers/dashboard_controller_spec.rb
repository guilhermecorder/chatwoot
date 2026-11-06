require 'rails_helper'

describe '/app/login', type: :request do
  context 'without DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      get '/app/login'
      expect(response).to have_http_status(:success)
    end
  end

  context 'with DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      with_modified_env DEFAULT_LOCALE: 'pt_BR' do
        get '/app/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include "selectedLocale: 'pt_BR'"
      end
    end
  end

  context 'with non-HTML format' do
    it 'returns not acceptable for JSON with error message' do
      get '/app/login', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.parsed_body).to eq({ 'error' => 'Please use API routes instead of dashboard routes for JSON requests' })
    end
  end

  # Routes are loaded once on app start
  # hence Rails.application.reload_routes! is used in this spec
  # ref : https://stackoverflow.com/a/63584877/939299
  context 'with CW_API_ONLY_SERVER true' do
    it 'returns 404' do
      with_modified_env CW_API_ONLY_SERVER: 'true' do
        Rails.application.reload_routes!
        get '/app/login'
        expect(response).to have_http_status(:not_found)
      end
      Rails.application.reload_routes!
    end
  end

  # 🏷️ 06/11: VPS com pacote de marca (ótica) — nome, logos, ícones do celular e
  # manifest saem do pacote, mesmo com o banco nos valores de fábrica
  context 'with brand package (MARCA=otica)' do
    # sem o front compilado na bancada o Vite derruba a página (500): aqui só o <head> importa
    before do
      allow_any_instance_of(ViteRails::TagHelpers).to receive_messages(vite_client_tag: '', vite_javascript_tag: '') # rubocop:disable RSpec/AnyInstance
      InstallationConfig.find_or_initialize_by(name: 'DISPLAY_MANIFEST').update!(value: true) # como na VPS
    end

    let(:otica) { YAML.safe_load(Rails.root.join('config/brands/otica.yml').read) }

    it 'shows the brand name, phone icons and manifest', :aggregate_failures do
      stub_const('MARCA', otica)
      get '/app/login'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('ÓTICA S.Un')
      expect(response.body).to include('"INSTALLATION_NAME":"ÓTICA S.Un"')
      expect(response.body).to include('href="/brand-assets/otica/apple-icon-180x180.png"')
      expect(response.body).to include('href="/brand-assets/otica/manifest.json"')
      expect(response.body).to include('href="/brand-assets/otica/favicon-32x32.png"')
      expect(response.body).to include('<meta name="apple-mobile-web-app-title" content="ÓTICA S.Un">')
      expect(response.body).not_to include('"INSTALLATION_NAME":"Chatwoot"')
    end

    it 'every icon and the manifest exist in the brand folder' do
      html_paths = %w[apple-icon-180x180.png android-icon-192x192.png ms-icon-144x144.png favicon-badge-32x32.png manifest.json]
      html_paths.each { |f| expect(Rails.public_path.join('brand-assets/otica', f)).to exist }
      manifest = JSON.parse(Rails.public_path.join('brand-assets/otica/manifest.json').read)
      expect(manifest['name']).to eq('ÓTICA S.Un')
      manifest['icons'].each { |i| expect(Rails.public_path.join(i['src'].delete_prefix('/'))).to exist }
    end
  end

  context 'without brand package (CEVICO)' do
    before do
      allow_any_instance_of(ViteRails::TagHelpers).to receive_messages(vite_client_tag: '', vite_javascript_tag: '') # rubocop:disable RSpec/AnyInstance
      InstallationConfig.find_or_initialize_by(name: 'DISPLAY_MANIFEST').update!(value: true) # como na VPS
    end

    it 'keeps the root icons and manifest' do
      get '/app/login'
      expect(response.body).to include('href="/apple-icon-180x180.png"')
      expect(response.body).to include('href="/manifest.json"')
    end
  end
end
