# Cesto de indicadores do Meu Painel (item 141): os números-base de um
# período com SÉRIE (dia / semana / mês, conforme o tamanho do período) e o
# PERÍODO ANTERIOR de mesmo tamanho para comparação. Alimenta os gráficos
# dos popups dos cards, os cards criados pelo admin no "+" e as FÓRMULAS
# ("appointments_booked / new_leads" = taxa de agendamento).
#
# Fontes: LeadsUniverse (leads), conversas, tarefas da Agenda (consultas e
# cirurgias) e o histórico de passagem pelas colunas (stage_logs), que é o
# mesmo que alimenta o PRO MAX — os números batem entre telas.
class Crm::KpiBagService # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MESES_PT = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

  # granularity: opcional (item 144) — a mini-régua do popup pode forçar o
  # balde; sem ela vale o automático pelo tamanho do período
  # lens: opcional (item 328) — a lente da fonte escolhida no Meu Painel
  # (Crm::SourceLens). Sem lente, tudo continua na régua de sempre.
  def initialize(account:, since:, until_at:, granularity: nil, lens: nil)
    @account = account
    @lens = lens
    @since = since
    @until_at = until_at
    forced = granularity.to_s.to_sym
    @granularity = %i[day week month].include?(forced) ? forced : pick_granularity
  end

  def call
    prev_until = @since - 1.second
    prev_since = prev_until - (@until_at - @since)
    keys = bucket_keys(@since, @until_at)
    # baldes do período ANTERIOR (item 144): a série sobreposta no gráfico
    # compara balde a balde, não só a média
    prev_keys = bucket_keys(prev_since, prev_until)
    # ⚡ item 237: cesto guardado por conta+período (2 min com o período aberto,
    # 10 min fechado) — a tela atualiza a cada 2 min e refazia ~120 queries
    ttl = @until_at >= Time.current ? 2.minutes : 10.minutes
    Rails.cache.fetch("cevico:kpibag:#{@account.id}:#{@lens&.key || 'padrao'}:#{@since.to_i}:#{@until_at.to_i}:#{@granularity}", expires_in: ttl) do
      build_bag(prev_since, prev_until, keys, prev_keys)
    end
  end

  def build_bag(prev_since, prev_until, keys, prev_keys)
    {
      granularity: @granularity,
      source: @lens&.key,
      points: keys.map { |k, label| { key: k, label: label } },
      prev_points: prev_keys.map { |k, label| { key: k, label: label } },
      previous_label: "#{prev_since.strftime('%d/%m')}–#{prev_until.strftime('%d/%m')}",
      metrics: base_metrics(@since, @until_at, prev_since, prev_until, keys.map(&:first), prev_keys.map(&:first))
    }
  end

  private

  # ── catálogo ──────────────────────────────────────────────────────────
  def base_metrics(since, until_at, prev_since, prev_until, keys, prev_keys) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    metrics = {}
    add = lambda do |key, label, unit, cur_scope, prev_scope, column, sum: nil, distinct: nil, date: false|
      series = bucketize(cur_scope, column, sum: sum, distinct: distinct, date: date)
      prev_series = bucketize(prev_scope, column, sum: sum, distinct: distinct, date: date)
      metrics[key] = {
        label: label,
        unit: unit,
        # item 237: o total é a soma dos baldes (antes: 2 queries a mais por indicador)
        value: series.values.sum.to_f.round(2),
        prev: prev_series.values.sum.to_f.round(2),
        series: keys.map { |k| (series[k] || 0).to_f.round(2) },
        prev_series: prev_keys.map { |k| (prev_series[k] || 0).to_f.round(2) }
      }
    end

    add.call('new_leads', 'Novos contatos (leads)', 'n',
             Crm::LeadsUniverse.scope(@account, since, until_at, lens: @lens),
             Crm::LeadsUniverse.scope(@account, prev_since, prev_until, lens: @lens), 'contacts.created_at')
    add.call('new_conversations', 'Novas conversas', 'n',
             conversations(since, until_at), conversations(prev_since, prev_until), 'conversations.created_at')
    # item 267 (28/09): NUNCA "chamar tudo de agendamento" — cada número diz de
    # quem é: consulta marcada de LEAD NOVO (chegou há até 30 dias) × de
    # paciente da BASE (mais antigo ou sem cadastro). "Entrou em Agendamento"
    # continua sendo a mudança de coluna no CRM (taxa oficial do item 233).
    add.call('appointments_booked', 'Consultas marcadas (leads novos + base; sem exame/tele)', 'n',
             booked(since, until_at), booked(prev_since, prev_until), 'tasks.created_at')
    add.call('appointments_booked_new', 'Consultas marcadas de LEADS NOVOS (chegaram há até 30 dias)', 'n',
             booked_new_leads(since, until_at), booked_new_leads(prev_since, prev_until), 'tasks.created_at')
    add.call('appointments_booked_base', 'Consultas marcadas de PACIENTES DA BASE (há mais de 30 dias)', 'n',
             booked_base(since, until_at), booked_base(prev_since, prev_until), 'tasks.created_at')
    # 📊 item 233: a TAXA oficial usa a ENTRADA na coluna de agendamento do CRM
    # item 267: PACIENTES distintos (quem entrou 2x no mesmo dia conta 1) — igual ao Gestor
    add.call('appointments_created', 'Entrou em Agendamento de Consulta (mudou de coluna no CRM)', 'n',
             Crm::BookingRate.entries(@account, since, until_at, lens: @lens),
             Crm::BookingRate.entries(@account, prev_since, prev_until, lens: @lens),
             'crm_contact_stage_logs.entered_at', distinct: 'crm_contact_stage_logs.crm_contact_id')
    # 📅 item 217: confirmou (SIM ao lembrete) e lançadas (já estavam marcadas fora do sistema)
    add.call('appointments_confirmed', 'Consultas confirmadas (SIM ao lembrete)', 'n',
             confirmed(since, until_at), confirmed(prev_since, prev_until), 'tasks.confirmed_at')
    add.call('appointments_registered', 'Consultas lançadas (já estavam marcadas)', 'n',
             registered(since, until_at), registered(prev_since, prev_until), 'tasks.created_at')
    add.call('appointments_due', 'Consultas do período (pela data)', 'n',
             due_tasks('consulta', since, until_at), due_tasks('consulta', prev_since, prev_until), 'tasks.due_at')
    add.call('indications', 'Indicações de cirurgia (consultas)', 'n',
             indicated(since, until_at), indicated(prev_since, prev_until), 'tasks.due_at')
    add.call('appointments_attended', 'Consultas com presença', 'n',
             attendance('consulta', 'attended', since, until_at), attendance('consulta', 'attended', prev_since, prev_until), 'tasks.due_at')
    add.call('appointments_missed', 'Faltas em consultas', 'n',
             attendance('consulta', 'missed', since, until_at), attendance('consulta', 'missed', prev_since, prev_until), 'tasks.due_at')

    # 🏥 POR UNIDADE (pedido 02/09: "indicador que separe as consultas da
    # Paulista e do Tatuapé") — consultas pela data, presenças e faltas de
    # cada casa: viram cards de 1 clique no "+ Novo indicador" e alimentam
    # a taxa de comparecimento por unidade nas fórmulas prontas
    Crm::AgendaSlots::UNIT_LABELS.each do |unit, unit_label|
      add.call("appointments_due_#{unit}", "Consultas · #{unit_label}", 'n',
               due_tasks('consulta', since, until_at).where(unit: unit),
               due_tasks('consulta', prev_since, prev_until).where(unit: unit), 'tasks.due_at')
      add.call("appointments_attended_#{unit}", "Presenças · #{unit_label}", 'n',
               attendance('consulta', 'attended', since, until_at).where(unit: unit),
               attendance('consulta', 'attended', prev_since, prev_until).where(unit: unit), 'tasks.due_at')
      add.call("appointments_missed_#{unit}", "Faltas · #{unit_label}", 'n',
               attendance('consulta', 'missed', since, until_at).where(unit: unit),
               attendance('consulta', 'missed', prev_since, prev_until).where(unit: unit), 'tasks.due_at')
    end
    add.call('surgeries_booked', @lens ? 'Cirurgias marcadas' : 'Cirurgias marcadas (todas: clínica + Oftalmofácil)', 'n',
             created_tasks('cirurgia', since, until_at), created_tasks('cirurgia', prev_since, prev_until), 'tasks.created_at')
    # item 267: fechamento honesto = cirurgia marcada de quem teve INDICAÇÃO em consulta
    add.call('surgeries_booked_indicated', 'Cirurgias marcadas após indicação (fechamento)', 'n',
             surgeries_after_indication(since, until_at), surgeries_after_indication(prev_since, prev_until), 'tasks.created_at')
    add.call('surgeries_done', 'Cirurgias realizadas (Agenda)', 'n',
             attendance('cirurgia', 'attended', since, until_at), attendance('cirurgia', 'attended', prev_since, prev_until), 'tasks.due_at')
    add.call('surgeries_missed', 'Cirurgias — não vieram', 'n',
             attendance('cirurgia', 'missed', since, until_at), attendance('cirurgia', 'missed', prev_since, prev_until), 'tasks.due_at')

    # passagem pelas colunas do funil + faturamento (mesma fonte do PRO MAX)
    # item 328: com a lente, as colunas dos funis das OUTRAS fontes entram
    # depois das da casa (o nome do funil vai junto, para não confundir colunas iguais)
    pipelines = funnels
    pipelines.each_with_index do |pipeline, index|
      suffix = index.zero? ? '' : " · #{pipeline.name}"
      pipeline.stages.order(:position).each do |stage|
        add.call("stage_#{stage.id}", "Entrou em #{stage.name}#{suffix}", 'n',
                 stage_entries(pipeline, stage.id, since, until_at),
                 stage_entries(pipeline, stage.id, prev_since, prev_until), 'crm_contact_stage_logs.entered_at')
      end
    end
    if pipelines.any?
      add.call('revenue', 'Faturamento fechado (R$)', 'brl',
               revenue_logs(pipelines, since, until_at), revenue_logs(pipelines, prev_since, prev_until),
               'crm_contact_stage_logs.entered_at', sum: 'COALESCE(crm_contacts.value, 0)')
    end

    # 💸 item 303 (30/09): o WhatsApp passou a custar por mensagem — quantas
    # saíram (robô + equipe + lembretes), o gasto ESTIMADO pelas tarifas
    # (marca da Meta em cada mensagem) e o gasto pela FATURA da Meta
    rates = Crm::WhatsappPricing.rates(@account)
    add.call('wa_messages_sent', 'Mensagens enviadas no WhatsApp (robô + equipe + lembretes)', 'n',
             wa_messages(since, until_at), wa_messages(prev_since, prev_until), 'messages.created_at')
    add.call('wa_cost', 'Gasto com WhatsApp (R$, estimado pelas tarifas)', 'brl',
             wa_messages(since, until_at), wa_messages(prev_since, prev_until), 'messages.created_at',
             sum: Crm::WhatsappPricing.cost_sql(rates))
    add.call('wa_cost_meta', 'Gasto com WhatsApp (fatura da Meta)', 'brl',
             wa_charges(since, until_at), wa_charges(prev_since, prev_until), 'crm_whatsapp_charges.day',
             sum: 'crm_whatsapp_charges.cost', date: true)
    metrics
  end

  def wa_messages(since, until_at)
    scope = Crm::WhatsappSpendService.outgoing_scope(@account, since, until_at)
    @lens ? @lens.inboxes(scope, 'messages.inbox_id') : scope
  end

  # ── item 328: a lente da fonte ────────────────────────────────────────
  # agendamentos da conta pela lente (sem lente = todos, como sempre foi)
  def tasks
    @lens ? @lens.tasks(@account.tasks) : @account.tasks
  end

  def conversations(since, until_at)
    scope = @account.conversations.where(created_at: since..until_at)
    @lens ? @lens.inboxes(scope) : scope
  end

  # funis cujas colunas viram indicador: sem lente, o principal da casa; com
  # lente, o da casa na frente (as colunas dele zeram sozinhas se a fonte for
  # outra) + os funis das fontes que a lente enxerga
  def funnels
    main = @account.crm_pipelines.order(:id).first
    return [main].compact if @lens.nil?

    ([main] + @lens.pipelines).compact.uniq
  end

  def wa_charges(since, until_at)
    Crm::WhatsappCharge.where(account_id: @account.id, day: since.to_date..until_at.to_date)
  end

  # ── escopos ───────────────────────────────────────────────────────────
  # item 217: só consulta NOVA conta como agendamento ('registro' = lançamento
  # de consulta que já existia fora do sistema)
  def booked(since, until_at)
    scope = tasks.bookings.where(task_type: 'consulta', created_at: since..until_at)
                 .where('tasks.due_at IS NULL OR tasks.due_at >= tasks.created_at')
                 .where(canceled_at: nil) # item 233: sem exame, tele ou cancelada
                 .where("tasks.modality IS NULL OR tasks.modality NOT IN ('teleconsulta', 'exames')")
    # sem lente: os parceiros ficam fora pela regra antiga; com lente, é ela quem separa
    @lens ? scope : scope.where(source_detail: nil).not_partner_origin
  end

  NEW_LEAD_DAYS = 30

  # consulta marcada por quem CHEGOU há até 30 dias (lead novo) × mais antigo
  def booked_new_leads(since, until_at)
    booked(since, until_at).joins(:contact)
                           .where("tasks.created_at - contacts.created_at <= interval '#{NEW_LEAD_DAYS} days'")
  end

  def booked_base(since, until_at)
    booked(since, until_at).left_joins(:contact)
                           .where("contacts.id IS NULL OR tasks.created_at - contacts.created_at > interval '#{NEW_LEAD_DAYS} days'")
  end

  # cirurgia marcada de paciente que teve consulta com indicação ANTES dela
  def surgeries_after_indication(since, until_at)
    created_tasks('cirurgia', since, until_at)
      .where('EXISTS (SELECT 1 FROM tasks i WHERE i.account_id = tasks.account_id AND i.contact_id = tasks.contact_id ' \
             "AND i.task_type = 'consulta' AND i.surgery_indication = 'indicated' AND i.due_at <= tasks.created_at)")
  end

  def confirmed(since, until_at)
    tasks.where(task_type: 'consulta', confirmed_at: since..until_at)
  end

  def registered(since, until_at)
    tasks.where(task_type: 'consulta', booking_kind: 'registro', created_at: since..until_at)
  end

  def created_tasks(type, since, until_at)
    tasks.where(task_type: type, created_at: since..until_at)
  end

  def due_tasks(type, since, until_at)
    tasks.where(task_type: type, canceled_at: nil, due_at: since..until_at)
  end

  def indicated(since, until_at)
    due_tasks('consulta', since, until_at).where(surgery_indication: 'indicated')
  end

  def attendance(type, status, since, until_at)
    tasks.where(task_type: type, attendance: status, canceled_at: nil, due_at: since..until_at)
  end

  # item 309: só entrada de verdade — carga em massa (`bulk`) não é paciente entrando na coluna
  def stage_entries(pipeline, stage_id, since, until_at)
    scope = Crm::StageLog.joins(:crm_contact)
                         .where(crm_contacts: { pipeline_id: pipeline.id }, stage_id: stage_id, entered_at: since..until_at,
                                event_type: Crm::StageLogBulk::ENTERED)
    @lens ? @lens.stage_logs(scope) : scope
  end

  def revenue_logs(pipelines, since, until_at)
    scope = Crm::StageLog.joins(:crm_contact)
                         .where(crm_contacts: { pipeline_id: pipelines.map(&:id) }, entered_at: since..until_at)
                         .where("crm_contact_stage_logs.stage_name ILIKE '%cirurgia realizada%'")
    @lens ? @lens.stage_logs(scope) : scope
  end

  # ── baldes ────────────────────────────────────────────────────────────
  def pick_granularity
    days = ((@until_at.to_date - @since.to_date).to_i + 1)
    return :day if days <= 45
    return :week if days <= 400

    :month
  end

  # date: true = a coluna já é uma DATA (sem hora/fuso a converter)
  def bucket_sql(column, date: false)
    tz_col = date ? column : "#{column} AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo'"
    case @granularity
    when :week then "to_char(date_trunc('week', #{tz_col}), 'YYYY-MM-DD')"
    when :month then "to_char(date_trunc('month', #{tz_col}), 'YYYY-MM-DD')"
    else "to_char(#{tz_col}, 'YYYY-MM-DD')"
    end
  end

  def bucket_keys(since, until_at)
    keys = []
    case @granularity
    when :week
      d = since.to_date.beginning_of_week
      while d <= until_at.to_date
        keys << [d.iso8601, d.strftime('%d/%m')]
        d += 7
      end
    when :month
      d = since.to_date.beginning_of_month
      while d <= until_at.to_date
        keys << [d.iso8601, "#{MESES_PT[d.month - 1]}/#{d.strftime('%y')}"]
        d = d.next_month
      end
    else
      (since.to_date..until_at.to_date).each { |d| keys << [d.iso8601, d.strftime('%d/%m')] }
    end
    keys
  end

  def bucketize(scope, column, sum: nil, distinct: nil, date: false)
    grouped = scope.reorder(nil).group(Arel.sql(bucket_sql(column, date: date)))
    return grouped.sum(Arel.sql(sum)) if sum
    return grouped.distinct.count(Arel.sql(distinct)) if distinct

    grouped.count
  end

  def total_of(scope, sum: nil)
    sum ? scope.reorder(nil).sum(Arel.sql(sum)).to_f.round(2) : scope.reorder(nil).count
  end
end
