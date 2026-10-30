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
module Cevico::PublicSite # rubocop:disable Metrics/ModuleLength
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

  # host global OU o domínio público de alguma empresa (rodada 334)
  def official_host?(request_host)
    global_host?(request_host) || account_for_host(request_host).present?
  end

  def global_host?(request_host)
    configured? && request_host.to_s.casecmp?(host)
  end

  # host do PRÓPRIO sistema (FRONTEND_URL): onde mora o que é só da equipe,
  # com login — a Biblioteca de guias e os números dela (29/10)
  def system_host?(request_host)
    app_host.present? && request_host.to_s.casecmp?(app_host)
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
    (dedicated_host? && global_host?(request_host)) || company_root?(request_host)
  end

  # domínio de uma empresa é sempre dedicado às páginas dela (nunca o host do app)
  def company_root?(request_host)
    return false if request_host.to_s.casecmp?(app_host.to_s)

    account_for_host(request_host).present?
  end

  def base_url
    configured? ? "https://#{host}" : ENV.fetch('FRONTEND_URL', '').chomp('/')
  end

  # 📚 29/10: a Biblioteca de guias mora DENTRO do sistema (host do FRONTEND_URL), com login
  def library_url
    "#{ENV.fetch('FRONTEND_URL', '').chomp('/')}/biblioteca"
  end

  # URL pública de uma página: raiz limpa no domínio oficial,
  # /p/slug no modo antigo. Com `account:`, no domínio da EMPRESA dona da
  # página (rodada 334); sem conta, igual a sempre.
  def page_url(slug, account: nil)
    page_host = account ? host_for(account) : host
    page_host.present? ? "https://#{page_host}/#{slug}" : "#{base_url}/p/#{slug}"
  end

  # ── 🏢 EMPRESAS (rodada 334): domínio, hub e rastreio POR CONTA ──
  # Cada conta (empresa) pode ter o próprio domínio público, WhatsApp do hub
  # e Pixel/GA4 em Configurações → Identidade da empresa. Campo vazio = vale
  # a configuração geral do sistema (Configurações → Domínio), como sempre.
  COMPANY_HOST_SQL = "agenda_config -> 'company' ->> 'public_host'".freeze

  def company_for(account)
    Cevico::Company.for(account)
  end

  # domínio público desta empresa (ou o global)
  def host_for(account)
    return host if account.nil?

    company_for(account).public_host.presence || host
  end

  # a conta cuja empresa tem este domínio público; nil se nenhuma
  def account_for_host(request_host)
    wanted = normalize(request_host.to_s)
    return nil if wanted.blank?

    CrmSetting.where("lower(#{COMPANY_HOST_SQL}) = ?", wanted.downcase).order(:account_id).first&.account
  end

  # hub (WhatsApp, frase, botão) da empresa; campo vazio cai no global
  def hub_config_for(account)
    return hub_config if account.nil?

    hub_config.merge(company_for(account).hub.to_h.transform_keys(&:to_s).compact_blank)
  end

  # rastreio (Pixel, GA4) da empresa; campo vazio cai no global (GTM é só global)
  def tracking_config_for(account)
    return tracking_config if account.nil?

    own = company_for(account).tracking.to_h.transform_keys(&:to_s)
    tracking_config.merge({ 'meta_pixel_id' => own['meta_pixel_id'], 'ga4_id' => own['ga4_measurement_id'] }.compact_blank)
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

  # link do botão do hub (sem protocolo — ele entra no clique). Com `account`,
  # o WhatsApp e a frase da EMPRESA (rodada 334); a frase padrão fala o nome dela.
  def hub_whatsapp_url(account = nil)
    cfg = hub_config_for(account)
    number = cfg['whatsapp'].presence
    return nil if number.blank?

    text = cfg['cta_text'].presence || default_hub_text(account)
    "https://wa.me/#{number}?text=#{ERB::Util.url_encode(text)}"
  end

  def default_hub_text(account = nil)
    company = account && company_for(account)
    return 'Olá! Vim do site da CEVICO e quero agendar uma avaliação.' if company.nil? || company.clinic?

    "Olá! Vim do site da #{company.name} e quero mais informações."
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
      'ga4_id' => attrs['ga4_id'].to_s.strip.upcase.gsub(/[^A-Z0-9-]/, '')[0, 20],
      'gtm_id' => attrs['gtm_id'].to_s.strip.upcase.gsub(/[^A-Z0-9-]/, '')[0, 20],
      # 🔥 21/10: Microsoft Clarity (mapa de calor + gravações, grátis) — ID do projeto
      'clarity_id' => attrs['clarity_id'].to_s.strip.downcase.gsub(/[^a-z0-9]/, '')[0, 20]
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
