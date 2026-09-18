# 🗺️ Uma MENSAGEM DA JORNADA (item 168): o quê (modelo aprovado ou texto
# livre), quando (gatilho de data/etapa + hora) e para quem (público). O
# motor (Crm::Journey::Planner + Dispatcher) cria e envia os
# Crm::JourneySend a partir daqui.
#
# trigger (jsonb):
#   kind: 'surgery'      → dia da cirurgia no espelho do OftalmoFácil (status agendada)
#         'appointment'  → dia da consulta na Agenda (task consulta)
#         'stage'        → entrou na coluna stage_id do CRM
#         'label'        → recebeu a etiqueta `label`
#         'call_missed'  → ligação perdida sem retorno (item 167)
#   offset_days: -1 = véspera, 0 = no dia, 3 = 3 dias depois
#   at: 'HH:MM' (hora de envio, São Paulo)
# == Schema Information
#
# Table name: cevico_journey_messages
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  approval      :string           default("auto"), not null
#  audience      :jsonb            not null
#  confirm_label :string
#  content       :jsonb            not null
#  decline_alert :boolean          default(TRUE), not null
#  expects_reply :boolean          default(FALSE), not null
#  name          :string           not null
#  position      :integer          default(0), not null
#  respect_quiet :boolean          default(TRUE), not null
#  step          :string           default("consulta"), not null
#  trigger       :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  inbox_id      :bigint
#
# Indexes
#
#  index_cevico_journey_messages_on_account_id             (account_id)
#  index_cevico_journey_messages_on_account_id_and_active  (account_id,active)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Crm::JourneyMessage < ApplicationRecord
  self.table_name = 'cevico_journey_messages'

  STEPS = {
    'lead' => 'Lead', 'consulta' => 'Consulta', 'orcamento' => 'Orçamento',
    'cirurgia' => 'Cirurgia agendada', 'pos_op' => 'Pós-operatório', 'retorno' => 'Retorno'
  }.freeze
  KINDS = %w[surgery appointment stage label call_missed].freeze
  KIND_LABELS = {
    'surgery' => 'Dia da cirurgia (OftalmoFácil)', 'appointment' => 'Dia da consulta (Agenda)',
    'stage' => 'Entrou na coluna do CRM', 'label' => 'Recebeu a etiqueta', 'call_missed' => 'Ligação perdida sem retorno'
  }.freeze
  APPROVALS = %w[auto review].freeze
  MODES = %w[template text].freeze
  OFFSET_RANGE = (-30..365)

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :sends, class_name: 'Crm::JourneySend', dependent: :destroy, inverse_of: :journey_message

  validates :name, presence: true, length: { maximum: 120 }
  validates :step, inclusion: { in: STEPS.keys }
  validates :approval, inclusion: { in: APPROVALS }
  validate :trigger_is_sane
  validate :content_is_sane

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  def kind = trigger['kind'].to_s
  def offset_days = trigger['offset_days'].to_i
  def send_at = trigger['at'].presence || '10:00'
  def mode = content['mode'].presence || 'template'
  def template_params = content['template_params']
  def message_preview = content['message_preview'].presence
  def text = content['text'].to_s

  def review? = approval == 'review'

  # o Crm::Campaign resolve o público com as mesmas chaves da Campanha WhatsApp
  def audience_filter?
    %w[include_label_ids include_stage_ids exclude_label_ids exclude_stage_ids].any? { |k| Array(audience[k]).any? }
  end

  def audience_contact_ids
    Crm::Campaign.new(account: account, audience: audience || {}).resolve_audience.pluck(:id)
  end

  def kind_label = KIND_LABELS[kind] || kind
  def step_label = STEPS[step] || step

  # "véspera da cirurgia às 10:00" — texto humano do gatilho
  def when_label
    base = case offset_days
           when -1 then 'véspera'
           when 0 then 'no dia'
           when 1 then '1 dia depois'
           else offset_days.negative? ? "#{offset_days.abs} dias antes" : "#{offset_days} dias depois"
           end
    "#{base} · #{send_at}"
  end

  def to_payload
    {
      id: id, name: name, active: active, step: step, step_label: step_label, inbox_id: inbox_id,
      trigger: trigger, kind_label: kind_label, when_label: when_label, audience: audience, content: content,
      approval: approval, expects_reply: expects_reply, confirm_label: confirm_label, decline_alert: decline_alert,
      respect_quiet: respect_quiet, position: position, created_at: created_at&.iso8601, updated_at: updated_at&.iso8601
    }
  end

  private

  def trigger_is_sane
    errors.add(:trigger, 'escolha o gatilho da mensagem') unless KINDS.include?(kind)
    errors.add(:trigger, 'a hora precisa ser HH:MM') unless send_at.match?(/\A([01]\d|2[0-3]):[0-5]\d\z/)
    errors.add(:trigger, 'dias fora do intervalo') unless OFFSET_RANGE.cover?(offset_days)
    trigger_target_is_sane
  end

  def trigger_target_is_sane
    errors.add(:trigger, 'escolha a coluna do CRM') if kind == 'stage' && trigger['stage_id'].blank?
    errors.add(:trigger, 'escolha a etiqueta') if kind == 'label' && trigger['label'].blank?
  end

  def content_is_sane
    errors.add(:content, 'tipo de conteúdo inválido') unless MODES.include?(mode)
    errors.add(:content, 'escolha a mensagem modelo') if mode == 'template' && template_params.blank?
    errors.add(:content, 'escreva o texto') if mode == 'text' && text.strip.blank?
  end
end
