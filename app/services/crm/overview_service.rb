# 🧭 item 337 (12/10 noite) — VISÃO GERAL do Meu Painel: as 14 perguntas do
# Guilherme num payload só, compondo os cálculos que já existem no sistema
# (universo de leads, coluna de orçamento, taxa oficial de agendamento do
# item 233, tempo de decisão, comparecimento, indicação, fechamento, CAC do
# item 318, médicos) e calculando o que faltava: coortes de hoje/7/30 dias,
# MÉDIA do tempo até agendar e OCUPAÇÃO da agenda no servidor.
#
#   entrada  → perguntas 1–5   agenda → 6–8   cirurgia → 9–10
#   dinheiro → 11–13 (SÓ ADMIN)   medicos → 14 (SÓ ADMIN)
#
# Toda lista de pessoas é limitada (LIST_LIMIT) — é o que o painel lateral
# mostra; o número é sempre o total.
#
# 🧹 item 342 (13/10) — "indicador de agendamento descontaminado". Pedido do
# Guilherme: "preciso saber quantos dos que chegaram hoje agendaram (de cada
# caixa de entrada), e qual o período médio que as outras pessoas agendaram"
# + "quero saber o volume de novos agendamentos de consulta, reagendamentos,
# cancelamentos, confirmações, comparecimentos, indicações, fechamentos,
# cirurgias realizadas de fato". O "Agendaram consulta" contava QUALQUER
# pessoa que entrou na coluna (base, pós-op, paciente do Oftalmofácil) e a
# taxa dividia isso pelos novos. Agora:
#   agendaram_novos  quem CHEGOU no período (universo de leads) e entrou na coluna
#   agendaram_base   o resto (chegou antes ou não é lead das portas de entrada)
#   taxa             agendaram_novos ÷ novos (mesma população em cima e embaixo)
#   safra            QUANDO chegaram os que agendaram (período, 1–7, 8–30, 31–90, +90 dias)
#   por_caixa        dos que chegaram no período, quantos agendaram, por caixa
#   volumes          os 9 números do período, cada um com fórmula e quebras
class Crm::OverviewService # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  LIST_LIMIT = 60
  IDS_LIMIT = 5000
  MODALITY_LABELS = { 'avaliacao' => 'Avaliação', 'retorno' => 'Retorno', 'pos_op' => 'Pós-operatório',
                      'exames' => 'Exames', 'teleconsulta' => 'Teleconsulta' }.freeze

  def initialize(account:, since:, until_at:, lens: nil, admin: false)
    @account = account
    @since = since
    @until_at = until_at
    @lens = lens || Crm::SourceLens.for(account, nil)
    @admin = admin
    @prev_since = since - (until_at - since)
    @prev_until = since
  end

  def call
    out = {
      periodo: { de: @since.iso8601, ate: @until_at.iso8601, anterior_de: @prev_since.iso8601, anterior_ate: @prev_until.iso8601 },
      entrada: entrada,
      agenda: agenda,
      cirurgia: cirurgia,
      volumes: volumes,
      series: series,
      admin: @admin
    }
    if @admin
      out[:dinheiro] = dinheiro
      out[:medicos] = medicos
    end
    out
  end

  private

  attr_reader :account, :lens

  def pct(part, total)
    total.to_f.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end

  # ── SÉRIES do período para os mini-gráficos (balde = dia até ~3 meses;
  #    depois, mês): novos, agendaram, consultas e compareceram ──
  def series # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    dias = ((@until_at - @since) / 86_400).ceil
    por_mes = dias > 95
    fmt = por_mes ? 'YYYY-MM' : 'YYYY-MM-DD'
    bucket = ->(col) { Arel.sql("TO_CHAR((#{col}) AT TIME ZONE 'America/Sao_Paulo', '#{fmt}')") }
    chaves = []
    d = @since.in_time_zone(TZ).to_date
    fim = @until_at.in_time_zone(TZ).to_date
    while d <= fim
      chaves << (por_mes ? d.strftime('%Y-%m') : d.to_s)
      d = por_mes ? d.next_month.beginning_of_month : d + 1
    end
    chaves.uniq!
    novos = leads.group(bucket.call('contacts.created_at')).count
    # item 342: PESSOAS (1ª entrada de cada uma no período), lead novo × base —
    # a soma dos baldes bate com o número de cima
    split = booking_split(@since, @until_at)
    chave = ->(t) { t.in_time_zone(TZ).strftime(por_mes ? '%Y-%m' : '%Y-%m-%d') }
    ag_novos = Hash.new(0)
    ag_base = Hash.new(0)
    split[:rows].each { |id, entered, _| (split[:novos].include?(id) ? ag_novos : ag_base)[chave.call(entered)] += 1 }
    consultas = consultas_ativas.group(bucket.call('tasks.due_at')).count
    compareceram = consultas_ativas.where(attendance: 'attended').group(bucket.call('tasks.due_at')).count
    {
      balde: por_mes ? 'mes' : 'dia',
      rotulos: chaves.map { |k| por_mes ? "#{k[5, 2]}/#{k[2, 2]}" : "#{k[8, 2]}/#{k[5, 2]}" },
      novos: chaves.map { |k| novos[k].to_i },
      agendaram: chaves.map { |k| ag_novos[k] + ag_base[k] },
      agendaram_novos: chaves.map { |k| ag_novos[k] },
      agendaram_base: chaves.map { |k| ag_base[k] },
      consultas: chaves.map { |k| consultas[k].to_i },
      compareceram: chaves.map { |k| compareceram[k].to_i }
    }
  end

  # ── 1–5 · ENTRADA E FUNIL ────────────────────────────────────────────────
  def leads(since = @since, until_at = @until_at)
    Crm::LeadsUniverse.scope(account, since, until_at, lens: lens)
  end

  def leads_ids
    @leads_ids ||= leads.limit(IDS_LIMIT).pluck(:id)
  end

  def budget_stage
    @budget_stage ||= Crm::BudgetSideEffects.stage(account)
  end

  # pacientes do universo que ENTRARAM na coluna de orçamento no período
  def budget_contact_ids(since = @since, until_at = @until_at)
    return [] unless budget_stage

    Crm::StageLog.joins(:crm_contact)
                 .where(stage_id: budget_stage.id, event_type: 'entered', entered_at: since..until_at)
                 .where(crm_contacts: { contact_id: leads(since, until_at).select(:id) })
                 .distinct.pluck('crm_contacts.contact_id')
  end

  # [contact_id, entered_at, contact.created_at] de quem entrou na coluna de agendamento
  def booking_rows(since, until_at)
    Crm::BookingRate.entries(account, since, until_at, lens: lens)
                    .joins(crm_contact: :contact)
                    .where(contacts: { id: leads(since, until_at).select(:id) })
                    .pluck('crm_contacts.contact_id', 'crm_contact_stage_logs.entered_at', 'contacts.created_at')
  end

  # 🧹 item 342: TODA pessoa que entrou na coluna de agendamento no período
  # (lead novo + base), uma linha por pessoa: [contact_id, 1ª entrada, chegada]
  def booking_people(since, until_at)
    Crm::BookingRate.entries(account, since, until_at, lens: lens)
                    .joins(crm_contact: :contact)
                    .reorder('crm_contact_stage_logs.entered_at')
                    .pluck('crm_contacts.contact_id', 'crm_contact_stage_logs.entered_at', 'contacts.created_at')
                    .uniq(&:first)
  end

  # quem destas pessoas é LEAD NOVO do período (chegou no período pelas portas de entrada)
  def booking_split(since, until_at)
    @booking_split ||= {}
    @booking_split[[since.to_i, until_at.to_i]] ||= begin
      rows = booking_people(since, until_at)
      novos = Crm::BookingRate.entries(account, since, until_at, lens: lens).joins(:crm_contact)
                              .where(crm_contacts: { contact_id: leads(since, until_at).select(:id) })
                              .distinct.pluck('crm_contacts.contact_id').to_set
      { rows: rows, novos: novos & rows.to_set(&:first) }
    end
  end

  def days_between(from, to)
    (to.in_time_zone(TZ).to_date - from.in_time_zone(TZ).to_date).to_i
  end

  def entrada # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    novos = leads.count
    novos_prev = leads(@prev_since, @prev_until).count
    orcamento_ids = budget_contact_ids
    orcamento_prev = budget_contact_ids(@prev_since, @prev_until).size
    # item 342: quem agendou no período, separado em lead novo × base
    cur = booking_split(@since, @until_at)
    prev = booking_split(@prev_since, @prev_until)
    ag_novos = cur[:novos].size
    ag_novos_prev = prev[:novos].size
    ag_total = cur[:rows].size
    ag_total_prev = prev[:rows].size

    rows_novos = cur[:rows].select { |id, _, _| cur[:novos].include?(id) }
    rows_base = cur[:rows].reject { |id, _, _| cur[:novos].include?(id) }
    dias = rows_novos.map { |_, entered, created| days_between(created, entered) }.reject(&:negative?)
    dias_por_id = cur[:rows].to_h { |id, e, c| [id, [days_between(c, e), 0].max] }
    agendaram_ids = rows_novos.map(&:first)
    base_ids = rows_base.map(&:first)

    origem = Crm::PatientKind.origin_inbox_by_contact(account, (leads_ids + base_ids.first(IDS_LIMIT)).uniq)
    canal = Crm::AcquisitionChannel.new(account).for_contacts(leads_ids)
    coluna = Crm::BookingRate.stage(account)&.name
    {
      novos: { valor: novos, anterior: novos_prev },
      orcamento: { valor: orcamento_ids.size, anterior: orcamento_prev, coluna: budget_stage&.name },
      agendaram_novos: { valor: ag_novos, anterior: ag_novos_prev, coluna: coluna,
                         formula: 'Pessoas que CHEGARAM no período pelas portas de entrada (contatos novos) e entraram na coluna ' \
                                  "\"#{coluna || 'Agendamento de Consulta'}\" no período." },
      agendaram_base: { valor: ag_total - ag_novos, anterior: ag_total_prev - ag_novos_prev,
                        formula: 'Pessoas que entraram na coluna de agendamento no período mas NÃO chegaram no período ' \
                                 '(chegaram antes, ou não vieram pelas portas de entrada).' },
      agendaram_total: { valor: ag_total, anterior: ag_total_prev,
                         formula: 'Todas as pessoas (sem repetir) que entraram na coluna de agendamento no período = novos + base.' },
      taxa_agendamento: pct(ag_novos, novos),
      taxa_agendamento_anterior: pct(ag_novos_prev, novos_prev),
      taxa_formula: 'Agendaram (novos) ÷ contatos novos do período — a mesma turma em cima e embaixo.',
      # 📈 item 345b (14/10, "hoje mesmo o total de agendamentos foi 17… gostaria
      # dessa taxa de conversão também"): RENDIMENTO do período = todos que
      # agendaram (novos + base) ÷ contatos novos. Mistura turmas (quem agendou
      # hoje pode ter chegado semana passada) — por isso fica AO LADO da taxa
      # novo → consulta, nunca no lugar dela.
      taxa_geral: pct(ag_total, novos),
      taxa_geral_anterior: pct(ag_total_prev, novos_prev),
      taxa_geral_formula: 'Todos que agendaram no período (novos + base) ÷ contatos novos do período — rendimento: ' \
                          'quantos agendamentos saíram para cada contato novo que entrou.',
      taxa_orcamento: pct(orcamento_ids.size, novos),
      # 4 · tempo até agendar (quem chegou E agendou no período)
      tempo: tempo_json(dias),
      # 3 · coortes fixas: dos que chegaram hoje / 7 dias / 30 dias, quantos já agendaram
      coortes: coortes,
      # item 342: quando chegaram TODOS os que agendaram no período
      safra: safra(cur[:rows], cur[:novos]),
      # item 342: dos que chegaram no período, quantos agendaram — por caixa de entrada
      por_caixa: por_caixa(origem, dias_por_id.slice(*agendaram_ids), novos),
      # de onde vieram (caixa da 1ª conversa) — novos, orçamento, agendaram
      origem: {
        novos: rows_by(leads_ids) { |id| origem[id]&.dig(:name) },
        orcamento: rows_by(orcamento_ids) { |id| origem[id]&.dig(:name) },
        agendaram: rows_by(agendaram_ids) { |id| origem[id]&.dig(:name) },
        agendaram_base: rows_by(base_ids.first(IDS_LIMIT)) { |id| origem[id]&.dig(:name) }
      },
      canal: {
        novos: rows_by(leads_ids) { |id| Crm::AcquisitionChannel::CHANNELS[canal[id]&.channel] },
        agendaram: rows_by(agendaram_ids) { |id| Crm::AcquisitionChannel::CHANNELS[canal[id]&.channel] }
      },
      pessoas: {
        novos: people_json(leads_ids.first(LIST_LIMIT), origem),
        agendaram: people_json(agendaram_ids.first(LIST_LIMIT), origem, dias_por_id: dias_por_id),
        agendaram_base: people_json(base_ids.first(LIST_LIMIT), origem, dias_por_id: dias_por_id)
      }
    }
  end

  def tempo_json(dias)
    return nil if dias.empty?

    {
      amostra: dias.size,
      media_dias: (dias.sum.to_f / dias.size).round(1),
      mediana_dias: dias.sort[dias.size / 2],
      mesmo_dia: dias.count(0),
      ate_7: dias.count { |d| d.between?(1, 7) },
      depois: dias.count { |d| d > 7 }
    }
  end

  # ── item 342 · SAFRA: quando chegaram os que agendaram no período ─────────
  SAFRA = [
    %w[periodo chegou_no_periodo],
    ['periodo_fora', 'Chegou no período, fora das portas de entrada'],
    ['d1_7', '1 a 7 dias antes'], ['d8_30', '8 a 30 dias antes'],
    ['d31_90', '31 a 90 dias antes'], ['d90', 'mais de 90 dias antes (base)']
  ].freeze
  SEMANAS_TOP = 8

  def um_dia?
    (@until_at - @since) <= 1.day + 1.minute
  end

  # quem foi cadastrado dentro do período mas NÃO é lead novo (não veio por uma
  # porta de entrada) tem faixa própria — senão aparecia como "chegou no
  # período" e também como "+ N da base" ao mesmo tempo
  def safra_key(created, dias, novo)
    return (novo ? 'periodo' : 'periodo_fora') if created >= @since
    return 'd1_7' if dias <= 7
    return 'd8_30' if dias <= 30
    return 'd31_90' if dias <= 90

    'd90'
  end

  def safra(rows, novos_ids = Set.new) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
    grupos = Hash.new { |h, k| h[k] = [] }
    semanas = Hash.new { |h, k| h[k] = [] }
    rows.each do |id, entered, created|
      dias = [days_between(created, entered), 0].max
      key = safra_key(created, dias, novos_ids.include?(id))
      grupos[key] << dias
      semanas[created.in_time_zone(TZ).to_date.beginning_of_week] << dias unless key.start_with?('periodo')
    end
    outros = grupos.except('periodo', 'periodo_fora').values.flatten
    por_semana = semanas.map do |ini, lista|
      { label: "sem. de #{ini.strftime('%d/%m/%y')}", inicio: ini.to_s, count: lista.size, media_dias: media(lista) }
    end
    {
      total: rows.size,
      faixas: SAFRA.map do |key, label|
        lista = grupos[key]
        label = um_dia? ? 'Chegou no mesmo dia' : 'Chegou dentro do período' if key == 'periodo'
        { key: key, label: label, count: lista.size, pct: pct(lista.size, rows.size), media_dias: media(lista) }
      end,
      # quem NÃO chegou no período: em média, há quantos dias tinha chegado
      outros: { count: outros.size, media_dias: media(outros), mediana_dias: outros.sort[outros.size / 2] },
      semanas: por_semana.sort_by { |r| [-r[:count], r[:inicio]] }.first(SEMANAS_TOP)
    }
  end

  def media(lista)
    lista.empty? ? nil : (lista.sum.to_f / lista.size).round(1)
  end

  # dos que chegaram no período (universo de leads), por caixa da 1ª conversa:
  # chegaram, agendaram (entraram na coluna no período), % e média de dias
  def por_caixa(origem, dias_dos_agendados, novos_total)
    linhas = leads_ids.group_by { |id| origem[id]&.dig(:name) || 'sem conversa' }.map do |label, ids|
      dias = ids.filter_map { |id| dias_dos_agendados[id] }
      { label: label, chegaram: ids.size, agendaram: dias.size, pct: pct(dias.size, ids.size), media_dias: media(dias) }
    end
    { linhas: linhas.sort_by { |r| [-r[:chegaram], r[:label].to_s] }, parcial: novos_total > IDS_LIMIT }
  end

  def coortes
    now = TZ.now
    { 'hoje' => now.beginning_of_day, 'dias7' => (now - 6.days).beginning_of_day, 'dias30' => (now - 29.days).beginning_of_day }
      .transform_values do |start|
      chegaram = leads(start, now).count
      agendaram = booking_rows(start, now).uniq(&:first).size
      { chegaram: chegaram, agendaram: agendaram, pct: pct(agendaram, chegaram) }
    end
  end

  def rows_by(ids, vazio: 'sem rastro')
    ids.group_by { |id| yield(id).presence || vazio }
       .map { |label, list| { label: label, count: list.size } }
       .sort_by { |r| -r[:count] }
  end

  def people_json(ids, origem, dias_por_id: {})
    return [] if ids.empty?

    account.contacts.where(id: ids).pluck(:id, :name, :phone_number, :created_at).map do |id, name, phone, created|
      { id: id, nome: name.presence || 'Sem nome', telefone: phone, chegou_em: created.iso8601,
        origem: origem[id]&.dig(:name) || 'sem conversa', dias: dias_por_id[id] }
    end
  end

  # ── 6–8 · AGENDA ─────────────────────────────────────────────────────────
  def consultas_periodo
    @consultas_periodo ||= lens.tasks(account.tasks).where(task_type: 'consulta', due_at: @since..@until_at)
  end

  def consultas_ativas
    consultas_periodo.where(canceled_at: nil)
  end

  def agenda # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    todas = consultas_periodo.count
    ativas = consultas_ativas.count
    confirmaram = consultas_ativas.where.not(confirmed_at: nil).count
    recusaram = consultas_ativas.where.not(declined_at: nil).count
    reagendaram = consultas_ativas.where('rescheduled_count > 0').count
    cancelaram = todas - ativas
    compareceram = consultas_ativas.where(attendance: 'attended').count
    faltaram = consultas_ativas.where(attendance: 'missed').count
    pendentes = consultas_ativas.where(attendance: nil).where('due_at < ?', Time.current).count
    {
      ocupacao: ocupacao,
      mix: mix,
      total: todas,
      ativas: ativas,
      confirmaram: confirmaram, taxa_confirmacao: pct(confirmaram, ativas),
      recusaram: recusaram,
      reagendaram: reagendaram, taxa_reagendamento: pct(reagendaram, todas),
      cancelaram: cancelaram, taxa_cancelamento: pct(cancelaram, todas),
      motivos_cancelamento: rows_by(consultas_periodo.where.not(canceled_at: nil).pluck(:cancel_reason)) { |r| r.to_s.strip.presence },
      compareceram: compareceram,
      faltaram: faltaram,
      pendentes: pendentes,
      taxa_comparecimento: pct(compareceram, compareceram + faltaram),
      taxa_falta: pct(faltaram, compareceram + faltaram)
    }
  end

  # 6 · mix do período: avaliação × retorno × pós-op × exames × tele, e os
  # cortes particular e Oftalmofácil (que atravessam os tipos)
  def mix # rubocop:disable Metrics/AbcSize
    ativas = consultas_ativas
    total = ativas.count
    por_tipo = ativas.group(:modality).count.each_with_object(Hash.new(0)) do |(mod, n), h|
      h[mod.presence || 'avaliacao'] += n
    end
    tipos = por_tipo.map { |k, n| { key: k, label: MODALITY_LABELS[k] || k, count: n, pct: pct(n, total) } }.sort_by { |r| -r[:count] }
    particular = ativas.where(particular: true).count
    oftalmo = ativas.where("tasks.external_ref IS NOT NULL AND tasks.external_ref <> '' OR tasks.source = 'oftalmofacil'").count
    {
      total: total,
      tipos: tipos,
      particular: { count: particular, pct: pct(particular, total) },
      oftalmofacil: { count: oftalmo, pct: pct(oftalmo, total) },
      convenio_ou_outro: { count: total - particular, pct: pct(total - particular, total) }
    }
  end

  # 6 · OCUPAÇÃO: horários das janelas dos médicos no período × consultas
  # marcadas (sem exame/retorno/pós-op, que não travam horário). Também por
  # médico (pergunta 14: agenda mais cheia e mais vazia).
  def ocupacao # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @ocupacao ||= begin
      cfg = CrmSetting.find_by(account: account)&.agenda_config || {}
      wins = Crm::AgendaSlots.windows(account)
      blocked_days = Array(cfg['blocked_days']).select { |b| b.is_a?(String) }.to_set
      blocked = Array(cfg['blocked']).to_set { |b| "#{b['date']}|#{b['time']}|#{b['unit']}" }
      from = @since.in_time_zone(TZ).to_date
      to = [@until_at.in_time_zone(TZ).to_date, TZ.now.to_date + 60].min
      por_medico = Hash.new { |h, k| h[k] = { vagas: 0, ocupadas: 0 } }
      total = 0
      ocupadas = 0
      keys = consultas_ativas.where('tasks.modality IS NULL OR tasks.modality NOT IN (?)', ['exames'] + Crm::AgendaSlots::SOFT_MODALITIES)
                             .pluck(:due_at, :unit)
                             .to_set { |due, unit| "#{due.in_time_zone(TZ).strftime('%Y-%m-%d|%H:%M')}|#{unit}" }
      (from..to).each do |day|
        next if day.saturday? || day.sunday? || blocked_days.include?(day.to_s)

        wins.select { |w| w['dow'] == day.wday }.each do |win|
          doc = Crm::DoctorNames.canonical(win['doctor']) || win['doctor'].to_s
          Crm::AgendaSlots.each_slot(win) do |hm|
            next if blocked.include?("#{day}|#{hm}|#{win['unit']}")

            total += 1
            por_medico[doc][:vagas] += 1
            next unless keys.include?("#{day}|#{hm}|#{win['unit']}") || keys.include?("#{day}|#{hm}|")

            ocupadas += 1
            por_medico[doc][:ocupadas] += 1
          end
        end
      end
      {
        vagas: total, ocupadas: [ocupadas, total].min, pct: pct([ocupadas, total].min, total),
        ate: to.to_s,
        por_medico: por_medico.map { |doc, h| { medico: doc, vagas: h[:vagas], ocupadas: h[:ocupadas], pct: pct(h[:ocupadas], h[:vagas]) } }
                              .sort_by { |r| -r[:pct] }
      }
    end
  end

  # ── 9–10 · CIRURGIA E JORNADA ────────────────────────────────────────────
  def cirurgias
    lens.tasks(account.tasks).where(task_type: 'cirurgia', canceled_at: nil)
  end

  def fecharam_scope(since = @since, until_at = @until_at)
    cirurgias.where(created_at: since..until_at)
             .where('EXISTS (SELECT 1 FROM tasks i WHERE i.account_id = tasks.account_id AND i.contact_id = tasks.contact_id ' \
                    "AND i.task_type = 'consulta' AND i.surgery_indication = 'indicated' AND i.due_at <= tasks.created_at)")
  end

  def cirurgia # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    realizadas = consultas_ativas.where(attendance: 'attended')
    compareceram = realizadas.count
    indicadas = realizadas.where(surgery_indication: 'indicated').count
    sem_indicacao = [compareceram - indicadas, 0].max
    fecharam = fecharam_scope.count
    cir = cirurgias.where(due_at: @since..@until_at)
    realizadas_cir = cir.where(attendance: 'attended').or(cir.where(status: :done)).count
    {
      consultas_realizadas: compareceram,
      indicadas: indicadas,
      sem_indicacao: sem_indicacao,
      taxa_indicacao: pct(indicadas, compareceram),
      fecharam: fecharam,
      aguardando: [indicadas - fecharam, 0].max,
      taxa_fechamento: pct(fecharam, indicadas),
      cirurgias_marcadas: cir.count,
      cirurgias_realizadas: realizadas_cir,
      jornada: jornada,
      pessoas: {
        indicadas: realizadas.where(surgery_indication: 'indicated').includes(:contact).limit(LIST_LIMIT).map { |t| task_person(t) },
        fecharam: fecharam_scope.includes(:contact).limit(LIST_LIMIT).map { |t| task_person(t) }
      }
    }
  end

  def task_person(task)
    { id: task.contact_id, nome: task.contact&.name.presence || task.title.to_s, telefone: task.contact&.phone_number || task.phone,
      medico: task.doctor, data: task.due_at&.iso8601 }
  end

  # 10 · linha do tempo da turma que chegou no período (medianas por etapa +
  # média do total até a cirurgia realizada); turma grande demais = só medianas
  def jornada # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if leads.count > IDS_LIMIT

    funil = Crm::FunnelService.new(account).acquisition(@since, @until_at, horizon_days: 365)
    etapas = funil[:steps].map { |s| { key: s[:key], label: s[:label], count: s[:count], pct: s[:pct_first], mediana_dias: s[:median_days] } }
    done = funil.dig(:lists, 'surgery_done', :reached) || []
    totais = done.filter_map do |p|
      a = p.dig(:steps, 'arrived')
      b = p.dig(:steps, 'surgery_done')
      ((Time.zone.parse(b) - Time.zone.parse(a)) / 86_400.0).round(1) if a && b
    end
    {
      etapas: etapas,
      ate_cirurgia: if totais.empty?
                      nil
                    else
                      { amostra: totais.size, media_dias: (totais.sum / totais.size).round(1),
                        mediana_dias: totais.sort[totais.size / 2] }
                    end,
      # pós-operatório: retornos de pós-op marcados para quem operou no período
      pos_op: consultas_ativas.where(modality: 'pos_op').count
    }
  end

  # ── item 342 · VOLUME DO PERÍODO: cada acontecimento um número ────────────
  # "Nunca chamar tudo de agendamento": cada número tem a sua régua (fórmula
  # devolvida para a tela), comparação com o período anterior e quebras.
  QUEBRA_LIMIT = 2000
  REAGENDADA_SQL = Api::V1::Accounts::Crm::AppointmentsController::RESCHEDULED_IN_PERIOD_SQL

  def volumes # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    cur = booking_split(@since, @until_at)
    prev = booking_split(@prev_since, @prev_until)
    [
      volume_agendamentos(cur, prev),
      volume_tasks('reagendamentos', 'Reagendamentos', 'consultas', ->(s, u) { consultas_todas.where(REAGENDADA_SQL, s: s, u: u) },
                   'Consultas que mudaram de dia ou hora no período (carimbo da remarcação — tocar na consulta não conta). ' \
                   'Uma consulta remarcada 2 vezes no período conta 1.'),
      volume_tasks('cancelamentos', 'Cancelamentos', 'consultas', ->(s, u) { consultas_todas.where(canceled_at: s..u) },
                   'Consultas desmarcadas no período (foram para a Lixeira), pela data do cancelamento.', motivo: true),
      volume_tasks('confirmacoes', 'Confirmações', 'consultas', ->(s, u) { consultas_todas.where(confirmed_at: s..u) },
                   'Consultas em que o paciente respondeu SIM ao lembrete no período (pela data da resposta).'),
      volume_tasks('comparecimentos', 'Comparecimentos', 'consultas', ->(s, u) { consultas_do(s, u).where(attendance: 'attended') },
                   'Consultas com data no período marcadas como "Compareceu" na conferência do dia (canceladas fora).'),
      volume_tasks('faltas', 'Faltas', 'consultas', ->(s, u) { consultas_do(s, u).where(attendance: 'missed') },
                   'Consultas com data no período marcadas como "Faltou" na conferência do dia (canceladas fora).'),
      volume_tasks('indicacoes', 'Indicações de cirurgia', 'consultas',
                   ->(s, u) { consultas_do(s, u).where(attendance: 'attended', surgery_indication: 'indicated') },
                   'Consultas com data no período, com presença, em que o médico marcou "indicada cirurgia".', tipo: :indicacao),
      volume_tasks('fechamentos', 'Fechamentos', 'cirurgias', ->(s, u) { fecharam_scope(s, u) },
                   'Cirurgias MARCADAS no período de quem teve indicação numa consulta antes (cirurgia da base sem indicação fica fora).',
                   tipo: :procedimento),
      volume_cirurgias_realizadas
    ]
  end

  def consultas_todas
    lens.tasks(account.tasks).where(task_type: 'consulta').where("tasks.title IS NULL OR tasks.title NOT LIKE '⚠️%'")
  end

  def consultas_do(since, until_at)
    lens.tasks(account.tasks).where(task_type: 'consulta', canceled_at: nil, due_at: since..until_at)
  end

  # consulta NOVA na Agenda (a mesma régua de "Marcadas na Agenda" do Meu Painel, item 217/233)
  def marcadas_na_agenda(since, until_at)
    lens.tasks(account.tasks).bookings.where(task_type: 'consulta', created_at: since..until_at, canceled_at: nil)
        .where('tasks.due_at IS NULL OR tasks.due_at >= tasks.created_at')
        .where("tasks.modality IS NULL OR tasks.modality NOT IN ('teleconsulta', 'exames')")
  end

  def volume_agendamentos(cur, prev) # rubocop:disable Metrics/AbcSize
    ids = cur[:rows].map(&:first)
    origem = Crm::PatientKind.origin_inbox_by_contact(account, ids.first(QUEBRA_LIMIT))
    agenda = marcadas_na_agenda(@since, @until_at)
    {
      key: 'agendamentos', label: 'Novos agendamentos', medida: 'pessoas',
      valor: ids.size, anterior: prev[:rows].size,
      novos: cur[:novos].size, novos_anterior: prev[:novos].size,
      base: ids.size - cur[:novos].size, base_anterior: prev[:rows].size - prev[:novos].size,
      formula: "Pessoas (sem repetir) que entraram na coluna \"#{Crm::BookingRate.stage(account)&.name || 'Agendamento de Consulta'}\" " \
               'no período. Remarcação e carga em massa ficam fora. Novos = chegaram no período pelas portas de entrada; base = o resto.',
      quebras: [
        { titulo: 'Quem é', rows: [{ label: 'Lead novo (chegou no período)', count: cur[:novos].size },
                                   { label: 'Paciente da base', count: ids.size - cur[:novos].size }] },
        { titulo: 'Caixa por onde chegou', rows: rows_by(ids.first(QUEBRA_LIMIT), vazio: 'sem conversa') { |id| origem[id]&.dig(:name) } }
      ],
      extra: [{ label: 'Consultas novas marcadas na Agenda no período (outra régua: conta consultas, não pessoas)', valor: agenda.count }],
      pessoas: people_json(ids.first(LIST_LIMIT), origem)
    }
  end

  def volume_tasks(key, label, medida, scope_for, formula, motivo: false, tipo: :modalidade) # rubocop:disable Metrics/ParameterLists
    scope = scope_for.call(@since, @until_at)
    tasks = scope.includes(:contact).limit(QUEBRA_LIMIT).to_a
    {
      key: key, label: label, medida: medida,
      valor: scope.count, anterior: scope_for.call(@prev_since, @prev_until).count,
      # sem cadastro (consulta sem paciente ligado) conta como 1 pessoa cada
      pessoas_distintas: scope.where.not(contact_id: nil).distinct.count(:contact_id) + scope.where(contact_id: nil).count,
      formula: formula,
      quebras: task_quebras(tasks, motivo: motivo, tipo: tipo),
      pessoas: tasks.first(LIST_LIMIT).map { |t| task_person(t) }
    }
  end

  def task_quebras(tasks, motivo: false, tipo: :modalidade) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    origem = Crm::PatientKind.origin_inbox_by_contact(account, tasks.map(&:contact_id))
    tipo_de = lambda do |t|
      case tipo
      when :indicacao then t.indicated_procedure.presence || 'procedimento não informado'
      when :procedimento then t.procedure.presence || t.title.to_s.sub(/\ACirurgia:\s*/i, '').split(' - ').first
      else MODALITY_LABELS[t.modality.presence || 'avaliacao'] || t.modality
      end
    end
    out = [
      { titulo: 'Caixa por onde chegou',
        rows: rows_by(tasks) { |t| t.contact_id ? origem[t.contact_id]&.dig(:name) || 'sem conversa' : 'sem cadastro' } },
      { titulo: 'Unidade', rows: rows_by(tasks, vazio: 'sem unidade') { |t| Crm::AgendaSlots::UNIT_LABELS[t.unit] || t.unit } },
      { titulo: 'Médico', rows: rows_by(tasks, vazio: 'sem médico') { |t| Crm::DoctorNames.canonical(t.doctor) || t.doctor } },
      { titulo: tipo == :modalidade ? 'Tipo' : 'Procedimento', rows: rows_by(tasks, vazio: 'sem tipo') { |t| tipo_de.call(t) } }
    ]
    out << { titulo: 'Motivo', rows: rows_by(tasks, vazio: 'sem motivo') { |t| t.cancel_reason.to_s.strip } } if motivo
    out.select { |q| q[:rows].any? }
  end

  # cirurgia REALIZADA de fato = o paciente passou por uma coluna "Cirurgia
  # Realizada" em qualquer funil que a lente enxerga (casa e/ou parceiros)
  SURGERY_DONE_STAGE = /cirurgia\s+realizada/i

  def surgery_done_stage_ids
    @surgery_done_stage_ids ||= begin
      pipelines = account.crm_pipelines.includes(:stages).select { |pipeline| lens_sees_pipeline?(pipeline) }
      pipelines.flat_map { |pipeline| pipeline.stages.select { |st| st.name.to_s.match?(SURGERY_DONE_STAGE) } }.map(&:id)
    end
  end

  # funil que nenhuma fonte pegou = da casa (a lente da casa e "tudo" enxergam todos eles)
  def lens_sees_pipeline?(pipeline)
    owner = Crm::Sources.map(account)['pipelines'][pipeline.id.to_s]
    owner.nil? ? (lens.all? || lens.own?) : lens.sees_source?(owner)
  end

  def surgery_done_logs(since, until_at)
    return Crm::StageLog.none if surgery_done_stage_ids.empty?

    lens.stage_logs(Crm::StageLog.where(stage_id: surgery_done_stage_ids, event_type: Crm::StageLogBulk::ENTERED, entered_at: since..until_at))
  end

  def volume_cirurgias_realizadas # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    rows = surgery_done_logs(@since, @until_at).joins(crm_contact: :pipeline).reorder('crm_contact_stage_logs.entered_at')
                                               .limit(QUEBRA_LIMIT).pluck('crm_contacts.contact_id', 'crm_pipelines.name').uniq(&:first)
    ids = rows.map(&:first)
    prev = surgery_done_logs(@prev_since, @prev_until).joins(:crm_contact).distinct.count('crm_contacts.contact_id')
    origem = Crm::PatientKind.origin_inbox_by_contact(account, ids)
    funil = rows.to_h
    cir = cirurgias.where(due_at: @since..@until_at)
    {
      key: 'cirurgias_realizadas', label: 'Cirurgias realizadas', medida: 'pessoas',
      valor: surgery_done_logs(@since, @until_at).joins(:crm_contact).distinct.count('crm_contacts.contact_id'), anterior: prev,
      formula: 'Pessoas (sem repetir) que entraram numa coluna "Cirurgia Realizada" no período, em qualquer funil desta fonte ' \
               '(CEVICO e/ou Oftalmofácil, conforme a chavinha). Carga em massa fica fora.',
      sem_coluna: surgery_done_stage_ids.empty?,
      quebras: [
        { titulo: 'Funil', rows: rows_by(ids) { |id| funil[id] } },
        { titulo: 'Caixa por onde chegou', rows: rows_by(ids, vazio: 'sem conversa') { |id| origem[id]&.dig(:name) } }
      ].select { |q| q[:rows].any? },
      extra: [{ label: 'Na Agenda: cirurgias com data no período marcadas como realizadas',
                valor: cir.where(attendance: 'attended').or(cir.where(status: :done)).count }],
      pessoas: people_json(ids.first(LIST_LIMIT), origem)
    }
  end

  # ── 11–13 · DINHEIRO (só admin) ─────────────────────────────────────────
  def dinheiro # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    cac = Crm::AcquisitionCostService.new(account: account, since: @since, until_at: @until_at).call
    resumo = cac[:summary]
    canais = cac[:channels].map do |c|
      c.merge(ticket_medio: c[:patients].to_i.positive? ? (c[:revenue].to_f / c[:patients]).round(2) : nil)
    end
    gastos = cac[:spend]
    medicos_rows = doctors_rows
    leads_total = leads.count
    agendaram = booking_split(@since, @until_at)[:rows].size
    compareceram = consultas_ativas.where(attendance: 'attended').count
    indicadas = consultas_ativas.where(attendance: 'attended', surgery_indication: 'indicated').count
    cir = cirurgias.where(due_at: @since..@until_at)
    realizadas = cir.where(attendance: 'attended').or(cir.where(status: :done)).count
    {
      cac_total: resumo[:cac_total],
      cac_ads: resumo[:cac_ads],
      cpl_ads: resumo[:cpl_ads],
      pacientes: resumo[:patients],
      faturamento: resumo[:revenue],
      roas: resumo[:roas_total],
      ticket_medio: resumo[:patients].to_i.positive? ? (resumo[:revenue].to_f / resumo[:patients]).round(2) : nil,
      canais: canais,
      ticket_por_medico: medicos_rows.map do |r|
        ticket = r[:conversions].positive? ? (r[:revenue].to_f / r[:conversions]).round(2) : nil
        { medico: r[:doctor], ticket_medio: ticket, fechamentos: r[:conversions], faturamento: r[:revenue] }
      end,
      # (o serviço do CAC devolve cada gasto com detalhes; aqui só o número em R$)
      gastos: { google: gastos.dig(:google, :cost).to_f.round(2), meta: gastos.dig(:meta, :spend).to_f.round(2),
                whatsapp: gastos.dig(:whatsapp, :brl).to_f.round(2), ia: gastos.dig(:ia, :brl).to_f.round(2),
                anuncios: gastos[:ads].to_f.round(2), total: gastos[:total].to_f.round(2),
                avisos: [gastos.dig(:google, :error), gastos.dig(:meta, :error)].compact },
      historico: cac[:monthly],
      # 13 · conversões de cirurgia (cirurgias REALIZADAS no período sobre cada base do período)
      conversoes: {
        por_lead: pct(realizadas, leads_total),
        por_agendamento: pct(realizadas, agendaram),
        por_comparecimento: pct(realizadas, compareceram),
        por_indicacao: pct(realizadas, indicadas),
        cirurgias_realizadas: realizadas
      }
    }
  end

  # ── 14 · MÉDICOS (só admin) ──────────────────────────────────────────────
  def medicos
    ocup = ocupacao[:por_medico].index_by { |r| r[:medico] }
    doctors_rows.map do |r|
      o = ocup[r[:doctor]]
      r.merge(ocupacao: o ? o[:pct] : nil, vagas: o&.dig(:vagas), ocupadas: o&.dig(:ocupadas))
    end
  end

  # espelho enxuto do ranking de Relatórios → Médicos (mesma normalização de nome)
  def doctors_rows # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
    @doctors_rows ||= begin
      scope = consultas_ativas.where.not(doctor: [nil, ''])
      variants = scope.distinct.pluck(:doctor).group_by { |raw| Crm::DoctorNames.canonical(raw) }
      variants.delete(nil)
      rows = variants.map do |doc, raw_names|
        d = scope.where(doctor: raw_names)
        attended = d.where(attendance: 'attended').count
        missed = d.where(attendance: 'missed').count
        indicated = d.where(surgery_indication: 'indicated').where.not(contact_id: nil).limit(300).to_a
        booked_ids = cirurgias.where(contact_id: indicated.map(&:contact_id).uniq).distinct.pluck(:contact_id).to_set
        closed = indicated.select { |t| booked_ids.include?(t.contact_id) }
        revenue = closed.sum { |t| Crm::Contact.where(contact_id: t.contact_id).maximum(:value).to_f }
        {
          doctor: doc, consultations: d.count, attended: attended, missed: missed,
          show_rate: pct(attended, attended + missed),
          indications: indicated.size, indication_rate: pct(indicated.size, attended),
          conversions: closed.size, conversion_rate: pct(closed.size, indicated.size),
          revenue: revenue.round
        }
      end
      rows.sort_by { |r| [-r[:conversion_rate], -r[:consultations]] }
    end
  end
end
