# Contador diário POR PESSOA para ações que custam dinheiro ou espaço
# (gerar página com IA, subir imagem). Auditoria rodada 2 (#169): antes
# qualquer pessoa do time podia disparar a geração quantas vezes quisesse.
#
# Uso: `Cevico::DailyQuota.hit!(:page_generate, account: a, user: u, limit: 40)`
# devolve true se ainda cabe (e já conta), false se passou do limite do dia.
# A chave mora no Redis e some sozinha depois de 1 dia.
module Cevico::DailyQuota
  module_function

  TTL = 1.day
  # o dia da cota vira à meia-noite de São Paulo (Date.current é UTC = 21h)
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def today
    Time.current.in_time_zone(TZ).to_date
  end

  def key(kind, account_id:, user_id:, date: today)
    "cevico:quota:#{kind}:#{account_id}:#{user_id}:#{date.iso8601}"
  end

  def hit!(kind, account:, user:, limit:)
    redis_key = key(kind, account_id: account.id, user_id: user.id)
    count = Redis::Alfred.incr(redis_key)
    Redis::Alfred.expire(redis_key, TTL.to_i) if count == 1
    count <= limit
  rescue StandardError => e
    # Redis fora do ar nunca pode travar a tela — registra e deixa passar
    Rails.logger.error "[Cevico::DailyQuota] #{e.class}: #{e.message}"
    true
  end

  def reset!(kind, account:, user:)
    Redis::Alfred.delete(key(kind, account_id: account.id, user_id: user.id))
  end
end
