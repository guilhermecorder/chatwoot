# 🚧 CERCA DOS PARCEIROS (item 231, 24/09/2026). Regra do Guilherme: "os
# pacientes da OFTALMOFÁCIL NÃO PODEM RECEBER MENSAGENS DA NOSSA IA; só a
# caixa Oftalmofácil fala com eles". Paciente que veio de um PARCEIRO do hub
# (fornecedor que não é o da CEVICO, CATARATA_SP) fica fora de TUDO que manda
# mensagem sozinho: atendentes de IA (WhatsApp e Instagram), automações de
# coluna (entrou/saiu, mensagem criada, parado, valor), robôs de follow-up,
# lembretes D-1/D-0, jornada, campanhas, régua, colheita e agente de ligação.
# E não ganha card no funil da CEVICO nem entra no universo de leads (não
# contamina os nossos números).
#
# Como reconhece um paciente de parceiro (qualquer um basta):
#   · card no funil dos parceiros (agenda_config.oftalmofacil.partner_pipeline_id)
#   · etiqueta `of_<parceiro>` (o sync coloca; `oftalmofacil` sozinha NÃO
#     serve — a CATARATA_SP também ganha essa e é a CEVICO)
#   · additional_attributes.parceiro preenchido (o sync grava)
#   · conversa numa caixa dos parceiros (agenda_config.oftalmofacil.partner_inbox_ids)
#
# REGRA B (item 245, 25/09 — "um paciente pode ter passado por um e por outro
# ao longo da jornada"): QUEM CHEGOU PRIMEIRO. Se a pessoa já era da CEVICO
# (card num funil da CEVICO criado ANTES da entrada dela no parceiro — card no
# funil dos parceiros ou item de parceiro marcado no hub), ela continua sendo
# lead da CEVICO: IA, automações e campanhas voltam a valer nas caixas da
# CEVICO. Continuam protegidos mesmo assim: a conversa na caixa dos parceiros
# (partner_inbox?) e os agendamentos do parceiro (partner_task?).
#
# Cada bloqueio deixa uma linha "[cerca OF] bloqueado: …" no log.
module Crm::PartnerGuard
  module_function

  LABEL_PREFIX = 'of_'.freeze
  IDS_CACHE_TTL = 10.minutes # item 237: o sync chama forget! ao terminar

  def config(account)
    return {} if account.blank?

    (CrmSetting.find_by(account_id: account.id)&.agenda_config || {})['oftalmofacil'] || {}
  end

  def partner_pipeline_id(account)
    id = config(account)['partner_pipeline_id'].to_i
    id.positive? ? id : nil
  end

  def partner_inbox_ids(account)
    Array(config(account)['partner_inbox_ids']).map(&:to_i).select(&:positive?)
  end

  def partner_inbox?(account, inbox_id)
    inbox_id.present? && partner_inbox_ids(account).include?(inbox_id.to_i)
  end

  # nome do fornecedor da CEVICO dentro do hub (CATARATA_SP), em minúsculas
  def own_provider_name(account)
    config(account)['provider_name'].to_s.strip.downcase
  end

  # item do espelho que veio de um parceiro (não é o fornecedor da CEVICO)
  def partner_surgery?(surgery, own: nil)
    return false if surgery.blank?

    own = own_provider_name(surgery.account) if own.nil?
    own.present? && surgery.provider_name.to_s.downcase.exclude?(own)
  end

  # agendamento da Agenda criado pelo sync para um item de PARCEIRO
  # (source_detail = nome do parceiro; o sync deixa em branco para a CEVICO)
  def partner_task?(task)
    task.present? && task.source == 'oftalmofacil' && task.source_detail.present?
  end

  def partner_contact?(contact)
    return false if contact.blank?

    partner_marked?(contact) && !cevico_first?(contact)
  end

  # tem alguma marca de parceiro (atributo, etiqueta of_ ou card no funil deles)
  def partner_marked?(contact)
    return true if (contact.additional_attributes || {})['parceiro'].present?
    return true if contact.label_list.any? { |l| l.to_s.start_with?(LABEL_PREFIX) }

    pid = partner_pipeline_id(contact.account)
    pid.present? && Crm::Contact.exists?(contact_id: contact.id, pipeline_id: pid)
  end

  # regra B: a pessoa já era da CEVICO antes de entrar pelo parceiro?
  def cevico_first?(contact)
    contact.present? && cevico_first_ids(contact.account, [contact.id]).any?
  end

  # dos ids informados, os que têm card num funil da CEVICO criado ANTES da
  # entrada no parceiro (1º card no funil dos parceiros ou 1º item de parceiro
  # marcado no hub; sem nenhum dos dois = CEVICO)
  def cevico_first_ids(account, ids) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    ids = Array(ids).compact
    return [] if account.blank? || ids.empty?

    pid = partner_pipeline_id(account)
    own = Crm::Contact.where(contact_id: ids)
    own = own.where.not(pipeline_id: pid) if pid
    own_first = own.group(:contact_id).minimum(:created_at)
    return [] if own_first.empty?

    starts = pid ? Crm::Contact.where(contact_id: own_first.keys, pipeline_id: pid).group(:contact_id).minimum(:created_at) : {}
    items = Crm::OftalmofacilSurgery.where(account_id: account.id, contact_id: own_first.keys)
    own_name = own_provider_name(account)
    items = items.where.not('LOWER(provider_name) LIKE ?', "%#{own_name}%") if own_name.present?
    item_starts = items.group(:contact_id).minimum(Arel.sql('COALESCE(of_created_at, created_at)'))
    own_first.select do |cid, t|
      start = [starts[cid], item_starts[cid]].compact.min
      start.nil? || t < start
    end.keys
  end

  def partner_conversation?(conversation)
    return false if conversation.blank?

    partner_inbox?(conversation.account, conversation.inbox_id) || partner_contact?(conversation.contact)
  end

  # ids de todos os pacientes de parceiro da conta (públicos de campanha,
  # régua, colheita, robôs, universo de leads). Cache curto: a lista muda no
  # ritmo do sync (15 min), não a cada chamada.
  def excluded_contact_ids(account)
    return [] if account.blank?

    Rails.cache.fetch("cevico:partner_guard:ids:#{account.id}", expires_in: IDS_CACHE_TTL) { compute_excluded_ids(account) }
  end

  def compute_excluded_ids(account) # rubocop:disable Metrics/AbcSize
    ids = []
    pid = partner_pipeline_id(account)
    ids |= Crm::Contact.where(pipeline_id: pid).pluck(:contact_id) if pid

    tag_ids = ActsAsTaggableOn::Tag.where('name LIKE ?', "#{LABEL_PREFIX.gsub('_', '\\_')}%").ids
    if tag_ids.any?
      ids |= ActsAsTaggableOn::Tagging.where(tag_id: tag_ids, taggable_type: 'Contact', context: 'labels',
                                             taggable_id: account.contacts.select(:id)).pluck(:taggable_id)
    end

    inbox_ids = partner_inbox_ids(account)
    ids |= account.conversations.where(inbox_id: inbox_ids).where.not(contact_id: nil).distinct.pluck(:contact_id) if inbox_ids.any?

    ids |= account.contacts.where("COALESCE(additional_attributes->>'parceiro', '') <> ''").pluck(:id)
    ids = ids.compact.uniq
    ids - cevico_first_ids(account, ids) # regra B: quem já era da CEVICO continua lead da CEVICO
  end

  # apaga o cache (o sync chama depois de rodar)
  def forget!(account)
    Rails.cache.delete("cevico:partner_guard:ids:#{account.id}") if account.present?
  end

  # registra o bloqueio (uma linha no log) e devolve true
  def block!(where, contact: nil, conversation: nil)
    Rails.logger.info "[cerca OF] bloqueado: #{where} · contato #{contact&.id || conversation&.contact_id} · conversa #{conversation&.id}"
    true
  end
end
