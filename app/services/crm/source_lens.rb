# 🔎 PORTA ÚNICA DE LEITURA (item 328, Fase 2 das Fontes — 05/10). Pedido do
# Guilherme: "a separação por origem tem de valer no Meu Painel".
#
# Até aqui cada tela decidia sozinha o que era da CEVICO e o que era do
# Oftalmofácil (uma tirava os parceiros, outra somava tudo) — por isso os
# números saíam misturados. A lente é o lugar ÚNICO dessa decisão: a tela diz
# qual fonte quer ver e a lente filtra agendamentos, pacientes, cards, entradas
# em coluna e conversas pelo CARIMBO (`cevico_source_id`, item 322).
#
#   Crm::SourceLens.for(account, 'cevico')        só o que é da casa (padrão)
#   Crm::SourceLens.for(account, 'oftalmofacil')  só o que é do Oftalmofácil
#   Crm::SourceLens.for(account, 'all')           tudo junto, sem filtro
#
# Registro ainda SEM carimbo (passado que não foi carimbado; paciente que ainda
# não deu a primeira evidência) é lido pelas mesmas regras que carimbam o
# passado (Crm::SourceBackfill): agendamento de parceiro → Oftalmofácil; card e
# entrada em coluna → dona do funil; paciente → a lista da cerca. Assim o
# número não muda no dia em que o carimbo chega.
#
# A lente só LÊ. Quem pode ou não receber mensagem continua sendo decisão da
# cerca dos parceiros (Crm::PartnerGuard).
class Crm::SourceLens
  ALL = 'all'.freeze
  ALL_ALIASES = %w[all tudo todas].freeze

  attr_reader :account, :source

  def self.for(account, key)
    key = key.to_s.strip.downcase
    return new(account, nil) if ALL_ALIASES.include?(key)

    sources = Crm::Sources.list(account)
    new(account, sources.find { |s| s.key == key } || sources.find(&:own?))
  end

  def initialize(account, source)
    @account = account
    @source = source
  end

  def all?
    source.nil?
  end

  def own?
    source&.own? == true
  end

  def key
    all? ? ALL : source.key
  end

  def label
    all? ? 'Tudo' : source.name
  end

  # as fontes que a lente deixa passar
  def sources
    @sources ||= all? ? Crm::Sources.list(account) : [source]
  end

  # ── filtros ───────────────────────────────────────────────────────────
  def tasks(scope)
    without_partner_patients(by_stamp(scope, 'tasks', legacy_task_sql), 'tasks.contact_id')
  end

  def cards(scope)
    without_partner_patients(by_stamp(scope, 'crm_contacts', pipeline_case('crm_contacts.pipeline_id')), 'crm_contacts.contact_id')
  end

  def stage_logs(scope)
    legacy = "(SELECT #{pipeline_case('lens_cards.pipeline_id')} FROM crm_contacts lens_cards " \
             'WHERE lens_cards.id = crm_contact_stage_logs.crm_contact_id)'
    scope = by_stamp(scope, 'crm_contact_stage_logs', legacy)
    ids = partner_contact_ids
    return scope if ids.empty?

    scope.where('NOT EXISTS (SELECT 1 FROM crm_contacts lens_partner WHERE lens_partner.id = crm_contact_stage_logs.crm_contact_id ' \
                'AND lens_partner.contact_id IN (:ids))', ids: ids)
  end

  # 🧹 item 342 (13/10, "indicador de agendamento descontaminado"): paciente do
  # Oftalmofácil que ganhou card no funil da CEVICO contava como da casa — o
  # card e a entrada em coluna levam o carimbo do FUNIL, não do paciente. Na
  # lente da casa, sai todo registro de quem é do outro ambiente:
  #   · paciente carimbado com a fonte parceira, OU
  #   · paciente que só conversou por caixa de parceiro (nenhuma conversa
  #     numa caixa da casa).
  # Lista curta em cache (como a da cerca dos parceiros) e com teto.
  PARTNER_IDS_TTL = 10.minutes
  PARTNER_IDS_LIMIT = 50_000

  def partner_contact_ids
    return [] unless own?

    @partner_contact_ids ||= Rails.cache.fetch("cevico:lens:partner_contacts:#{account.id}", expires_in: PARTNER_IDS_TTL) do
      compute_partner_contact_ids
    end
  end

  def compute_partner_contact_ids
    foreign_sources = Crm::Sources.list(account).reject(&:own?).map(&:id)
    ids = foreign_sources.any? ? account.contacts.where(cevico_source_id: foreign_sources).limit(PARTNER_IDS_LIMIT).pluck(:id) : []
    taken = foreign_inbox_ids
    if taken.any?
      ids |= account.conversations.where(inbox_id: taken).where.not(contact_id: nil)
                    .where('NOT EXISTS (SELECT 1 FROM conversations own_conv WHERE own_conv.account_id = conversations.account_id ' \
                           'AND own_conv.contact_id = conversations.contact_id AND own_conv.inbox_id NOT IN (:taken))', taken: taken)
                    .distinct.limit(PARTNER_IDS_LIMIT).pluck(:contact_id)
    end
    ids.first(PARTNER_IDS_LIMIT)
  end

  # paciente sem carimbo = ainda sem evidência → vale a cerca (parceiro × casa)
  def contacts(scope)
    return scope if all?
    return scope.where(contacts: { cevico_source_id: source.id }) unless own? || source.legacy_partner?

    fenced = Crm::PartnerGuard.excluded_contact_ids(account).presence || [0]
    unstamped = own? ? 'contacts.id NOT IN (:fenced)' : 'contacts.id IN (:fenced)'
    scope = scope.where("contacts.cevico_source_id = :id OR (contacts.cevico_source_id IS NULL AND #{unstamped})", id: source.id, fenced: fenced)
    without_partner_patients(scope, 'contacts.id')
  end

  # conversas e mensagens: pela caixa de entrada (caixa que nenhuma fonte pegou = da casa)
  def inboxes(scope, column = 'conversations.inbox_id')
    return scope if all?

    taken = foreign_inbox_ids
    return taken.any? ? scope.where("#{column} NOT IN (?)", taken) : scope if own?

    scope.where("#{column} IN (?)", source.inbox_ids.presence || [0])
  end

  # caixas das fontes que NÃO são a casa
  def foreign_inbox_ids
    Crm::Sources.map(account)['inboxes'].keys.map(&:to_i)
  end

  # funis que a lente enxerga, com o funil principal da casa na frente
  def pipelines
    @pipelines ||= begin
      taken = Crm::Sources.map(account)['pipelines']
      foreign = account.crm_pipelines.order(:position, :id).select { |p| sees_source?(taken[p.id.to_s]) }
      house = all? || own? ? [account.crm_pipelines.order(:id).first].compact : []
      house + foreign
    end
  end

  # a lente enxerga esta fonte parceira? (nil = funil da casa, tratado à parte)
  def sees_source?(source_id)
    source_id.present? && (all? || source_id == source.id)
  end

  private

  # item 342: na lente da casa, tira os pacientes do outro ambiente
  def without_partner_patients(scope, column)
    ids = partner_contact_ids
    return scope if ids.empty?

    scope.where("#{column} IS NULL OR #{column} NOT IN (?)", ids)
  end

  def by_stamp(scope, table, legacy_sql)
    return scope if all?

    scope.where("COALESCE(#{table}.cevico_source_id, #{legacy_sql}) = ?", source.id)
  end

  def own_id
    @own_id ||= Crm::Sources.own_id(account).to_i
  end

  # sem carimbo: agendamento de parceiro (origem escolhida no formulário ou
  # item de parceiro vindo do hub) × o resto, que é da casa
  def legacy_task_sql
    partner = Crm::Sources.id_for_key(account, Crm::Source::PARTNER_KEY)
    return own_id.to_s if partner.blank?

    "CASE WHEN tasks.origin = 'oftalmofacil' OR (tasks.source = 'oftalmofacil' AND COALESCE(tasks.source_detail, '') <> '') " \
      "THEN #{partner.to_i} ELSE #{own_id} END"
  end

  # sem carimbo: a fonte dona do funil (funil que ninguém pegou = da casa)
  def pipeline_case(column)
    taken = Crm::Sources.map(account)['pipelines']
    return own_id.to_s if taken.empty?

    whens = taken.map { |pipeline_id, source_id| "WHEN #{pipeline_id.to_i} THEN #{source_id.to_i}" }.join(' ')
    "CASE #{column} #{whens} ELSE #{own_id} END"
  end
end
