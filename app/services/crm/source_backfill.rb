# 🏷️ item 322: CARIMBAR O PASSADO. Tudo o que nasceu antes do carimbo ganha a
# fonte pelas MESMAS regras que o sistema usa hoje para separar os dados:
#
#   cards e entradas em coluna → a fonte dona do funil
#   agendamentos               → Oftalmofácil se a origem escolhida foi essa ou
#                                se veio de parceiro do hub; senão a casa
#   itens do espelho do hub    → fornecedor da casa (CATARATA_SP) × parceiro
#   pacientes                  → a lista da cerca dos parceiros (item 231, com
#                                a regra B "quem chegou primeiro"); o resto é da casa
#
# E o "como nasceu" do que dá para saber: entrada marcada como carga em massa
# (item 309) → carga; agendamento e item vindos do hub → sync. O resto do
# passado fica sem "como" (a tela mostra "antes do carimbo") — não inventamos.
#
# Só toca em registro SEM carimbo: rodar de novo não muda nada, e nada do que
# já nasceu carimbado é reescrito. `preview` conta; `run!` grava.
module Crm::SourceBackfill
  module_function

  TABLES = %i[contacts cards stage_logs tasks surgeries].freeze

  # quanto falta carimbar, por tabela
  def pending(account)
    TABLES.index_with { |table| base(account, table).where(cevico_source_id: nil).count }
  end

  # o que seria carimbado: { tabela => { chave_da_fonte => quantos } }
  def preview(account)
    plan(account).each_with_object(TABLES.index_with { {} }) do |step, out|
      n = step[:scope].count
      out[step[:table]][step[:source].key] = out[step[:table]][step[:source].key].to_i + n if n.positive?
    end
  end

  # grava; devolve o mesmo formato do preview com o que foi de fato carimbado
  def run!(account)
    out = TABLES.index_with { {} }
    plan(account).each do |step|
      n = step[:scope].update_all(cevico_source_id: step[:source].id) # rubocop:disable Rails/SkipsModelValidations
      out[step[:table]][step[:source].key] = out[step[:table]][step[:source].key].to_i + n if n.positive?
    end
    stamp_known_vias!(account)
    Crm::PartnerGuard.forget!(account)
    out
  end

  # O FUNIL MUDOU DE DONO (fonte nova pegou um funil, ou devolveu): cards e
  # entradas em coluna acompanham o funil. Paciente não muda — a fonte dele é
  # a da primeira evidência.
  def restamp_funnels!(account) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    sources = Crm::Sources.list(account)
    own = sources.find(&:own?)
    taken = sources.reject(&:own?).flat_map(&:pipeline_ids)
    groups = sources.reject(&:own?).map { |s| [s, s.pipeline_ids] } << [own, account.crm_pipelines.pluck(:id) - taken]
    groups.sum do |source, pipeline_ids|
      next 0 if pipeline_ids.empty?

      cards = Crm::Contact.where(pipeline_id: pipeline_ids)
      Crm::StageLog.where(crm_contact_id: cards.select(:id)).where.not(cevico_source_id: source.id)
                   .update_all(cevico_source_id: source.id) + # rubocop:disable Rails/SkipsModelValidations
        cards.where.not(cevico_source_id: source.id).update_all(cevico_source_id: source.id) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # passos em ordem: cada fonte parceira pega o que é dela; a casa fica com o resto
  def plan(account)
    sources = Crm::Sources.list(account)
    own = sources.find(&:own?)
    steps = sources.reject(&:own?).flat_map { |source| partner_steps(account, source) }
    steps + TABLES.map { |table| { table: table, source: own, scope: own_scope(account, table, steps) } }
  end

  def base(account, table)
    case table
    when :contacts then account.contacts
    when :cards then Crm::Contact.where(pipeline_id: account.crm_pipelines.select(:id))
    when :stage_logs then Crm::StageLog.where(crm_contact_id: Crm::Contact.where(pipeline_id: account.crm_pipelines.select(:id)).select(:id))
    when :tasks then account.tasks
    when :surgeries then Crm::OftalmofacilSurgery.where(account_id: account.id)
    end
  end

  def partner_steps(account, source)
    pipelines = source.pipeline_ids
    steps = []
    if pipelines.any?
      cards = Crm::Contact.where(pipeline_id: pipelines)
      steps << { table: :cards, source: source, scope: cards.where(cevico_source_id: nil) }
      steps << { table: :stage_logs, source: source, scope: Crm::StageLog.where(crm_contact_id: cards.select(:id), cevico_source_id: nil) }
    end
    return steps unless source.legacy_partner?

    steps << { table: :tasks, source: source, scope: partner_tasks(account).where(cevico_source_id: nil) }
    steps << { table: :surgeries, source: source, scope: partner_surgeries(account).where(cevico_source_id: nil) }
    steps << { table: :contacts, source: source,
               scope: account.contacts.where(id: Crm::PartnerGuard.compute_excluded_ids(account), cevico_source_id: nil) }
    steps
  end

  # a casa fica com o que sobrou sem carimbo DEPOIS dos passos das parceiras;
  # no preview (nada gravado ainda) tira da conta o que as parceiras vão pegar
  def own_scope(account, table, partner_steps)
    scope = base(account, table).where(cevico_source_id: nil)
    partner_steps.select { |s| s[:table] == table }.each do |step|
      scope = scope.where.not(id: step[:scope].select(:id))
    end
    scope
  end

  def partner_tasks(account)
    account.tasks.where("tasks.origin = 'oftalmofacil' OR (tasks.source = 'oftalmofacil' AND COALESCE(tasks.source_detail, '') <> '')")
  end

  def partner_surgeries(account)
    own_name = Crm::PartnerGuard.own_provider_name(account)
    scope = Crm::OftalmofacilSurgery.where(account_id: account.id)
    return scope.none if own_name.blank?

    scope.where("LOWER(COALESCE(provider_name, '')) NOT LIKE ?", "%#{Crm::OftalmofacilSurgery.sanitize_sql_like(own_name)}%")
  end

  # o "como nasceu" que o passado já deixa saber
  def stamp_known_vias!(account)
    base(account, :stage_logs).where(cevico_born_via: nil, event_type: Crm::StageLogBulk::BULK).update_all(cevico_born_via: 'carga') # rubocop:disable Rails/SkipsModelValidations
    account.tasks.where(cevico_born_via: nil, source: 'oftalmofacil').update_all(cevico_born_via: 'sync') # rubocop:disable Rails/SkipsModelValidations
    base(account, :surgeries).where(cevico_born_via: nil).update_all(cevico_born_via: 'sync') # rubocop:disable Rails/SkipsModelValidations
  end
end
