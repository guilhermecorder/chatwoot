# ✉️ ITEM 410 (24/11): a MENSAGEM MODELO da tela de Indicações cirúrgicas.
# Pedido dele: "apertou que tem indicação, apertar ali para mandar a mensagem
# modelo de oportunidade, já pré-preenchida com as informações do paciente…
# aparece para ela editar… é só a própria humana, sem IA".
#
# Quem decide COMO a mensagem sai é o WhatsApp, não a gente:
#   · paciente escreveu nas últimas 24 h  → texto LIVRE (ela edita tudo);
#   · passou das 24 h                     → só o MODELO aprovado pela Meta
#     (o texto é fixo; ela ajusta os campos: nome, quem assina, médico…).
# A mensagem sai SOZINHA pelo número em que o paciente já conversa (ver
# chosen_inbox); a pessoa pode trocar, e a tela avisa quando troca.
# Paciente do Oftalmofácil só pela caixa do parceiro (regra de ouro).
#
# SEM IA: no envio, o Atendente IA fica desligado NESTA conversa por
# HUMAN_ONLY_DAYS dias (pausa 'indicacao' do Crm::ResponderPause); a chavinha
# do topo da conversa religa antes, se a equipe quiser.
#
# O envio fica anotado na própria consulta (tasks.comments, kind
# 'indication_message'), sem migration: a tela mostra "mensagem enviada".
class Crm::IndicationMessages # rubocop:disable Metrics/ClassLength
  KIND = 'indication_message'.freeze
  MARK = 'cevico_indicacao'.freeze
  HUMAN_ONLY_DAYS = 30
  # quem assina é sempre ela, com Z (decisão dele, 24/11: "não precisa nem
  # deixar em aberto"); as meninas só conferem o nome do paciente e o médico
  SIGNATURE = 'Elizângela'.freeze
  FIXED_FIELDS = %w[atendente].freeze
  OUTCOMES = { 'indicated' => 'indicado', 'not_indicated' => 'sem_indicacao' }.freeze
  VARIABLE = /\{\{\s*(\d+)\s*\}\}/
  FIELD_LABELS = { 'nome' => 'Nome do paciente', 'atendente' => 'Quem assina', 'medico' => 'Médico',
                   'procedimento' => 'Procedimento' }.freeze
  # como o procedimento entra na frase "a {{4}} é indicada" (sempre no feminino)
  PROCEDURE_PHRASES = {
    'Refrativa Lasik' => 'cirurgia refrativa', 'Refrativa PRK' => 'cirurgia refrativa',
    'Catarata' => 'cirurgia de catarata', 'Facorrefrativa' => 'cirurgia facorrefrativa',
    'Lente Fácica' => 'cirurgia com implante de lente fácica',
    'Lente de Foco Estendido' => 'cirurgia com lente de foco estendido',
    'Trifocal' => 'cirurgia com lente trifocal', 'Anel de Ferrara' => 'cirurgia de implante do anel de Ferrara',
    'Pterígio' => 'cirurgia de pterígio', 'Capsulotomia YAG' => 'capsulotomia a laser'
  }.freeze

  # Os modelos desta tela. `template` é o nome do modelo na Meta; `fields` diz o
  # que entra em {{1}}, {{2}}… Todo modelo tem uma linha em branco entre os
  # blocos (pedido dele: "gosto sempre que eles tenham espaçamento") e o médico
  # é sempre campo ({{3}}): Dr. Henrique, Dr. Gustavo, Dra. Roberta, ou outro.
  # O texto de "boa notícia" é o rascunho de 20/11
  # (reativacao-base/fim-de-ano-refrativa-20-11.md, frente 3); o de "sem
  # indicação" é rascunho de 24/11 e espera a leitura do Dr. Gustavo.
  MODELS = [
    { key: 'boa_noticia', outcome: 'indicado', label: 'Boa notícia', template: 'boas_noticias_indicacao',
      category: 'UTILITY', fields: %w[nome atendente medico procedimento],
      body: "Saudações, {{1}}, tudo bem?\n\n" \
            "Aqui quem está falando é {{2}}, da CEVICO, e estou te chamando com uma excelente notícia.\n\n" \
            "Recebi agora o retorno da equipe médica: {{3}} avaliou o seu caso e me disse que a {{4}} é indicada e segura para você.\n\n" \
            'Você gostaria de ver alguma data que seja bem confortável para você?',
      footer: 'CEVICO · Cuidados Oculares', buttons: ['Sim', 'Não', 'Não quero receber'],
      examples: ['Mariana', 'Elizângela', 'Dr. Gustavo Bittar', 'cirurgia refrativa'] },
    { key: 'boa_noticia_curta', outcome: 'indicado', label: 'Boa notícia (curta)', template: 'boas_noticias_indicacao_b',
      category: 'UTILITY', fields: %w[nome atendente medico procedimento],
      body: "Oi, {{1}}, tudo bem?\n\n" \
            "Aqui é {{2}}, da CEVICO, com uma boa notícia para você.\n\n" \
            "{{3}} analisou os seus exames e me contou que você tem indicação para a {{4}}, e que ela é segura para o seu caso.\n\n" \
            'Você gostaria de ver alguma data que seja bem confortável para você?',
      footer: 'CEVICO · Cuidados Oculares', buttons: ['Sim', 'Agora não', 'Não quero receber'],
      examples: ['Mariana', 'Elizângela', 'Dr. Gustavo Bittar', 'cirurgia refrativa'] },
    { key: 'sem_indicacao', outcome: 'sem_indicacao', label: 'Retorno sem indicação', template: 'retorno_avaliacao_sem_indicacao',
      category: 'UTILITY', fields: %w[nome atendente medico],
      body: "Oi, {{1}}, tudo bem?\n\n" \
            "Aqui é {{2}}, da CEVICO. Estou te chamando para dar o retorno da sua avaliação.\n\n" \
            "{{3}} analisou os seus exames com calma e, neste momento, a cirurgia não é o caminho indicado para o seu caso.\n\n" \
            "Essa resposta também é um cuidado: a cirurgia só é indicada quando é segura e eficaz para a pessoa.\n\n" \
            'Posso te explicar o que isso significa e quais são as opções para você?',
      footer: 'CEVICO · Cuidados Oculares', buttons: ['Quero entender', 'Agora não', 'Não quero receber'],
      examples: ['Mariana', 'Elizângela', 'Dr. Gustavo Bittar'] }
  ].freeze

  attr_reader :account, :task, :user

  def initialize(account:, task: nil, user: nil)
    @account = account
    @task = task
    @user = user
  end

  def self.models_for(outcome)
    MODELS.select { |m| m[:outcome] == outcome }
  end

  def self.model(key)
    MODELS.find { |m| m[:key] == key.to_s }
  end

  # envios já anotados nesta consulta (mais antigo primeiro)
  def self.history(task)
    Array(task.comments).select { |e| e.is_a?(Hash) && e['kind'] == KIND }
  end

  # 🙋 contatos cuja conversa está com a EQUIPE da indicação (pausa 'indicacao'
  # ainda valendo): disparo em lote (Reativação, Segmentação) não encosta neles
  def self.human_led_contact_ids(account, now = Time.current)
    state = "additional_attributes -> '#{Crm::ResponderAgentJob::STATE_KEY}'"
    account.conversations
           .where("#{state} ->> 'paused' = 'true' AND #{state} ->> 'reason' = ?", Crm::ResponderPause::INDICATION)
           .where("(#{state} ->> 'until') IS NULL OR (#{state} ->> 'until')::timestamptz > ?", now)
           .distinct.pluck(:contact_id)
  end

  # ── catálogo (bloco "Mensagens desta tela"): cada modelo × cada número ────
  def catalog
    boxes = whatsapp_inboxes
    { models: MODELS.map { |m| model_json(m).merge(numbers: boxes.map { |i| number_json(i, m) }) },
      human_only_days: HUMAN_ONLY_DAYS }
  end

  # pede à Meta a aprovação de um modelo nos números em que ele ainda não existe
  def request_approval(model_key, inbox_ids)
    model = self.class.model(model_key)
    return { ok: false, errors: ['Modelo desconhecido.'], results: [] } unless model

    boxes = whatsapp_inboxes.select { |i| Array(inbox_ids).map(&:to_i).include?(i.id) && template_in(i, model).nil? }
    return { ok: false, errors: ['Este modelo já foi pedido à Meta nos números escolhidos.'], results: [] } if boxes.empty?

    spec = { name: model[:template], category: model[:category], body: model[:body], footer: model[:footer],
             buttons: model[:buttons], examples: model[:examples] }
    Crm::WhatsappTemplateCreator.new(account, spec).call(boxes)
  end

  # ── prévia para UM paciente: o que a tela mostra antes de enviar ──────────
  def preview
    outcome = OUTCOMES[task.surgery_indication]
    return { error: 'A mensagem existe para quem já tem a decisão: com indicação ou sem indicação.' } unless outcome

    values = default_values
    boxes = candidate_inboxes
    models = self.class.models_for(outcome)
    inbox, why = chosen_inbox(boxes, models)
    {
      outcome: outcome, first_name: values['nome'], partner: partner?, signature: SIGNATURE,
      blocked: blocker(boxes), human_only_days: HUMAN_ONLY_DAYS, doctors: Crm::DoctorNames::OFFICIAL.keys,
      models: models.map { |m| model_json(m).merge(fields: fields_json(m, values)) },
      inboxes: boxes.map { |i| inbox_json(i, models) },
      inbox_id: inbox&.id, inbox_reason: why,
      history: self.class.history(task)
    }
  end

  # ── envio ─────────────────────────────────────────────────────────────────
  # mode 'text' (janela de 24 h aberta, texto livre) | 'template' (modelo da Meta)
  def deliver(model_key:, inbox_id:, mode:, text: nil, values: {}) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    outcome = OUTCOMES[task.surgery_indication]
    model = self.class.model(model_key)
    return failure('Modelo desconhecido para esta decisão.') unless model && model[:outcome] == outcome

    boxes = candidate_inboxes
    why = blocker(boxes)
    return failure(why) if why

    inbox = boxes.find { |i| i.id == inbox_id.to_i }
    return failure('Escolha o número do WhatsApp por onde a mensagem sai.') unless inbox

    conversation, message =
      if mode.to_s == 'text'
        send_text(inbox, text)
      else
        send_template(inbox, model, values)
      end
    return failure(@error || 'Não deu para enviar agora.') unless conversation && message

    entry = stamp!(model, inbox, conversation, message, mode.to_s == 'text' ? 'text' : 'template')
    { ok: true, entry: entry, conversation_id: conversation.display_id }
  rescue StandardError => e
    Rails.logger.error "[CEVICO indicação] envio da consulta #{task&.id}: #{e.class}: #{e.message}"
    failure('Não deu para enviar agora. Tente de novo ou abra a conversa pelo balão.')
  end

  private

  def failure(text)
    { ok: false, error: text }
  end

  # ── paciente ──────────────────────────────────────────────────────────────
  def contact
    return @contact if defined?(@contact)

    @contact = task.contact || Task.match_contact(account, task.phone)
  end

  def phone_digits
    (task.phone.presence || contact&.phone_number).to_s.delete('^0-9')
  end

  def patient_name
    task.title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia):\s*/i, '').strip.presence || contact&.name.to_s
  end

  def partner?
    return @partner if defined?(@partner)

    @partner = Crm::PartnerGuard.partner_task?(task) || (contact.present? && Crm::PartnerGuard.partner_contact?(contact))
  end

  def default_values
    {
      'nome' => first_name(patient_name),
      'atendente' => SIGNATURE,
      'medico' => Crm::DoctorNames.canonical(task.doctor) || task.doctor.to_s.strip.presence || 'o médico responsável',
      'procedimento' => PROCEDURE_PHRASES[task.indicated_procedure.to_s] || 'cirurgia'
    }
  end

  def first_name(full)
    word = full.to_s.strip.split(/\s+/).first.to_s
    word.match?(/\A[[:upper:]]+\z/) || word.match?(/\A[[:lower:]]+\z/) ? word.capitalize : word
  end

  # ── números ───────────────────────────────────────────────────────────────
  def whatsapp_inboxes
    @whatsapp_inboxes ||= account.inboxes.where(channel_type: 'Channel::Whatsapp').includes(:channel).order(:id).to_a
  end

  # paciente de parceiro só pela caixa do parceiro; os demais, nunca por ela
  def candidate_inboxes
    partner_ids = Crm::PartnerGuard.partner_inbox_ids(account)
    whatsapp_inboxes.select { |i| partner? ? partner_ids.include?(i.id) : partner_ids.exclude?(i.id) }
  end

  def blocker(boxes)
    return 'Esta consulta não tem telefone. Complete o cadastro na Agenda.' if phone_digits.length < 10
    return 'Este paciente pediu para não receber mensagens. Se precisar, fale pela conversa (balão).' if opted_out?
    return 'Paciente do Oftalmofácil: a mensagem só sai pela caixa do parceiro, e ela não está configurada.' if partner? && boxes.empty?
    return 'Nenhum número de WhatsApp ligado ao sistema.' if boxes.empty?

    nil
  end

  def opted_out?
    contact.present? && contact.label_list.include?(Crm::OptOut::LABEL)
  end

  def latest_conversation(inbox)
    return nil if contact.blank?

    @latest ||= {}
    return @latest[inbox.id] if @latest.key?(inbox.id)

    @latest[inbox.id] = account.conversations.where(inbox_id: inbox.id, contact_id: contact.id).order(last_activity_at: :desc).first
  end

  def window_open?(inbox)
    conversation = latest_conversation(inbox)
    conversation.present? && conversation.can_reply?
  rescue StandardError
    false
  end

  # 📱 pedido dele (24/11): "a mensagem seja enviada especialmente pelo número
  # que a pessoa já tem conversa". A escolha é automática, nesta ordem:
  #   conversa        o número em que o paciente FALOU por último (lembrete e
  #                   campanha que só a clínica mandou não contam como conversa);
  #   ultimo_contato  ele nunca respondeu: o número do último contato com ele;
  #   sem_conversa    nenhuma conversa: o 1º número com o modelo aprovado.
  # Devolve [caixa, motivo]. A tela mostra o motivo e avisa se a pessoa trocar.
  def chosen_inbox(boxes, models) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    spoke = boxes.select { |i| last_spoke_at[i.id] }.max_by { |i| last_spoke_at[i.id] }
    return [spoke, 'conversa'] if spoke

    recent = boxes.select { |i| latest_conversation(i) }.max_by { |i| latest_conversation(i).last_activity_at || Time.zone.at(0) }
    return [recent, 'ultimo_contato'] if recent

    approved = boxes.find { |i| models.any? { |m| template_status(i, m) == 'approved' } }
    [approved || boxes.first, 'sem_conversa']
  end

  # quando o paciente escreveu pela última vez em cada número: { inbox_id => hora }
  def last_spoke_at
    return {} if contact.blank?

    @last_spoke_at ||= Message.unscope(:order).where(account_id: account.id, message_type: :incoming, private: false)
                              .joins(:conversation).where(conversations: { contact_id: contact.id })
                              .group('messages.inbox_id').maximum('messages.created_at')
  end

  # ── modelos na Meta ───────────────────────────────────────────────────────
  # o modelo como a Meta devolveu para este número (aprovado vence os demais)
  def template_in(inbox, model)
    found = Array(inbox.channel.try(:message_templates)).select { |t| t['name'] == model[:template] }
    found.find { |t| t['status'].to_s.casecmp?('approved') } || found.first
  end

  # approved | pending | rejected | missing
  def template_status(inbox, model)
    tpl = template_in(inbox, model)
    return 'missing' unless tpl

    status = tpl['status'].to_s.downcase
    %w[approved rejected].include?(status) ? status : 'pending'
  end

  # o texto que VALE é o aprovado na Meta (pode ter sido ajustado lá)
  def template_body(inbox, model)
    tpl = template_in(inbox, model)
    body = Array(tpl && tpl['components']).find { |c| c['type'].to_s.casecmp?('BODY') }
    (body && body['text'].presence) || model[:body]
  end

  def model_json(model)
    model.slice(:key, :label, :template, :body, :footer, :buttons, :outcome).merge(readable: readable_body(model))
  end

  # o texto como gente lê: "[nome do paciente]" no lugar de {{1}}, e a assinatura já escrita
  def readable_body(model)
    model[:body].gsub(VARIABLE) do
      field = model[:fields][Regexp.last_match(1).to_i - 1]
      FIXED_FIELDS.include?(field) ? SIGNATURE : "[#{FIELD_LABELS[field].to_s.downcase}]"
    end
  end

  def fields_json(model, values)
    model[:fields].each_with_index.map do |f, i|
      { n: (i + 1).to_s, key: f, label: FIELD_LABELS[f], value: values[f], fixed: FIXED_FIELDS.include?(f) }
    end
  end

  def number_json(inbox, model)
    { inbox_id: inbox.id, inbox: inbox.name, status: template_status(inbox, model),
      partner: Crm::PartnerGuard.partner_inbox?(account, inbox.id) }
  end

  def inbox_json(inbox, models)
    conversation = latest_conversation(inbox)
    { id: inbox.id, name: inbox.name, window_open: window_open?(inbox), conversation_id: conversation&.display_id,
      talks: last_spoke_at[inbox.id].present?,
      templates: models.to_h { |m| [m[:key], { status: template_status(inbox, m), body: template_body(inbox, m) }] } }
  end

  # ── envio de fato ─────────────────────────────────────────────────────────
  def finder(inbox)
    Crm::Calls::ConversationFinder.new(inbox: inbox, wa_id: phone_digits, name: patient_name, contact: contact)
  end

  def send_text(inbox, text)
    body = text.to_s.strip
    return fail_with('Escreva a mensagem.') if body.blank?
    return fail_with('A mensagem passa de 4.000 letras.') if body.length > 4000

    conversation = finder(inbox).conversation
    unless conversation.can_reply?
      return fail_with('Passaram as 24 horas desde a última mensagem do paciente: agora o WhatsApp só aceita o modelo aprovado.')
    end

    hold_ai!(conversation)
    message = conversation.messages.create!(
      account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: body, sender: user,
      additional_attributes: { 'cevico_auto' => 'indicacao', MARK => { 'task_id' => task.id } }
    )
    [conversation, message]
  end

  def send_template(inbox, model, values) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    tpl = template_in(inbox, model)
    unless tpl && tpl['status'].to_s.casecmp?('approved')
      return fail_with("O modelo “#{model[:label]}” ainda não está aprovado pela Meta no número #{inbox.name}.")
    end

    body = template_body(inbox, model)
    filled = filled_values(model, body, values)
    return fail_with('Preencha todos os campos da mensagem.') if filled.nil?

    params = { 'name' => tpl['name'], 'category' => tpl['category'].presence || model[:category],
               'language' => tpl['language'].presence || 'pt_BR', 'processed_params' => { 'body' => filled } }
    source = Crm::TemplateSource.new(account, inbox, user, params, body, model[:label])
    source.define_singleton_method(:auto_label) { 'indicacao' }
    target = contact || finder(inbox).contact
    service = Crm::SendTemplateService.new(source: source, contact: target)
    conversation = service.perform
    return fail_with('Não deu para montar a mensagem para este paciente.') unless conversation && service.message

    hold_ai!(conversation)
    [conversation, service.message]
  end

  # { '1' => 'Vanessa', … } só com os campos que o texto aprovado usa; nil se faltar algum
  def filled_values(model, body, values) # rubocop:disable Metrics/CyclomaticComplexity
    defaults = default_values
    given = (values || {}).to_h.transform_keys(&:to_s)
    numbers = body.scan(VARIABLE).flatten.uniq
    filled = numbers.to_h do |n|
      field = model[:fields][n.to_i - 1]
      [n, clean_value(FIXED_FIELDS.include?(field) ? defaults[field] : given[n].presence || defaults[field])]
    end
    filled.values.any?(&:blank?) ? nil : filled
  end

  # a Meta recusa campo com quebra de linha ou vários espaços; chaves viram texto comum
  def clean_value(value)
    value.to_s.delete('{}').squish.first(120)
  end

  def fail_with(text)
    @error = text
    nil
  end

  # 🙋 SEM IA: a conversa da indicação é da equipe. Pausa própria, com prazo
  # (não é renovada nem encurtada pelas mensagens da equipe; a chavinha religa).
  def hold_ai!(conversation) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    state = Crm::ResponderPause.state_of(conversation)
    return if state['urgente']

    already = state['paused'] && state['reason'] == Crm::ResponderPause::INDICATION
    now = Time.current
    Cevico::AttributeMerge.merge!(conversation) do |attrs|
      attrs.merge(Crm::ResponderAgentJob::STATE_KEY => {
        'paused' => true, 'reason' => Crm::ResponderPause::INDICATION, 'by' => user&.name,
        'at' => now.iso8601, 'until' => (now + HUMAN_ONLY_DAYS.days).iso8601
      }.compact)
    end
    return if already

    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: "🎯 Mensagem da indicação cirúrgica enviada por #{user&.name || 'a equipe'}. O Atendente IA fica desligado nesta " \
               "conversa por #{HUMAN_ONLY_DAYS} dias: quem conduz é a equipe. Para religar antes, use a chavinha no topo."
    )
  rescue StandardError => e
    Rails.logger.warn "[CEVICO indicação] pausa da IA (conversa #{conversation.id}): #{e.message}"
  end

  # anota o envio na consulta SOMANDO no banco (mesma técnica do carimbo de remarcação)
  def stamp!(model, inbox, conversation, message, mode) # rubocop:disable Metrics/AbcSize
    entry = {
      'kind' => KIND, 'at' => Time.current.iso8601(3), 'user_id' => user&.id, 'name' => user&.name.presence || 'Equipe',
      'model' => model[:key], 'model_label' => model[:label], 'mode' => mode, 'inbox_id' => inbox.id, 'inbox' => inbox.name,
      'conversation_id' => conversation.display_id, 'message_id' => message.id,
      'text' => "✉️ Mensagem “#{model[:label]}” enviada pelo WhatsApp (#{inbox.name})"
    }
    Task.where(id: task.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["comments = (CASE WHEN jsonb_typeof(comments) = 'array' THEN comments ELSE '[]'::jsonb END) || ?::jsonb", [entry].to_json]
    )
    task.comments = Array(task.comments) + [entry]
    task.send(:clear_attribute_changes, %w[comments])
    entry
  end
end
