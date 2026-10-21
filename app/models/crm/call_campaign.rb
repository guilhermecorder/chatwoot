# 🤖📞 Campanha de ligação (item 169): a assistente virtual liga para um
# público (mesmas chaves de audiência da Campanha WhatsApp) com um objetivo.
# O discador (Crm::VoiceAgent::CampaignDialerJob) consome a fila de
# contatos respeitando horário, teto diário e ligações simultâneas; o
# pós-chamada fecha cada contato com o resultado.
# == Schema Information
#
# Table name: cevico_call_campaigns
#
#  id            :bigint           not null, primary key
#  apply_label   :string
#  audience      :jsonb            not null
#  concurrency   :integer          default(2), not null
#  daily_cap     :integer          default(50), not null
#  finished_at   :datetime
#  first_message :text
#  hours         :jsonb
#  name          :string           not null
#  objective     :text
#  scheduled_at  :datetime
#  started_at    :datetime
#  stats         :jsonb            not null
#  status        :integer          default("draft"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_cevico_call_campaigns_on_account_id             (account_id)
#  index_cevico_call_campaigns_on_account_id_and_status  (account_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::CallCampaign < ApplicationRecord
  self.table_name = 'cevico_call_campaigns'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :campaign_contacts, class_name: 'Crm::CallCampaignContact',
                               inverse_of: :call_campaign, dependent: :destroy
  has_many :calls, class_name: 'Crm::Call', foreign_key: :campaign_id, inverse_of: :campaign, dependent: :nullify

  enum :status, { draft: 0, scheduled: 1, processing: 2, paused: 3, completed: 4, failed: 5 }

  validates :name, presence: true
  validates :daily_cap, numericality: { greater_than: 0, less_than_or_equal_to: 1000 }
  validates :concurrency, numericality: { greater_than: 0, less_than_or_equal_to: 20 }

  scope :due, -> { scheduled.where(scheduled_at: ..Time.current) }

  # mesmo público da Campanha WhatsApp (etiquetas/colunas/período)
  def resolve_audience
    Crm::Campaign.new(account: account, audience: audience || {}).resolve_audience
  end

  # Começar: resolve o público e enfileira quem ainda não está na campanha
  # (idempotente — Retomar/Começar de novo não duplica ninguém)
  def start!
    existing = campaign_contacts.pluck(:contact_id).to_set
    resolve_audience.find_each do |contact|
      next if existing.include?(contact.id)

      campaign_contacts.create!(contact: contact, status: 'queued')
    end
    update!(status: :processing, started_at: started_at || Time.current, finished_at: nil)
    refresh_stats!
  end

  # { total, queued, calling, done, failed, skipped, no_permission }
  def progress
    counts = campaign_contacts.group(:status).count
    base = Crm::CallCampaignContact::STATUSES.index_with { |status| counts[status].to_i }
    { total: counts.values.sum }.merge(base.symbolize_keys)
  end

  # { 'agendou consulta' => 3, ... } (rótulos pt-BR)
  def outcomes
    campaign_contacts.where.not(outcome: [nil, '']).group(:outcome).count
                     .transform_keys { |key| Crm::Call::OUTCOME_LABELS[key] || key }
  end

  # stats desnormalizado p/ a lista (a fonte da verdade são os contatos)
  def refresh_stats!
    p = progress
    update_column(:stats, { # rubocop:disable Rails/SkipsModelValidations
                    'total' => p[:total], 'called' => p[:total] - p[:queued], 'done' => p[:done],
                    'failed' => p[:failed] + p[:no_permission], 'skipped' => p[:skipped], 'outcomes' => outcomes
                  })
  end

  # fila vazia e ninguém no meio da ligação = campanha concluída
  def finish_if_done!
    return unless processing?
    return if campaign_contacts.exists?(status: %w[queued calling])

    update!(status: :completed, finished_at: Time.current)
  end
end
