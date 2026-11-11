# 🧭 item 394 (11/11) — JORNADA DO PACIENTE de ponta a ponta, com LINHA e BASE
# DE COMPARAÇÃO em cada etapa. Pedido do Guilherme: "enriquecer todos os
# indicadores… para conseguir visualizar melhor a jornada do paciente… gosto
# daquelas linhas… sempre poder ter uma base de comparação".
#
#   chegou → conversou → orçamento → agendou → confirmou → compareceu →
#   indicação → fechou cirurgia → operou → pós-operatório
#
# Cada etapa devolve: o número do período, o número da base de comparação
# (Crm::PeriodComparison), a série por dia (ou por mês acima de 95 dias) dos
# dois períodos — alinhadas balde a balde, para a tela desenhar a linha de
# agora e a de antes juntas — e a fórmula (o que conta).
#
# As réguas são AS MESMAS do "Volume do período" da Visão geral
# (Crm::OverviewService#volumes) e do cesto do painel clássico
# (Crm::KpiBagService): os números batem entre as telas. O spec confere.
# Aqui tudo é ACONTECIMENTO do período (quem agendou hoje pode ter chegado
# semana passada) — a turma que chegou e o que virou dela fica no bloco
# "Chegaram" / "Agendaram" da Visão geral.
class Crm::JourneyService # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  SURGERY_DONE_STAGE = /cirurgia\s+realizada/i
  MONTH_AFTER_DAYS = 95

  # key, rótulo, medida, ícone, etapa-base do rendimento, fórmula
  STEPS = [
    ['chegaram', 'Chegaram', 'contatos novos', 'i-lucide-door-open', nil,
     'Contatos novos que chegaram pelas portas de entrada no período (o mesmo número de "Contatos novos").'],
    ['conversaram', 'Conversaram', 'conversas novas', 'i-lucide-messages-square', nil,
     'Conversas abertas no período nas caixas de entrada desta fonte (o mesmo número de "Novas conversas").'],
    ['orcamento', 'Receberam orçamento', 'pessoas', 'i-lucide-receipt', 'chegaram',
     'Pessoas (sem repetir) que entraram na coluna de orçamento no período, de qualquer turma. Carga em massa fica fora.'],
    ['agendaram', 'Agendaram consulta', 'pessoas', 'i-lucide-calendar-plus', 'chegaram',
     'Pessoas (sem repetir) que entraram na coluna de agendamento de consulta no período: leads novos + pacientes da base. ' \
     'Remarcação e carga em massa ficam fora.'],
    ['confirmaram', 'Confirmaram', 'consultas', 'i-lucide-check-check', 'agendaram',
     'Consultas em que o paciente respondeu SIM ao lembrete no período (pela data da resposta).'],
    ['compareceram', 'Compareceram', 'consultas', 'i-lucide-user-check', 'confirmaram',
     'Consultas com data no período marcadas como "Compareceu" na conferência do dia (canceladas fora).'],
    ['indicacoes', 'Indicação de cirurgia', 'consultas', 'i-lucide-stethoscope', 'compareceram',
     'Consultas com data no período, com presença, em que o médico marcou "indicada cirurgia".'],
    ['fecharam', 'Fecharam cirurgia', 'cirurgias', 'i-lucide-handshake', 'indicacoes',
     'Cirurgias MARCADAS no período de quem teve indicação numa consulta antes.'],
    ['operaram', 'Cirurgia realizada', 'pessoas', 'i-lucide-sparkles', 'fecharam',
     'Pessoas (sem repetir) que entraram numa coluna "Cirurgia Realizada" no período. Carga em massa fica fora.'],
    ['pos_op', 'Pós-operatório', 'retornos', 'i-lucide-heart-pulse', 'operaram',
     'Retornos de pós-operatório com data no período (cancelados fora).']
  ].freeze

  # DESVIOS do caminho (e o total marcado na Agenda): não são etapas, mas
  # explicam a perda entre uma etapa e outra. As chaves são as mesmas do
  # "Volume do período" da Visão geral. bom_quando_sobe: false = cair é bom.
  DETOURS = [
    ['marcadas', 'Consultas marcadas', 'consultas', 'i-lucide-calendar-check', true,
     'Primeiras consultas (avaliação) criadas na Agenda no período, pela data em que foram marcadas, não canceladas. ' \
     'Retorno, pós-op, exame, teleconsulta e consulta lançada ficam fora. Conta consultas, não pessoas.'],
    ['faltas', 'Faltaram', 'consultas', 'i-lucide-user-x', false,
     'Consultas com data no período marcadas como "Faltou" na conferência do dia (canceladas fora).'],
    ['reagendamentos', 'Remarcaram', 'consultas', 'i-lucide-refresh-cw', false,
     'Consultas que mudaram de dia ou hora no período. Uma consulta remarcada 2 vezes no período conta 1.'],
    ['cancelamentos', 'Cancelaram', 'consultas', 'i-lucide-calendar-x', false,
     'Consultas desmarcadas no período, pela data do cancelamento.']
  ].freeze
  RESCHEDULED_SQL = Api::V1::Accounts::Crm::AppointmentsController::RESCHEDULED_IN_PERIOD_SQL

  def initialize(account:, since:, until_at:, lens: nil, compare: nil)
    @account = account
    @since = since
    @until_at = until_at
    @lens = lens || Crm::SourceLens.for(account, nil)
    @compare = compare || Crm::PeriodComparison.new(since, until_at)
    @by_month = ((until_at - since) / 86_400).ceil > MONTH_AFTER_DAYS
  end

  def call
    keys = bucket_keys(@since, @until_at)
    prev_keys = bucket_keys(@compare.since, @compare.until_at)
    {
      periodo: { de: @since.iso8601, ate: @until_at.iso8601, datas: range_label(@since, @until_at) },
      comparacao: @compare.to_h,
      balde: by_month? ? 'mes' : 'dia',
      rotulos: keys.map { |k| bucket_label(k) },
      rotulos_anterior: aligned(prev_keys, keys.size).map { |k| k && bucket_label(k) },
      etapas: STEPS.map { |step| step_json(step, keys, prev_keys) },
      desvios: DETOURS.map { |detour| detour_json(detour, keys, prev_keys) }
    }
  end

  private

  attr_reader :account, :lens

  def step_json(step, keys, prev_keys)
    key, label, medida, icon, base, formula = step
    cur = tally(times_for(key, @since, @until_at))
    prev = tally(times_for(key, @compare.since, @compare.until_at))
    {
      key: key, label: label, medida: medida, icon: icon, base: base, formula: formula,
      valor: cur.values.sum, anterior: prev.values.sum,
      serie: keys.map { |k| cur[k].to_i },
      # alinhada balde a balde com o período de agora (1º dia com 1º dia);
      # balde que não existe na base de comparação vai vazio (nil)
      serie_anterior: aligned(prev_keys, keys.size).map { |k| k && prev[k].to_i }
    }
  end

  def detour_json(detour, keys, prev_keys)
    key, label, medida, icon, good_up, formula = detour
    step_json([key, label, medida, icon, nil, formula], keys, prev_keys).merge(bom_quando_sobe: good_up)
  end

  # ── os acontecimentos de cada etapa: uma data por unidade contada ─────────
  def times_for(key, since, until_at) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    case key
    when 'chegaram'
      Crm::LeadsUniverse.scope(account, since, until_at, lens: lens).pluck('contacts.created_at')
    when 'conversaram'
      lens.inboxes(account.conversations.where(created_at: since..until_at)).pluck('conversations.created_at')
    when 'orcamento' then first_entry_per_person(budget_logs(since, until_at))
    when 'agendaram'
      first_entry_per_person(Crm::BookingRate.entries(account, since, until_at, lens: lens).joins(crm_contact: :contact))
    when 'confirmaram' then consultas_todas.where(confirmed_at: since..until_at).pluck(:confirmed_at)
    when 'compareceram' then consultas_do(since, until_at).where(attendance: 'attended').pluck(:due_at)
    when 'indicacoes'
      consultas_do(since, until_at).where(attendance: 'attended', surgery_indication: 'indicated').pluck(:due_at)
    when 'fecharam' then fecharam_scope(since, until_at).pluck(:created_at)
    when 'operaram' then first_entry_per_person(surgery_done_logs(since, until_at))
    when 'pos_op' then consultas_do(since, until_at).where(modality: 'pos_op').pluck(:due_at)
    else detour_times(key, since, until_at)
    end
  end

  def detour_times(key, since, until_at)
    case key
    when 'marcadas' then marcadas_na_agenda(since, until_at).pluck(:created_at)
    when 'faltas' then consultas_do(since, until_at).where(attendance: 'missed').pluck(:due_at)
    when 'reagendamentos' then rescheduled_times(since, until_at)
    when 'cancelamentos' then consultas_todas.where(canceled_at: since..until_at).pluck(:canceled_at)
    else []
    end
  end

  # consulta NOVA na Agenda (a régua de "Consultas marcadas", itens 217/233/385)
  def marcadas_na_agenda(since, until_at)
    lens.tasks(account.tasks).bookings.where(task_type: 'consulta', created_at: since..until_at, canceled_at: nil)
        .where('tasks.due_at IS NULL OR tasks.due_at >= tasks.created_at')
        .primeira_consulta
  end

  # a 1ª remarcação de cada consulta dentro do período (carimbo próprio, nunca o updated_at)
  def rescheduled_times(since, until_at)
    consultas_todas.where(RESCHEDULED_SQL, s: since, u: until_at).select(:id, :comments, :rescheduled_count).map do |task|
      task.rescheduled_times.select { |at| at.between?(since, until_at) }.min || since
    end
  end

  # PESSOAS: a 1ª entrada de cada uma no período — a soma dos baldes bate com o total
  def first_entry_per_person(logs)
    logs.joins(:crm_contact).reorder('crm_contact_stage_logs.entered_at')
        .pluck('crm_contacts.contact_id', 'crm_contact_stage_logs.entered_at')
        .uniq(&:first).map(&:last)
  end

  def budget_logs(since, until_at)
    stage = (@budget_stage ||= [Crm::BudgetSideEffects.stage(account)]).first
    return Crm::StageLog.none unless stage

    lens.stage_logs(Crm::StageLog.where(stage_id: stage.id, event_type: Crm::StageLogBulk::ENTERED, entered_at: since..until_at))
  end

  def consultas_todas
    lens.tasks(account.tasks).where(task_type: 'consulta').where("tasks.title IS NULL OR tasks.title NOT LIKE '⚠️%'")
  end

  def consultas_do(since, until_at)
    lens.tasks(account.tasks).where(task_type: 'consulta', canceled_at: nil, due_at: since..until_at)
  end

  def fecharam_scope(since, until_at)
    lens.tasks(account.tasks).where(task_type: 'cirurgia', canceled_at: nil, created_at: since..until_at)
        .where('EXISTS (SELECT 1 FROM tasks i WHERE i.account_id = tasks.account_id AND i.contact_id = tasks.contact_id ' \
               "AND i.task_type = 'consulta' AND i.surgery_indication = 'indicated' AND i.due_at <= tasks.created_at)")
  end

  def surgery_done_stage_ids
    @surgery_done_stage_ids ||= begin
      pipelines = account.crm_pipelines.includes(:stages).select { |pipeline| lens_sees_pipeline?(pipeline) }
      pipelines.flat_map { |pipeline| pipeline.stages.select { |st| st.name.to_s.match?(SURGERY_DONE_STAGE) } }.map(&:id)
    end
  end

  def lens_sees_pipeline?(pipeline)
    owner = Crm::Sources.map(account)['pipelines'][pipeline.id.to_s]
    owner.nil? ? (lens.all? || lens.own?) : lens.sees_source?(owner)
  end

  def surgery_done_logs(since, until_at)
    return Crm::StageLog.none if surgery_done_stage_ids.empty?

    lens.stage_logs(Crm::StageLog.where(stage_id: surgery_done_stage_ids, event_type: Crm::StageLogBulk::ENTERED, entered_at: since..until_at))
  end

  # ── baldes: dia até ~3 meses; depois, mês (a mesma régua da Visão geral) ──
  def by_month?
    @by_month
  end

  def bucket_of(time)
    time.in_time_zone(TZ).strftime(by_month? ? '%Y-%m' : '%Y-%m-%d')
  end

  def tally(times)
    times.compact.each_with_object(Hash.new(0)) { |time, acc| acc[bucket_of(time)] += 1 }
  end

  def bucket_keys(since, until_at)
    day = since.in_time_zone(TZ).to_date
    last = until_at.in_time_zone(TZ).to_date
    keys = []
    while day <= last
      keys << bucket_of(day.in_time_zone(TZ))
      day = by_month? ? day.next_month.beginning_of_month : day + 1
    end
    keys.uniq
  end

  def bucket_label(key)
    by_month? ? "#{key[5, 2]}/#{key[2, 2]}" : "#{key[8, 2]}/#{key[5, 2]}"
  end

  def aligned(keys, size)
    keys.first(size) + Array.new([size - keys.size, 0].max)
  end

  def range_label(since, until_at)
    from = since.in_time_zone(TZ).strftime('%d/%m')
    to = until_at.in_time_zone(TZ).strftime('%d/%m')
    from == to ? from : "#{from}–#{to}"
  end
end
