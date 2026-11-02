# 02/11: QUEM SÃO os leads das Páginas num período — a lista com nome,
# página de origem (ou linktree), origem da visita (Google Ads, SEO, Meta…),
# data, a caixa do WhatsApp em que a conversa caiu e o link da conversa.
# Pedido do Guilherme: "os leads que vieram do linktree, hipermetropia e tal,
# eu não tenho acesso a isso e precisava ter".
#
# Mesma fonte dos números de Resultados de tráfego (Cevico::TrafficReport):
# contatos carimbados com page_ads (Protocolo) pela data do carimbo.
class Cevico::LeadRoster
  LIMIT = 500
  ATTR_PRE = Cevico::PageLead::ATTR

  def initialize(account, since_date, until_date, source: nil, page_id: nil)
    @account = account
    @since_date = since_date
    @until_date = until_date
    @source = source
    @page_id = page_id
  end

  def call
    contacts = scope.to_a
    conversations = latest_conversations(contacts.map(&:id))
    pages = pages_by_id(contacts)
    cards = booked_contact_ids(contacts.map(&:id))
    contacts.map { |contact| row(contact, conversations[contact.id], pages, cards) }
  end

  private

  def scope
    rel = @account.contacts
                  .where("additional_attributes -> 'page_ads' IS NOT NULL")
                  .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz >= ?", @since_date.beginning_of_day)
                  .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz <= ?", @until_date.end_of_day)
    rel = rel.where("additional_attributes -> 'page_ads' ->> 'source' = ?", @source) if @source.present?
    rel = rel.where("(additional_attributes -> 'page_ads' ->> 'page_id')::bigint = ?", @page_id) if @page_id.present?
    rel.order(Arel.sql("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz DESC")).limit(LIMIT)
  end

  # a conversa mais recente de cada contato (é nela que a equipe responde)
  def latest_conversations(contact_ids)
    return {} if contact_ids.empty?

    inboxes = @account.inboxes.pluck(:id, :name).to_h
    Conversation.where(account_id: @account.id, contact_id: contact_ids)
                .order(created_at: :desc)
                .pluck(:contact_id, :id, :inbox_id, :status, :created_at)
                .each_with_object({}) do |(contact_id, id, inbox_id, status, created_at), out|
      out[contact_id] ||= { id: id, inbox: inboxes[inbox_id], status: status, created_at: created_at }
    end
  end

  def pages_by_id(contacts)
    ids = contacts.filter_map { |c| c.additional_attributes.dig('page_ads', 'page_id') }.uniq
    @account.cevico_pages.where(id: ids).pluck(:id, :slug, :title).to_h { |id, slug, title| [id, { slug: slug, title: title }] }
  end

  # tem card numa coluna de agendamento ou além (mesma régua do relatório)
  def booked_contact_ids(contact_ids)
    return Set.new if contact_ids.empty?

    stage_ids = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
                          .where('crm_stages.name ILIKE ?', '%agend%').select(:id)
    Crm::Contact.where(contact_id: contact_ids, stage_id: stage_ids).pluck(:contact_id).to_set
  rescue StandardError
    Set.new
  end

  def row(contact, conversation, pages, cards)
    ads = contact.additional_attributes['page_ads'] || {}
    page = pages[ads['page_id']] || { slug: 'hub', title: ads['title'].presence || 'Linktree (porta de entrada)' }
    {
      id: contact.id, nome: contact.name.presence || 'Sem nome', telefone: contact.phone_number,
      pagina: page[:title], slug: page[:slug],
      origem: ads['source'].presence || 'direto', campanha: ads['campaign'].presence,
      em: ads['captured_at'], via: ads['via'].presence || 'whatsapp',
      pre_analise: contact.additional_attributes.dig(ATTR_PRE, 'respostas'),
      conversa: conversation, agendou: cards.include?(contact.id)
    }
  end
end
