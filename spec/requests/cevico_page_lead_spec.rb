require 'rails_helper'

# 02/11: lead que a página Pré-análise manda ANTES do WhatsApp (nome +
# telefone + respostas) — o paciente nasce no sistema com o carimbo da página
RSpec.describe 'CEVICO lead da página (POST /p/:slug/lead)', type: :request do
  let(:account) { create(:account) }
  let!(:page) do
    CevicoPage.create!(account: account, title: 'Pré-análise refrativa', slug: 'cirurgia-refrativa-posso-fazer', status: 'published',
                       category: 'captacao', custom_html: '<html><body><a href="https://wa.me/5511960593996">WhatsApp</a></body></html>',
                       daily_stats: {}, sections: [], team_comments: [])
  end
  let(:body) do
    { nome: 'Ana Teste', telefone: '(11) 99999-0000',
      respostas: { corrigir: 'Miopia', grau: 'De 3 a 6', idade: '26 a 40', estavel: 'Não, está estável' },
      origem: { utm_source: 'google', utm_medium: 'cpc', gclid: 'abc123' }, url: 'https://clinica.cevico.com.br/cirurgia-refrativa-posso-fazer' }
  end

  it 'cria o paciente novo com as respostas, o carimbo da página e devolve o Protocolo', :aggregate_failures do
    expect { post "/p/#{page.slug}/lead", params: body, as: :json }.to change(Contact, :count).by(1)

    expect(response).to have_http_status(:ok)
    token = response.parsed_body['token']
    expect(token).to be_present
    expect(response.parsed_body['line']).to eq("Protocolo: #{token}")

    contact = Contact.last
    expect(contact.name).to eq('Ana Teste')
    expect(contact.phone_number).to eq('+5511999990000')
    attrs = contact.reload.additional_attributes
    expect(attrs.dig('pre_analise', 'respostas')).to include('corrigir' => 'Miopia', 'grau' => 'De 3 a 6')
    expect(attrs.dig('page_ads', 'slug')).to eq(page.slug)
    expect(attrs.dig('page_ads', 'source')).to eq('google_ads')
    expect(attrs.dig('page_ads', 'token')).to eq(token)
    expect(attrs.dig('page_ads', 'via')).to eq('pagina_lead')
    expect(CevicoPageRef.find_by(token: token).contact_id).to eq(contact.id)
    expect(page.reload.daily_stats.dig(Date.current.iso8601, 'cta')).to eq(1)
  end

  it 'telefone de cadastro existente: não muda o nome nem cria outro paciente', :aggregate_failures do
    existing = account.contacts.create!(name: 'Maria Original', phone_number: '+5511999990000')

    expect { post "/p/#{page.slug}/lead", params: body, as: :json }.not_to change(Contact, :count)

    expect(response).to have_http_status(:ok)
    expect(existing.reload.name).to eq('Maria Original')
    expect(existing.additional_attributes.dig('pre_analise', 'nome_informado')).to eq('Ana Teste')
    expect(existing.additional_attributes['cevico_page_lead_pending']).to be_nil
  end

  it 'primeiro toque vence: quem já tem page_ads não é recarimbado' do
    existing = account.contacts.create!(name: 'Maria', phone_number: '+5511999990000',
                                        additional_attributes: { 'page_ads' => { 'slug' => 'refrativa', 'source' => 'meta_ads' } })

    post "/p/#{page.slug}/lead", params: body, as: :json

    expect(existing.reload.additional_attributes.dig('page_ads', 'slug')).to eq('refrativa')
  end

  it 'nome curto ou telefone inválido = 422 com erro de identidade' do
    post "/p/#{page.slug}/lead", params: body.merge(telefone: '123'), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('ok' => false, 'error' => 'identity')
  end

  it 'página não publicada = 404' do
    page.update!(status: 'draft')

    post "/p/#{page.slug}/lead", params: body, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
