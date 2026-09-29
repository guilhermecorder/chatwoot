# 🩺 Os DEGRAUS da jornada de quem chegou por anúncio (itens 289 e 294, 29/09).
# Filosofia: revelar o dado pelas conexões — cada degrau diz de ONDE vem
# (CRM × Agenda × Oftalmofácil) e sempre cabe no degrau anterior.
#   consultas    = card chegou na coluna oficial de agendamento ou além, OU consulta na Agenda
#   compareceram = card chegou em "Consulta Realizada" ou além, OU presença marcada na Agenda
#   fechadas     = cirurgia FECHADA (a venda): card chegou em "Cirurgia Agendada" ou além,
#                  OU cirurgia na Agenda, OU cirurgia ativa/aguardando pagamento no Oftalmofácil
#   realizadas   = card chegou em "Cirurgia Realizada"/2º olho/pós-operatório, OU cirurgia
#                  realizada na Agenda, OU cirurgia do Oftalmofácil ATIVA com a data já passada
# ⚠️ No Oftalmofácil NENHUMA cirurgia recebe a situação "realizada" (produção, 21/09:
# 935 "Ativa", 280 "Aguardando pagamento", 134 "Cancelada") — por isso a realizada
# de lá é a ATIVA cuja data já passou. Esperar "realizada" dava sempre zero.
#   receita      = das realizadas: o valor do Oftalmofácil (pago; senão o cobrado); sem ele, o valor do card
class Crm::AdFunnelSteps
  SURGERY_DONE = /cirurgia\s+realizada|2.{0,2}\s*olho|p[oó]s[\s-]?op/i
  SURGERY_CLOSED = /cirurgia\s+agendada/i
  ATTENDED_FROM = /consulta\s+realizada/i
  OF_CLOSED = %w[agendada realizada aguardando_pagamento].freeze
  OF_DONE = %w[agendada realizada].freeze

  attr_reader :crm, :booked_agenda, :attended_agenda, :closed_agenda, :of_closed, :of_done,
              :booked, :attended, :closed, :surgeries

  def initialize(account, contact_ids) # rubocop:disable Metrics/AbcSize
    @account = account
    @ids = contact_ids
    load_sources
    @surgeries = crm[:surgeries] | done_agenda | of_done.keys.to_set
    @closed = crm[:closed] | closed_agenda | of_closed | surgeries
    @attended = crm[:attended] | attended_agenda | closed
    @booked = crm[:booked] | booked_agenda | attended
  end

  # colunas do CRM de cada degrau (a linha do tempo usa para DATAR cada passo)
  def self.stage_ids_for(account)
    new(account, []).send(:stage_ids)
  end

  def revenue_of(contact_id)
    of_done[contact_id].to_f.positive? ? of_done[contact_id].to_f : card_values[contact_id].to_f
  end

  private

  attr_reader :done_agenda

  def load_sources # rubocop:disable Metrics/AbcSize
    @crm = stage_ids.transform_values { |ids| passed(ids) }
    @booked_agenda = tasks('consulta').distinct.pluck(:contact_id).to_set
    @attended_agenda = tasks('consulta').where(attendance: 'attended').distinct.pluck(:contact_id).to_set
    @closed_agenda = tasks('cirurgia').where(canceled_at: nil).distinct.pluck(:contact_id).to_set
    @done_agenda = tasks('cirurgia').where(attendance: 'attended').distinct.pluck(:contact_id).to_set
    surgeries = Crm::OftalmofacilSurgery.where(account_id: @account.id, contact_id: @ids)
    @of_closed = surgeries.where(status_kind: OF_CLOSED).distinct.pluck(:contact_id).to_set
    @of_done = surgeries.where(status_kind: OF_DONE).where(surgery_date: ...Time.zone.today)
                        .group(:contact_id).sum('COALESCE(NULLIF(paid_amount, 0), amount, 0)')
  end

  def tasks(type)
    @account.tasks.where(task_type: type, contact_id: @ids)
  end

  # colunas de cada degrau, pelo funil da coluna oficial de agendamento
  def stage_ids # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    all = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).to_a
    booking = Crm::BookingRate.stage(@account)
    line = booking ? all.select { |s| s.pipeline_id == booking.pipeline_id } : []
    from = ->(stage) { stage ? line.select { |s| s.position >= stage.position }.map(&:id) : [] }
    first = ->(pattern) { line.select { |s| s.name.match?(pattern) }.min_by(&:position) }
    done = all.select { |s| s.name.match?(SURGERY_DONE) }.map(&:id)
    closed = all.select { |s| s.name.match?(SURGERY_CLOSED) }.map(&:id) | done
    { booked: from.call(booking) | closed, attended: from.call(first.call(ATTENDED_FROM)) | closed,
      closed: closed, surgeries: done }
  end

  # quem está ou já passou por alguma dessas colunas
  def passed(stage_ids)
    return Set.new if @ids.empty? || stage_ids.empty?

    now = cards.where(stage_id: stage_ids).pluck(:contact_id)
    before = cards.where(id: Crm::StageLog.where(stage_id: stage_ids).select(:crm_contact_id)).pluck(:contact_id)
    (now + before).to_set
  end

  def cards
    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).where(contact_id: @ids)
  end

  def card_values
    @card_values ||= cards.where(contact_id: surgeries.to_a).group(:contact_id).maximum(:value)
  end
end
