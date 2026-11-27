# 👣 ENTRADA NO SISTEMA (27/11/2026 · LIFE, pedido do Guilherme): "quando ele entra no sistema, quando ele inicia a
# resposta…". Cada chamada autenticada da tela (Api::V1::Accounts::BaseController) marca o dia da pessoa: o 1º acesso
# fica, o último é atualizado. Para não escrever no banco a cada clique, grava no máximo 1 vez a cada 5 min por pessoa
# (marca no cache). A tela aberta faz chamadas sozinha (o Meu Painel atualiza a cada 2 min), então "último acesso" quer
# dizer "último momento com o sistema aberto"; "entrou" é o 1º acesso do dia.
module Crm::PresenceTracker
  module_function

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  THROTTLE = 5.minutes

  def touch!(account, user, at: Time.current)
    return if account.nil? || user.nil?

    day = at.in_time_zone(TZ).to_date
    key = "cevico:presenca:#{account.id}:#{user.id}:#{day.iso8601}"
    return if Rails.cache.read(key)

    Rails.cache.write(key, true, expires_in: THROTTLE)
    Crm::UserDay.upsert( # rubocop:disable Rails/SkipsModelValidations
      { account_id: account.id, user_id: user.id, day: day, first_seen_at: at, last_seen_at: at, hits: 1,
        created_at: at, updated_at: at },
      unique_by: %i[account_id user_id day],
      on_duplicate: Arel.sql('last_seen_at = EXCLUDED.last_seen_at, hits = crm_user_days.hits + 1, ' \
                             'updated_at = EXCLUDED.updated_at')
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::PresenceTracker] #{e.class}: #{e.message}"
  end
end
