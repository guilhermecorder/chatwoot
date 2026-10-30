# 🔐 29/10: login do SISTEMA para telas em HTML fora do painel Vue — a
# Biblioteca de guias e os números dela. O painel guarda o token de acesso
# no cookie cw_d_session_info (dashboard/store/utils/api.js); aqui ele é lido
# e conferido pelo devise_token_auth, como o painel faz nas chamadas da API.
module Cevico::SystemLogin
  extend ActiveSupport::Concern

  SESSION_COOKIE = 'cw_d_session_info'.freeze

  # quem está logado no painel, ou nil
  def system_user
    return @system_user if defined?(@system_user)

    @system_user = user_from_session_cookie
  end

  # a pessoa logada participa desta conta?
  def system_user_in?(account)
    account.present? && system_user.present? && system_user.account_users.exists?(account_id: account.id)
  end

  # sem login: JSON responde 401; tela vai para o login do sistema
  def require_system_login!
    if request.path.end_with?('.json')
      head :unauthorized
    else
      redirect_to '/app/login'
    end
  end

  private

  def user_from_session_cookie
    info = session_cookie_info
    return nil if info['uid'].blank? || info['access-token'].blank?

    user = User.find_by(uid: info['uid'].to_s)
    user if user&.valid_token?(info['access-token'].to_s, info['client'].presence || 'default')
  end

  # o cookie é um JSON com os cabeçalhos do devise_token_auth; qualquer coisa estranha = {}
  def session_cookie_info
    raw = cookies[SESSION_COOKIE].presence
    info = raw && JSON.parse(raw)
    info.is_a?(Hash) ? info : {}
  rescue JSON::ParserError
    {}
  end
end
