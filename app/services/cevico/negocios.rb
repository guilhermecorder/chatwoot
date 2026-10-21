# 🏢 MEUS NEGÓCIOS (21/10/2026) — o lançador do dono.
#
# Uma tela só do Guilherme com os ícones das empresas dele (CEVICO, LIFE,
# Sua Ótica…); clicar = entrar no sistema daquela empresa já logado, pela
# API de plataforma do Chatwoot (link de uso único, 5 minutos). Cada sistema
# continua na sua VPS, com seu banco: aqui só se guarda o endereço e o token
# que gera o login. Nada de dado de negócio passa por esta instalação.
#
# Configuração pelo AMBIENTE (nunca no código):
#   MEUS_NEGOCIOS_DONOS  e-mails separados por vírgula — só eles veem a tela
#   MEUS_NEGOCIOS        JSON (uma linha) com a lista de negócios:
#     [{"chave":"cevico","nome":"CEVICO","descricao":"clínica · São Paulo",
#       "logo":"https://…/brand-assets/logo_thumbnail.png","cor":"#152C61",
#       "url":"https://sistema.cevico.com.br","user_id":1,"account_id":1,
#       "token":"<token do app de plataforma criado lá>"},
#      {"chave":"life","nome":"LIFE Energia Solar","local":true,"account_id":1}]
#   `local: true` = este mesmo sistema (abre direto, sem SSO).
#   O token nasce no sistema de destino com:
#     bundle exec rake "cevico:negocios:autorizar[email@do.dono]"
module Cevico
  class Negocios
    class Erro < StandardError; end

    TIMEOUT = 15

    class << self
      def ativo?
        donos.any? && lista.any?
      end

      # dono = e-mail listado; sem lista, no sistema pessoal (marca hub) todo
      # administrador é dono (é o sistema do Guilherme) — nas outras marcas
      # a tela só existe com MEUS_NEGOCIOS_DONOS preenchido
      def dono?(user)
        return false if user.nil?
        return hub? if donos.empty?

        donos.include?(user.email.to_s.strip.downcase)
      end

      def hub?
        defined?(MARCA) && MARCA['id'] == 'hub'
      end

      # sem MEUS_NEGOCIOS no ambiente, o HUB já mostra os 3 negócios dele:
      # a LIFE é este sistema; CEVICO e Sua Ótica ficam "a configurar"
      # (sem endereço/token ainda) até o ambiente ser preenchido
      PADRAO_HUB = [
        { 'chave' => 'cevico', 'nome' => 'CEVICO', 'descricao' => 'clínica · São Paulo',
          'logo' => '/brand-assets/logo_thumbnail.png', 'cor' => '#152C61', 'pendente' => true },
        { 'chave' => 'life', 'nome' => 'LIFE Energia Solar', 'descricao' => 'energia solar · Piracicaba',
          'logo' => '/brand-assets/life/logo_thumbnail.png', 'cor' => '#D2990B', 'local' => true },
        { 'chave' => 'sua-otica', 'nome' => 'Sua Ótica', 'descricao' => 'óticas · São Paulo',
          'cor' => '#0A84FF', 'pendente' => true }
      ].freeze

      def donos
        ENV.fetch('MEUS_NEGOCIOS_DONOS', '').split(/[,\s;]+/).map { |e| e.strip.downcase }.compact_blank
      end

      # lista completa (com token) — só para uso interno
      def lista
        raw = ENV.fetch('MEUS_NEGOCIOS', '').strip
        return (hub? ? PADRAO_HUB.map { |n| normaliza(n) } : []) if raw.blank?

        itens = JSON.parse(raw)
        return [] unless itens.is_a?(Array)

        itens.filter_map { |item| normaliza(item) }
      rescue JSON::ParserError => e
        Rails.logger.warn("[negocios] MEUS_NEGOCIOS inválido: #{e.message}")
        []
      end

      # o que a tela recebe: nunca o token
      def publicos
        lista.map { |n| n.except('token', 'user_id') }
      end

      def encontrar(chave)
        lista.find { |n| n['chave'] == chave.to_s }
      end

      # link de entrada no sistema do negócio (uso único, expira em 5 min)
      def link_de_entrada(chave, account: nil)
        negocio = encontrar(chave)
        raise Erro, 'negócio não configurado' if negocio.nil?
        raise Erro, "#{negocio['nome']} ainda não está ligado: preencha MEUS_NEGOCIOS (docs/MEUS_NEGOCIOS.md)" if negocio['pendente']

        return link_local(negocio, account) if negocio['local']

        url = "#{negocio['url']}/platform/api/v1/users/#{negocio['user_id']}/login"
        response = HTTParty.get(url, headers: { 'api_access_token' => negocio['token'].to_s }, timeout: TIMEOUT)
        raise Erro, "o sistema #{negocio['nome']} respondeu #{response.code}" unless response.success?

        link = response.parsed_response.is_a?(Hash) ? response.parsed_response['url'] : nil
        raise Erro, "o sistema #{negocio['nome']} não devolveu o link" if link.blank?

        negocio['account_id'].present? ? "#{link}&sso_account_id=#{negocio['account_id']}" : link
      rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, HTTParty::Error => e
        raise Erro, "não consegui falar com #{negocio['nome']}: #{e.class}"
      end

      private

      def link_local(negocio, account)
        account_id = negocio['account_id'].presence || account&.id
        "/app/accounts/#{account_id}/inicio"
      end

      def normaliza(item)
        return nil unless item.is_a?(Hash)

        chave = item['chave'].to_s.strip.downcase
        return nil if chave.blank?

        local = item['local'] == true
        pendente = item['pendente'] == true
        return nil if !local && !pendente && (item['url'].blank? || item['token'].blank? || item['user_id'].blank?)

        {
          'chave' => chave,
          'nome' => item['nome'].presence || chave.upcase,
          'descricao' => item['descricao'].to_s,
          'logo' => item['logo'].to_s,
          'cor' => item['cor'].presence || '#152C61',
          'local' => local,
          'pendente' => pendente,
          'url' => item['url'].to_s.delete_suffix('/'),
          'user_id' => item['user_id'],
          'account_id' => item['account_id'],
          'token' => item['token'].to_s
        }
      end
    end
  end
end
