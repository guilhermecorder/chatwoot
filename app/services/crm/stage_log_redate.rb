# 📅 ITEM 364 (22/10): RE-DATAR as cargas em massa (item 309). A carga de
# 10/07 (migração do Robomaster) e as de 14/07 e 21/07 gravaram ~26 mil
# entradas de coluna no minuto da carga. O item 309 tira essas entradas dos
# indicadores; aqui, as que têm a DATA REAL provada em outro lugar voltam a
# contar, no dia certo. Medido em produção (22/10): o histórico migrado guardou
# a data original das mensagens (9.466 de 9.607 pessoas).
#
# Só colunas em que a prova é a própria coisa que a coluna diz:
#   Novos Contatos      → a 1ª mensagem da pessoa
#   Envio de Orçamento  → a 1ª mensagem da EQUIPE com um valor em R$ (100+)
#   Pós Operatório /
#   Cirurgia Realizada  → a data da cirurgia no hub (OftalmoFácil)
# Agendamento de Consulta, Consulta Confirmada e o resto ficam como estão: a
# única data que existe é a da 1ª mensagem, que é quando a pessoa escreveu, não
# quando marcou.
#
# A data real precisa ser de um DIA ANTERIOR ao da carga (do mesmo dia ou de
# depois não prova nada). A hora original fica em created_at da entrada (a carga
# gravou entered_at = created_at); só re-data quem tem essa hora guardada, e é
# por ela que o undo! devolve tudo como estava.
module Crm::StageLogRedate
  TZ = 'America/Sao_Paulo'.freeze
  EARLIEST = Time.utc(2015, 1, 1)
  SAFE = { 'novos' => /novos? contatos?/, 'orcamento' => /orcamento/, 'pos_op' => /pos.?op|cirurgia realizada/ }.freeze
  LABELS = { 'novos' => '1ª mensagem', 'orcamento' => 'orçamento enviado', 'pos_op' => 'cirurgia no hub' }.freeze
  # valor de R$ 100 para cima ("R$ 4.900", "R$ 4900", "R$ 1.250,00") — "R$ 5" de taxa não conta
  BUDGET_SQL = "messages.content ~* 'R\\$\\s*([0-9]{1,3}(\\.[0-9]{3})+|[0-9]{3,})'".freeze
  SLICE = 2000

  Plan = Struct.new(:log_id, :stage_name, :burst_day, :kind, :real_at, :skip, keyword_init: true)

  module_function

  def kind_for(stage_name)
    name = I18n.transliterate(stage_name.to_s).downcase
    SAFE.find { |_k, re| name.match?(re) }&.first
  end

  # as entradas da carga: as já marcadas (item 309) + as rajadas que ainda contam
  def candidate_ids(account, min: Crm::StageLogBulk::THRESHOLD)
    ids = Crm::StageLogBulk.scope(account).where(event_type: Crm::StageLogBulk::BULK).pluck('crm_contact_stage_logs.id')
    Crm::StageLogBulk.bursts(account, min: min).each do |b|
      ids.concat(Crm::StageLogBulk.scope(account).where(event_type: Crm::StageLogBulk::ENTERED, stage_id: b[:stage_id])
                                  .where(crm_contact_stage_logs: { entered_at: b[:minute]...(b[:minute] + 1.minute) })
                                  .pluck('crm_contact_stage_logs.id'))
    end
    ids.uniq
  end

  # uma linha por entrada da carga: o dia real (ou o motivo de ficar fora)
  def plan(account, min: Crm::StageLogBulk::THRESHOLD)
    rows = Crm::StageLog.where(id: candidate_ids(account, min: min)).joins(:crm_contact)
                        .pluck('crm_contact_stage_logs.id', 'crm_contact_stage_logs.stage_name', 'crm_contact_stage_logs.entered_at',
                               'crm_contact_stage_logs.created_at', 'crm_contacts.contact_id')
    proofs = proofs_for(account, rows.map(&:last).uniq)
    rows.map { |id, stage, at, created, contact_id| plan_one(id, stage, at, created, contact_id, proofs) }
  end

  def plan_one(id, stage, entered_at, created_at, contact_id, proofs) # rubocop:disable Metrics/ParameterLists, Metrics/AbcSize
    kind = kind_for(stage)
    row = Plan.new(log_id: id, stage_name: stage, burst_day: entered_at.in_time_zone(TZ).to_date, kind: kind)
    return row.tap { |r| r.skip = 'coluna sem data confiável' } if kind.nil?
    return row.tap { |r| r.skip = 'sem a hora original guardada' } if (created_at - entered_at).abs > 2.minutes

    real = proofs[kind][contact_id]
    return row.tap { |r| r.skip = 'sem data real' } if real.nil? || real < EARLIEST
    return row.tap { |r| r.skip = 'dado só do dia da carga ou depois' } if real.in_time_zone(TZ).to_date >= row.burst_day

    row.tap { |r| r.real_at = real }
  end

  # { 'novos' => { contact_id => Time }, 'orcamento' => {...}, 'pos_op' => {...} }
  def proofs_for(account, contact_ids) # rubocop:disable Metrics/AbcSize
    out = { 'novos' => {}, 'orcamento' => {}, 'pos_op' => {} }
    contact_ids.each_slice(SLICE) do |part|
      msgs = Message.joins(:conversation).where(conversations: { contact_id: part, account_id: account.id }).reorder(nil)
      out['novos'].merge!(msgs.group('conversations.contact_id').minimum('messages.created_at'))
      out['orcamento'].merge!(msgs.where(message_type: :outgoing).where(BUDGET_SQL)
                                  .group('conversations.contact_id').minimum('messages.created_at'))
      Crm::OftalmofacilSurgery.where(account_id: account.id, contact_id: part).concluidas.cirurgias
                              .group(:contact_id).minimum(:surgery_date)
                              .each { |cid, day| out['pos_op'][cid] = ActiveSupport::TimeZone[TZ].parse("#{day.iso8601} 12:00") }
    end
    out
  end

  # volta a contar, no dia real; devolve quantas mudaram
  def apply!(plans)
    ready = plans.select(&:real_at)
    ready.each_slice(500) do |slice|
      Crm::StageLog.transaction do
        slice.each do |p|
          Crm::StageLog.where(id: p.log_id).update_all(entered_at: p.real_at, event_type: Crm::StageLogBulk::ENTERED) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end
    ready.size
  end

  # desfaz: a entrada re-datada volta para a hora da carga (created_at) e fica fora
  # dos indicadores. A carga é achada pela hora em que foi GRAVADA (created_at:
  # 30+ entradas da mesma coluna no mesmo minuto), que a re-datação não mexe.
  def undo!(account, min: Crm::StageLogBulk::THRESHOLD)
    minute = "date_trunc('minute', crm_contact_stage_logs.created_at)"
    groups = Crm::StageLogBulk.scope(account).group(:stage_id, Arel.sql(minute)).having('COUNT(*) >= ?', min)
                              .pluck(:stage_id, Arel.sql(minute), Arel.sql('MAX(crm_contact_stage_logs.stage_name)'))
    groups.sum do |stage_id, at, name|
      next 0 if kind_for(name).nil?

      ids = Crm::StageLogBulk.scope(account).where(event_type: Crm::StageLogBulk::ENTERED, stage_id: stage_id)
                             .where(crm_contact_stage_logs: { created_at: at...(at + 1.minute) })
                             .where("crm_contact_stage_logs.created_at - crm_contact_stage_logs.entered_at > interval '1 day'")
                             .pluck('crm_contact_stage_logs.id')
      Crm::StageLog.where(id: ids).update_all("entered_at = created_at, event_type = '#{Crm::StageLogBulk::BULK}'") # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
