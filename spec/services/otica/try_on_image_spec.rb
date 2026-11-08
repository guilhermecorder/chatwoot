require 'rails_helper'

# 🪞 08/11: a imagem da prova virtual no Gemini (interactions → generateContent → próximo modelo)
RSpec.describe Otica::TryOnImage do
  let(:account) { create(:account) }
  let(:product) { Otica::Product.create!(account: account, kind: 'armacao', brand: 'Ray-Ban', model: 'Wayfarer', color: 'preto', list_price: 500, quantity: 1, frame_shape: 'quadrada') }
  let(:png) { Base64.strict_encode64('fake-png-bytes') }

  before { CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' }) }

  def resp(code, body)
    double('resp', success?: code == 200, code: code, parsed_response: body) # rubocop:disable RSpec/VerifiedDoubles
  end

  def generate
    described_class.new(account).generate(selfie: 'selfie', selfie_mime: 'image/jpeg', frame: 'frame', frame_mime: 'image/png', product: product)
  end

  it 'usa a Interactions API, acha a imagem dentro de steps/content e registra o gasto por imagem', :aggregate_failures do
    body = { 'status' => 'completed', 'steps' => [{ 'type' => 'model_output', 'content' => [{ 'type' => 'text', 'text' => 'ok' },
                                                                                          { 'type' => 'image', 'mime_type' => 'image/png', 'data' => png }] }],
             'usage' => { 'total_input_tokens' => 900, 'total_output_tokens' => 1290 } }
    expect(HTTParty).to receive(:post).once do |url, opts|
      expect(url).to eq(described_class::INTERACTIONS_URL)
      expect(opts[:headers]['x-goog-api-key']).to eq('AIza-teste')
      sent = JSON.parse(opts[:body])
      expect(sent['model']).to eq('gemini-nano-banana-2.1')
      expect(sent['input'].map { |p| p['type'] }).to eq(%w[image image text])
      expect(sent['input'].last['text']).to include('Ray-Ban Wayfarer, preto, quadrada shape').and include('keep the person EXACTLY')
      resp(200, body)
    end

    out = generate
    expect(out).to include(bytes: 'fake-png-bytes', mime: 'image/png', model: 'gemini-nano-banana-2.1')
    use = Crm::AiUsage.where(account: account, agent_key: 'visagismo').last
    expect(use).to have_attributes(model: 'gemini-nano-banana-2.1', input_tokens: 900, output_tokens: 1290)
    expect(use.cost_usd.to_f).to eq(0.067)
  end

  it 'sem a Interactions API cai no generateContent clássico (inlineData) do MESMO modelo', :aggregate_failures do
    calls = []
    allow(HTTParty).to receive(:post) do |url, _opts|
      calls << url
      if url == described_class::INTERACTIONS_URL
        resp(404, { 'error' => { 'message' => 'not found' } })
      else
        resp(200, { 'candidates' => [{ 'content' => { 'parts' => [{ 'inlineData' => { 'mimeType' => 'image/jpeg', 'data' => png } }] } }],
                    'usageMetadata' => { 'promptTokenCount' => 10, 'candidatesTokenCount' => 20 } })
      end
    end
    out = generate
    expect(out).to include(bytes: 'fake-png-bytes', mime: 'image/jpeg', model: 'gemini-nano-banana-2.1')
    expect(calls).to eq([described_class::INTERACTIONS_URL, format(described_class::GENERATE_URL, model: 'gemini-nano-banana-2.1')])
  end

  it 'modelo aposentado (404 nos dois caminhos) → tenta o próximo da lista; erro de verdade (429) para na hora', :aggregate_failures do
    seen = []
    allow(HTTParty).to receive(:post) do |url, opts|
      model = url == described_class::INTERACTIONS_URL ? JSON.parse(opts[:body])['model'] : url[%r{models/([^:]+):}, 1]
      seen << model
      if model == 'gemini-nano-banana-2.1'
        resp(404, { 'error' => { 'message' => 'model not found' } })
      else
        resp(200, { 'steps' => [{ 'type' => 'model_output', 'content' => [{ 'type' => 'image', 'data' => png }] }] })
      end
    end
    expect(generate[:model]).to eq('gemini-3.1-flash-image')
    expect(seen.uniq).to eq(%w[gemini-nano-banana-2.1 gemini-3.1-flash-image])

    allow(HTTParty).to receive(:post).and_return(resp(429, { 'error' => { 'message' => 'quota' } }))
    expect { generate }.to raise_error(described_class::Error, /429/)
  end

  it 'sem chave do Gemini não chama nada' do
    CrmSetting.find_by(account: account).update!(ai_config: {})
    expect(HTTParty).not_to receive(:post)
    expect { generate }.to raise_error(described_class::Error, /chave do Gemini/)
  end
end
