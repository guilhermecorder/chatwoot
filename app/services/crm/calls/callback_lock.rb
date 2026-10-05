# 📵🔒 LIGAÇÃO TRAVADA (item 325, 05/10). Pedido do Guilherme: "precisamos que
# as ligações sejam atendidas e que, quando não atendidas, sejam retornadas…
# após 5 segundos da 'ligação está chamando', ela impeça qualquer outra ação;
# e se ela não foi atendida, que fique travada até ligar de volta… se o
# paciente não atendeu, o ideal seria que a gente ligasse duas vezes… poder
# atribuir responsável por cada etapa do CRM".
#
# Configuração em agenda_config.calls:
#   lock          { enabled, after_seconds (5), attempts (2), exclusive }
#   stage_owners  { "<id da coluna do CRM>" => id da pessoa }
#   default_owner id da pessoa para coluna sem responsável (opcional)
#
# RESPONSÁVEL pela ligação = quem responde pela coluna em que o card do
# paciente está agora (o card mexido por último); paciente sem card → a coluna
# de entrada do funil principal; coluna sem responsável → o responsável padrão.
#
# Tocando: o responsável toca primeiro e, passados `after_seconds`, a tela
# dele trava até atender ou recusar. Sem `exclusive`, os outros da caixa
# continuam tocando depois da espera de sempre (ninguém fica sem ouvir).
#
# Perdida: o responsável fica guardado na própria ligação (evento `lock`) e a
# tela dele trava até a ligação ser RETORNADA:
#   · uma ligação ATENDIDA com o paciente depois da perdida, ou
#   · `attempts` ligações de volta feitas (o paciente não atendeu), ou
#   · alguém marcou "retornada" à mão (fica o nome de quem marcou).
# A trava dura no máximo 72 h. Sem a trava ligada, nada disso acontece e o
# aviso de ligação perdida segue como era (item 167).
module Crm::Calls::CallbackLock # rubocop:disable Metrics/ModuleLength
  module_function

  TTL = 72.hours
  DEFAULTS = { 'enabled' => false, 'after_seconds' => 5, 'attempts' => 2, 'exclusive' => false }.freeze
  SECONDS_RANGE = (3..30)
  ATTEMPTS_RANGE = (1..3)

  def calls_config(account)
    (CrmSetting.find_by(account_id: account.id)&.agenda_config || {})['calls'] || {}
  end

  def config(account, calls = nil)
    DEFAULTS.merge(((calls || calls_config(account))['lock'] || {}).slice(*DEFAULTS.keys))
  end

  def enabled?(account)
    config(account)['enabled'] == true
  end

  # o que a tela manda → o que fica gravado (só gente e colunas da conta)
  def sanitize(account, params) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    lock = params[:lock].respond_to?(:to_unsafe_h) ? params[:lock].to_unsafe_h : (params[:lock] || {}).to_h
    seconds = lock['after_seconds'].to_i
    attempts = lock['attempts'].to_i
    bool = ActiveModel::Type::Boolean.new
    user_ids = account.users.pluck(:id)
    stage_ids = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).pluck(:id)
    owners = params[:stage_owners].respond_to?(:to_unsafe_h) ? params[:stage_owners].to_unsafe_h : (params[:stage_owners] || {}).to_h
    {
      'lock' => { 'enabled' => bool.cast(lock['enabled']) == true,
                  'after_seconds' => SECONDS_RANGE.cover?(seconds) ? seconds : DEFAULTS['after_seconds'],
                  'attempts' => ATTEMPTS_RANGE.cover?(attempts) ? attempts : DEFAULTS['attempts'],
                  'exclusive' => bool.cast(lock['exclusive']) == true },
      'stage_owners' => owners.to_h { |stage_id, user_id| [stage_id.to_i, user_id.to_i] }
                              .select { |stage_id, user_id| stage_ids.include?(stage_id) && user_ids.include?(user_id) }
                              .transform_keys(&:to_s),
      'default_owner' => (user_ids.include?(params[:default_owner].to_i) ? params[:default_owner].to_i : nil)
    }
  end

  # quem responde por esta ligação agora (nil = ninguém definido)
  def owner_id(account, contact_id, calls = nil)
    calls ||= calls_config(account)
    owners = calls['stage_owners'] || {}
    stage_id = stage_id_for(account, contact_id)
    id = (stage_id && owners[stage_id.to_s]).presence || calls['default_owner']
    id.to_i.positive? && account.users.exists?(id: id) ? id.to_i : nil
  end

  def stage_id_for(account, contact_id)
    pipelines = account.crm_pipelines
    card = contact_id && Crm::Contact.where(contact_id: contact_id, pipeline_id: pipelines.select(:id))
                                     .order(Arel.sql('COALESCE(stage_moved_at, updated_at) DESC')).first
    card&.stage_id || pipelines.order(:position, :id).first&.stages&.first&.id
  end

  # o que vai junto do "está chamando": quem trava e depois de quantos segundos
  def ringing(account, call, ring_user_ids, ring_first_user_ids)
    calls = calls_config(account)
    cfg = config(account, calls)
    owner = cfg['enabled'] ? owner_id(account, call.contact_id, calls) : nil
    return { ring_user_ids: ring_user_ids, ring_first_user_ids: ring_first_user_ids } if owner.nil?

    { ring_user_ids: cfg['exclusive'] ? [owner] : (ring_user_ids | [owner]),
      ring_first_user_ids: [owner], lock_user_ids: [owner], lock_after_seconds: cfg['after_seconds'] }
  end

  # ligação perdida: guarda o responsável na ligação (nil = trava desligada ou coluna sem dono)
  def arm!(call)
    account = call.account
    return nil unless call.inbound? && enabled?(account)

    owner = owner_id(account, call.contact_id)
    return nil if owner.nil?

    call.add_event('lock', user_id: owner, user_name: account.users.find_by(id: owner)&.available_name)
    call.save!
    owner
  rescue StandardError => e
    Rails.logger.warn("[CEVICO calls] trava não armada: #{e.message}")
    nil
  end

  def locked_user_id(call)
    entry = Array(call.events).reverse.find { |event| event['event'] == 'lock' }
    entry&.dig('raw', 'user_id')
  end

  # ligações de volta feitas para o paciente depois da perdida
  def attempts(call)
    return 0 if call.contact_id.blank?

    since = call.ended_at || call.started_at || call.created_at
    Crm::Call.where(account_id: call.account_id, contact_id: call.contact_id, direction: :outbound)
             .where.not(id: call.id).where('created_at > ?', since).count
  end

  def answered_after?(call)
    return false if call.contact_id.blank?

    since = call.ended_at || call.started_at || call.created_at
    Crm::Call.where(account_id: call.account_id, contact_id: call.contact_id).answered
             .where.not(id: call.id).exists?(['started_at > ?', since])
  end

  # a trava desta ligação já pode soltar?
  def done?(call, cfg = nil)
    cfg ||= config(call.account)
    since = call.ended_at || call.started_at || call.created_at
    return true if since < TTL.ago
    return true if call.returned? || answered_after?(call)

    attempts(call) >= cfg['attempts'].to_i
  end

  # a ligação que está travando a tela desta pessoa (a mais antiga primeiro) — nil = livre
  def pending_for(account, user)
    return nil unless enabled?(account)

    cfg = config(account)
    Crm::Call.where(account_id: account.id, direction: :inbound, status: %i[missed rejected])
             .where('created_at > ?', TTL.ago).order(:id).find do |call|
      locked_user_id(call).to_i == user.id && !done?(call, cfg)
    end
  end

  def payload(call, cfg = nil)
    cfg ||= config(call.account)
    { call: call.to_payload(crm: true), attempts_done: attempts(call), attempts_needed: cfg['attempts'].to_i }
  end
end
