require 'rails_helper'

# 👇 11/11/2026: foto olhando pra baixo não serve para a prova virtual
RSpec.describe Otica::FaceReading do
  let(:rosto) do
    described_class.normalize('pessoas' => 1, 'frontal' => true, 'angulo' => 'frente', 'olhar' => 'camera', 'formato' => 'oval',
                              'usa_oculos' => false, 'adulto' => true, 'qualidade' => 'ok', 'observacao' => '')
  end

  it 'aceita a foto de frente e a de 3/4 olhando para a câmera' do
    expect(described_class.usable(rosto)).to eq([true, nil])
    expect(described_class.usable(rosto.merge('angulo' => 'tres_quartos'))).to eq([true, nil])
  end

  it 'recusa a foto olhando pra baixo e diz como tirar outra' do
    ok, motivo = described_class.usable(rosto.merge('olhar' => 'baixo'))
    expect(ok).to be(false)
    expect(motivo).to include('olhando pra baixo').and include('altura dos olhos').and include('exemplo')
    expect(described_class.summary(rosto.merge('olhar' => 'baixo'))).to include('olhando pra baixo')
  end

  it 'não recusa leitura antiga (sem o campo) nem valor desconhecido' do
    sem_campo = { 'pessoas' => 1, 'frontal' => true, 'angulo' => 'frente', 'formato' => 'oval', 'adulto' => true, 'qualidade' => 'ok' }
    antiga = described_class.normalize(sem_campo)
    expect(antiga['olhar']).to eq('camera')
    expect(described_class.usable(antiga).first).to be(true)
    expect(described_class.normalize('olhar' => 'Câmera')['olhar']).to eq('camera')
    expect(described_class.normalize('olhar' => 'qualquer coisa')['olhar']).to eq('camera')
    expect(described_class.usable(sem_campo).first).to be(true)
  end

  it 'pede o olhar no prompt da leitura da imagem' do
    expect(described_class::IMAGE_PROMPT).to include('"olhar"').and include('"baixo"')
  end
end
