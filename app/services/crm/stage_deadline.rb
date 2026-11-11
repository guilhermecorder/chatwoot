# ⏳ PRAZO DA ETAPA (11/11/2026 · LIFE, pedido do Guilherme): cada coluna do funil pode ter um
# PRAZO e um COMPROMISSO. Ex.: "Orçamento a fazer" → próximo dia útil às 09:00, compromisso
# "Montar e enviar o orçamento". O cartão mostra o prazo em cores (verde com folga, amarelo quando
# vence em menos de 24 h, vermelho quando venceu) e, ao ENTRAR na coluna, nasce o compromisso
# datado para quem cuida dela (aparece em Tarefas, no Meu Painel e na "Minha agenda"). Ao SAIR da
# coluna, o compromisso recebe baixa sozinho.
#
# Configuração em crm_stages.settings['prazo']:
#   { 'modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Montar e enviar o orçamento' }
#   { 'modo' => 'horas', 'horas' => 24 }                       # só o prazo colorido, sem compromisso
# 'dia_util' = próximo dia de semana (sexta, sábado e domingo → segunda), na hora marcada.
#
# O compromisso é uma tarefa com data igual às do Atendente (⏰, task_type pos_op): se o Atendente
# já abriu a dele para o mesmo cliente e o mesmo dia ("Orçamento: conta recebida"), ela é ADOTADA
# em vez de duplicar. O vínculo com a etapa fica num comentário de sistema da tarefa.
class Crm::StageDeadline
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  KEY = 'prazo'.freeze
  MODES = %w[horas dia_util].freeze
  MAX_HOURS = 24 * 90
  TASK_TYPE = Crm::HandoffTask::TASK_TYPE
  MARK = Task::DUE_ALERT_MARK

  # o que a tela manda → o que fica gravado (nil = etapa sem prazo)
  def self.sanitize(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw
    return nil unless h.respond_to?(:to_h)

    h = h.to_h.transform_keys(&:to_s)
    modo = h['modo'].to_s
    return nil unless MODES.include?(modo)

    out = { 'modo' => modo, 'tarefa' => h['tarefa'].to_s.squish[0, 80].presence }
    if modo == 'horas'
      horas = h['horas'].to_i
      return nil unless horas.positive?

      out['horas'] = [horas, MAX_HOURS].min
    else
      out['hora'] = h['hora'].to_s.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/) ? h['hora'].to_s : '09:00'
    end
    out.compact
  end

  def self.config(stage)
    sanitize(stage&.settings&.[](KEY))
  end

  # quando vence o cartão que entrou nesta etapa em `moved_at` (nil = etapa sem prazo)
  def self.due_at(stage_or_config, moved_at)
    cfg = stage_or_config.is_a?(Hash) ? stage_or_config : config(stage_or_config)
    return nil if cfg.nil? || moved_at.nil?

    start = moved_at.in_time_zone(TZ)
    return start + cfg['horas'].to_i.hours if cfg['modo'] == 'horas'

    day = start.to_date + 1
    day += 1 while day.saturday? || day.sunday?
    hour, minute = cfg['hora'].split(':').map(&:to_i)
    TZ.local(day.year, day.month, day.day, hour, minute)
  end

  # o cartão mudou de coluna (ou nasceu numa): dá baixa no compromisso da coluna antiga e abre o da nova.
  # Nunca atrapalha a mudança: qualquer erro só vai para o log.
  def self.on_move(card, previous_stage_id: nil)
    return if Crm::CardRouter.quiet?

    leave!(card, previous_stage_id) if previous_stage_id.present?
    enter!(card)
  rescue StandardError => e
    Rails.logger.error "[Crm::StageDeadline] cartão #{card&.id}: #{e.class}: #{e.message}"
    nil
  end

  def self.enter!(card)
    stage = card.stage
    cfg = config(stage)
    return nil if cfg.nil? || cfg['tarefa'].blank? || card.contact.nil?

    new(card, stage, cfg).open!
  end

  def self.leave!(card, stage_id)
    account = card.pipeline&.account
    return 0 if account.nil?

    now_stage = card.stage&.name.to_s
    open_tasks(account, stage_id, card.id).to_a.each do |task|
      task.with_lock do
        task.update!(status: :done, comments: Array(task.comments) + [system_comment("Baixa automática: o cartão foi para «#{now_stage}».")])
      end
    end.size
  end

  # tarefas em aberto que são o compromisso desta etapa para este cartão
  def self.open_tasks(account, stage_id, card_id)
    marker = [{ 'etapa' => { 'stage_id' => stage_id.to_i, 'card_id' => card_id.to_i } }].to_json
    account.tasks.where(task_type: TASK_TYPE, status: %i[todo doing], canceled_at: nil).where('tasks.comments @> ?::jsonb', marker)
  end

  def self.system_comment(text, extra = {})
    { 'name' => 'Sistema', 'text' => text, 'at' => Time.current.iso8601 }.merge(extra)
  end

  def initialize(card, stage, cfg)
    @card = card
    @stage = stage
    @cfg = cfg
    @contact = card.contact
    @account = card.pipeline.account
    @due_at = self.class.due_at(cfg, card.stage_moved_at || Time.current)
  end

  def open!
    return nil if self.class.open_tasks(@account, @stage.id, @card.id).exists?

    task = adopt! || create!
    Crm::TaskDueAlertJob.set(wait_until: @due_at).perform_later(task.id, nil) if @due_at.future?
    task
  end

  private

  def marker_comment
    self.class.system_comment("Compromisso da etapa «#{@stage.name}»: #{@cfg['tarefa']}. Prazo: #{@due_at.strftime('%d/%m %H:%M')}.",
                              'etapa' => { 'stage_id' => @stage.id, 'card_id' => @card.id })
  end

  # o Atendente já abriu a tarefa datada deste cliente para o mesmo dia? Ela vira o compromisso da etapa.
  def adopt!
    task = @account.tasks.where(contact_id: @contact.id, task_type: TASK_TYPE, status: %i[todo doing], canceled_at: nil)
                   .where(due_at: @due_at.all_day).order(:created_at).first
    return nil if task.nil?

    task.with_lock { task.update!(comments: Array(task.comments) + [marker_comment]) }
    task
  end

  def create!
    @account.tasks.create!(
      title: "#{MARK} #{@contact.name.to_s.strip.presence || 'Cliente'} — #{@cfg['tarefa']}",
      description: "#{TZ.now.strftime('%d/%m %H:%M')} · Etapa «#{@stage.name}»: #{@cfg['tarefa']}",
      task_type: TASK_TYPE, priority: :high, status: :todo, due_at: @due_at,
      contact: @contact, phone: @contact.phone_number,
      creator: @account.administrators.order(:id).first || @account.users.first,
      assignee: owner, comments: [marker_comment]
    )
  end

  # quem cuida da coluna; sem dono, o responsável do cartão; por último, um administrador
  def owner
    @account.users.find_by(id: @stage.settings&.[]('task_owner_id').to_i) || @card.assignee ||
      @account.administrators.order(:id).first
  end
end
