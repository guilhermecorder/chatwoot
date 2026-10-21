# Variáveis das mensagens da jornada: a partir da FONTE do evento (cirurgia
# do OftalmoFácil, consulta da Agenda, card do CRM, etiqueta, ligação) monta
# o dicionário {{token}} → valor que entra nas variáveis do modelo antes do
# Liquid. Tokens: nome, primeiro_nome, data, dia_semana, hora, unidade,
# endereco, procedimento, medico.
class Crm::Journey::Variables
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  WEEKDAYS = %w[domingo segunda-feira terça-feira quarta-feira quinta-feira sexta-feira sábado].freeze
  TOKENS = %w[nome primeiro_nome data dia_semana hora unidade endereco procedimento medico].freeze

  # 🛡️ auditoria R3 (#46): a Meta recusa modelo com variável em branco (e o
  # envio ficava como "enviada"). Regra: token usado NUNCA sai vazio.
  # - texto de reserva para o que dá para contornar (unidade, endereço...);
  # - bloqueio do envio (motivo "Variável sem valor") para o que importa de
  #   verdade: cirurgia sem hora/médico/procedimento, consulta sem hora, e
  #   paciente sem nome — a equipe completa o dado e reenvia pela tela.
  FALLBACKS = {
    'nome' => 'paciente', 'primeiro_nome' => 'paciente', 'data' => 'a combinar', 'dia_semana' => 'a combinar',
    'hora' => 'a combinar', 'unidade' => 'nossa clínica', 'endereco' => 'endereço a confirmar',
    'procedimento' => 'o procedimento', 'medico' => 'nossa equipe médica'
  }.freeze
  REQUIRED = {
    'surgery' => %w[nome primeiro_nome data hora medico procedimento],
    'appointment' => %w[nome primeiro_nome data hora]
  }.freeze
  REQUIRED_DEFAULT = %w[nome primeiro_nome].freeze
  TOKEN_LABELS = {
    'nome' => 'nome', 'primeiro_nome' => 'nome', 'data' => 'data', 'dia_semana' => 'dia da semana', 'hora' => 'hora',
    'unidade' => 'unidade', 'endereco' => 'endereço', 'procedimento' => 'procedimento', 'medico' => 'médico'
  }.freeze
  TOKEN_RE = /\{\{\s*([a-z_]+)\s*\}\}/

  def self.build(source, contact, settings)
    new(source, contact, settings).build
  end

  def initialize(source, contact, settings)
    @source = source
    @contact = contact
    @settings = settings
  end

  # dicionário pronto para o modelo: o que a fonte não tem recebe o texto de
  # reserva (nunca ''); quem decide bloquear é `missing_reason`
  def build
    raw_values.to_h { |k, v| [k, v.to_s.strip.presence || FALLBACKS.fetch(k, '—')] }
  end

  # tokens que a fonte não preencheu (antes do texto de reserva)
  def blank_tokens
    raw_values.select { |_k, v| v.to_s.strip.empty? }.keys
  end

  # tokens que a mensagem usa de fato (texto livre ou variáveis do modelo;
  # `followup: true` olha o modelo do reforço)
  def self.used_tokens(message, followup: false)
    message_texts(message, followup).flat_map { |t| t.to_s.scan(TOKEN_RE).flatten }.uniq & TOKENS
  end

  # os pedaços de texto onde podem aparecer {{token}}
  def self.message_texts(message, followup)
    return [message.text] if message.mode == 'text' && !followup

    params = followup ? message.followup_template_params : message.template_params
    ((params || {}).dig('processed_params', 'body') || {}).values
  end

  # motivo para NÃO mandar (nil = pode): a mensagem usa um token obrigatório
  # para esse gatilho e a fonte está sem o dado
  def self.missing_reason(message, source, contact, settings, followup: false)
    required = REQUIRED.fetch(message.kind, REQUIRED_DEFAULT)
    missing = used_tokens(message, followup: followup) & required & new(source, contact, settings).blank_tokens
    return nil if missing.empty?

    labels = missing.map { |t| TOKEN_LABELS[t] }.uniq.join(', ')
    "Variável sem valor: #{labels} — a fonte está sem esse dado e a mensagem ia em branco"
  end

  # 🧪 dados FICTÍCIOS do botão "Testar no meu número" (#416): nada de
  # paciente real; só o lugar vem da configuração da jornada
  def self.sample(settings)
    date = TZ.today + 1
    place = settings.place_for(unit: 'paulista')
    {
      'nome' => 'Ana Exemplo', 'primeiro_nome' => 'Ana', 'data' => date.strftime('%d/%m'), 'dia_semana' => WEEKDAYS[date.wday],
      'hora' => '09:30', 'unidade' => place['unidade'].presence || 'Unidade de exemplo',
      'endereco' => place['endereco'].presence || 'Endereço de exemplo, 100', 'procedimento' => 'Cirurgia de exemplo',
      'medico' => 'Dr. Exemplo'
    }
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

  # valores crus (podem vir vazios da fonte). Começa do dicionário COMPLETO:
  # gatilho de coluna/etiqueta/ligação não tem hora/unidade/médico, mas a tela
  # oferece todos os tokens — token que a fonte não tem precisa contar como
  # vazio (ganha texto de reserva em `build` e aparece em `blank_tokens`), em
  # vez de sair literal "{{hora}}" para o paciente no modo texto.
  def raw_values
    base = { 'nome' => name, 'primeiro_nome' => name.split.first.to_s }
    TOKENS.index_with { '' }.merge(base).merge(source_values).transform_values(&:to_s)
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
