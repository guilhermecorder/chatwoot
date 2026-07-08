class Crm::Campaign < ApplicationRecord
  self.table_name = 'crm_campaigns'

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true
  has_many :campaign_contacts, class_name: 'Crm::CampaignContact', foreign_key: :campaign_id, dependent: :destroy

  validates :name, presence: true
  validates :template_params, presence: true
  validate :inbox_must_be_whatsapp_cloud

  enum status: { draft: 0, processing: 1, completed: 2, failed: 3 }

  # Resultados: cruza quem recebeu a campanha com os cards do CRM que
  # chegaram nas colunas de conversão (ex: "Cirurgia Realizada").
  # Futuramente o Oftalmofácil alimentará estes mesmos dados em tempo real.
  def converted_crm_contacts
    return Crm::Contact.none if Array(conversion_stage_ids).empty?

    Crm::Contact.joins(:pipeline)
                .where(crm_pipelines: { account_id: account_id })
                .where(contact_id: campaign_contacts.select(:contact_id))
                .where(stage_id: Array(conversion_stage_ids))
                .includes(:contact, :stage)
  end

  # audience (jsonb):
  #   include_label_ids:  [1, 2]   — contatos com qualquer uma dessas etiquetas
  #   include_stage_ids:  [3, 4]   — contatos com card nessas colunas do CRM
  #   exclude_label_ids:  [5]      — remove do público quem tem essas etiquetas
  #   exclude_stage_ids:  [6]      — remove quem tem card nessas colunas
  def resolve_audience
    contacts = included_contacts
    contacts = contacts.where.not(id: excluded_contact_ids) if excluded_contact_ids.any?
    contacts.where.not(phone_number: [nil, '']).distinct
  end

  private

  def included_contacts
    ids = []
    label_ids = Array(audience['include_label_ids'])
    stage_ids = Array(audience['include_stage_ids'])

    if label_ids.any?
      titles = account.labels.where(id: label_ids).pluck(:title)
      ids |= account.contacts.tagged_with(titles, any: true).pluck(:id) if titles.any?
    end

    if stage_ids.any?
      ids |= Crm::Contact.joins(:pipeline)
                         .where(crm_pipelines: { account_id: account.id }, stage_id: stage_ids)
                         .pluck(:contact_id)
    end

    account.contacts.where(id: ids)
  end

  def excluded_contact_ids
    ids = []
    label_ids = Array(audience['exclude_label_ids'])
    stage_ids = Array(audience['exclude_stage_ids'])

    if label_ids.any?
      titles = account.labels.where(id: label_ids).pluck(:title)
      ids |= account.contacts.tagged_with(titles, any: true).pluck(:id) if titles.any?
    end

    if stage_ids.any?
      ids |= Crm::Contact.joins(:pipeline)
                         .where(crm_pipelines: { account_id: account.id }, stage_id: stage_ids)
                         .pluck(:contact_id)
    end

    ids
  end

  def inbox_must_be_whatsapp_cloud
    return if inbox.blank?
    return if inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'

    errors.add(:inbox, 'deve ser um canal WhatsApp Cloud (API oficial)')
  end
end
