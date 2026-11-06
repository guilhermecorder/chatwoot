# 🏥 Sincronização periódica com o OftalmoFácil (item 157): a cada 15 min,
# toda conta com a conexão CONFIGURADA e LIGADA puxa o que mudou lá desde o
# último cursor e trata (paciente, card, valor, etiquetas). Guarda o cursor
# e o resumo da última rodada em agenda_config.oftalmofacil pra tela mostrar.
# Também é o que o botão "Sincronizar agora" do card chama (perform_later).
class Crm::OftalmofacilSyncJob < ApplicationJob
  queue_as :scheduled_jobs

  # Rodada 2 (achado #193): o aviso único de "integração desligada", usado pelo
  # botão "Sincronizar agora" e pelo "Trazer para a Agenda" do Oftalmofácil
  OFF_MESSAGE = 'A integração está desligada. Ligue em Integrações → OftalmoFácil antes de sincronizar.'.freeze
  # Rodada 4 (achado #172): uma rodada por conta de cada vez — cron, botão
  # "Sincronizar agora" e "Trazer para a Agenda" disputam a MESMA trava.
  # Quem chega com a trava ocupada pula. A trava leva uma senha própria e só é
  # solta por quem a pegou (como o Crm::NpsSurvey.run_account): se uma rodada
  # passar do tempo e a seguinte entrar, a primeira não apaga a trava da segunda.
  # 60 min porque a recarga completa (histórico inteiro) pode passar de 30;
  # e a cada lote lido do hub a trava ganha mais 60 min (renew_lock), para uma
  # recarga ainda mais longa não perder a trava no meio.
  LOCK_TTL = 60.minutes
  BUSY_MESSAGE = 'Outra sincronização do OftalmoFácil ainda está rodando. Tente de novo em alguns minutos.'.freeze
  # Rodada 4 (achado #382): sem rodada boa há mais que isso, a tela avisa
  STALE_AFTER = 45.minutes

  def self.lock_key(account_id)
    "CRM_OF_SYNC_LOCK::#{account_id}"
  end

  # tem rodada em andamento nesta conta? (os botões recusam com aviso, em vez
  # de dizer "iniciada" e nada acontecer)
  def self.busy?(account_id)
    Redis::LockManager.new.locked?(lock_key(account_id))
  end

  # pega a trava da conta: devolve a senha (para soltar depois) ou nil se ocupada
  def self.acquire_lock(account_id)
    token = SecureRandom.uuid
    Redis::Alfred.set(lock_key(account_id), token, nx: true, ex: LOCK_TTL.to_i) ? token : nil
  end

  # renova a trava (mais LOCK_TTL) enquanto a rodada anda — só se a senha
  # ainda for a nossa. Ler e renovar não é uma operação só, mas o pior caso
  # (a trava venceu bem nesse instante e outra rodada entrou) apenas estica a
  # trava da outra, que a solta normalmente no fim.
  def self.renew_lock(account_id, token)
    return if token.nil?

    key = lock_key(account_id)
    Redis::Alfred.expire(key, LOCK_TTL.to_i) if Redis::Alfred.get(key) == token
  end

  # solta a trava só se a senha ainda for a nossa (quem passou do tempo não
  # apaga a trava de quem entrou depois)
  def self.release_lock(account_id, token)
    Redis::Alfred.delete_if_equals(lock_key(account_id), token) if token
  end

  # Rodada 4 (achado #382): o que a tela mostra em faixa vermelha, a partir do
  # que está gravado em agenda_config.oftalmofacil. nil = tudo em dia.
  #   erro   → a última tentativa falhou (last_error_at mais novo que last_run_at)
  #   parada → integração ligada e configurada, mas sem rodada boa há > 45 min
  # Devolve só texto genérico: o erro cru fica em last_error (admin vê no modal).
  # account_id (opcional): com uma rodada em andamento nesta conta (a recarga
  # completa pode levar mais de 45 min), não acusa "parada".
  def self.alert_for(of, account_id: nil) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    of = of.to_h
    return nil unless of['enabled'] == true && Crm::OftalmofacilSyncService.configured?(of)

    run_at = parse_time(of['last_run_at'])
    error_at = parse_time(of['last_error_at'])
    if error_at && (run_at.nil? || error_at > run_at)
      return { 'kind' => 'erro', 'at' => error_at.iso8601,
               'message' => 'A última sincronização com o OftalmoFácil falhou. Confira a conexão em Integrações → OftalmoFácil.' }
    end

    # conta a partir do que for mais novo: a última rodada boa ou a última vez
    # que o admin salvou o card (integração religada agora não ganha faixa
    # vermelha só porque a rodada boa é de antes de desligar)
    saved_at = parse_time(of['updated_at'])
    reference = [run_at, saved_at].compact.max
    return nil if reference.nil? || reference >= STALE_AFTER.ago
    return nil if account_id && busy?(account_id)

    message = if run_at && reference == run_at
                'A sincronização com o OftalmoFácil não roda há mais de 45 minutos.'
              elsif run_at
                'A sincronização com o OftalmoFácil não rodou desde que a conexão foi salva.'
              else
                'A sincronização com o OftalmoFácil ainda não concluiu nenhuma rodada.'
              end
    { 'kind' => 'parada', 'at' => reference.iso8601, 'message' => message }
  end

  def self.parse_time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end

  def perform(account_id = nil, full: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    scope = account_id ? CrmSetting.where(account_id: account_id) : CrmSetting.all
    scope.find_each do |settings|
      cfg = settings.agenda_config&.dig('oftalmofacil') || {}
      # Rodada 2 (achado #193): account_id é só FILTRO (qual conta), não atalho
      # da chave — desligada pelo admin, nem o cron nem o botão sincronizam
      next unless cfg['enabled'] == true
      next unless Crm::OftalmofacilSyncService.configured?(cfg)

      run_for(settings, cfg, full)
    rescue StandardError => e
      Rails.logger.error "[OftalmoFácil sync] conta #{settings.account_id}: #{e.message}"
      # Rodada 4 (achado #382): a falha fica gravada e aparece na tela, em vez
      # de a tela seguir mostrando a última rodada boa como se estivesse tudo em dia
      record_error(settings, e)
      # 🚨 #217: falha da rodada do cron (o botão já mostra a falha na tela)
      Crm::CronHealth.failed!('oftalmofacil', e, account: settings.account) if account_id.nil?
    end
    Crm::CronHealth.ran!('oftalmofacil') if account_id.nil? # 🚨 #217: sinal de vida da rodada do cron
  end

  private

  def run_for(settings, cfg, full)
    token = self.class.acquire_lock(settings.account_id)
    if token.nil?
      Rails.logger.info "[OftalmoFácil sync] conta #{settings.account_id}: #{BUSY_MESSAGE}"
      return
    end

    begin
      sync!(settings, cfg, full, token)
    ensure
      self.class.release_lock(settings.account_id, token)
    end
  end

  def sync!(settings, cfg, full, token) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
    service = Crm::OftalmofacilSyncService.new(account: settings.account, config: cfg,
                                               since: full ? nil : :cursor, silent: full ? true : nil,
                                               heartbeat: -> { self.class.renew_lock(settings.account_id, token) })
    result = service.call
    # item 254: a Agenda se conserta sozinha (próximos 14 dias, pelo espelho) e,
    # na rodada das :07, pergunta ao hub os próximos 7 dias atrás do que nunca veio
    service.heal_agenda!
    # auditoria 10/2026 (#462/#472): consulta lançada pela recepção DEPOIS de o hub
    # trazer o item vira uma só (a da equipe fica com o vínculo; a cópia vai para a Lixeira)
    service.dedupe_tasks!
    # 🗂️ ponta 3 (22/10): cirurgia que passou (com prova) ou foi cancelada tira o card de "Cirurgia Agendada"
    service.settle_cards!
    # Rodada 4 (revisão do #382): o service não levanta quando o hub cai — devolve
    # result.fatal. Os consertos acima usam só o espelho daqui e podem rodar;
    # mas a rodada NÃO conta como boa: nada de last_run_at nem de cursor novo.
    # O erro sobe para o rescue de perform, que grava last_error/last_error_at
    # e a tela mostra a faixa vermelha.
    raise Crm::OftalmofacilSyncService::Unreachable, result.fatal if result.fatal.present?

    service.refresh_upcoming! if full || Time.current.min < 15

    # cursor + resumo da rodada, sob a trava da linha (Rodada 4, achado #383):
    # só a chave 'oftalmofacil' muda; o que o admin salvou nas irmãs ('calls',
    # a Agenda…) enquanto o job rodava fica intacto
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, 'oftalmofacil') do |of|
      of['last_sync_at'] = result.cursor if result.cursor.present?
      of['last_sync_id'] = result.cursor_id.to_i if result.cursor.present? # item 249: desempate do cursor
      of['last_run_at'] = Time.current.iso8601
      of['last_result'] = {
        'pulled' => result.pulled, 'created_contacts' => result.created_contacts, 'moved' => result.moved,
        'ahead' => result.ahead, 'labeled' => result.labeled, 'errors' => result.errors.first(5),
        'error_count' => result.errors.size,
        # item 228
        'tasks_created' => result.tasks_created, 'tasks_updated' => result.tasks_updated,
        'partners' => result.partners, 'skipped_partners' => result.skipped_partners,
        # item 254
        'healed' => result.healed, 'unread_found' => result.unread_found,
        # #462/#472: consultas da equipe que ganharam o vínculo com o hub (adotadas ou unidas)
        'tasks_adopted' => result.tasks_adopted
      }
      of
    end
  end

  # Rodada 4 (achado #382): grava a falha em agenda_config.oftalmofacil (sob a
  # mesma trava), sem apagar o cursor nem a última rodada boa. Nunca levanta.
  def record_error(settings, error)
    # a falha do hub já vem em texto da casa (friendly_error); as outras levam o tipo
    text = error.is_a?(Crm::OftalmofacilSyncService::Unreachable) ? error.message : "#{error.class.name.demodulize}: #{error.message}"
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, 'oftalmofacil') do |of|
      of['last_error'] = text.truncate(200)
      of['last_error_at'] = Time.current.iso8601
      of
    end
  rescue StandardError => e
    Rails.logger.error "[OftalmoFácil sync] conta #{settings.account_id}: não conseguiu gravar o erro (#{e.message})"
  end
end
