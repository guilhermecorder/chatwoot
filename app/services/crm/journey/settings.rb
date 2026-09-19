# Configuração geral da jornada (crm_settings.agenda_config['journey']):
# locais/endereços por unidade e por clínica do OftalmoFácil (viram
# {{unidade}}/{{endereco}}), janela de envio e teto diário.
class Crm::Journey::Settings
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DEFAULT_HOURS = { 'start' => '08:00', 'end' => '20:00' }.freeze
  DEFAULT_DAILY_CAP = 300
  # convenção da base: quem tem nao_perturbe ou perda_* não recebe robô nenhum
  QUIET_LABELS_FIXED = %w[nao_perturbe].freeze
  QUIET_LABEL_PREFIXES = %w[perda_].freeze

  attr_reader :account

  def initialize(account, crm_settings: nil)
    @account = account
    @crm_settings = crm_settings
  end

  def raw
    @raw ||= (crm_settings&.agenda_config || {})['journey'] || {}
  end

  # { default: {unidade, endereco}, tatuape: {...}, paulista: {...}, clinics: { 'IOP' => {...} } }
  def places
    raw['places'] || {}
  end

  # local para uma consulta (task.unit) ou cirurgia (clinic_name)
  def place_for(unit: nil, clinic_name: nil)
    by_unit = unit.present? ? places[unit.to_s] : nil
    by_clinic = clinic_name.present? ? clinic_place(clinic_name) : nil
    (by_clinic || by_unit || places['default'] || {}).to_h
  end

  def hours
    DEFAULT_HOURS.merge((raw['hours'] || {}).to_h.slice('start', 'end').compact_blank)
  end

  def within_hours?(now = TZ.now)
    hhmm = now.strftime('%H:%M')
    hhmm >= hours['start'] && hhmm < hours['end']
  end

  def daily_cap
    value = raw['daily_cap'].to_i
    value.positive? ? value : DEFAULT_DAILY_CAP
  end

  def quiet_labels
    QUIET_LABELS_FIXED + Array(raw['quiet_labels']).map(&:to_s)
  end

  def quiet?(labels)
    names = Array(labels).map(&:to_s)
    names.any? { |l| quiet_labels.include?(l) || QUIET_LABEL_PREFIXES.any? { |p| l.start_with?(p) } }
  end

  def to_h
    { places: places, hours: hours, daily_cap: daily_cap, quiet_labels: Array(raw['quiet_labels']), map: (raw['map'] || {}).to_h }
  end

  private

  def crm_settings
    @crm_settings ||= CrmSetting.find_by(account: account)
  end

  # casa por clínica: chave exata ou "contém" (IOP ↔ "IOP - Instituto…")
  def clinic_place(name)
    clinics = (places['clinics'] || {}).to_h
    return clinics[name] if clinics[name]

    down = name.to_s.downcase
    _key, value = clinics.find { |k, _v| down.include?(k.to_s.downcase) || k.to_s.downcase.include?(down) }
    value
  end
end
