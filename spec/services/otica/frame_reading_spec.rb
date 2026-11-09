require 'rails_helper'

# 🪞 08/11 (noite): o Gemini lê a foto da armação → formato, público, cor e dica de visagismo
RSpec.describe Otica::FrameReading do
  let(:account) { create(:account) }

  before do
    CrmSetting.create!(account: account, ai_config: { 'gemini_api_key' => 'AIza-teste' })
  end

  def armacao(name, shape: '', fit: '', photo: true, kind: 'armacao')
    p = Otica::Product.create!(account: account, kind: kind, name: name, frame_shape: shape, frame_fit: fit, list_price: 300, quantity: 1)
    p.photo.attach(io: File.open(Rails.root.join('spec/assets/sample.png')), filename: 'a.png', content_type: 'image/png') if photo
    p
  end

  def gemini_says(json)
    response = instance_double(HTTParty::Response, success?: true, code: 200,
                                                   parsed_response: { 'candidates' => [{ 'content' => { 'parts' => [{ 'text' => json }] } }] })
    allow(Crm::GeminiModels).to receive(:post).and_return([response, 'gemini-x'])
  end

  it 'preenche o que está vazio, normaliza os valores e não sobrescreve sem force', :aggregate_failures do
    gemini_says('```json {"armacao": true, "formato": "Gatinho", "publico": "Feminino", "cor": "vinho", "material": "Acetato", ' \
                '"frase": "Levanta o olhar."} ```')
    p = armacao('Roma 123')
    out = described_class.read!(p)
    expect(out).to include('formato' => 'gatinho', 'publico' => 'feminina', 'cor' => 'vinho', 'material' => 'acetato')
    expect(out['gravado']).to match_array(%w[frame_shape frame_fit visagismo_notes color])
    expect(p.reload).to have_attributes(frame_shape: 'gatinho', frame_fit: 'feminina', color: 'vinho', visagismo_notes: 'Levanta o olhar.')

    gemini_says('{"armacao": true, "formato": "redonda", "publico": "unissex", "frase": "x"}')
    described_class.read!(p)
    expect(p.reload.frame_shape).to eq('gatinho') # sem force, o que já estava fica
    described_class.read!(p, force: true)
    expect(p.reload).to have_attributes(frame_shape: 'redonda', frame_fit: 'unissex', visagismo_notes: 'x')

    gemini_says('{"armacao": true, "formato": "marciana"}')
    expect(described_class.read!(armacao('Estranha'))['formato']).to eq('') # formato desconhecido não entra
  end

  it 'recusa sem foto, fora de armação/solar, sem chave e quando a foto não é uma armação', :aggregate_failures do
    expect { described_class.read!(armacao('Sem foto', photo: false)) }.to raise_error(described_class::Error, /não tem foto/)
    expect { described_class.read!(armacao('Lente', kind: 'lente')) }.to raise_error(described_class::Error, /não é armação/)
    gemini_says('{"armacao": false}')
    expect { described_class.read!(armacao('Caneca')) }.to raise_error(described_class::Error, /não parece ser de uma armação/)
    CrmSetting.find_by(account: account).update!(ai_config: {})
    expect { described_class.read!(armacao('Sem chave')) }.to raise_error(described_class::Error, /chave do Gemini/)
  end

  it 'lê todas as armações com foto e sem formato, contando as que faltam e os erros', :aggregate_failures do
    gemini_says('{"armacao": true, "formato": "aviador", "publico": "masculina"}')
    a = armacao('A')
    b = armacao('B')
    armacao('Já tem', shape: 'oval')
    armacao('Sem foto', photo: false)
    expect(described_class.missing_count(account)).to eq(2)
    done, errors = described_class.read_missing!(account)
    expect([done, errors]).to eq([2, []])
    expect([a.reload.frame_shape, b.reload.frame_shape]).to eq(%w[aviador aviador])
    expect(described_class.missing_count(account)).to eq(0)
  end
end
