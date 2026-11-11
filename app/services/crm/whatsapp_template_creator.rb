# 📨 item 391 (11/11): CRIAR mensagem modelo do WhatsApp daqui do sistema.
#
# Até agora o modelo nascia só no Gerenciador do WhatsApp da Meta, número por
# número — por isso as caixas INSTAGRAM 2 e ORGÂNICO ficaram sem os modelos de
# follow-up que a GOOGLE e a INSTAGRAM têm. Aqui o administrador escreve o
# modelo UMA vez, escolhe os números e o sistema pede a aprovação à Meta em
# cada conta do WhatsApp (o mesmo caminho que a pesquisa de satisfação já usa:
# POST /<conta do WhatsApp>/message_templates). A Meta analisa e aprova ou
# recusa; a lista de modelos é atualizada na hora para mostrar "em análise".
#
# Só texto: título (opcional), mensagem com {{1}}, {{2}}…, rodapé (opcional) e
# até 3 botões de resposta. Modelo com foto/vídeo no topo continua nascendo na
# Meta (precisa enviar o arquivo por outro caminho).
#
# Uso:
#   Crm::WhatsappTemplateCreator.new(account, spec).call(inboxes)
#   # => { ok:, errors: [texto…], results: [{ inbox_id:, inbox_name:, ok:, status:, error: }] }
class Crm::WhatsappTemplateCreator
  NAME = /\A[a-z0-9_]{1,512}\z/
  CATEGORIES = %w[MARKETING UTILITY].freeze
  LIMITS = { header: 60, body: 1024, footer: 60, button: 25 }.freeze
  MAX_BUTTONS = 3
  VARIABLE = /\{\{\s*(\d+)\s*\}\}/
  TIMEOUT = 20

  def initialize(account, spec)
    @account = account
    @spec = normalize(spec)
  end

  def call(inboxes)
    errors = validation_errors
    channels = cloud_channels(inboxes)
    errors << 'Escolha pelo menos um número de WhatsApp ligado direto à Meta.' if channels.empty?
    return { ok: false, errors: errors, results: [] } if errors.any?

    results = channels.group_by { |channel| channel.provider_config['business_account_id'].to_s }
                      .flat_map { |_waba, group| submit(group) }
    { ok: results.all? { |row| row[:ok] }, errors: [], results: results }
  end

  # o corpo que vai para a Meta (também serve para a tela mostrar a prévia)
  def payload
    { name: @spec[:name], language: @spec[:language], category: @spec[:category], components: components }
  end

  private

  def normalize(spec)
    spec = spec.to_h.with_indifferent_access
    texts = %i[name header body footer].index_with { |key| spec[key].to_s.strip }
    texts.merge(category: spec[:category].to_s.upcase.presence || 'MARKETING',
                language: spec[:language].to_s.strip.presence || 'pt_BR',
                buttons: clean_list(spec[:buttons]).compact_blank, examples: clean_list(spec[:examples]))
  end

  def clean_list(values)
    Array(values).map { |text| text.to_s.strip }
  end

  # ── conferência antes de pedir à Meta (ela recusa tudo isto, em inglês) ───
  def validation_errors
    [name_error, category_error, header_error, body_error, variables_error, footer_error, buttons_error].compact
  end

  def name_error
    'O nome do modelo só pode ter letras minúsculas sem acento, números e _ (ex.: retorno_combinado).' unless @spec[:name].match?(NAME)
  end

  def category_error
    'Escolha o tipo do modelo: Marketing ou Utilidade.' unless CATEGORIES.include?(@spec[:category])
  end

  def header_error
    header = @spec[:header]
    return if header.blank?
    return "O título passa de #{LIMITS[:header]} letras." if header.length > LIMITS[:header]

    'O título não pode ter quebra de linha, negrito (*) nem campo {{1}}.' if header.match?(/[\n*_~]/) || header.match?(VARIABLE)
  end

  def body_error
    body = @spec[:body]
    return 'Escreva a mensagem.' if body.blank?
    return "A mensagem passa de #{LIMITS[:body]} letras." if body.length > LIMITS[:body]

    'A mensagem não pode começar nem terminar com um campo {{1}}: a Meta recusa.' if body.match?(/\A#{VARIABLE}/o) || body.match?(/#{VARIABLE}\z/o)
  end

  def variables_error
    numbers = variable_numbers
    return if numbers.empty?
    return 'Os campos têm de ir em ordem, sem pular: {{1}}, {{2}}, {{3}}…' unless numbers == (1..numbers.size).to_a

    examples = @spec[:examples].first(numbers.size)
    'Dê um exemplo para cada campo {{1}}, {{2}}… (a Meta exige para analisar).' if examples.size < numbers.size || examples.any?(&:blank?)
  end

  def footer_error
    footer = @spec[:footer]
    return if footer.blank?
    return "O rodapé passa de #{LIMITS[:footer]} letras." if footer.length > LIMITS[:footer]

    'O rodapé não pode ter campo {{1}}.' if footer.match?(VARIABLE)
  end

  def buttons_error
    buttons = @spec[:buttons]
    return "São no máximo #{MAX_BUTTONS} botões." if buttons.size > MAX_BUTTONS
    return "Cada botão tem no máximo #{LIMITS[:button]} letras." if buttons.any? { |text| text.length > LIMITS[:button] }

    'Dois botões não podem ter o mesmo texto.' if buttons.uniq.size != buttons.size
  end

  def variable_numbers
    @spec[:body].scan(VARIABLE).flatten.map(&:to_i).uniq.sort
  end

  # ── o modelo no formato da Meta ──────────────────────────────────────────
  def components
    [header_component, body_component, footer_component, buttons_component].compact
  end

  def header_component
    { type: 'HEADER', format: 'TEXT', text: @spec[:header] } if @spec[:header].present?
  end

  def body_component
    body = { type: 'BODY', text: @spec[:body] }
    count = variable_numbers.size
    body[:example] = { body_text: [@spec[:examples].first(count)] } if count.positive?
    body
  end

  def footer_component
    { type: 'FOOTER', text: @spec[:footer] } if @spec[:footer].present?
  end

  def buttons_component
    return if @spec[:buttons].empty?

    { type: 'BUTTONS', buttons: @spec[:buttons].map { |text| { type: 'QUICK_REPLY', text: text } } }
  end

  # ── envio ────────────────────────────────────────────────────────────────
  # só número ligado direto à Meta (WhatsApp Cloud) e com a conta do WhatsApp salva
  def cloud_channels(inboxes)
    Array(inboxes).filter_map do |inbox|
      channel = inbox.channel
      next unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

      channel if channel.provider_config['business_account_id'].present?
    end
  end

  # números da MESMA conta do WhatsApp dividem os modelos: pede uma vez só
  def submit(group)
    outcome = request(group.first)
    group.map do |channel|
      refresh(channel) if outcome[:ok]
      { inbox_id: channel.inbox&.id, inbox_name: channel.inbox&.name, phone_number: channel.phone_number }.merge(outcome)
    end
  end

  def request(channel)
    response = HTTParty.post(url(channel), headers: headers(channel), body: payload.to_json, timeout: TIMEOUT)
    return { ok: true, status: response['status'].to_s.presence || 'PENDING', template_id: response['id'].to_s } if response.success?

    waba = channel.provider_config['business_account_id']
    Rails.logger.warn "[WhatsappTemplateCreator] #{@spec[:name]} recusado na conta #{waba}: #{response.code}"
    { ok: false, status: 'ERRO', error: meta_error(response) }
  rescue StandardError => e
    Rails.logger.error "[WhatsappTemplateCreator] #{e.class}: #{scrub(e.message, channel)}"
    { ok: false, status: 'ERRO', error: 'Não consegui falar com a Meta agora. Tente de novo em alguns minutos.' }
  end

  # a lista de modelos da caixa já volta com o novo "em análise"; se a Meta
  # demorar a listar, a sincronização de 3 em 3 horas (ou o botão) resolve
  def refresh(channel)
    channel.sync_templates
  rescue StandardError => e
    Rails.logger.warn "[WhatsappTemplateCreator] lista não atualizada: #{e.class}"
  end

  def url(channel)
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
    base = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base}/#{version}/#{channel.provider_config['business_account_id']}/message_templates"
  end

  def headers(channel)
    { 'Authorization' => "Bearer #{channel.template_access_token}", 'Content-Type' => 'application/json' }
  end

  # a explicação da própria Meta (título + mensagem para o usuário), sem nunca devolver token
  def meta_error(response)
    error = response.parsed_response.is_a?(Hash) ? response.parsed_response['error'] || {} : {}
    text = [error['error_user_title'], error['error_user_msg']].compact_blank.join(': ').presence
    text ||= "A Meta respondeu: #{error['message']}" if error['message'].present?
    text ||= 'A Meta recusou o pedido, sem explicar o motivo.'
    text.gsub(/access_token=[^&\s]+/, 'access_token=[token]')[0, 500]
  end

  def scrub(message, channel)
    message.to_s.gsub(channel.template_access_token.to_s.presence || '[sem token]', '[token]')
  end
end
