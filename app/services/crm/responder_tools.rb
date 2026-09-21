# 🔧 FERRAMENTAS DOS RESPONDEDORES (rodada 192): o que o Atendente pode FAZER
# além de falar — buscar uma consulta na Agenda (a própria ou a de um
# familiar), remarcar, cancelar e confirmar presença. Entram na chamada da IA
# como `tools` (tool use): a IA pede, este serviço executa e devolve o
# resultado em JSON no `tool_result`; a IA lê e só então escreve ao paciente.
#
# Regras de segurança (valem para todas as ferramentas):
# - a consulta tem que ser DESTA conta, de hoje 00:00 (fuso SP) em diante,
#   não cancelada e não concluída — fora disso é "não encontrada";
# - telefone de TERCEIRO nunca sai inteiro (só os 4 finais);
# - em SOMBRA nenhuma ferramenta escreve: só valida e responde `simulado`.
# `acoes` acumula o que foi feito, para a nota de sombra e os balões da tela
# (montado aqui, nunca pelo modelo).
class Crm::ResponderTools # rubocop:disable Metrics/ClassLength
  TZ = Crm::AgendaSlots::TZ
  MAX_RESULTS = 5
  LOCK_TTL = 30.seconds
  NAMES = %w[buscar_consulta remarcar_consulta cancelar_consulta confirmar_presenca].freeze
  AGENT_NAMES = { 'atendente_agendamento' => 'Atendente de Agendamento', 'atendente_pos' => 'Atendente Pós-agendamento' }.freeze
  WEEKDAYS_SHORT = %w[dom seg ter qua qui sex sáb].freeze

  attr_reader :acoes

  def initialize(conversation:, agent_key:, live:)
    @conversation = conversation
    @account = conversation.account
    @contact = conversation.contact
    @agent_key = agent_key.to_s
    @live = live == true
    @acoes = []
  end

  # definições para a API (input_schema em JSON Schema)
  def definitions # rubocop:disable Metrics/MethodLength
    [
      {
        name: 'buscar_consulta',
        description: 'Busca consultas marcadas na Agenda da clínica (de hoje em diante). Sem filtro devolve as do próprio ' \
                     'paciente desta conversa. Com nome e/ou dia encontra também a consulta de OUTRA pessoa (mãe, filho, ' \
                     'esposa). Devolve id, paciente, dia, hora, unidade, médico e os 4 últimos dígitos do telefone.',
        input_schema: {
          type: 'object',
          properties: {
            nome: { type: 'string', description: 'Nome (ou parte do nome) do paciente da consulta' },
            telefone: { type: 'string', description: 'Telefone com DDD, quando o paciente informar' },
            dia: { type: 'string', description: 'Dia da consulta no formato YYYY-MM-DD' }
          },
          additionalProperties: false
        }
      },
      {
        name: 'remarcar_consulta',
        description: 'Move uma consulta existente para outro dia/hora/unidade. Use SÓ depois de o paciente confirmar dia, hora ' \
                     'e unidade de um horário presente em HORÁRIOS DISPONÍVEIS. Devolve ok=true quando remarcou; ok=false com ' \
                     'motivo quando a vaga não está livre (ofereça outra).',
        input_schema: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'id da consulta (de buscar_consulta ou do contexto)' },
            dia: { type: 'string', description: 'Novo dia, YYYY-MM-DD' },
            hora: { type: 'string', description: 'Nova hora, HH:MM' },
            unidade: { type: 'string', enum: %w[tatuape paulista] }
          },
          required: %w[id dia hora unidade],
          additionalProperties: false
        }
      },
      {
        name: 'cancelar_consulta',
        description: 'Cancela uma consulta (sem novo horário). Use SÓ depois de o paciente manter o cancelamento.',
        input_schema: {
          type: 'object',
          properties: {
            id: { type: 'integer', description: 'id da consulta' },
            motivo: { type: 'string', description: 'Motivo dito pelo paciente, em poucas palavras' }
          },
          required: %w[id],
          additionalProperties: false
        }
      },
      {
        name: 'confirmar_presenca',
        description: 'Registra que o paciente confirmou que vai à consulta ("confirmo", "estarei lá").',
        input_schema: {
          type: 'object',
          properties: { id: { type: 'integer', description: 'id da consulta' } },
          required: %w[id],
          additionalProperties: false
        }
      }
    ]
  end

  # executa a ferramenta pedida pela IA; devolve o Hash que vai como JSON no tool_result
  def call(name, input) # rubocop:disable Metrics/CyclomaticComplexity
    args = (input || {}).to_h.transform_keys(&:to_s)
    case name.to_s
    when 'buscar_consulta' then buscar(args)
    when 'remarcar_consulta' then remarcar(args)
    when 'cancelar_consulta' then cancelar(args)
    when 'confirmar_presenca' then confirmar(args)
    else
      { ok: false, motivo: "Ferramenta desconhecida: #{name}" }
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::ResponderTools##{name}] #{e.class}: #{e.message}"
    log_acao(name.to_s, false, "erro: #{e.message.truncate(80)}")
    { ok: false, motivo: 'Falha interna ao executar a ferramenta; diga que vai verificar com a equipe.' }
  end

  # consultas que as ferramentas enxergam: desta conta, futuras, ativas
  def scope
    @account.tasks.where(task_type: 'consulta', canceled_at: nil)
            .where.not(status: 'done')
            .where('due_at >= ?', TZ.now.beginning_of_day)
  end

  # o Postgres tem a extensão unaccent? (uma vez por processo)
  def self.unaccent?
    return @unaccent unless @unaccent.nil?

    @unaccent = ActiveRecord::Base.connection.extension_enabled?('unaccent')
  rescue StandardError
    @unaccent = false
  end

  private

  # ── buscar ──────────────────────────────────────────────────────────────
  def buscar(args) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    name = args['nome'].to_s.strip
    digits = args['telefone'].to_s.gsub(/\D/, '')
    day = parse_date(args['dia'])

    found = own_appointments
    found |= by_phone(digits, day) if digits.length >= 8
    found |= by_name(name, day) if name.present?
    found = found.uniq(&:id).sort_by(&:due_at)
    total = found.size
    aviso = nil
    if total > MAX_RESULTS
      found = found.first(MAX_RESULTS)
      aviso = if day
                'Há mais consultas do que as listadas; peça o nome completo do paciente e busque de novo.'
              else
                'Muitas consultas com esse nome; pergunte o DIA da consulta e busque de novo com nome + dia.'
              end
    end
    log_acao('buscar_consulta', true, resumo_busca(found, total))
    { consultas: found.map { |t| serialize(t) }, total: total, aviso: aviso }.compact
  end

  # sempre entram: as do próprio contato (contact_id) e as do telefone deste WhatsApp
  def own_appointments
    list = @contact ? scope.where(contact_id: @contact.id).to_a : []
    own_digits = @contact&.phone_number.to_s.gsub(/\D/, '')
    list |= by_phone(own_digits, nil) if own_digits.length >= 8
    list
  end

  def by_phone(digits, day)
    rel = scope.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
    rel = rel.where(due_at: day_range(day)) if day
    rel.select { |t| Crm::AppointmentRecorder.same_phone_line?(digits, t.phone) }
  end

  # por nome: ILIKE sem acento (unaccent do Postgres quando existe; senão
  # normaliza em Ruby sobre as futuras) — "Maisa" acha "Maísa"
  def by_name(name, day)
    rel = scope
    rel = rel.where(due_at: day_range(day)) if day
    if self.class.unaccent?
      rel.where('unaccent(title) ILIKE unaccent(?)', "%#{ActiveRecord::Base.sanitize_sql_like(name)}%").order(:due_at).limit(50).to_a
    else
      needle = I18n.transliterate(name).downcase
      rel.order(:due_at).limit(2000).select { |t| I18n.transliterate(t.title.to_s).downcase.include?(needle) }
    end
  end

  def resumo_busca(found, total)
    return 'buscou consulta: nenhuma encontrada' if total.zero?

    first = found.first
    at = first.due_at.in_time_zone(TZ)
    day = at.to_date == TZ.now.to_date ? 'hoje' : "#{WEEKDAYS_SHORT[at.wday]} #{at.strftime('%d/%m')}"
    "buscou consulta: #{total} encontrada#{'s' if total > 1} (#{patient_name(first)}, #{day} #{at.strftime('%H:%M')})"
  end

  # ── remarcar ────────────────────────────────────────────────────────────
  def remarcar(args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    task = find_task(args['id'])
    return not_found('remarcar_consulta') unless task

    date = parse_date(args['dia'])
    time = args['hora'].to_s.strip
    unit = args['unidade'].to_s.strip
    if date.nil? || !time.match?(/\A\d{2}:\d{2}\z/) || !Crm::AgendaSlots::UNIT_LABELS.key?(unit)
      return refuse('remarcar_consulta', 'Informe dia (YYYY-MM-DD), hora (HH:MM) e unidade (tatuape ou paulista) de um horário da lista.')
    end

    label = "#{WEEKDAYS_SHORT[date.wday]} #{date.strftime('%d/%m')} #{time} · #{unit_label(unit)}"
    unless @live
      free = Crm::AgendaSlots.slot_available?(@account, date: date, time: time, unit: unit)
      log_acao('remarcar_consulta', free, "remarcaria #{patient_name(task)} p/ #{label} (simulado#{free ? '' : ', vaga ocupada'})")
      mensagem = free ? 'Em sombra nada foi alterado; a vaga está livre.' : 'Em sombra nada foi alterado; a vaga NÃO está livre — ofereça outra.'
      return { simulado: true, ok: free, mensagem: mensagem }
    end

    with_slot_lock(date, time, unit) do
      next refuse('remarcar_consulta', 'Essa vaga não está mais livre. Ofereça outra de HORÁRIOS DISPONÍVEIS.') unless
        Crm::AgendaSlots.slot_available?(@account, date: date, time: time, unit: unit)

      starts_at = TZ.parse("#{date} #{time}")
      doctor = Crm::AgendaSlots.windows(@account).find { |w| w['dow'] == date.wday && w['unit'] == unit }&.[]('doctor')
      task.update!(
        due_at: starts_at, unit: unit, doctor: doctor.presence || task.doctor,
        rescheduled_count: task.rescheduled_count + 1, status: :todo, canceled_at: nil,
        description: append_note(task.description, "Remarcada pelo #{agent_name} via WhatsApp (conversa ##{@conversation.display_id}) em #{stamp}")
      )
      Crm::AgentAlert.push(account: @account, kind: 'agente_remarcou', task: task, conversation: @conversation, agent_key: @agent_key)
      activity_note!("🔁 #{agent_name} remarcou: #{patient_name(task)} — #{label}. #{agenda_link(starts_at)}")
      log_acao('remarcar_consulta', true, "remarcou #{patient_name(task)} p/ #{label}")
      { ok: true, consulta: serialize(task.reload) }
    end
  end

  # ── cancelar ────────────────────────────────────────────────────────────
  def cancelar(args) # rubocop:disable Metrics/AbcSize
    task = find_task(args['id'])
    return not_found('cancelar_consulta') unless task

    motivo = args['motivo'].to_s.strip.truncate(200)
    unless @live
      log_acao('cancelar_consulta', true, "cancelaria a consulta de #{patient_name(task)} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi alterado; a consulta seria cancelada.' }
    end

    note = "Cancelada pelo #{agent_name} via WhatsApp (conversa ##{@conversation.display_id}) em #{stamp}"
    note += " — motivo: #{motivo}" if motivo.present?
    task.update!(canceled_at: Time.current, description: append_note(task.description, note))
    Crm::AgentAlert.push(account: @account, kind: 'agente_cancelou', task: task, conversation: @conversation, agent_key: @agent_key)
    activity_note!("🚫 #{agent_name} cancelou a consulta de #{patient_name(task)} (#{when_label(task)})#{" — motivo: #{motivo}" if motivo.present?}")
    log_acao('cancelar_consulta', true, "cancelou a consulta de #{patient_name(task)}")
    { ok: true, consulta: serialize(task) }
  end

  # ── confirmar presença ──────────────────────────────────────────────────
  def confirmar(args)
    task = find_task(args['id'])
    return not_found('confirmar_presenca') unless task

    unless @live
      log_acao('confirmar_presenca', true, "confirmaria presença de #{patient_name(task)} (simulado)")
      return { simulado: true, ok: true, mensagem: 'Em sombra nada foi alterado; a presença seria registrada.' }
    end

    task.update!(description: append_note(task.description, "Presença confirmada pelo paciente (WhatsApp, #{agent_name}) em #{stamp}"))
    log_acao('confirmar_presenca', true, "presença confirmada: #{patient_name(task)} (#{when_label(task)})")
    { ok: true, consulta: serialize(task) }
  end

  # ── apoio ───────────────────────────────────────────────────────────────
  # só consultas do escopo (conta + futura + ativa): id de fora = não existe
  def find_task(id)
    return nil unless id.to_i.positive?

    scope.find_by(id: id.to_i)
  end

  def not_found(tool)
    refuse(tool, 'Consulta não encontrada (confira o id com buscar_consulta).')
  end

  def refuse(tool, motivo)
    log_acao(tool, false, motivo.truncate(80))
    { ok: false, motivo: motivo }
  end

  # mesma trava da reserva do job (conta+dia+hora+unidade), 30 s
  def with_slot_lock(date, time, unit)
    lock = Redis::LockManager.new
    key = "CRM_SLOT_LOCK::#{@account.id}::#{date}::#{time}::#{unit}"
    return refuse('remarcar_consulta', 'Outra pessoa está pegando essa vaga agora; tente de novo em instantes.') unless lock.lock(key, LOCK_TTL)

    begin
      yield
    ensure
      lock.unlock(key)
    end
  end

  def serialize(task)
    at = task.due_at.in_time_zone(TZ)
    {
      id: task.id, paciente: patient_name(task),
      dia: at.strftime('%Y-%m-%d'), hora: at.strftime('%H:%M'), dia_semana: Crm::AgendaSlots::WEEKDAYS[at.wday],
      unidade: unit_label(task.unit), medico: task.doctor.presence || 'a definir',
      procedimento: task.procedure.presence || 'consulta de avaliação',
      telefone_final: task.phone.to_s.gsub(/\D/, '').last(4).presence,
      status: status_label(task), do_proprio_contato: own?(task)
    }
  end

  def status_label(task)
    return 'cancelada' if task.canceled_at.present?
    return 'presença confirmada' if task.description.to_s.include?('Presença confirmada')

    task.status == 'doing' ? 'em atendimento' : 'agendada'
  end

  def own?(task)
    return true if @contact && task.contact_id == @contact.id

    own_digits = @contact&.phone_number.to_s.gsub(/\D/, '')
    own_digits.length >= 8 && Crm::AppointmentRecorder.same_phone_line?(own_digits, task.phone)
  end

  def patient_name(task)
    task.title.to_s.sub(/\AConsulta:\s*/i, '').strip.presence || 'Paciente'
  end

  def unit_label(unit)
    Crm::AgendaSlots::UNIT_LABELS[unit] || unit.presence || 'unidade a definir'
  end

  def when_label(task)
    at = task.due_at.in_time_zone(TZ)
    "#{WEEKDAYS_SHORT[at.wday]} #{at.strftime('%d/%m %H:%M')} · #{unit_label(task.unit)}"
  end

  def agent_name
    AGENT_NAMES[@agent_key] || @agent_key
  end

  def stamp
    TZ.now.strftime('%d/%m %H:%M')
  end

  def parse_date(value)
    return nil if value.blank?

    Date.strptime(value.to_s.strip, '%Y-%m-%d')
  rescue ArgumentError, TypeError
    nil
  end

  def day_range(day)
    TZ.parse(day.to_s).all_day
  end

  def append_note(description, note)
    [description.presence, note].compact.join("\n\n")
  end

  def agenda_link(starts_at)
    "[📆 Ver na agenda](/app/accounts/#{@account.id}/agenda?date=#{starts_at.strftime('%Y-%m-%d')})"
  end

  # rastro na conversa para a equipe (nota interna, nunca chega ao paciente)
  def activity_note!(content)
    @conversation.messages.create!(
      account_id: @account.id, inbox_id: @conversation.inbox_id,
      message_type: :activity, private: true, content: content
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::ResponderTools] nota: #{e.message}"
  end

  def log_acao(ferramenta, success, resumo)
    @acoes << { 'ferramenta' => ferramenta, 'ok' => success == true, 'resumo' => resumo.to_s }
  end
end
