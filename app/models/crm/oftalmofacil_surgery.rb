# Espelho de UMA cirurgia do OftalmoFácil (item 157) — ver a migration.
# resultado = o que sobra pra CEVICO: valor cobrado − custo do prestador −
# taxa da plataforma (fórmula do split lida no código do OftalmoFácil).
# == Schema Information
#
# Table name: cevico_oftalmofacil_surgeries
#
#  id             :bigint           not null, primary key
#  amount         :decimal(12, 2)
#  applied_action :string
#  applied_at     :datetime
#  clinic_name    :string
#  clinic_price   :decimal(12, 2)
#  doctor_crm     :string
#  eye            :string
#  item_token     :string           not null
#  match_via      :string
#  of_created_at  :datetime
#  of_modified_at :datetime
#  paid_amount    :decimal(12, 2)
#  patient_cpf    :string
#  patient_email  :string
#  patient_name   :string
#  patient_phone  :string
#  procedure_name :string
#  procedure_type :string
#  profit         :decimal(12, 2)
#  provider_name  :string
#  raw            :jsonb            not null
#  rebate         :decimal(12, 2)
#  status_kind    :string           default("outro"), not null
#  status_label   :string
#  surgery_date   :date
#  surgery_hour   :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  clinic_id      :integer
#  contact_id     :bigint
#  item_id        :integer
#  scheduling_id  :integer
#  status_id      :string
#
# Indexes
#
#  idx_on_account_id_status_kind_028c0b09a6           (account_id,status_kind)
#  idx_on_account_id_surgery_date_a7392a9e19          (account_id,surgery_date)
#  index_cevico_oftalmofacil_surgeries_on_contact_id  (contact_id)
#  index_of_surgeries_unique_token                    (account_id,item_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#
class Crm::OftalmofacilSurgery < ApplicationRecord
  self.table_name = 'cevico_oftalmofacil_surgeries'

  belongs_to :account
  belongs_to :contact, class_name: '::Contact', optional: true

  KINDS = %w[agendada realizada cancelada ausente aguardando_pagamento outro].freeze

  scope :in_period, ->(from, to) { where(surgery_date: from..to) }
  scope :realizadas, -> { where(status_kind: 'realizada') }
  scope :faturaveis, -> { where(status_kind: %w[agendada realizada aguardando_pagamento]) }

  def resultado
    amount.to_f - clinic_price.to_f - profit.to_f
  end

  # rótulo humano da classificação
  # 🕐 item 242: o MySQL do hub devolve a HORA como SEGUNDOS desde a meia-noite
  # ("39600.0" = 11:00); também aceita "11:00:00" e Time. 0/vazio = sem hora.
  def self.normalize_hour(raw)
    s = raw.respond_to?(:strftime) ? raw.strftime('%H:%M') : raw.to_s.strip
    return nil if s.blank?

    if s.match?(/\A\d+(\.\d+)?\z/)
      secs = s.to_f.round
      return nil unless secs.positive? && secs < 86_400

      return format('%<h>02d:%<m>02d', h: secs / 3600, m: (secs % 3600) / 60)
    end
    m = s.match(/(\d{1,2}):(\d{2})/)
    m ? format('%<h>02d:%<m>02d', h: m[1].to_i, m: m[2].to_i) : nil
  end

  # hora "HH:MM" mesmo nos registros gravados antes da correção
  def hour_hhmm
    self.class.normalize_hour(surgery_hour)
  end

  # data + hora no fuso de SÃO PAULO (o app roda em UTC: sem isso a hora
  # certa ainda cairia 3h antes) — sem hora = fallback
  def local_time(fallback = '08:00')
    return nil if surgery_date.blank?

    ActiveSupport::TimeZone['America/Sao_Paulo'].parse("#{surgery_date.iso8601} #{hour_hhmm || fallback}")
  end

  def status_kind_label
    {
      'agendada' => 'Agendada', 'realizada' => 'Realizada', 'cancelada' => 'Cancelada',
      'ausente' => 'Não compareceu', 'aguardando_pagamento' => 'Aguardando pagamento'
    }[status_kind] || status_label.presence || 'Outro'
  end
end
