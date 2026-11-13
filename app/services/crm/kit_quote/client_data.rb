# 📋 O que a ficha do cliente (Crm::ClientSummary) já tem para montar o orçamento sozinho — mesma leitura do
# botão "Preencher com os dados do cliente" do Gerador (proposalBuilder.js prefillFromSummary + roofFromText).
#   Crm::KitQuote::ClientData.new(contact).call
#     → { 'hoje' => 495.3, 'kwh' => 371, 'aumento' => 'vai pôr 2 ar', 'cidade' => 'Piracicaba', 'telhado' => 'ceramica' }
class Crm::KitQuote::ClientData
  ROOF_WORDS = [
    ['laje', /laje/i],
    ['metalica', /met[aá]l|zinco|galvan|sandu[ií]che/i],
    ['fibrocimento_madeira', /fibro|eternit|brasilit|amianto/i],
    ['ceramica', /cer[aâ]m|barro|colonial|romana|americana|portuguesa/i]
  ].freeze
  # "não vai aumentar", "nada", "não" no campo do aumento = sem aumento
  NO_INCREASE = /\A\W*(n[aã]o|nada|nenhum|sem\b|mesmo consumo)/i

  def initialize(contact)
    @contact = contact
  end

  def call
    {
      'hoje' => money(field('conta')),
      'kwh' => kwh,
      'aumento' => increase,
      'cidade' => field('cidade').to_s.split(%r{[/,-]}).first.to_s.strip,
      'telhado' => self.class.roof_from_text(field('telhado'))
    }
  end

  def self.roof_from_text(text)
    ROOF_WORDS.find { |_key, pattern| text.to_s.match?(pattern) }&.first
  end

  private

  def saved
    @saved ||= (@contact&.additional_attributes || {})[Crm::ClientSummary::ATTR_KEY].to_h
  end

  def field(key)
    saved.dig(key, 'valor').to_s.presence
  end

  # 1º valor em reais escrito ("R$ 495,30 (foto da conta)" → 495.3; "R$130 a R$150" → 130, como na tela)
  def money(text)
    found = text.to_s.match(/R\$\s*([\d.]+(?:,\d{1,2})?)/)
    found ? found[1].delete('.').tr(',', '.').to_f : 0.0
  end

  def kwh
    found = "#{field('consumo_medio')} #{field('conta')}".match(/([\d.]+)\s*kwh/i)
    found ? found[1].delete('.').to_i : 0
  end

  def increase
    text = field('consumo_futuro').to_s.strip
    text.blank? || text.match?(NO_INCREASE) ? nil : text
  end
end
