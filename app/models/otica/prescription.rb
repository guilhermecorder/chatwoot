# Receita (grau) do cliente: médico, data, validade e os valores de cada
# olho — esfera, cilindro, eixo, adição, DNP e altura. A foto é um link
# (upload de arquivo entra em fase posterior).
# == Schema Information
#
# Table name: otica_prescriptions
#
#  id            :bigint           not null, primary key
#  doctor_name   :string           default("")
#  notes         :string           default("")
#  od_addition   :decimal(6, 2)
#  od_axis       :integer
#  od_cylinder   :decimal(6, 2)
#  od_dnp        :decimal(6, 2)
#  od_height     :decimal(6, 2)
#  od_sphere     :decimal(6, 2)
#  oe_addition   :decimal(6, 2)
#  oe_axis       :integer
#  oe_cylinder   :decimal(6, 2)
#  oe_dnp        :decimal(6, 2)
#  oe_height     :decimal(6, 2)
#  oe_sphere     :decimal(6, 2)
#  photo_url     :string           default("")
#  prescribed_on :date
#  valid_until   :date
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  contact_id    :bigint           not null
#
# Indexes
#
#  index_otica_prescriptions_on_account_id  (account_id)
#  index_otica_prescriptions_on_contact_id  (contact_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#
class Otica::Prescription < ApplicationRecord
  belongs_to :account
  belongs_to :contact, class_name: '::Contact'
  has_many :orders, class_name: 'Otica::Order', dependent: :nullify, inverse_of: :prescription

  EYES = %w[od oe].freeze
  FIELDS = %w[sphere cylinder axis addition dnp height].freeze

  validates :od_axis, :oe_axis, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 180 }, allow_nil: true

  def eye(prefix)
    FIELDS.index_with do |f|
      value = public_send("#{prefix}_#{f}")
      f == 'axis' ? value : value&.to_f
    end
  end

  def as_json_otica
    { id: id, doctor_name: doctor_name, prescribed_on: prescribed_on&.iso8601, valid_until: valid_until&.iso8601,
      notes: notes, photo_url: photo_url, od: eye('od'), oe: eye('oe') }
  end

  # "OD -2,00 -0,50 180° · OE -1,75" para o resumo do WhatsApp e o card
  def summary # rubocop:disable Metrics/CyclomaticComplexity
    EYES.filter_map do |prefix|
      sphere = public_send("#{prefix}_sphere")
      cylinder = public_send("#{prefix}_cylinder")
      axis = public_send("#{prefix}_axis")
      addition = public_send("#{prefix}_addition")
      next if [sphere, cylinder, axis, addition].all?(&:nil?)

      parts = [prefix.upcase]
      parts << format_dioptry(sphere) if sphere
      parts << format_dioptry(cylinder) if cylinder
      parts << "#{axis}°" if axis
      parts << "ad. #{format_dioptry(addition)}" if addition
      parts.join(' ')
    end.join(' · ')
  end

  def format_dioptry(value)
    number = value.to_f
    sign = number.positive? ? '+' : ''
    "#{sign}#{format('%.2f', number).tr('.', ',')}"
  end
end
