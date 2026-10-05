# 🏷️ item 322: o retrato das FONTES para a tela Fontes de pacientes — cada
# fonte com o seu ambiente (funis e caixas), quanto ela tem de cada coisa,
# quanto do banco ainda está sem carimbo e COMO as entradas em coluna dos
# últimos 30 dias nasceram (paciente, equipe, robô, sincronização, carga…).
class Crm::SourceOverview
  WINDOW = 30.days

  def initialize(account)
    @account = account
  end

  def call
    sources = Crm::Sources.list(@account)
    { sources: sources.map { |source| source_json(source, sources) },
      pending: Crm::SourceBackfill.pending(@account),
      vias: Crm::Stamp::VIAS,
      fence: fence_check(sources),
      main_pipeline_ids: Crm::Sources.main_pipeline_ids(@account),
      pipelines: pipelines.map { |p| { id: p.id, name: p.name } },
      inboxes: inboxes.map { |i| { id: i.id, name: i.name } } }
  end

  private

  def pipelines
    @pipelines ||= @account.crm_pipelines.order(:position, :id).to_a
  end

  def inboxes
    @inboxes ||= @account.inboxes.order(:name).to_a
  end

  def source_json(source, sources)
    { id: source.id, key: source.key, name: source.name, kind: source.kind, color: source.color,
      legacy_partner: source.legacy_partner?,
      pipeline_ids: owned_ids(source, sources, :pipeline_ids, pipelines), inbox_ids: owned_ids(source, sources, :inbox_ids, inboxes),
      counts: counts(source), entries: entries(source) }
  end

  # a fonte da casa fica com tudo o que nenhuma outra pegou
  def owned_ids(source, sources, method, all)
    return source.public_send(method) & all.map(&:id) unless source.own?

    all.map(&:id) - sources.reject(&:own?).flat_map(&method)
  end

  def counts(source)
    { patients: count(:contacts, source), cards: count(:cards, source),
      appointments: Crm::SourceBackfill.base(@account, :tasks).where(cevico_source_id: source.id, task_type: Task::APPOINTMENT_TYPES).count,
      hub_items: count(:surgeries, source) }
  end

  def count(table, source)
    Crm::SourceBackfill.base(@account, table).where(cevico_source_id: source.id).count
  end

  # entradas em coluna dos últimos 30 dias, por como nasceram ('' = antes do carimbo)
  def entries(source)
    by_via = Crm::SourceBackfill.base(@account, :stage_logs)
                                .where(cevico_source_id: source.id, entered_at: WINDOW.ago..)
                                .group(:cevico_born_via).count
    { total: by_via.values.sum, by_via: by_via.transform_keys(&:to_s) }
  end

  # CONFERÊNCIA carimbo × cerca: enquanto a cerca dos parceiros (item 231) é
  # quem manda nas telas, os dois têm de dizer a mesma coisa sobre cada paciente
  def fence_check(sources)
    partner = sources.find(&:legacy_partner?)
    return nil if partner.nil?

    stamped = @account.contacts.where(cevico_source_id: partner.id).pluck(:id)
    fenced = Crm::PartnerGuard.compute_excluded_ids(@account)
    unstamped = @account.contacts.where(id: fenced, cevico_source_id: nil).pluck(:id)
    { stamped: stamped.size, fenced: fenced.size, only_stamp: (stamped - fenced).size, only_fence: (fenced - stamped - unstamped).size }
  end
end
