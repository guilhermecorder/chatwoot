# Variáveis das mensagens da jornada: a partir da FONTE do evento (cirurgia
# do OftalmoFácil, consulta da Agenda, card do CRM, etiqueta, ligação) monta
# o dicionário {{token}} → valor que entra nas variáveis do modelo antes do
# Liquid. Tokens: nome, primeiro_nome, data, dia_semana, hora, unidade,
# endereco, procedimento, medico.
class Crm::Journey::Variables
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  WEEKDAYS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  TOKENS = %w[nome primeiro_nome data dia_semana hora unidade endereco procedimento medico].freeze

  def self.build(source, contact, settings)
    new(source, contact, settings).build
  end

  def initialize(source, contact, settings)
    @source = source
    @contact = contact
    @settings = settings
  end

  def build
    base = { 'nome' => name, 'primeiro_nome' => name.split.first.to_s }
    base.merge(source_values).transform_values(&:to_s)
  end

  # troca {{token}} nos VALORES das variáveis do modelo (o {{contact.name}}
  # do Liquid continua sendo tratado pelo SendTemplateService)
  def self.apply(template_params, values)
    params = template_params.deep_dup
    body = params.dig('processed_params', 'body')
    body&.transform_values! { |v| substitute(v, values) }
    params
  end

  def self.substitute(text, values)
    text.to_s.gsub(/\{\{\s*([a-z_]+)\s*\}\}/) { values.key?(Regexp.last_match(1)) ? values[Regexp.last_match(1)] : Regexp.last_match(0) }
  end

  private

  def name
    @contact&.name.presence || (@source.respond_to?(:patient_name) ? @source.patient_name.to_s : '')
  end

  def source_values
    case @source
    when Crm::OftalmofacilSurgery then surgery_values
    when Task then task_values
    else {}
    end
  end

  def surgery_values
    date = @source.surgery_date
    place = @settings.place_for(clinic_name: @source.clinic_name)
    date_values(date).merge(
      'hora' => @source.surgery_hour.to_s.presence || '',
      'unidade' => place['unidade'].presence || @source.clinic_name.to_s,
      'endereco' => place['endereco'].to_s,
      'procedimento' => @source.procedure_name.to_s,
      'medico' => @source.provider_name.to_s
    )
  end

  def task_values
    at = @source.due_at&.in_time_zone(TZ)
    place = @settings.place_for(unit: @source.unit)
    date_values(at&.to_date).merge(
      'hora' => at&.strftime('%H:%M').to_s,
      'unidade' => place['unidade'].presence || Crm::AgendaSlots::UNIT_LABELS[@source.unit.to_s] || @source.unit.to_s,
      'endereco' => place['endereco'].to_s,
      'procedimento' => @source.procedure.to_s,
      'medico' => @source.doctor.to_s
    )
  end

  def date_values(date)
    return { 'data' => '', 'dia_semana' => '' } if date.nil?

    { 'data' => date.strftime('%d/%m'), 'dia_semana' => WEEKDAYS[date.wday] }
  end
end
