# CEVICO — domínio público OFICIAL das páginas e formulários (pedido 16/07).
#
# O domínio é configurado pelo admin em Configurações → Domínio (fica no
# banco, InstallationConfig CEVICO_PUBLIC_HOST, com cache do GlobalConfig);
# a env CEVICO_PUBLIC_HOST continua valendo como fallback.
#
# Dois modos, decididos sozinhos pelo host configurado:
# - Domínio DEDICADO (ex.: conteudo.cevico.com.br, diferente do host do
#   sistema): páginas respondem na RAIZ (ex.: /preoperatorio) e a raiz "/"
#   vira o índice das páginas publicadas.
# - MESMO domínio do sistema (ex.: sistema.cevico.com.br no FRONTEND_URL):
#   o app continua dono da raiz e do /app; as páginas respondem em
#   /nome-da-pagina (rota fica no fim, nunca atropela rota real).
# Nos dois modos: /p/slug e links antigos de formulário redirecionam 301
# pro endereço oficial, e canonical/og:url apontam sempre pra ele.
#
# Sem host configurado, nada muda: tudo continua no FRONTEND_URL (/p/slug).
module Cevico::PublicSite
  module_function

  def host
    db_host = begin
      GlobalConfig.get('CEVICO_PUBLIC_HOST')['CEVICO_PUBLIC_HOST']
    rescue StandardError
      nil
    end
    normalize(db_host.presence || ENV['CEVICO_PUBLIC_HOST'].presence)
  end

  def normalize(raw)
    raw&.strip
       &.sub(%r{\Ahttps?://}, '')
       &.chomp('/')
       .presence
  end

  def configured?
    host.present?
  end

  def official_host?(request_host)
    configured? && request_host.to_s.casecmp?(host)
  end

  # host do sistema (FRONTEND_URL) — para saber se o domínio público é
  # dedicado ou o mesmo do app
  def app_host
    URI.parse(ENV.fetch('FRONTEND_URL', '')).host
  rescue StandardError
    nil
  end

  def dedicated_host?
    configured? && !host.casecmp?(app_host.to_s)
  end

  # a raiz "/" só vira índice de páginas em domínio DEDICADO — no domínio
  # do próprio sistema a raiz continua sendo o app (login)
  def public_root?(request_host)
    dedicated_host? && official_host?(request_host)
  end

  def base_url
    configured? ? "https://#{host}" : ENV.fetch('FRONTEND_URL', '').chomp('/')
  end

  # URL pública de uma página: raiz limpa no domínio oficial,
  # /p/slug no modo antigo.
  def page_url(slug)
    configured? ? "#{base_url}/#{slug}" : "#{base_url}/p/#{slug}"
  end

  # ── HUB (porta de entrada na raiz do domínio dedicado) ──
  # Config do admin em Configurações → Domínio: WhatsApp do atendimento,
  # frase de boas-vindas e texto da mensagem. Fica no banco
  # (InstallationConfig CEVICO_HUB), igual ao host.
  def hub_config
    raw = begin
      GlobalConfig.get('CEVICO_HUB')['CEVICO_HUB']
    rescue StandardError
      nil
    end
    raw.is_a?(Hash) ? raw : {}
  end

  def save_hub!(attrs)
    value = {
      'whatsapp' => attrs['whatsapp'].to_s.gsub(/\D/, '')[0, 15],
      'tagline' => attrs['tagline'].to_s.strip[0, 300],
      'cta_text' => attrs['cta_text'].to_s.strip[0, 300]
    }.compact_blank
    config = InstallationConfig.where(name: 'CEVICO_HUB').first_or_initialize
    config.value = value
    config.save!
    GlobalConfig.clear_cache
    value
  end

  # link do botão do hub (sem protocolo — ele entra no clique)
  def hub_whatsapp_url
    number = hub_config['whatsapp'].presence
    return nil if number.blank?

    text = hub_config['cta_text'].presence || 'Olá! Vim do site da CEVICO e quero agendar uma avaliação.'
    "https://wa.me/#{number}?text=#{ERB::Util.url_encode(text)}"
  end

  # ── 📊 RASTREAMENTO central (item 117) ──
  # Pixel da Meta + GA4 configurados UMA vez em Configurações → Domínio e
  # injetados sozinhos em TODA página publicada (e no hub). A página viaja
  # dentro do evento (content_name) — um pixel só, cada página identificada.
  def tracking_config
    raw = begin
      GlobalConfig.get('CEVICO_TRACKING')['CEVICO_TRACKING']
    rescue StandardError
      nil
    end
    raw.is_a?(Hash) ? raw : {}
  end

  def save_tracking!(attrs)
    value = {
      'meta_pixel_id' => attrs['meta_pixel_id'].to_s.gsub(/\D/, '')[0, 20],
      'ga4_id' => attrs['ga4_id'].to_s.strip.upcase.gsub(/[^A-Z0-9-]/, '')[0, 20]
    }.compact_blank
    config = InstallationConfig.where(name: 'CEVICO_TRACKING').first_or_initialize
    config.value = value
    config.save!
    GlobalConfig.clear_cache
    value
  end

  # grava o host no banco (Configurações → Domínio); string vazia limpa
  def save_host!(raw)
    value = normalize(raw)
    config = InstallationConfig.where(name: 'CEVICO_PUBLIC_HOST').first_or_initialize
    config.value = value.to_s
    config.save!
    GlobalConfig.clear_cache
    value
  end
end
