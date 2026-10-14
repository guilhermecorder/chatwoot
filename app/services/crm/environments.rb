# 🧭 AMBIENTES DO CRM (item 341, 13/10). Pedido do Guilherme: "quero um
# ambiente de configuração do CRM, ou das caixas de entrada, em que eu
# seleciono qual número fica dentro de qual ambiente de CRM" — e a caixa 12
# (Oftalmofácil) NUNCA pode cair no CRM da CEVICO.
#
# Ambiente = Fonte (Crm::Source, item 322). Cada caixa de entrada e cada funil
# pertencem a UM ambiente só (a tela Ambientes do CRM é a verdade única; o card
# do OftalmoFácil em Integrações vira só leitura de compatibilidade). Até aqui
# a fonte era só um RÓTULO; agora ela manda:
#   · a conversa nova abre card no funil do ambiente da CAIXA (CrmListener)
#   · nenhum caminho cria card da CEVICO para paciente de outro ambiente
#     (Crm::CardRouter, no próprio modelo do card)
#   · o board e o filtro de conversas por funil escondem as caixas de fora
#
# QUEM É o paciente (contact_environment): a cerca dos parceiros (item 231)
# com a caixa contando de verdade — carimbo de parceiro, marca de parceiro
# (atributo, etiqueta of_, card no funil deles, item de parceiro no hub,
# agendamento de parceiro) OU conversa numa caixa de outro ambiente. REGRA B
# continua: quem falou com a CEVICO ANTES (conversa numa caixa da casa, card ou
# agendamento da casa criado 5+ min antes da 1ª entrada no parceiro, ou um
# agendamento marcado "CEVICO" na Agenda) segue da CEVICO.
module Crm::Environments # rubocop:disable Metrics/ModuleLength
  module_function

  # o card automático da CEVICO nasce no mesmo minuto da conversa da caixa 12;
  # só conta como "falou com a CEVICO antes" o que veio 5+ min antes
  OWN_MARGIN = 5.minutes
  PARTNER_ORIGINS = %w[oftalmofacil oftalmofácil].freeze
  PARTNER_TASK_SQL = "(COALESCE(tasks.origin, '') = 'oftalmofacil' OR " \
                     "(COALESCE(tasks.source, '') = 'oftalmofacil' AND COALESCE(tasks.source_detail, '') <> ''))".freeze

  # ---- ambientes, caixas e funis -------------------------------------------

  def own_id(account)
    Crm::Sources.own_id(account)
  end

  def source(account, id)
    id && Crm::Source.find_by(account_id: account.id, id: id)
  end

  def environment_id_for_inbox(account, inbox_id)
    Crm::Sources.id_for_inbox(account, inbox_id)
  end

  def environment_for_inbox(account, inbox_id)
    source(account, environment_id_for_inbox(account, inbox_id))
  end

  def environment_id_for_pipeline(account, pipeline_id)
    Crm::Sources.id_for_pipeline(account, pipeline_id)
  end

  def partner_environment_id?(account, source_id)
    source_id.present? && source_id != own_id(account)
  end

  # caixas/funis de TODOS os ambientes que não são a casa
  def partner_inbox_ids(account)
    Crm::Sources.map(account)['inboxes'].keys.map(&:to_i)
  end

  def partner_pipeline_ids(account)
    Crm::Sources.map(account)['pipelines'].keys.map(&:to_i)
  end

  def pipeline_ids_for(source)
    return source.account.crm_pipelines.pluck(:id) - partner_pipeline_ids(source.account) if source.own?

    source.pipeline_ids
  end

  def inbox_ids_for(source)
    return source.account.inboxes.pluck(:id) - partner_inbox_ids(source.account) if source.own?

    source.inbox_ids
  end

  # funil de entrada de uma caixa: CEVICO → o 1º funil da casa (como sempre
  # foi); Oftalmofácil → o funil dela; outro ambiente → o 1º funil dele
  def entry_pipeline_for_inbox(account, inbox_id)
    entry_pipeline(account, environment_id_for_inbox(account, inbox_id))
  end

  def entry_pipeline(account, source_id)
    unless partner_environment_id?(account, source_id)
      return account.crm_pipelines.where.not(id: partner_pipeline_ids(account)).order(:position, :id).first
    end

    src = source(account, source_id)
    return nil if src.nil?
    return Crm::PartnerFunnel.pipeline(account) if src.legacy_partner?

    account.crm_pipelines.where(id: src.pipeline_ids).order(:position, :id).first
  end

  # caixas que NÃO são do ambiente do funil (as conversas delas somem do board
  # e do filtro "funil" das Conversas)
  def foreign_inbox_ids(account, pipeline)
    pipeline_id = pipeline.respond_to?(:id) ? pipeline.id : pipeline
    env = environment_id_for_pipeline(account, pipeline_id)
    inboxes = Crm::Sources.map(account)['inboxes'].transform_keys(&:to_i)
    return inboxes.keys unless partner_environment_id?(account, env) # funil da casa: tudo o que é dos outros

    account.inboxes.pluck(:id) - inboxes.select { |_id, src| src == env }.keys
  end

  # ---- quem é o paciente ---------------------------------------------------

  def contact_environment(account, contact)
    source(account, contact_environment_id(account, contact))
  end

  # ambiente do paciente: o do parceiro em que ele está ancorado, senão a casa
  def contact_environment_id(account, contact)
    anchored_partner_id(account, contact) || own_id(account)
  end

  # ambientes de outros com evidência do paciente (sem olhar a regra B)
  def partner_candidate_ids(account, contact) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return [] if contact.blank? || contact.id.blank?

    own = own_id(account)
    ids = []
    ids << contact.cevico_source_id if contact.cevico_source_id.present? && contact.cevico_source_id != own
    ids << Crm::Sources.partner_id(account) if Crm::PartnerGuard.partner_marked?(contact) || partner_task_scope(account, [contact.id]).exists?
    inbox_map = Crm::Sources.map(account)['inboxes']
    if inbox_map.any?
      first = account.conversations.where(contact_id: contact.id, inbox_id: inbox_map.keys.map(&:to_i)).order(:created_at).pick(:inbox_id)
      ids << inbox_map[first.to_s] if first
    end
    pipeline_map = Crm::Sources.map(account)['pipelines']
    if pipeline_map.any?
      first = Crm::Contact.where(contact_id: contact.id, pipeline_id: pipeline_map.keys.map(&:to_i)).order(:created_at).pick(:pipeline_id)
      ids << pipeline_map[first.to_s] if first
    end
    ids.compact.uniq
  end

  def anchored_partner_id(account, contact)
    candidates = partner_candidate_ids(account, contact)
    return nil if candidates.empty? || own_first_ids(account, [contact.id]).any?

    candidates.first
  end

  def partner_anchored?(account, contact)
    anchored_partner_id(account, contact).present?
  end

  # ---- em lote (tela Ambientes e rake de migração) -------------------------

  # todos os pacientes com ALGUMA evidência de outro ambiente (antes da regra B)
  def partner_evidence_ids(account) # rubocop:disable Metrics/AbcSize
    map = Crm::Sources.map(account)
    own = own_id(account)
    ids = Crm::PartnerGuard.marked_contact_ids(account)
    ids |= account.contacts.where.not(cevico_source_id: [nil, own]).pluck(:id)
    inboxes = map['inboxes'].keys.map(&:to_i)
    ids |= account.conversations.where(inbox_id: inboxes).where.not(contact_id: nil).distinct.pluck(:contact_id) if inboxes.any?
    pipelines = map['pipelines'].keys.map(&:to_i)
    ids |= Crm::Contact.where(pipeline_id: pipelines).distinct.pluck(:contact_id) if pipelines.any?
    ids.compact.uniq
  end

  # { contact_id => ambiente (fonte) em que está ancorado } — já com a regra B
  def anchored_partner_map(account, ids) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    ids = Array(ids).compact.uniq
    return {} if ids.empty?

    map = Crm::Sources.map(account)
    own = own_id(account)
    out = account.contacts.where(id: ids).where.not(cevico_source_id: [nil, own]).pluck(:id, :cevico_source_id).to_h
    if map['inboxes'].any?
      account.conversations.where(contact_id: ids, inbox_id: map['inboxes'].keys.map(&:to_i))
             .reorder(Arel.sql('conversations.contact_id, conversations.created_at'))
             .pluck(Arel.sql('DISTINCT ON (conversations.contact_id) conversations.contact_id'), 'conversations.inbox_id')
             .each { |cid, inbox| out[cid] ||= map['inboxes'][inbox.to_s] }
    end
    if map['pipelines'].any?
      Crm::Contact.where(contact_id: ids, pipeline_id: map['pipelines'].keys.map(&:to_i))
                  .reorder(Arel.sql('crm_contacts.contact_id, crm_contacts.created_at'))
                  .pluck(Arel.sql('DISTINCT ON (crm_contacts.contact_id) crm_contacts.contact_id'), 'crm_contacts.pipeline_id')
                  .each { |cid, pid| out[cid] ||= map['pipelines'][pid.to_s] }
    end
    legacy = map['keys'][Crm::Source::PARTNER_KEY]
    (ids & Crm::PartnerGuard.marked_contact_ids(account)).each { |cid| out[cid] ||= legacy } if legacy
    out.compact.except(*own_first_ids(account, out.keys))
  end

  # REGRA B (item 245) com a caixa contando: dos ids informados, os que falaram
  # com a CEVICO ANTES de entrar num parceiro. "Entrar no parceiro" = 1ª
  # conversa numa caixa de outro ambiente, 1º card num funil de outro
  # ambiente, 1º item de parceiro no hub ou 1º agendamento de parceiro.
  # "Falar com a CEVICO" = conversa numa caixa da casa em que o paciente
  # escreveu, ANTES; card da casa (menos o
  # card automático que a caixa 12 abria — origem = nome da caixa) ou
  # agendamento da casa, 5+ min antes. Agendamento marcado "CEVICO" na Agenda
  # vale sempre (a equipe disse). Sem entrada no parceiro + evidência da casa = casa.
  def own_first_ids(account, ids) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    ids = Array(ids).compact.uniq
    return [] if account.blank? || ids.empty?

    explicit = account.tasks.where(contact_id: ids, origin: 'cevico').distinct.pluck(:contact_id)
    convs, cards, tasks = own_evidence_times(account, ids)
    candidates = convs.keys | cards.keys | tasks.keys
    return explicit if candidates.empty?

    starts = partner_start_times(account, candidates)
    firsts = candidates.select do |cid|
      start = starts[cid]
      # marca de parceiro sem data (etiqueta/atributo/carimbo): como antes do
      # item 341, só um CARD da casa prova que a pessoa já era da CEVICO
      next cards[cid].present? if start.nil?

      record = [cards[cid], tasks[cid]].compact.min
      (convs[cid] && convs[cid] < start) || (record && record < start - OWN_MARGIN)
    end
    explicit | firsts
  end

  # [{ contact_id => 1ª conversa da casa em que o paciente escreveu },
  #  { contact_id => 1º card da casa }, { contact_id => 1º agendamento/tarefa da casa }]
  def own_evidence_times(account, ids)
    partner_pids = partner_pipeline_ids(account)
    partner_inboxes = partner_inbox_ids(account)
    names = partner_origin_names(account)

    cards = Crm::Contact.where(contact_id: ids)
    cards = cards.where.not(pipeline_id: partner_pids) if partner_pids.any?
    cards = cards.where('crm_contacts.origin IS NULL OR LOWER(crm_contacts.origin) NOT IN (?)', names)
    # conversa da casa só vale se o PACIENTE escreveu nela (lembrete/robô sozinho não é "falou com a CEVICO")
    convs = account.conversations.where(contact_id: ids)
                   .where('EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = conversations.id AND m.message_type = 0)')
    convs = convs.where.not(inbox_id: partner_inboxes) if partner_inboxes.any?
    tasks = account.tasks.where(contact_id: ids).where.not(PARTNER_TASK_SQL)
    [convs.group(:contact_id).minimum(:created_at), cards.group(:contact_id).minimum(:created_at),
     tasks.group(:contact_id).minimum(:created_at)]
  end

  # { contact_id => 1ª entrada num parceiro }
  def partner_start_times(account, ids) # rubocop:disable Metrics/AbcSize
    partner_pids = partner_pipeline_ids(account)
    partner_inboxes = partner_inbox_ids(account)
    cards = partner_pids.any? ? Crm::Contact.where(contact_id: ids, pipeline_id: partner_pids).group(:contact_id).minimum(:created_at) : {}
    convs = {}
    convs = account.conversations.where(contact_id: ids, inbox_id: partner_inboxes).group(:contact_id).minimum(:created_at) if partner_inboxes.any?
    items = Crm::OftalmofacilSurgery.where(account_id: account.id, contact_id: ids)
    own_name = Crm::PartnerGuard.own_provider_name(account)
    items = own_name.present? ? items.where.not('LOWER(provider_name) LIKE ?', "%#{own_name}%") : items.none
    item_starts = items.group(:contact_id).minimum(Arel.sql('COALESCE(of_created_at, created_at)'))
    tasks = partner_task_scope(account, ids).group(:contact_id).minimum(:created_at)
    merge_min(cards, convs, item_starts, tasks)
  end

  # agendamentos de parceiro (origem "Oftalmofácil" no formulário ou item de
  # parceiro vindo do sync do hub) — o mesmo que PartnerGuard.partner_task?
  def partner_task_scope(account, ids)
    account.tasks.where(contact_id: ids).where(PARTNER_TASK_SQL)
  end

  # origens que marcam o card AUTOMÁTICO aberto pela caixa do parceiro (o
  # CrmListener gravava o nome da caixa como origem)
  def partner_origin_names(account)
    names = account.inboxes.where(id: partner_inbox_ids(account)).pluck(:name).map { |n| n.to_s.strip.downcase }
    (names + PARTNER_ORIGINS).uniq
  end

  def merge_min(*hashes)
    hashes.each_with_object({}) do |hash, out|
      hash.each { |cid, t| out[cid] = [out[cid], t].compact.min if t }
    end
  end
end
