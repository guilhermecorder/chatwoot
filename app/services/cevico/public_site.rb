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
