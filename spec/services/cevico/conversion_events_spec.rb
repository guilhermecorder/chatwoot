require 'rails_helper'

# Item 313: lista fechada dos eventos de conversão + nome que o GA4 aceita
RSpec.describe Cevico::ConversionEvents do
  describe '.ga4_name' do
    it 'keeps a valid name untouched (não muda evento já cadastrado no Google)' do
      expect(described_class.ga4_name('generate_lead')).to eq('generate_lead')
      expect(described_class.ga4_name('Refrativa_PRK')).to eq('Refrativa_PRK')
    end

    it 'fixes names the GA4 would silently drop' do
      expect(described_class.ga4_name('Refrativa PRK')).to eq('Refrativa_PRK')
      expect(described_class.ga4_name('agendou-consulta')).to eq('agendou_consulta')
      expect(described_class.ga4_name('  cirurgia fácica ')).to eq('cirurgia_facica')
      expect(described_class.ga4_name('1a consulta')).to eq('a_consulta')
    end

    it 'cuts at 40 characters and escapes reserved prefixes' do
      expect(described_class.ga4_name('a' * 60).length).to eq(40)
      expect(described_class.ga4_name('google_lead')).to eq('ev_google_lead')
    end

    it 'returns nil when nothing usable is left' do
      expect(described_class.ga4_name('')).to be_nil
      expect(described_class.ga4_name('123 !!')).to be_nil
    end
  end

  it 'has only GA4-valid names in the closed list' do
    expect(described_class::GA4_EVENTS.keys).to all(satisfy { |n| described_class.ga4_valid?(n) })
  end

  it 'translates site events to the messaging list of Meta' do
    expect(described_class.meta_messaging_name('Lead')).to eq('LeadSubmitted')
    expect(described_class.meta_messaging_name('Schedule')).to eq('QualifiedLead')
    expect(described_class.meta_messaging_name('Purchase')).to eq('Purchase')
    expect(described_class::META_MESSAGING.values - described_class::META_MESSAGING_ALLOWED).to be_empty
  end
end
