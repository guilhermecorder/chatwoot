require 'rails_helper'

# 🎨 Personalização por conta (28/10): frases, nomes dos ambientes, dicionário
# global, identidade visual e imagens da EMPRESA — tudo em cima da Identidade
# da empresa (rodada 334). Regra de ouro: conta sem nada salvo = clínica de
# sempre (dicionário desligado, sem frase/nome próprios, sem imagem).
RSpec.describe Cevico::Company do
  let(:account) { create(:account) }

  describe 'conta sem configuração' do
    subject(:company) { described_class.for(account) }

    it 'não muda nada: dicionário desligado, sem frases, nomes ou imagens', :aggregate_failures do
      expect(company.dictionary_enabled?).to be(false)
      expect(company.dictionary_pairs).to eq([])
      expect(company.phrases).to eq({})
      expect(company.labels).to eq({})
      expect(company.label(:Inicio, 'Meu Painel')).to eq('Meu Painel')
      expect(company.visual['watermark']).to be(true)
      expect(company.images.values).to all(be_nil)
    end

    it 'resolve frase pelo segmento da instalação quando a conta não tem a sua' do
      expect(company.phrase(:novo_atendimento, 'Nova consulta')).to eq(Segmento.frase(:novo_atendimento, 'Nova consulta'))
    end
  end

  describe '.save! com personalização' do
    it 'grava frases, nomes, dicionário e visual, descartando o que está vazio ou inválido', :aggregate_failures do
      described_class.save!(account, {
        'name' => 'LIFE', 'segment' => 'outro',
        'phrases' => { 'inicio.consultas_hoje' => ' Vistorias de hoje ', 'vazia' => '', 'chave inválida!' => 'x' },
        'labels' => { 'Agenda' => 'Vistorias', 'Doctors Dashboard' => '' },
        'dictionary' => { 'enabled' => 'true', 'pairs' => [{ 'de' => 'consulta', 'para' => 'vistoria' }, { 'de' => 'igual', 'para' => 'Igual' }, { 'de' => '', 'para' => 'x' }] },
        'visual' => { 'system_name' => 'Sistema LIFE', 'palette' => 'tangerine', 'watermark' => 'false', 'accent' => '#D2990B' }
      })
      company = described_class.for(account)

      expect(company.phrases).to eq('inicio.consultas_hoje' => 'Vistorias de hoje')
      expect(company.phrase('inicio.consultas_hoje', 'Consultas hoje')).to eq('Vistorias de hoje')
      expect(company.labels).to eq('Agenda' => 'Vistorias')
      expect(company.label('Agenda', 'Agenda')).to eq('Vistorias')
      expect(company.label('Doctors Dashboard', 'Dashboard dos Médicos')).to eq('Dashboard dos Médicos')
      expect(company.dictionary_enabled?).to be(true)
      expect(company.dictionary_pairs).to eq([{ 'de' => 'consulta', 'para' => 'vistoria' }])
      expect(company.visual).to eq('system_name' => 'Sistema LIFE', 'palette' => 'tangerine', 'watermark' => false, 'accent' => '#D2990B')
      expect(company.to_h[:dictionary]['explicit']).to be(true)
    end

    it 'fora da clínica o dicionário nasce ligado com os pares do vocabulário; na clínica, desligado', :aggregate_failures do
      described_class.save!(account, { 'name' => 'Ótica X', 'segment' => 'otica' })
      otica = described_class.for(account)
      expect(otica.dictionary_enabled?).to be(true)
      expect(otica.dictionary_pairs).to include({ 'de' => 'paciente', 'para' => 'cliente' }, { 'de' => 'consultas', 'para' => 'atendimentos' })
      expect(otica.to_h[:dictionary]['explicit']).to be(false)

      described_class.save!(account, { 'segment' => 'clinica' })
      clinica = described_class.for(account)
      expect(clinica.dictionary_enabled?).to be(false)
      expect(clinica.dictionary_pairs).to eq([]) # nenhuma palavra muda na clínica
    end

    it 'a decisão explícita vence o automático' do
      described_class.save!(account, { 'segment' => 'otica', 'dictionary' => { 'enabled' => false } })
      expect(described_class.for(account).dictionary_enabled?).to be(false)
    end
  end

  describe '.save_image!' do
    let(:png) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

    it 'anexa e remove a imagem do cabeçalho da conta', :aggregate_failures do
      company = described_class.save_image!(account, 'hero', file: png)
      expect(company.images['hero']).to start_with('/rails/active_storage/')
      expect(CrmSetting.find_by!(account: account).brand_hero).to be_attached

      company = described_class.save_image!(account, 'hero', remove: true)
      expect(company.images['hero']).to be_nil
    end

    it 'recusa tipo desconhecido e arquivo que não é imagem', :aggregate_failures do
      expect { described_class.save_image!(account, 'banner', file: png) }.to raise_error(ArgumentError)
      texto = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/contacts.csv'), 'text/csv')
      expect { described_class.save_image!(account, 'logo', file: texto) }.to raise_error(ArgumentError, /imagens/)
    end
  end
end
