# 📍 ANTES × DEPOIS de um marco do atendimento (24/11/2026), por caixa.
# Para cada caixa em que os atendentes de IA leem: quantas conversas NOVAS
# chegaram e quantas viraram consulta marcada, nos BEFORE_DAYS antes do marco e
# do marco até agora.
# Comparação justa: consulta demora a ser marcada, então o "antes" só conta a
# consulta marcada dentro do MESMO prazo que o "depois" já teve (o horizonte:
# tempo desde o marco, no máximo HORIZON_MAX). Sem isso o "antes" ganharia
# sempre, por ter tido semanas para amadurecer.
class Crm::AttendanceBeforeAfter
  BEFORE_DAYS = 14
  HORIZON_MAX = 7.days
  AGENTS = %w[atendente_agendamento atendente_pos atendente_pos_op].freeze

  def initialize(account, at:, now: Time.current)
    @account = account
    @at = at
    @now = now
  end

  def call # rubocop:disable Metrics/AbcSize
    return nil if @at.nil? || @at > @now

    horizon = [@now - @at, HORIZON_MAX].min
    before = window(@at - BEFORE_DAYS.days, @at, horizon)
    after = window(@at, @now, horizon)
    names = @account.inboxes.where(id: inbox_ids).pluck(:id, :name).to_h
    rows = inbox_ids.map do |id|
      { inbox_id: id, name: names[id] || "Caixa #{id}", before: summary(before[id], BEFORE_DAYS.to_f), after: summary(after[id], days_after) }
    end
    { at: @at.iso8601, before_days: BEFORE_DAYS, after_days: days_after.round(1), horizon_hours: (horizon / 3600.0).round(1),
      rows: rows.sort_by { |row| -row[:after][:conversas] },
      total: { before: summary(before.values.flatten(1), BEFORE_DAYS.to_f), after: summary(after.values.flatten(1), days_after) } }
  end

  private

  def days_after
    [(@now - @at) / 86_400.0, 0.01].max
  end

  # caixas em que algum atendente de IA lê
  def inbox_ids
    @inbox_ids ||= begin
      agents = (CrmSetting.find_by(account: @account)&.ai_config || {})['agents'] || {}
      agents.slice(*AGENTS).values.flat_map { |agent| Array(agent['inbox_ids']).map(&:to_i) }.uniq
    end
  end

  # { inbox_id => [marcou?, …] } das conversas criadas na janela
  def window(from, to, horizon)
    convs = @account.conversations.where(inbox_id: inbox_ids, created_at: from...to).pluck(:inbox_id, :contact_id, :created_at)
    booked = bookings(convs.filter_map { |row| row[1] }.uniq, from)
    convs.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(inbox_id, contact_id, created_at), map|
      limit = created_at + horizon
      map[inbox_id] << Array(booked[contact_id]).any? { |at| at.between?(created_at, limit) }
    end
  end

  def bookings(contact_ids, from)
    return {} if contact_ids.empty?

    @account.tasks.where(task_type: 'consulta', canceled_at: nil, contact_id: contact_ids).where('tasks.created_at >= ?', from)
            .pluck(:contact_id, :created_at).group_by(&:first).transform_values { |rows| rows.map(&:last) }
  end

  def summary(flags, days)
    flags = Array(flags)
    total = flags.size
    booked = flags.count(true)
    { conversas: total, consultas: booked, taxa: total.zero? ? nil : (booked * 100.0 / total).round(1),
      por_dia: (total / days).round(1) }
  end
end
