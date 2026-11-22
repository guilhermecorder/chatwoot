require 'rails_helper'

# 🖼️ 22/11: a moldura da prova virtual (rosto + modelos ideais + as opções numeradas)
RSpec.describe Otica::TryOnFrame do
  let(:png) { { bytes: File.binread(Rails.root.join('spec/assets/sample.png')), mime: 'image/png' } }

  it 'monta 1080×1350 com 2 opções ou com 1, com e sem marca', :aggregate_failures do
    two = described_class.compose(selfie: png, face_label: 'oval', ideais: %w[retangular quadrada], logo: png[:bytes],
                                  options: [{ image: png, title: 'Bulget BG8040M G21 preto fosco muito comprido', subtitle: 'Retangular' },
                                            { image: png, title: 'HB 93178', subtitle: 'Quadrada' }])
    one = described_class.compose(selfie: png, face_label: 'quadrado', ideais: [], options: [{ image: png, title: '100% acetato', subtitle: '' }])
    [two, one].each do |card|
      img = MiniMagick::Image.read(card[:bytes])
      expect([img.width, img.height, img.type]).to eq([1080, 1350, 'JPEG'])
    end
    expect(File).to exist(described_class::FONT)
  end
end
