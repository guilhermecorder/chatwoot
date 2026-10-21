# 🧹 item 309 (01/10): CARGA EM MASSA no histórico de colunas.
# Achado (print dele: "Entrou em Envio de Orçamento — pico 10.292"): o
# histórico grava CADA mudança de coluna com a hora em que ela aconteceu —
# inclusive as cargas e reorganizações em massa (importação da base em 10/07 de
# madrugada, re-arrumação de 14/07, lote de 21/07, 1ª carga do Oftalmofácil em
# 14/09). No backup de 21/09, 26.745 das 38.299 entradas (70%) eram isso.
# Nenhum paciente "entrou" na coluna naquele minuto: os indicadores de
# "Entrou em…" não podem contar.
#
# Regra: 30 ou mais cartões entrando na MESMA coluna no MESMO minuto = carga em
# massa (o maior grupo orgânico medido tem 23 — os robôs das 10h). A entrada
# continua no banco e no histórico do paciente, só muda de `entered` para
# `bulk`; quem conta indicador lê só `entered`. Tem volta (undo!).
module Crm::StageLogBulk
  THRESHOLD = 30
  ENTERED = 'entered'.freeze
  BULK = 'bulk'.freeze

  module_function

  def scope(account)
    Crm::StageLog.joins(crm_contact: :pipeline).where(crm_pipelines: { account_id: account.id })
  end

  # rajadas: [{ stage_id:, stage_name:, minute:, count: }], da mais antiga para a mais nova
  def bursts(account, since: nil, min: THRESHOLD)
    logs = scope(account).where(event_type: ENTERED)
    logs = logs.where(crm_contact_stage_logs: { entered_at: since.. }) if since
    minute = "date_trunc('minute', crm_contact_stage_logs.entered_at)"
    logs.group(:stage_id, Arel.sql(minute)).having('COUNT(*) >= ?', [min.to_i, 2].max)
        .order(Arel.sql(minute)).pluck(:stage_id, Arel.sql(minute), Arel.sql('MAX(crm_contact_stage_logs.stage_name)'), Arel.sql('COUNT(*)'))
        .map { |stage_id, at, name, count| { stage_id: stage_id, stage_name: name, minute: at, count: count } }
  end

  # resumo por dia e coluna (o que o rake e a tela mostram antes de aplicar)
  def summary(account, since: nil, min: THRESHOLD)
    bursts(account, since: since, min: min)
      .group_by { |b| [b[:minute].to_date, b[:stage_name]] }
      .map do |(day, name), list|
        { day: day, stage_name: name, entries: list.sum { |b| b[:count] }, minutes: list.size,
          from: list.first[:minute], to: list.last[:minute] }
      end
  end

  # marca as rajadas como carga em massa; devolve quantas entradas mudaram
  def mark!(account, since: nil, min: THRESHOLD)
    bursts(account, since: since, min: min).sum do |b|
      scope(account).where(event_type: ENTERED, stage_id: b[:stage_id])
                    .where(crm_contact_stage_logs: { entered_at: b[:minute]...(b[:minute] + 1.minute) })
                    .update_all(event_type: BULK, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # desfaz: tudo que foi marcado volta a contar
  def undo!(account)
    scope(account).where(event_type: BULK).update_all(event_type: ENTERED, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def marked_count(account)
    scope(account).where(event_type: BULK).count
  end
end
