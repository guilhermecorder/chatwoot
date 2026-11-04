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

  # ⏸ R3 da auditoria (#415): "paused" = a equipe pediu para parar (campanha
  # em envio ou agendada). Quem já recebeu fica registrado; "Enviar agora"
  # retoma de onde parou sem repetir ninguém.
  enum status: { draft: 0, processing: 1, completed: 2, failed: 3, scheduled: 4, paused: 5 }

  # 🕐 R3 da auditoria (CONTRATO-0/#411): o Rails deste sistema roda em UTC e
  # as datas digitadas pela equipe são de São Paulo — mesmo fuso que o resto
  # do CEVICO usa (Crm::AgendaSlots, Crm::NpsSurvey...).
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  scope :due, -> { scheduled.where('scheduled_at <= ?', Time.current) }

  # Resultados: cruza quem recebeu a campanha com os cards do CRM que
  # chegaram nas colunas de conversão (ex: "Cirurgia Realizada").
  # Futuramente o Oftalmofácil alimentará estes mesmos dados em tempo real.
  def converted_crm_contacts
    return Crm::Contact.none if Array(conversion_stage_ids).empty?

    Crm::Contact.joins(:pipeline)
                .where(crm_pipelines: { account_id: account_id })
                .where(contact_id: recipients.select(:contact_id))
                .where(stage_id: Array(conversion_stage_ids))
                .includes(:contact, :stage)
  end

  # 🔁 item 379: campanha RECORRENTE (mãe) — regras em audience['recurrence'];
  # cada rodada é uma campanha-filha (audience['parent_id']). Ver Crm::RecurringCampaign.
  def recurrence_rules
    Crm::RecurringCampaign.rules(audience)
  end

  def recurring?
    Crm::RecurringCampaign.mother?(self)
  end

  def parent_id
    id = Crm::RecurringCampaign.parent_id(self)
    id.positive? ? id : nil
  end

  # 📣 item 381: plano de reativação em fatias (mãe com audience['reactivation_plan'])
  def reactivation_plan?
    Crm::ReactivationPlan.plan?(self)
  end

  # quem recebeu: a campanha comum olha os seus destinatários; a mãe (recorrente
  # ou plano) soma as rodadas
  def recipients
    return campaign_contacts unless recurring? || reactivation_plan?

    Crm::CampaignContact.where(campaign_id: Crm::RecurringCampaign.family_ids(self))
  end

  # audience (jsonb):
  #   include_label_ids:  [1, 2]   — contatos com qualquer uma dessas etiquetas
  #   include_stage_ids:  [3, 4]   — contatos com card nessas colunas do CRM
  #   exclude_label_ids:  [5]      — remove do público quem tem essas etiquetas
  #   exclude_stage_ids:  [6]      — remove quem tem card nessas colunas
  #   period_field: 'contact_created' | 'label_applied' — filtro de período
  #   period_from / period_to: datas (ISO) para acionar a base em blocos
  def resolve_audience # rubocop:disable Metrics/AbcSize
    contacts = included_contacts
    contacts = contacts.where.not(id: excluded_contact_ids) if excluded_contact_ids.any?
    # opt-out fixo (conformidade 20/09): nao_perturbe / perda_* nunca entram
    quiet_ids = Crm::OptOut.excluded_contact_ids(account)
    contacts = contacts.where.not(id: quiet_ids) if quiet_ids.any?
    # 🚧 item 231 (cerca dos parceiros): paciente de parceiro do hub nunca entra
    partner_ids = Crm::PartnerGuard.excluded_contact_ids(account)
    contacts = contacts.where.not(id: partner_ids) if partner_ids.any?
    # 🧪 item 383: quem está num SEGMENTO (teste de mensagens ou escala) é da
    # Segmentação — campanha comum e recorrente não encostam nessa pessoa, para
    # o teste não ser contaminado e ninguém receber duas abordagens
    contacts = contacts.where.not(id: Crm::SegmentMember.holding.joins(:segment).where(crm_segments: { account_id: account_id }).select(:contact_id))
    contacts = apply_period_filter(contacts)
    apply_recurrence(contacts.where.not(phone_number: [nil, '']).distinct)
  end

  private

  # 🔁 item 379: as regras da cadência (quem recebeu há pouco, atendimento em
  # andamento, consulta marcada, idade mínima, teto da rodada) valem para a
  # mãe (prévia) e para cada rodada (filha)
  def apply_recurrence(contacts)
    rules = recurrence_rules
    return contacts if rules.blank?

    excluded = Crm::RecurringCampaign.excluded_ids(self, rules)
    contacts = contacts.where.not(id: excluded) if excluded.any?
    Crm::RecurringCampaign.shape(contacts, rules)
  end

  # 🕐 R3 da auditoria (#411): "de 01/10 a 01/10" é o DIA de São Paulo
  # inteiro (00:00 até 23:59:59 no fuso da clínica), não o dia em UTC —
  # senão o lead das 21h–0h do último dia ficava de fora e o das 21h+ do dia
  # anterior entrava.
  def period_range
    from = parse_period_day(audience['period_from'])&.beginning_of_day
    to   = parse_period_day(audience['period_to'])&.end_of_day
    return nil if from.blank? && to.blank?

    (from || 100.years.ago)..(to || Time.current)
  end

  # "2026-10-01" → meia-noite desse dia em São Paulo; vazio/inválido → nil
  def parse_period_day(raw)
    return nil if raw.blank?

    TZ.parse(raw.to_s)
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
