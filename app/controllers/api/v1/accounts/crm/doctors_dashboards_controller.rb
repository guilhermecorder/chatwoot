# Dashboard dos Médicos (análise do gestor): desempenho de cada médico em
# consultas realizadas, indicações de cirurgia, CONVERSÃO em cirurgia
# (indicados que viraram cirurgia marcada — match por telefone) e NPS dos
# pacientes que ele atendeu. Traz também o volume de cirurgias por clínica
# parceira (IOP, Ocular Surgery...). Fonte: Agenda (tasks) + contatos.
class Api::V1::Accounts::Crm::DoctorsDashboardsController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  def show
    since, until_at = resolve_range

    render json: {
      period: params[:preset].presence || 'month',
      doctors: doctors_rows(since, until_at),
      surgeries_by_clinic: surgeries_by_clinic(since, until_at),
      consultations_by_unit: consultations_by_unit(since, until_at)
    }
  end

  private

  def account
    Current.account
  end

  def resolve_range
    now = TZ.now
    case params[:preset]
    when 'week'  then [now.beginning_of_week.beginning_of_day, now.end_of_week.end_of_day]
    when 'year'  then [now.beginning_of_year.beginning_of_day, now.end_of_year.end_of_day]
    when 'all'   then [Time.zone.at(0), now.end_of_day]
    when 'last_month' then [now.last_month.beginning_of_month, now.last_month.end_of_month]
    else [now.beginning_of_month.beginning_of_day, now.end_of_month.end_of_day] # mês (padrão)
    end
  end

  def consultas(since, until_at)
    account.tasks.where(task_type: 'consulta', canceled_at: nil, due_at: since..until_at)
  end

  def cirurgias_range(since, until_at)
    account.tasks.where(task_type: 'cirurgia', canceled_at: nil, due_at: since..until_at)
  end

  # SÓ os 3 médicos da casa. O campo doctor é texto livre (a IA preenche
  # variações: "Roberta Negri", "Dra Roberta Negri"...) — cada variação é
  # normalizada pelo sobrenome/nome e AGREGADA no médico oficial; nomes de
  # fora (ex. médico citado no script) ficam fora do ranking.
  def canonical_doctor(raw)
    Crm::DoctorNames.canonical(raw)
  end

  def doctors_rows(since, until_at)
    scope = consultas(since, until_at).where.not(doctor: [nil, ''])
    variants = scope.distinct.pluck(:doctor).group_by { |raw| canonical_doctor(raw) }
    variants.delete(nil) # quem não é da casa sai do ranking

    rows = variants.map do |doc, raw_names|
      d_scope = scope.where(doctor: raw_names)
      attended = d_scope.where(attendance: 'attended').count
      missed = d_scope.where(attendance: 'missed').count
      indicated = d_scope.where(surgery_indication: 'indicated').limit(300).to_a
      infos = conversion_infos(indicated)
      conversions = infos.count { |i| i[:booked] }
      # 💰 faturamento gerado pela indicação: soma dos fechamentos dos
      # pacientes indicados por este médico que viraram cirurgia
      revenue = infos.select { |i| i[:booked] }.sum { |i| i[:value] }
      nps_scores = nps_scores_for(d_scope.where(attendance: 'attended'))
      # cirurgias também podem vir com grafia variada do médico
      surgery_names = cirurgias_range(since, until_at).where.not(doctor: [nil, ''])
                                                      .distinct.pluck(:doctor)
                                                      .select { |raw| canonical_doctor(raw) == doc }
      surgeries_done_scope = cirurgias_range(since, until_at).where(doctor: surgery_names)

      {
        doctor: doc,
        consultations: d_scope.count,
        attended: attended,
        missed: missed,
        show_rate: pct(attended, attended + missed),
        indications: indicated.size,
        indication_rate: pct(indicated.size, attended),
        conversions: conversions,
        conversion_rate: pct(conversions, indicated.size),
        revenue: revenue.round,
        surgeries_done: surgeries_done_scope.where(attendance: 'attended').or(surgeries_done_scope.where(status: :done)).count,
        nps_avg: nps_scores.any? ? (nps_scores.sum.to_f / nps_scores.size).round(1) : nil,
        nps_count: nps_scores.size
      }
    end
    # ranking: quem mais converte consulta em cirurgia
    rows.sort_by { |r| [-r[:conversion_rate], -r[:conversions], -r[:consultations]] }
  end

  # volume de cirurgias em cada clínica parceira (IOP, Ocular Surgery...)
  def surgeries_by_clinic(since, until_at)
    locations = CrmSetting.find_by(account: account)&.agenda_config&.dig('surgery_locations') || []
    labels = locations.to_h { |l| [l['key'], l['label']] }

    scope = cirurgias_range(since, until_at)
    scope.group(:unit).count.map do |unit, count|
      done_scope = scope.where(unit: unit)
      # NPS dos pacientes que OPERARAM nesta clínica → performance do ambiente
      nps_scores = nps_scores_for(done_scope.where(attendance: 'attended').or(done_scope.where(status: :done)))
      {
        key: unit.presence || 'sem_local',
        label: labels[unit] || unit.presence || 'Sem local definido',
        count: count,
        done: done_scope.where(attendance: 'attended').or(done_scope.where(status: :done)).count,
        nps_avg: nps_scores.any? ? (nps_scores.sum.to_f / nps_scores.size).round(1) : nil,
        nps_count: nps_scores.size
      }
    end.sort_by { |c| -c[:count] }
  end

  # volume de consultas + comparecimento por UNIDADE (Tatuapé / Av. Paulista)
  UNIT_LABELS = { 'tatuape' => 'Tatuapé', 'paulista' => 'Av. Paulista' }.freeze

  def consultations_by_unit(since, until_at)
    scope = consultas(since, until_at)
    scope.group(:unit).count.map do |unit, count|
      u_scope = scope.where(unit: unit)
      attended = u_scope.where(attendance: 'attended').count
      missed = u_scope.where(attendance: 'missed').count
      {
        key: unit.presence || 'sem_unidade',
        label: UNIT_LABELS[unit] || unit.presence || 'Sem unidade',
        count: count,
        attended: attended,
        missed: missed,
        show_rate: pct(attended, attended + missed)
      }
    end.sort_by { |c| -c[:count] }
  end

  # os indicados viraram cirurgia? e por quanto fecharam? Fase 0: tudo em
  # LOTE pelo contact_id (3 queries no total) — o regexp de telefone em loop
  # ficou só como fallback dos registros antigos que não casaram no backfill.
  def conversion_infos(indicated)
    linked, legacy = indicated.partition { |t| t.contact_id.present? }

    booked_ids = account.tasks.where(task_type: 'cirurgia', canceled_at: nil)
                        .where(contact_id: linked.map(&:contact_id).uniq)
                        .distinct.pluck(:contact_id).to_set
    contacts = account.contacts.where(id: booked_ids.to_a).index_by(&:id)
    cards = Crm::Contact.joins(:pipeline)
                        .where(crm_pipelines: { account_id: account.id }, contact_id: booked_ids.to_a)
                        .group_by(&:contact_id)

    infos = linked.map do |t|
      next { booked: false, value: 0.0 } unless booked_ids.include?(t.contact_id)

      contact = contacts[t.contact_id]
      value = contact&.additional_attributes&.dig('surgery_closing', 'value').to_f
      value = cards[t.contact_id]&.first&.value.to_f if value.zero?
      { booked: true, value: value }
    end
    infos + legacy.map { |t| legacy_conversion_info(t.phone) }
  end

  # fallback (registro antigo sem contact_id): match por telefone, um a um
  def legacy_conversion_info(phone)
    digits = phone.to_s.gsub(/\D/, '')
    return { booked: false, value: 0.0 } if digits.length < 8

    booked = account.tasks.where(task_type: 'cirurgia', canceled_at: nil)
                    .where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
                    .exists?
    return { booked: false, value: 0.0 } unless booked

    contact = Task.match_contact(account, phone)
    value = contact&.additional_attributes&.dig('surgery_closing', 'value').to_f
    if value.zero? && contact
      card = Crm::Contact.joins(:pipeline)
                         .where(crm_pipelines: { account_id: account.id }, contact_id: contact.id)
                         .first
      value = card&.value.to_f
    end
    { booked: true, value: value }
  end

  # NPS dos pacientes das tasks: 1 query pelos contact_ids (Fase 0)
  def nps_scores_for(tasks_scope)
    contact_ids = tasks_scope.limit(200).pluck(:contact_id).compact
    return [] if contact_ids.empty?

    account.contacts.where(id: contact_ids.uniq)
           .filter_map { |c| c.additional_attributes&.dig('nps', 'score') }
  end

  def pct(part, total)
    total.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
end
