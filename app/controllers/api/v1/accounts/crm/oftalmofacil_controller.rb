# 🏥 item 229 (24/09): ambiente "Oftalmofácil" DENTRO do sistema — o espelho
# do hub (cevico_oftalmofacil_surgeries) lido do nosso banco, no design da
# casa. Só leitura: nada aqui escreve no banco do Oftalmofácil.
#   overview → parceiros, meses, clínicas, tipos e a SAÚDE DA AGENDA
#   items    → lista com filtros + estado de cada item na nossa Agenda/CRM
#   show     → ficha completa de um item (raw só para admin)
class Api::V1::Accounts::Crm::OftalmofacilController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  PER_MAX = 500

  def overview # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    scope = period_scope
    by_status = scope.group(:provider_name, :status_kind).count
    partners = {}
    by_status.each do |(provider, kind), n|
      p = (partners[provider.to_s] ||= blank_partner(provider))
      p[:total] += n
      p[kind.to_s.to_sym] = n if p.key?(kind.to_s.to_sym)
    end
    tasks_by_partner = Current.account.tasks.where(source: 'oftalmofacil', external_ref: scope.select(:item_token))
                              .group(:source_detail).count
    tasks_by_partner.each do |detail, n|
      key = detail.presence || own_name(partners.keys)
      (partners[key] ||= blank_partner(key))[:with_task] = n
    end
    if admin?
      scope.faturaveis.group(:provider_name).sum(:amount).each { |prov, v| (partners[prov.to_s] ||= blank_partner(prov))[:amount] = v.to_f }
      scope.realizadas.group(:provider_name).sum(:amount).each { |prov, v| (partners[prov.to_s] ||= blank_partner(prov))[:amount_done] = v.to_f }
    end
    months = scope.group("to_char(surgery_date, 'YYYY-MM')").count
    months_done = scope.realizadas.group("to_char(surgery_date, 'YYYY-MM')").count
    # 24/09 (pedido dele): REPRESENTATIVIDADE — procedimentos e clínicas por volume,
    # e o recorte de procedimentos dentro de cada clínica e de cada parceiro
    partner_procs = top_by(scope.group(:provider_name, :procedure_name).count)
    partners.each_value { |p| p[:top_procedures] = partner_procs[p[:name]] || [] }
    clinic_status = scope.group(:clinic_name, :status_kind).count
    clinic_procs = top_by(scope.group(:clinic_name, :procedure_name).count)
    clinics = scope.group(:clinic_name).count.map do |name, n|
      st = ->(k) { clinic_status[[name, k]] || 0 }
      { name: name.presence || '(sem clínica)', total: n, unit: unit_for(name), realizada: st.call('realizada'),
        agendada: st.call('agendada') + st.call('aguardando_pagamento'), cancelada: st.call('cancelada'), ausente: st.call('ausente'),
        top_procedures: clinic_procs[name] || [] }
    end
    render json: {
      period: { from: period_from.iso8601, to: period_to.iso8601 },
      totals: scope.group(:status_kind).count.merge('total' => scope.count),
      partners: partners.values.sort_by { |p| [p[:own] ? 0 : 1, -p[:total]] },
      months: months.keys.sort.map { |m| { month: m, total: months[m], realizada: months_done[m] || 0 } },
      clinics: clinics.sort_by { |c| -c[:total] },
      procedures: procedures_json(scope),
      types: scope.group(:procedure_type).count.map { |name, n| { name: name.presence || '(sem tipo)', total: n } }.sort_by { |t| -t[:total] },
      agenda: agenda_health,
      sync: sync_json
    }
  end

  def items # rubocop:disable Metrics/AbcSize
    scope = filtered_scope
    total = scope.count
    per = params[:per].to_i.clamp(1, PER_MAX)
    per = 50 if params[:per].blank?
    page = [params[:page].to_i, 1].max
    rows = scope.order(surgery_date: :desc, surgery_hour: :desc, id: :desc).offset((page - 1) * per).limit(per).to_a
    tasks = Current.account.tasks.where(external_ref: rows.map(&:item_token)).index_by(&:external_ref)
    contacts = ::Contact.where(id: rows.filter_map(&:contact_id)).index_by(&:id)
    cards = Crm::Contact.includes(:stage, :pipeline).joins(:pipeline)
                        .where(crm_pipelines: { account_id: Current.account.id }, contact_id: contacts.keys)
                        .order('crm_pipelines.position').group_by(&:contact_id)
    render json: {
      total: total, page: page, per: per,
      rows: rows.map { |s| item_json(s, tasks[s.item_token], contacts[s.contact_id], cards[s.contact_id]&.first) }
    }
  end

  # pacientes do hub (agrupados): quem é, quantos itens, próximo/último, de que parceiro(s)
  def patients # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    scope = filtered_scope
    per = params[:per].blank? ? 50 : params[:per].to_i.clamp(1, PER_MAX)
    page = [params[:page].to_i, 1].max
    total = scope.distinct.count('(patient_name, patient_phone, contact_id)')
    groups = scope.group(:patient_name, :patient_phone, :contact_id)
                  .select(<<~SQL.squish)
                    patient_name, patient_phone, contact_id, COUNT(*) AS total,
                    MIN(surgery_date) AS first_date, MAX(surgery_date) AS last_date,
                    MAX(CASE WHEN surgery_date >= CURRENT_DATE
                             AND status_kind IN ('agendada', 'aguardando_pagamento') THEN 1 ELSE 0 END) AS has_upcoming,
                    STRING_AGG(DISTINCT COALESCE(provider_name, ''), ' · ') AS providers
                  SQL
                  .order(Arel.sql('MAX(surgery_date) DESC NULLS LAST, patient_name ASC'))
                  .offset((page - 1) * per).limit(per).to_a
    contacts = ::Contact.where(id: groups.filter_map(&:contact_id)).index_by(&:id)
    render json: {
      total: total, page: page, per: per,
      rows: groups.map do |g|
        c = contacts[g.contact_id]
        { patient_name: g.patient_name, patient_phone: g.patient_phone, total: g.total.to_i,
          first_date: g.first_date, last_date: g.last_date, has_upcoming: g.has_upcoming.to_i == 1,
          providers: g.providers.to_s.split(' · ').compact_blank, own: g.providers.to_s.split(' · ').any? { |n| own_provider?(n) },
          contact: c ? { id: c.id, name: c.name, phone: c.phone_number } : nil }
      end
    }
  end

  def show # rubocop:disable Metrics/AbcSize
    s = mirror.find(params[:id])
    task = Current.account.tasks.find_by(external_ref: s.item_token)
    contact = s.contact_id && ::Contact.find_by(id: s.contact_id)
    card = contact && Crm::Contact.includes(:stage, :pipeline).joins(:pipeline)
                                  .where(crm_pipelines: { account_id: Current.account.id }, contact_id: contact.id)
                                  .order('crm_pipelines.position').first
    payload = item_json(s, task, contact, card)
    payload[:raw] = s.raw if admin?
    payload[:match_via] = s.match_via
    payload[:applied_action] = s.applied_action
    payload[:applied_at] = s.applied_at
    render json: payload
  end

  # 🔎 item 249 (26/09): CONFERÊNCIA DO DIA — cada item marcado no hub para a
  # data × o que está na nossa Agenda, com o motivo em palavras simples.
  # ?date=AAAA-MM-DD (padrão: próximo dia útil) · ?hub=1 consulta o banco do
  # hub (só leitura) para achar item que o incremental nunca leu.
  def day_check
    date = safe_date(params[:date]) || Crm::OftalmofacilDayCheck.default_date
    render json: Crm::OftalmofacilDayCheck.new(account: Current.account, date: date, config: of_config)
                                          .report(hub: params[:hub].to_s == '1')
  end

  # traz para a Agenda o que faltou no dia (só admin; nada muda no hub)
  def reconcile_day
    return render json: { error: 'Apenas administradores.' }, status: :forbidden unless admin?

    date = safe_date(params[:date]) || Crm::OftalmofacilDayCheck.default_date
    render json: Crm::OftalmofacilDayCheck.new(account: Current.account, date: date, config: of_config).reconcile!
  end

  private

  def admin?
    Current.account_user.administrator?
  end

  def of_config
    @of_config ||= (CrmSetting.find_by(account: Current.account)&.agenda_config || {})['oftalmofacil'] || {}
  end

  def own_provider?(name)
    own = of_config['provider_name'].to_s.strip.downcase
    own.present? && name.to_s.downcase.include?(own)
  end

  def own_name(names)
    names.find { |n| own_provider?(n) } || of_config['provider_name'].to_s
  end

  def blank_partner(name)
    { name: name.to_s, own: own_provider?(name), total: 0, agendada: 0, realizada: 0, cancelada: 0, ausente: 0,
      aguardando_pagamento: 0, with_task: 0, amount: nil, amount_done: nil }
  end

  def mirror
    Crm::OftalmofacilSurgery.where(account_id: Current.account.id)
  end

  # ── período (a régua manda from/to sempre) ──
  def period_from
    @period_from ||= safe_date(params[:from]) || Date.current.beginning_of_month
  end

  def period_to
    @period_to ||= safe_date(params[:to]) || Date.current.end_of_month
  end

  def safe_date(value)
    value.present? ? Date.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end

  def period_scope
    mirror.where(surgery_date: period_from..period_to)
  end

  # ── filtros da lista ──
  def filtered_scope # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    scope = mirror
    scope = scope.where(surgery_date: period_from..period_to) if params[:from].present? || params[:to].present?
    scope = scope.where(provider_name: params[:partner]) if params[:partner].present?
    scope = scope.where(clinic_name: params[:clinic]) if params[:clinic].present?
    scope = scope.where(status_kind: params[:status]) if params[:status].present?
    scope = scope.where(procedure_type: params[:type]) if params[:type].present?
    scope = scope.where(contact_id: nil) if params[:unmatched] == 'true'
    if params[:side] == 'own'
      scope = scope.where('LOWER(provider_name) LIKE ?', "%#{of_config['provider_name'].to_s.downcase}%")
    elsif params[:side] == 'partners'
      scope = scope.where.not('LOWER(provider_name) LIKE ?', "%#{of_config['provider_name'].to_s.downcase}%")
    end
    if params[:agenda].present?
      with = Current.account.tasks.where(source: 'oftalmofacil').select(:external_ref)
      scope = params[:agenda] == 'with' ? scope.where(item_token: with) : scope.where.not(item_token: with)
    end
    if params[:q].present?
      q = params[:q].to_s.strip
      digits = q.gsub(/\D/, '')
      scope = if digits.length >= 4 && digits.length == q.length
                scope.where('patient_phone LIKE ? OR patient_cpf LIKE ?', "%#{digits}%", "%#{digits}%")
              else
                scope.where('patient_name ILIKE ?', "%#{q}%")
              end
    end
    scope
  end

  # a nossa Agenda está "assentada"? o que falta para o hub virar agenda de verdade
  def agenda_health # rubocop:disable Metrics/AbcSize
    upcoming = mirror.where(status_kind: %w[agendada aguardando_pagamento]).where('surgery_date >= ?', Date.current)
    with_task = Current.account.tasks.where(source: 'oftalmofacil', external_ref: upcoming.select(:item_token))
    {
      upcoming: upcoming.count,
      with_task: with_task.count,
      without_task: upcoming.count - with_task.count,
      task_without_unit: with_task.where(unit: [nil, '']).count,
      task_without_doctor: with_task.where(doctor: [nil, '']).count,
      unmatched_contacts: upcoming.where(contact_id: nil).count,
      past_still_scheduled: mirror.where(status_kind: %w[agendada aguardando_pagamento]).where('surgery_date < ?', Date.current - 7).count,
      clinics_unmapped: upcoming.where.not(clinic_name: [nil, '']).distinct.pluck(:clinic_name).reject { |c| unit_for(c).present? }
    }
  end

  # { chave => [{ name, total }, ...] } com os 5 maiores de cada chave
  def top_by(grouped, limit = 5)
    out = Hash.new { |h, k| h[k] = [] }
    grouped.each { |(key, name), n| out[key] << { name: name.presence || '(sem procedimento)', total: n } }
    out.transform_values { |list| list.sort_by { |x| -x[:total] }.first(limit) }
  end

  def procedures_json(scope)
    done = scope.realizadas.group(:procedure_name).count
    scope.group(:procedure_name).count.map { |name, n| { name: name.presence || '(sem procedimento)', total: n, realizada: done[name] || 0 } }
         .sort_by { |x| -x[:total] }
  end

  def unit_for(clinic_name)
    map = of_config['clinics'] || {}
    return nil if clinic_name.blank?

    key = clinic_name.to_s.strip.downcase
    hit = map.find { |name, _u| name.to_s.strip.downcase == key }
    hit && hit[1].presence
  end

  def doctor_name(crm)
    (of_config['doctors'] || {})[crm.to_s.gsub(/\D/, '')].presence
  end

  def sync_json
    {
      enabled: of_config['enabled'] == true, partners_enabled: of_config['partners_enabled'] == true,
      agenda_enabled: of_config['agenda_enabled'] == true, agenda_from: of_config['agenda_from'],
      partner_pipeline_id: of_config['partner_pipeline_id'], last_sync_at: of_config['last_sync_at'],
      last_run_at: of_config['last_run_at'], mirror_count: mirror.count, own_provider: of_config['provider_name']
    }
  end

  def item_json(s, task, contact, card) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/MethodParameterName
    {
      id: s.id, item_token: s.item_token,
      patient_name: s.patient_name, patient_phone: s.patient_phone, patient_email: s.patient_email,
      patient_cpf: admin? ? s.patient_cpf : nil,
      provider_name: s.provider_name, own: own_provider?(s.provider_name),
      clinic_name: s.clinic_name, unit: unit_for(s.clinic_name),
      doctor_crm: s.doctor_crm, doctor: doctor_name(s.doctor_crm),
      procedure_name: s.procedure_name, procedure_type: s.procedure_type, eye: s.eye,
      status_kind: s.status_kind, status_label: s.status_label, status_kind_label: s.status_kind_label,
      surgery_date: s.surgery_date, surgery_hour: s.hour_hhmm,
      amount: admin? ? s.amount : nil, paid_amount: admin? ? s.paid_amount : nil,
      of_created_at: s.of_created_at, of_modified_at: s.of_modified_at,
      contact: contact ? { id: contact.id, name: contact.name, phone: contact.phone_number } : nil,
      card: card ? { id: card.id, stage: card.stage&.name, stage_color: card.stage&.color, pipeline: card.pipeline&.name } : nil,
      task: if task
              { id: task.id, unit: task.unit, doctor: task.doctor, due_at: task.due_at, attendance: task.attendance,
                canceled: task.canceled_at.present?, status: task.status, task_type: task.task_type }
            end
    }
  end
end
