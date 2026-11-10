# 🧭 DE ONDE VEIO A CONVERSA (10/11/2026 · LIFE, pedido do Guilherme): na
# PRIMEIRA mensagem do cliente numa conversa do WhatsApp, o sistema diz de onde
# ele veio e deixa isso à vista na lista de conversas:
#   · origem-anuncio     → clicou num anúncio da Meta (o CTWA já carimbou meta_ads);
#   · origem-formulario  → é o lead do formulário instantâneo (a boas-vindas abriu a conversa);
#   · origem-site        → chegou com a MENSAGEM PRONTA de uma página do site
#                          (cada página tem a sua pergunta, ex.: "Oi! Quantas placas eu preciso?");
#   · origem-direto      → escreveu do jeito dele (indicação, Google sem página, Instagram…).
# A página vai numa nota da conversa ("🧭 Chegou pelo site: …") e em
# additional_attributes['origem_whatsapp']; o contato ganha o carimbo
# canal_origem (Crm::LeadChannel) quando ainda não tem nenhum — PRIMEIRO TOQUE.
#
# Só liga na conta que tem a lista das páginas em ai_config['origens_site']:
#   [{ 'pagina' => 'placa-solar-piracicaba', 'canal' => 'google_busca',
#      'frases' => ['Quanto eu economizo na minha conta de luz?',
#                   'Minha conta de luz é de uns R$ * Quanto eu economizo?'] }]
# A frase vale se aparecer dentro da mensagem (sem acento, sem pontuação, sem
# "Oi"); "*" é "qualquer coisa no meio" (o valor da calculadora). Duas páginas
# batendo → vence a frase mais comprida (a mais específica).
class Crm::WhatsappOrigin
  ATTR = 'origem_whatsapp'.freeze
  LABELS = { 'anuncio' => 'origem-anuncio', 'formulario' => 'origem-formulario',
             'site' => 'origem-site', 'direto' => 'origem-direto' }.freeze
  MAX_PAGES = 80
  MAX_PHRASES = 6
  GREETING = /\A(?:oi+|ola|opa|bom dia|boa tarde|boa noite)\b\s*/

  def self.pages(account)
    raw = Array(CrmSetting.find_by(account: account)&.ai_config&.dig('origens_site')).first(MAX_PAGES)
    raw.filter_map { |entry| normalize_page(entry.to_h.transform_keys(&:to_s)) }
  end

  def self.normalize_page(entry)
    pagina = entry['pagina'].to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '')[0, 80]
    frases = Array(entry['frases']).first(MAX_PHRASES).map { |f| f.to_s.strip[0, 300] }.compact_blank
    return if pagina.blank? || frases.empty?

    { 'pagina' => pagina, 'canal' => (entry['canal'].to_s if Crm::LeadChannel.valid?(entry['canal'])), 'frases' => frases }
  end

  # texto comparável: minúsculo, sem acento, só letras/números, sem saudação no começo
  def self.normalize(text)
    plain = I18n.transliterate(text.to_s.downcase, replacement: '')
    plain.gsub(/[^a-z0-9*]+/, ' ').squeeze(' ').strip.sub(GREETING, '').strip
  end

  # { 'pagina', 'canal', 'frase' } da página cuja frase está na mensagem (a mais comprida vence)
  def self.match_page(account, text)
    msg = normalize(text).delete('*')
    return if msg.blank?

    hits = pages(account).flat_map do |page|
      page['frases'].filter_map do |frase|
        tamanho = phrase_size_in(msg, frase)
        page.merge('frase' => frase, 'tamanho' => tamanho) if tamanho
      end
    end
    hits.max_by { |h| h['tamanho'] }&.except('tamanho')
  end

  # tamanho da frase (sem o "*") quando ela está na mensagem; nil quando não está
  def self.phrase_size_in(msg, frase)
    partes = normalize(frase).split('*').map(&:strip).compact_blank
    return if partes.empty?

    re = Regexp.new(partes.map { |p| "\\b#{Regexp.escape(p)}\\b" }.join('.*'))
    partes.sum(&:length) if re.match?(msg)
  end

  # historico: true = conversa antiga (script de carga): a 1ª mensagem do cliente
  # já ficou para trás, então não confere a contagem
  def initialize(conversation:, text:, historico: false)
    @historico = historico
    @conversation = conversation
    @account = conversation&.account
    @contact = conversation&.contact
    @text = text.to_s
  end

  # devolve o tipo gravado ('site', 'anuncio'…) ou nil quando não é a hora/conta
  def call
    return unless first_message?

    origem = detect
    stamp!(origem)
    origem['tipo']
  rescue StandardError => e
    Rails.logger.error "[Crm::WhatsappOrigin] conversa #{@conversation&.id}: #{e.class}: #{e.message}"
    nil
  end

  private

  # conta com a lista das páginas, conversa ainda sem origem e esta é a 1ª mensagem do cliente
  def first_message?
    return false if @conversation.nil? || self.class.pages(@account).empty?
    return false if (@conversation.reload.additional_attributes || {})[ATTR].present?

    @historico || @conversation.messages.incoming.count <= 1
  end

  def detect
    attrs = @conversation.additional_attributes || {}
    return { 'tipo' => 'anuncio', 'anuncio' => attrs.dig('meta_ads', 'headline').to_s[0, 120].presence } if attrs['meta_ads'].present?
    return { 'tipo' => 'formulario' } if attrs['meta_lead_id'].present?

    page = self.class.match_page(@account, @text)
    return { 'tipo' => 'direto' } if page.nil?

    { 'tipo' => 'site', 'pagina' => page['pagina'], 'canal' => page['canal'] }
  end

  def stamp!(origem)
    dados = origem.compact.merge('em' => Time.current.iso8601)
    Cevico::AttributeMerge.merge!(@conversation) { |a| a[ATTR].present? ? a : a.merge(ATTR => dados) }
    label = LABELS.fetch(origem['tipo'])
    @account.labels.find_or_create_by!(title: label)
    @conversation.add_labels([label])
    note!(origem)
    stamp_contact!(origem) if origem['tipo'] == 'site' && origem['canal'].present?
  end

  def note!(origem)
    texto = case origem['tipo']
            when 'site' then "🧭 Chegou pelo site: página #{origem['pagina']} (mensagem pronta da página)."
            when 'anuncio' then "🧭 Chegou por anúncio da Meta#{origem['anuncio'] ? ": #{origem['anuncio']}" : ''}."
            when 'formulario' then '🧭 Chegou pelo formulário do Meta.'
            else '🧭 Escreveu direto (sem anúncio e sem mensagem pronta de página).'
            end
    @conversation.messages.create!(account_id: @account.id, inbox_id: @conversation.inbox_id,
                                   message_type: :activity, private: true, content: texto)
  rescue StandardError => e
    Rails.logger.warn "[Crm::WhatsappOrigin] nota: #{e.message}"
  end

  # carimbo "como chegou" do contato, só se ninguém (automático ou equipe) carimbou antes
  def stamp_contact!(origem)
    return if @contact.nil? || Crm::LeadChannel.key_of(@contact).present?

    Cevico::AttributeMerge.merge!(@contact) do |a|
      next a if a[Crm::LeadChannel::ATTR].is_a?(Hash) && a[Crm::LeadChannel::ATTR]['key'].present?

      a.merge(Crm::LeadChannel::ATTR => { 'key' => origem['canal'], 'por' => "Site (página #{origem['pagina']})",
                                          'em' => Time.current.iso8601 })
    end
  end
end
