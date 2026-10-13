# 🚨 SAÚDE DOS ROBÔS (auditoria 10/2026, achado #217 — Rodada 6 "Rede de
# segurança"). Antes, quando um robô (cron) parava ou quebrava, o erro ia só
# para o log e ninguém ficava sabendo — o lembrete D-1 que não saiu só era
# descoberto pelo paciente que faltou.
#
# Agora cada robô CEVICO deixa um "sinal de vida" no Redis a cada rodada:
#   Crm::CronHealth.ran!('lembretes')            → no FIM da rodada
#   Crm::CronHealth.failed!('lembretes', e, account: conta) → nos rescues
# e o vigia (Crm::CronWatchdogJob, a cada 10 min) confere:
#   parado = não registrou rodada nos 2 últimos horários do cron (2× o
#            intervalo; respeita o calendário — a Colheitadeira não roda à
#            noite nem no domingo e isso não é "parado")
#   erro   = as 2 últimas rodadas terminaram com erro
# Os erros também vão para o ChatwootExceptionTracker (Sentry, se ligado).
#
# Fila dos robôs: um cron de 1 min (Crm::SidekiqHeartbeatJob, fila
# scheduled_jobs — a mesma do Radar e de vários crons; fica ABAIXO da 'low' na
# ordem do sidekiq.yml, por isso o prazo é folgado) renova uma chave; o /health
# do web (?sidekiq=1) responde 503 quando ela envelhece. O Meu Painel do
# administrador também lê Crm::CronHealth.problems direto do Redis (pelo WEB):
# se o Sidekiq morrer inteiro, o vigia não roda, mas a faixa vermelha aparece.
#
# Nada aqui pode quebrar o robô que chama: toda falha vira só uma linha de log.
module Crm::CronHealth # rubocop:disable Metrics/ModuleLength
  module_function

  # robôs vigiados: chave → nome que a equipe lê + entrada do config/schedule.yml
  JOBS = {
    'lembretes' => { label: 'Lembretes de consulta', schedule: 'crm_appointment_reminder_send_job' },
    'nps' => { label: 'Pesquisa de satisfação (NPS)', schedule: 'crm_nps_survey_send_job' },
    'jornada' => { label: 'Mensagens da jornada', schedule: 'crm_journey_run_job' },
    'resgate' => { label: 'Resgate do Atendente de IA', schedule: 'crm_responder_rescue_job' },
    'oftalmofacil' => { label: 'Sincronização com o OftalmoFácil', schedule: 'crm_oftalmofacil_sync_job' },
    'colheita' => { label: 'Colheitadeira da Base', schedule: 'crm_harvest_job' },
    'followup' => { label: 'Robôs de follow-up', schedule: 'crm_followup_bot_job' },
    'discador' => { label: 'Discador das campanhas de ligação', schedule: 'crm_voice_campaign_dialer_job' },
    'radar' => { label: 'Radar de Oportunidades', schedule: 'crm_opportunity_radar_job' }
  }.freeze

  KEY = 'cevico:cron_health:%<job>s'.freeze
  ROUND_ERRORS_KEY = 'cevico:cron_health:%<job>s:round_errors'.freeze
  SIDEKIQ_KEY = 'cevico:cron_health:sidekiq_beat'.freeze
  SIDEKIQ_LABEL = 'Fila dos robôs (Sidekiq)'.freeze
  # a rodada pode atrasar um pouco na fila: só conta como perdida depois disto
  GRACE = 10.minutes
  # erro em tantas rodadas seguidas = aviso
  ERROR_STREAK = 2
  # sem o sinal de 1 min da fila há mais que isso = fila parada (folgado: a
  # fila scheduled_jobs espera a 'low' esvaziar — campanha grande atrasa uns minutos)
  SIDEKIQ_STALE = 15.minutes
  # o mesmo erro (tipo + item) vai ao rastreador no máximo 1× nesse prazo
  TRACK_DEDUP = 1.hour
  STATE_TTL = 30.days

  # ── sinais dos robôs ───────────────────────────────────────────────────

  # fim de uma rodada do cron. Se algum failed! aconteceu nesta rodada, ela
  # conta como rodada com erro (soma na sequência); senão zera a sequência.
  def ran!(job, now: Time.current)
    errors = take_round_errors(job)
    write(job) do |state|
      state['last_run_at'] = now.iso8601
      if errors.positive?
        state['error_streak'] = state['error_streak'].to_i + 1
      else
        state['error_streak'] = 0
        state['last_ok_at'] = now.iso8601
      end
      state
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO saúde dos robôs] #{job}: sinal de vida não gravado (#{e.message})"
    nil
  end

  # erro dentro da rodada (o robô segue para a próxima conta): manda para o
  # rastreador de erros e marca a rodada como "com erro".
  # item: o que falhou (ex.: "conversa 12") — o mesmo erro do mesmo item só
  #   vai ao rastreador 1× por hora (não lota o Sentry a cada 2 min).
  # count: false = só registra; quem chama decide no fim da rodada se ela
  #   conta como "com erro" (mark_round_error!) — follow-up e discador, onde
  #   uma conversa/campanha com dado ruim não pode marcar o robô inteiro.
  def failed!(job, error, account: nil, now: Time.current, item: nil, count: true) # rubocop:disable Metrics/ParameterLists
    track(job, error, account, item)
    mark_round_error!(job) if count
    write(job) do |state|
      state['last_error'] = error_text(error, account)
      state['last_error_at'] = now.iso8601
      state
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO saúde dos robôs] #{job}: erro não registrado (#{e.message})"
    nil
  end

  # a rodada atual terminou "com erro" (soma 1 na sequência quando o ran! vier).
  # Com failed:/tried: só marca quando METADE OU MAIS dos itens da rodada
  # falharam (follow-up por conversa, discador por campanha)
  def mark_round_error!(job, failed: nil, tried: nil)
    return nil if failed && !(failed.positive? && failed * 2 >= tried.to_i)

    key = format(ROUND_ERRORS_KEY, job: job)
    Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, 1.day.to_i)
  rescue StandardError => e
    Rails.logger.warn "[CEVICO saúde dos robôs] #{job}: rodada com erro não registrada (#{e.message})"
    nil
  end

  # sinal de 1 min da fila (Crm::SidekiqHeartbeatJob)
  def sidekiq_beat!(now: Time.current)
    Redis::Alfred.with { |conn| conn.set(SIDEKIQ_KEY, now.iso8601, ex: 1.day.to_i) }
  rescue StandardError => e
    Rails.logger.warn "[CEVICO saúde dos robôs] sinal da fila não gravado (#{e.message})"
    nil
  end

  # a fila está andando? (usado pelo /health?sidekiq=1 e pelo vigia)
  def sidekiq_alive?(now: Time.current)
    at = parse_time(Redis::Alfred.get(SIDEKIQ_KEY))
    at.present? && at >= now - SIDEKIQ_STALE
  rescue StandardError
    false
  end

  # ── leitura (vigia e telas) ────────────────────────────────────────────

  def state(job)
    raw = Redis::Alfred.get(format(KEY, job: job))
    raw.present? ? JSON.parse(raw) : {}
  rescue JSON::ParserError
    {}
  end

  # foto de todos os robôs, para o resumo em ai_config.cron_health
  def snapshot(now: Time.current)
    JOBS.to_h do |job, meta|
      st = state(job)
      problem = problem_for(job, now: now, current: st)
      [job, st.slice('last_run_at', 'last_ok_at', 'last_error', 'last_error_at', 'error_streak')
              .merge('label' => meta[:label], 'status' => problem ? problem[:kind] : 'ok')]
    end
  end

  # problemas de agora: { 'lembretes' => { job:, label:, kind: 'parado'|'erro', message: } }
  def problems(now: Time.current)
    found = JOBS.keys.filter_map { |job| problem_for(job, now: now) }.index_by { |p| p[:job] }
    if sidekiq_stalled?(now)
      found['sidekiq'] = { job: 'sidekiq', label: SIDEKIQ_LABEL, kind: 'parado',
                           message: 'A fila dos robôs não andou nos últimos minutos — lembretes, NPS e jornada podem estar atrasados.' }
    end
    found
  end

  # o robô está com problema agora? nil = em dia
  def problem_for(job, now: Time.current, current: nil)
    meta = JOBS[job.to_s]
    return nil if meta.nil?

    st = current || state(job)
    if st['error_streak'].to_i >= ERROR_STREAK
      return { job: job.to_s, label: meta[:label], kind: 'erro',
               message: "#{meta[:label]}: as #{st['error_streak']} últimas rodadas terminaram com erro. " \
                        "Último erro: #{st['last_error'].presence || 'sem detalhe'}" }
    end
    return nil unless stalled?(job, st, now)

    last = parse_time(st['last_run_at'])
    { job: job.to_s, label: meta[:label], kind: 'parado',
      message: "#{meta[:label]}: o robô não roda desde #{last ? sp(last) : 'que o vigia começou a olhar'}." }
  end

  # perdeu os 2 últimos horários do cron? Sem nenhum registro ainda (logo
  # depois do deploy), conta a partir da 1ª vez que o vigia olhou.
  def stalled?(job, current, now)
    cron = cron_for(job)
    return false if cron.nil?

    reference = parse_time(current['last_run_at']) || watch_since(job, now)
    first_tick = cron.previous_time(now - GRACE).to_t
    second_tick = cron.previous_time(first_tick).to_t
    reference < second_tick
  end

  # fila sem o sinal de 1 min? Sem sinal nenhum ainda (logo depois do deploy),
  # dá o mesmo prazo a partir da 1ª vez que o vigia olhou
  def sidekiq_stalled?(now)
    return false if sidekiq_alive?(now: now)
    return true if Redis::Alfred.get(SIDEKIQ_KEY).present?

    watch_since('sidekiq', now) < now - SIDEKIQ_STALE
  end

  # ── ajudantes ──────────────────────────────────────────────────────────

  def cron_for(job)
    expr = schedule.dig(JOBS.dig(job.to_s, :schedule), 'cron')
    expr.present? ? Fugit::Cron.parse("#{expr} UTC") : nil # o servidor roda os crons em UTC
  end

  def schedule
    @schedule ||= YAML.load_file(Rails.root.join('config/schedule.yml'))
  end

  # 1ª vez que o vigia olhou um robô que ainda não deixou sinal nenhum
  def watch_since(job, now)
    at = parse_time(state(job)['watch_since'])
    return at if at

    write(job) do |st|
      st['watch_since'] ||= now.iso8601
      st
    end
    now
  end

  def write(job)
    key = format(KEY, job: job)
    updated = yield(state(job))
    # conexão direta (não Redis::Alfred.set): specs dos robôs vigiam o .set das marcas deles
    Redis::Alfred.with { |conn| conn.set(key, updated.to_json, ex: STATE_TTL.to_i) }
    updated
  end

  # lê e zera numa tacada só (MULTI): um failed! no meio não se perde nem
  # cai na conta da rodada seguinte
  def take_round_errors(job)
    key = format(ROUND_ERRORS_KEY, job: job)
    replies = Redis::Alfred.with do |conn|
      conn.multi do |tx|
        tx.get(key)
        tx.del(key)
      end
    end
    replies.first.to_i
  end

  def track(job, error, account, item)
    if item.present?
      dedup = "cevico:cron_health:#{job}:tracked:#{Digest::MD5.hexdigest("#{error.class.name}|#{item}")}"
      return unless Redis::Alfred.with { |conn| conn.set(dedup, 1, nx: true, ex: TRACK_DEDUP.to_i) }
    end
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  # texto curto do erro (tipo + mensagem + conta), sem pilha
  def error_text(error, account)
    prefix = account ? "conta #{account.id} · " : ''
    "#{prefix}#{error.class.name.demodulize}: #{error.message}".truncate(200)
  end

  def parse_time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end

  def sp(time)
    time.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M')
  end
end
