# 👋 BOAS-VINDAS DO LEAD DO FORMULÁRIO (08/11/2026 · LIFE, pedido do Guilherme):
# assim que um lead do formulário instantâneo do Meta chega, sai para ele uma
# MENSAGEM MODELO do WhatsApp chamando pelo nome e apontando o que ele mandou,
# com uma pergunta leve de abertura. Ex. (modelo aprovado no Meta):
#   "Oi, {{1}}! Aqui é o Fernando, da Life Energia Solar.
#    Recebi o seu pedido de orçamento. Vi que você é de {{2}} e gasta mais ou
#    menos {{3}} de luz por mês.
#    Posso te fazer umas perguntas rápidas por aqui pra montar o seu orçamento certinho?"
# {{1}} = primeiro nome · {{2}} = cidade · {{3}} = valor da conta (respostas do formulário).
#
# A mensagem sai pelo Crm::SendTemplateService (marcada como automática: não
# pausa a IA) e abre a conversa na caixa do WhatsApp; quando o lead responde,
# o Atendente da IA segue dali. Uma nota privada guarda tudo o que ele respondeu.
#
# Não manda (e abre TAREFA para a equipe chamar o lead) quando: falta telefone,
# nome, cidade ou valor; o lead é velho (importação retroativa, > max_age_hours);
# ou o contato já está conversando nessa caixa nas últimas 24 h (só a nota).
#
# Configuração em meta_ads_config['lead_welcome']:
#   { 'enabled' => true, 'template_name' => 'life_lead_formulario', 'language' => 'pt_BR',
#     'inbox_id' => 3, 'max_age_hours' => 24, 'preview' => 'Oi, {{1}}! …' }
class Crm::MetaLeadWelcome
  DEFAULT_MAX_AGE_HOURS = 24
  CITY_KEYS = %w[city cidade municipio município].freeze
  BILL_KEYS = %w[conta valor gasto luz consumo].freeze
  NAME_KEYS = %w[first_name full_name nome name].freeze
  LOWER_WORDS = %w[de da do das dos e].freeze
  AUTO_LABEL = 'Boas-vindas do formulário do Meta'.freeze

  def self.sanitize_config(raw)
    h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    h = h.transform_keys(&:to_s)
    {
      'enabled' => ActiveModel::Type::Boolean.new.cast(h['enabled']) == true,
      'template_name' => h['template_name'].to_s.strip.downcase.gsub(/[^a-z0-9_]/, '')[0, 80].presence,
      'language' => h['language'].to_s.strip.presence || 'pt_BR',
      'inbox_id' => h['inbox_id'].presence&.to_i,
      'max_age_hours' => (h['max_age_hours'].presence || DEFAULT_MAX_AGE_HOURS).to_i.clamp(1, 24 * 90),
      'preview' => h['preview'].to_s.strip[0, 1000].presence
    }.compact
  end

  def initialize(account:, config:)
    @account = account
    @cfg = config.to_h.transform_keys(&:to_s)
  end

  def enabled?
    @cfg['enabled'] == true && @cfg['template_name'].present? && inbox.present?
  end

  # devolve :sent, :noted (já conversando), :task (equipe chama) ou :off
  def call(contact:, lead:, leadgen_id:)
    return :off unless enabled?
    return :old if too_old?(lead)

    params = template_values(contact, lead)
    missing = params.select { |_, v| v.blank? }.keys
    return open_task(contact, lead, "faltou #{missing.join(', ')} no formulário") if missing.any? || contact.phone_number.blank?

    return open_task(contact, lead, 'a mensagem modelo ainda não foi aprovada pelo Meta') unless template_approved?

    talking = recent_conversation(contact)
    return note_only(talking, lead, leadgen_id) if talking

    send_template(contact, lead, leadgen_id, params)
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaLeadWelcome] lead #{leadgen_id}: #{e.class}: #{e.message}"
    open_task(contact, lead, 'a mensagem de boas-vindas não saiu') if contact
    :task
  end

  # { 'nome' => 'Maria', 'cidade' => 'Piracicaba', 'valor' => 'R$ 500 a R$ 800' }
  def template_values(contact, lead)
    {
      'nome' => first_name(field(lead, NAME_KEYS).presence || contact.name),
      'cidade' => city(field(lead, CITY_KEYS)),
      'valor' => bill(field(lead, BILL_KEYS))
    }
  end

  private

  def inbox
    @inbox ||= @account.inboxes.find_by(id: @cfg['inbox_id'])
  end

  # o modelo aprovado já chegou na caixa (o sistema sincroniza os modelos da
  # Meta sozinho): antes disso a mensagem falharia — vai tarefa para a equipe
  def template_approved?
    return true if approved_in_inbox?

    # o sistema só sincroniza os modelos a cada 3 h: busca na Meta agora
    # (no máximo a cada 10 min), senão o modelo recém-aprovado ficaria de fora
    channel = inbox.channel
    return false unless channel.respond_to?(:provider_service)
    return false if channel.message_templates_last_updated.present? && channel.message_templates_last_updated > 10.minutes.ago

    channel.provider_service.sync_templates
    channel.reload
    approved_in_inbox?
  rescue StandardError => e
    Rails.logger.warn "[Crm::MetaLeadWelcome] sincronizar modelos: #{e.message}"
    false
  end

  def approved_in_inbox?
    Array(inbox.channel.try(:message_templates)).any? do |t|
      t['name'] == @cfg['template_name'] && t['language'].to_s.casecmp((@cfg['language'] || 'pt_BR').to_s).zero? &&
        t['status'].to_s.casecmp('approved').zero?
    end
  end

  def too_old?(lead)
    created = Time.zone.parse(lead['created_time'].to_s)
    created.present? && created < (@cfg['max_age_hours'] || DEFAULT_MAX_AGE_HOURS).to_i.hours.ago
  rescue ArgumentError
    false
  end

  def fields(lead)
    Array(lead['field_data']).map { |f| f.to_h.with_indifferent_access }
  end

  # 1º campo cujo nome contém uma das chaves (na ordem das chaves)
  def field(lead, keys)
    list = fields(lead)
    keys.each do |k|
      hit = list.find { |f| f['name'].to_s.downcase.include?(k) }
      return Array(hit['values']).first.to_s.strip if hit
    end
    nil
  end

  # o WhatsApp recusa parâmetro com quebra de linha, tab ou 4+ espaços seguidos
  def clean(text, max = 60)
    text.to_s.tr('_', ' ').gsub(/[\r\n\t]+/, ' ').squeeze(' ').strip[0, max].to_s.strip
  end

  def first_name(name)
    word = clean(name).split.first.to_s
    return '' if word.length < 2 || word.match?(/\d|@/) || word.casecmp('lead').zero?

    word.capitalize
  end

  def city(raw)
    clean(raw).downcase.split.map.with_index { |w, i| i.positive? && LOWER_WORDS.include?(w) ? w : w.capitalize }.join(' ')
  end

  # "r$_500_a_r$_800" → "R$ 500 a R$ 800" · "600" → "R$ 600" · "até 300 reais" fica
  def bill(raw)
    text = clean(raw).gsub(/r\$\s*/i, 'R$ ').squeeze(' ').strip
    return '' if text.blank?
    return "R$ #{text}" if text.match?(/\A\d[\d.,]*\z/)

    text
  end

  def recent_conversation(contact)
    @account.conversations.where(inbox_id: inbox.id, contact_id: contact.id)
            .joins(:messages).where(messages: { message_type: :incoming, created_at: 24.hours.ago.. })
            .order(created_at: :desc).first
  end

  def send_template(contact, lead, leadgen_id, values)
    params = { 'name' => @cfg['template_name'], 'language' => @cfg['language'] || 'pt_BR',
               'processed_params' => { 'body' => { '1' => values['nome'], '2' => values['cidade'], '3' => values['valor'] } } }
    source = Crm::TemplateSource.new(@account, inbox, nil, params, @cfg['preview'], AUTO_LABEL)
    service = Crm::SendTemplateService.new(source: source, contact: contact)
    conversation = service.perform
    return open_task(contact, lead, 'a mensagem de boas-vindas não saiu') if conversation.nil?

    Cevico::AttributeMerge.merge!(conversation) { |a| a.merge('meta_lead_id' => leadgen_id.to_s) }
    note!(conversation, lead, '📋 Lead do formulário do Meta: a mensagem de boas-vindas saiu agora. A IA segue quando ele responder.')
    Crm::MetaLeadWelcomeCheckJob.set(wait: 3.minutes).perform_later(service.message.id, leadgen_id.to_s) if service.message
    :sent
  end

  def note_only(conversation, lead, _leadgen_id)
    note!(conversation, lead, '📋 Este contato também preencheu o formulário do Meta (já estava conversando: a boas-vindas não foi mandada).')
    :noted
  end

  def note!(conversation, lead, title)
    conversation.messages.create!(account_id: @account.id, inbox_id: conversation.inbox_id, message_type: :activity,
                                  private: true, content: ([title, ''] + answers(lead)).join("\n"))
  rescue StandardError => e
    Rails.logger.warn "[Crm::MetaLeadWelcome] nota: #{e.message}"
  end

  def answers(lead)
    lines = []
    lines << "Anúncio: #{lead['ad_name']}" if lead['ad_name'].present?
    fields(lead).each { |f| lines << "#{f['name'].to_s.tr('_', ' ').capitalize}: #{Array(f['values']).join(', ')}" }
    lines
  end

  def open_task(contact, lead, why)
    return :task if contact.nil?

    Crm::HandoffTask.open!(account: @account, contact: contact, conversation: nil, agent_key: 'atendente_agendamento',
                           motivo: "Chamar lead do formulário do Meta (#{why})", detalhes: answers(lead).join("\n"))
    :task
  rescue StandardError => e
    Rails.logger.error "[Crm::MetaLeadWelcome] tarefa: #{e.message}"
    :task
  end
end
