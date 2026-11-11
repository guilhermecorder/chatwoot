# ── ↪ Redirecionamento permanente (item 395) ─────────────────────────
# Página "redirecionada para" outra da MESMA conta: o endereço dela responde
# 301 para o endereço da página de destino (CevicoPagesController#show) e
# sai do sitemap. Serve para juntar guias que disputam a mesma busca sem
# perder o que o Google já aprendeu sobre o endereço que sai.
# SEM migration: o estado é um status novo ('redirected') e os detalhes
# moram numa chave reservada do daily_stats (jsonb que já existia):
#   { 'redirect' => { 'page_id', 'anchor', 'was' (status de antes), 'at' } }
# A chave não é uma data — quem lê o daily_stats por dia nunca a enxerga.
# O next_page_id (funil do botão) fica intacto: o "desfazer" devolve a
# página exatamente como estava.
module CevicoPageRedirect
  extend ActiveSupport::Concern

  REDIRECT_KEY = 'redirect'.freeze
  REDIRECT_ANCHOR = /\A[A-Za-z0-9_-]{1,80}\z/
  # o 301 só precisa disto — nunca carrega o HTML anexado (até 2 MB)
  REDIRECT_COLUMNS = %i[id account_id slug title status daily_stats].freeze

  included do
    scope :redirected, -> { where(status: 'redirected') }

    # saiu de "redirecionada" por qualquer caminho (desfazer, publicar pelo
    # editor): a chave reservada vai embora junto
    before_save :drop_redirect_info, if: -> { will_save_change_to_status? && !redirected? }
  end

  def redirected?
    status == 'redirected'
  end

  def redirect_info
    info = daily_stats.is_a?(Hash) ? daily_stats[REDIRECT_KEY] : nil
    redirected? && info.is_a?(Hash) ? info : nil
  end

  # só devolve âncora dentro da régua (ela vai para o cabeçalho Location)
  def redirect_anchor
    anchor = redirect_info&.dig('anchor').to_s
    anchor.match?(REDIRECT_ANCHOR) ? anchor : nil
  end

  # a página apontada (mesma conta, nunca ela mesma), publicada ou não
  def redirect_target
    target_id = redirect_info&.dig('page_id')
    return nil if target_id.blank?

    self.class.select(*REDIRECT_COLUMNS).where(account_id: account_id).where.not(id: id).find_by(id: target_id)
  end

  # [página PUBLICADA para onde o visitante vai, âncora] ou nil (= 404).
  # Cadeia e laço: se o destino também foi redirecionado, segue UM nível só
  # (A → B → C publicada responde direto para C); mais fundo que isso, destino
  # apagado, despublicado ou em laço (A → B → A) não redireciona.
  def redirect_destination
    target = redirect_target
    return nil if target.nil?
    return [target, redirect_anchor] if target.published?

    final = target.redirect_target
    final&.published? ? [final, target.redirect_anchor] : nil
  end

  # marca o redirecionamento. Trava a linha como os contadores de visita
  # (bump_daily_stats!): um aviso chegando na mesma hora não apaga a chave
  def redirect_to_page!(target, anchor: nil)
    transaction do
      lock!
      info = { 'page_id' => target.id, 'anchor' => anchor.presence, 'was' => redirect_info&.dig('was') || status,
               'at' => Time.current.iso8601 }.compact
      update!(status: 'redirected', daily_stats: (daily_stats.presence || {}).merge(REDIRECT_KEY => info))
    end
  end

  # desfaz: a página volta para a etapa em que estava (publicada volta ao ar)
  def undo_redirect!
    transaction do
      lock!
      was = redirect_info&.dig('was')
      update!(status: self.class::STATUSES.key?(was) && was != 'redirected' ? was : 'draft')
    end
  end

  private

  def drop_redirect_info
    self.daily_stats = daily_stats.except(REDIRECT_KEY) if daily_stats.is_a?(Hash) && daily_stats.key?(REDIRECT_KEY)
  end
end
