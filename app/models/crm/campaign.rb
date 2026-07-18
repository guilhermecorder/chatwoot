# == Schema Information
#
# Table name: crm_campaigns
#
#  id                   :bigint           not null, primary key
#  apply_label          :string
#  audience             :jsonb            not null
#  conversion_label_ids :jsonb            not null
#  conversion_stage_ids :jsonb            not null
#  finished_at          :datetime
#  message_preview      :text
#  name                 :string           not null
#  scheduled_at         :datetime
#  started_at           :datetime
#  stats                :jsonb            not null
#  status               :integer          default("draft"), not null
#  template_params      :jsonb            not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  inbox_id             :bigint           not null
#  sender_id            :bigint
#
# Indexes
#
#  index_crm_campaigns_on_account_id             (account_id)
#  index_crm_campaigns_on_account_id_and_status  (account_id,status)
#  index_crm_campaigns_on_inbox_id               (inbox_id)
#  index_crm_campaigns_on_scheduled_at           (scheduled_at)
#  index_crm_campaigns_on_sender_id              (sender_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sender_id => users.id)
#
class Crm::Campaign < ApplicationRecord
  self.table_name = 'crm_campaigns'

  belongs_to :account
  belongs_to :inbox
  belongs_to :sender, class_name: 'User', optional: true
  has_many :campaign_contacts, class_name: 'Crm::CampaignContact', foreign_key: :campaign_id, dependent: :destroy

  validates :name, presence: true
  validates :template_params, presence: true
  validate :inbox_must_be_whatsapp_cloud
  validate :inbox_belongs_to_account

  enum status: { draft: 0, processing: 1, completed: 2, failed: 3, scheduled: 4 }

  scope :due, -> { scheduled.where('scheduled_at <= ?', Time.current) }

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
  #   period_field: 'contact_created' | 'label_applied' — filtro de período
  #   period_from / period_to: datas (ISO) para acionar a base em blocos
  def resolve_audience
    contacts = included_contacts
    contacts = contacts.where.not(id: excluded_contact_ids) if excluded_contact_ids.any?
    contacts = apply_period_filter(contacts)
    contacts.where.not(phone_number: [nil, '']).distinct
  end

  private

  def period_range
    from = audience['period_from'].presence && Date.parse(audience['period_from']).beginning_of_day
    to   = audience['period_to'].presence && Date.parse(audience['period_to']).end_of_day
    return nil if from.blank? && to.blank?

    (from || 100.years.ago)..(to || Time.current)
  rescue ArgumentError
    nil
  end

  def apply_period_filter(contacts)
    range = period_range
    return contacts if range.blank?
    return contacts.where(created_at: range) unless audience['period_field'] == 'label_applied'

    # etiqueta aplicada no período: usa a data de criação da tagging
    titles = account.labels.where(id: Array(audience['include_label_ids'])).pluck(:title)
    return contacts if titles.empty?

    tag_ids = ActsAsTaggableOn::Tag.where(name: titles).pluck(:id)
    tagged_ids = ActsAsTaggableOn::Tagging.where(
      tag_id: tag_ids, taggable_type: 'Contact', context: 'labels', created_at: range
    ).pluck(:taggable_id)
    contacts.where(id: tagged_ids)
  end

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

  # higiene multi-tenant: a caixa tem que ser da MESMA conta da campanha
  def inbox_belongs_to_account
    return if inbox.blank? || account_id.blank?
    return if inbox.account_id == account_id

    errors.add(:inbox, 'não pertence a esta conta')
  end
end
