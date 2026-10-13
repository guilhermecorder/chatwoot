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
    agendaram = Crm::BookingRate.entries(account, @since, @until_at, lens: lens)
                                .group(bucket.call('crm_contact_stage_logs.entered_at')).count
    consultas = consultas_ativas.group(bucket.call('tasks.due_at')).count
    compareceram = consultas_ativas.where(attendance: 'attended').group(bucket.call('tasks.due_at')).count
    {
      balde: por_mes ? 'mes' : 'dia',
      rotulos: chaves.map { |k| por_mes ? "#{k[5, 2]}/#{k[2, 2]}" : "#{k[8, 2]}/#{k[5, 2]}" },
      novos: chaves.map { |k| novos[k].to_i },
      agendaram: chaves.map { |k| agendaram[k].to_i },
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

  def days_between(from, to)
    (to.in_time_zone(TZ).to_date - from.in_time_zone(TZ).to_date).to_i
  end

  def entrada # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    novos = leads.count
    novos_prev = leads(@prev_since, @prev_until).count
    orcamento_ids = budget_contact_ids
    orcamento_prev = budget_contact_ids(@prev_since, @prev_until).size
    agendaram = Crm::BookingRate.count(account, @since, @until_at, lens: lens)
    agendaram_prev = Crm::BookingRate.count(account, @prev_since, @prev_until, lens: lens)

    rows = booking_rows(@since, @until_at).uniq(&:first)
    dias = rows.map { |_, entered, created| days_between(created, entered) }.reject(&:negative?)
    agendaram_ids = rows.map(&:first)

    origem = Crm::PatientKind.origin_inbox_by_contact(account, leads_ids)
    canal = Crm::AcquisitionChannel.new(account).for_contacts(leads_ids)
    {
      novos: { valor: novos, anterior: novos_prev },
      orcamento: { valor: orcamento_ids.size, anterior: orcamento_prev, coluna: budget_stage&.name },
      agendaram: { valor: agendaram, anterior: agendaram_prev, coluna: Crm::BookingRate.stage(account)&.name },
      taxa_agendamento: pct(agendaram, novos),
      taxa_agendamento_anterior: pct(agendaram_prev, novos_prev),
      taxa_orcamento: pct(orcamento_ids.size, novos),
      # 4 · tempo até agendar (quem chegou E agendou no período)
      tempo: if dias.empty?
               nil
             else
               {
                 amostra: dias.size,
                 media_dias: (dias.sum.to_f / dias.size).round(1),
                 mediana_dias: dias.sort[dias.size / 2],
                 mesmo_dia: dias.count(0),
                 ate_7: dias.count { |d| d.between?(1, 7) },
                 depois: dias.count { |d| d > 7 }
               }
             end,
      # 3 · coortes fixas: dos que chegaram hoje / 7 dias / 30 dias, quantos já agendaram
      coortes: coortes,
      # de onde vieram (caixa da 1ª conversa) — novos, orçamento, agendaram
      origem: {
        novos: rows_by(leads_ids) { |id| origem[id]&.dig(:name) },
        orcamento: rows_by(orcamento_ids) { |id| origem[id]&.dig(:name) },
        agendaram: rows_by(agendaram_ids) { |id| origem[id]&.dig(:name) }
      },
      canal: {
        novos: rows_by(leads_ids) { |id| Crm::AcquisitionChannel::CHANNELS[canal[id]&.channel] },
        agendaram: rows_by(agendaram_ids) { |id| Crm::AcquisitionChannel::CHANNELS[canal[id]&.channel] }
      },
      pessoas: {
        novos: people_json(leads_ids.first(LIST_LIMIT), origem),
        agendaram: people_json(agendaram_ids.first(LIST_LIMIT), origem, dias_por_id: rows.to_h { |id, e, c| [id, days_between(c, e)] })
      }
    }
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

  def rows_by(ids)
    ids.group_by { |id| yield(id).presence || 'sem rastro' }
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

  def fecharam_scope
    cirurgias.where(created_at: @since..@until_at)
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
    agendaram = Crm::BookingRate.count(account, @since, @until_at, lens: lens)
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
