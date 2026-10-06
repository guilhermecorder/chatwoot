# 📊 item 233 (25/09): a TAXA DE AGENDAMENTO oficial, uma só para o sistema
# inteiro. Regra do Guilherme: conta a MUDANÇA DE COLUNA no CRM para
# "Agendamento de Consulta" (vindo de Envio de Orçamento ou de qualquer coluna
# anterior) — nunca as consultas da Agenda (exame, pós-op, tele e Oftalmofácil
# inflavam o número). Numerador = pacientes distintos que ENTRARAM na coluna de
# agendamento no período (histórico de colunas); denominador = universo de leads.
# A coluna é a mesma dos efeitos do agendamento (Agendamentos → Ajustes →
# "Ao agendar, mover para"); sem configurar, a primeira coluna do 1º funil com
# "agendamento" no nome (fora pós/desmarcou).
module Crm::BookingRate
  module_function

  def stage(account) # rubocop:disable Metrics/CyclomaticComplexity
    id = Crm::BookingSideEffects.booking_stage_id(account)
    found = id && Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).find_by(id: id)
    return found if found

    pipeline = account.crm_pipelines.order(:position).first
    pipeline&.stages&.order(:position)&.detect { |s| s.name.match?(/agendamento/i) && !s.name.match?(/p[oó]s|desmarc|n[aã]o foi/i) }
  end

  # entradas na coluna de agendamento no período (uma linha por passagem)
  # lens (item 328): com a lente, vale a coluna de agendamento de CADA fonte
  # que ela enxerga (a da casa + "Consulta Agendada" do funil do Oftalmofácil)
  def entries(account, since, until_at, lens: nil)
    return lens_entries(account, since, until_at, lens) if lens

    target = stage(account)
    return Crm::StageLog.none unless target

    Crm::StageLog.where(stage_id: target.id, event_type: 'entered', entered_at: since..until_at)
  end

  def lens_entries(account, since, until_at, lens)
    ids = stage_ids(account, lens)
    return Crm::StageLog.none if ids.empty?

    lens.stage_logs(Crm::StageLog.where(stage_id: ids, event_type: 'entered', entered_at: since..until_at))
  end

  PARTNER_BOOKING = /consulta agendada|agendamento/i
  NOT_BOOKING = /cirurgia|p[oó]s|desmarc|n[aã]o foi/i

  # colunas de agendamento que a lente enxerga: a oficial da casa e, em cada
  # funil de outra fonte, a primeira "Consulta Agendada" (nunca a de cirurgia)
  def stage_ids(account, lens)
    foreign = Crm::Sources.map(account)['pipelines']
    ids = lens.pipelines.select { |pipeline| foreign.key?(pipeline.id.to_s) }.filter_map { |pipeline| partner_stage_id(pipeline) }
    house = stage(account)
    ids.unshift(house.id) if house && (lens.all? || lens.own?)
    ids.uniq
  end

  def partner_stage_id(pipeline)
    pipeline.stages.order(:position).detect { |s| s.name.match?(PARTNER_BOOKING) && !s.name.match?(NOT_BOOKING) }&.id
  end

  # pacientes distintos que entraram na coluna no período
  def count(account, since, until_at, lens: nil)
    entries(account, since, until_at, lens: lens).distinct.count(:crm_contact_id)
  end

  def rate(account, since, until_at, leads: nil)
    leads = Crm::LeadsUniverse.scope(account, since, until_at).count if leads.nil?
    return 0.0 unless leads.to_i.positive?

    ((count(account, since, until_at).to_f / leads) * 100).round(1)
  end
end
