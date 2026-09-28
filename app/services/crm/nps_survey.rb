# 📊 PESQUISA DE SATISFAÇÃO (NPS) PÓS-CIRURGIA (item 256, 26/09 — substitui o
# fluxo "AGENTE DE NPS" do N8N).
#
# ENVIO: N dias depois da cirurgia REALIZADA (presença marcada ou concluída na
# Agenda — inclusive as do Oftalmofácil da CEVICO), com o dia escolhido POR
# TIPO DE CIRURGIA (catarata, refrativa, outras… por palavras do procedimento),
# vai a mensagem modelo da Meta com os botões de nota. Sombra (só lista quem
# receberia) ou ao vivo. 1 por cirurgia, e nunca 2 pesquisas para a mesma pessoa
# dentro de `min_interval_days` (cirurgia do segundo olho).
#
# RESPOSTA: o toque no botão ("🟢 9 a 10", "🟡 5 a 6"…) ou uma nota solta
# ("10", "nota 8") de quem tem pesquisa pendente é lido SEM IA na hora:
#   · etiqueta nps-9-10 / 7-8 / 5-6 / 3-4 / 1-2 (o painel de satisfação já usa)
#   · additional_attributes.nps = { score, band, at, source: 'pesquisa' }
#   · nota interna na conversa
#   · 1 a 6 → tarefa no Meu Painel (1–4 urgente, com aviso no Radar)
# A conversa continua com o Atendente de Pós-operatório (ele recebe a nota no
# contexto e segue o roteiro: Google para 9–10, o que faltou para 7–8,
# formulário para as notas baixas). Cerca dos parceiros e nao_perturbe valem.
#
# Config em agenda_config['nps_survey']; última rodada em 'nps_survey_state'.
#
# 27/09 (fluxo "NPS v1.1" do N8N trazido para dentro — ele manda que era o último):
#   · dias padrão iguais à INTENÇÃO do N8N: LASIK/SMILE 1 dia, PRK 29, catarata 15
#     (lá o Switch tinha uma regra "PRK" que casava com tudo → catarata ia em 29)
#   · catch_up_days: quem ficou para trás (cron parado, card ligado depois) ainda
#     recebe até N dias depois do dia certo — a marca por cirurgia não repete
#     (o N8N reenviava TODA sexta para toda cirurgia com mais de 30 dias)
#   · lembrete para quem não respondeu (reminder): N horas depois, mensagem
#     MODELO (a janela de 24h ainda está fechada) — só ao vivo, 8h–20h, 1 vez
#   · agradecimento com o link do Google (thanks) para 9–10 e 7–8 quando o
#     Atendente de Pós-operatório NÃO está ao vivo na conversa — texto simples,
#     sem IA (a janela abriu com a resposta). Com o Pós-op ao vivo, ele conduz.
class Crm::NpsSurvey # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  CONFIG_KEY = 'nps_survey'.freeze
  STATE_KEY = 'nps_survey_state'.freeze
  MARK_KEY = 'cevico_nps_survey'.freeze
  REPLY_WINDOW = 10.days
  ALREADY_SENT = 'já recebeu por esta cirurgia'.freeze
  LIST_CAP = 80
  QUIET_LABELS = %w[nao_perturbe].freeze

  # ordem importa: a 1ª que casar vence ("CIRURGIA REFRATIVA - LASIK" é LASIK)
  DEFAULT_RULES = [
    { 'key' => 'lasik', 'label' => 'LASIK / SMILE', 'days_after' => 1, 'enabled' => true, 'keywords' => %w[lasik smile] },
    { 'key' => 'prk', 'label' => 'PRK', 'days_after' => 29, 'enabled' => true, 'keywords' => %w[prk] },
    { 'key' => 'catarata', 'label' => 'Catarata', 'days_after' => 15, 'enabled' => true,
      'keywords' => %w[catarata faco facectomia lio intraocular trifocal multifocal monofocal] },
    { 'key' => 'refrativa', 'label' => 'Outras refrativas', 'days_after' => 15, 'enabled' => true,
      'keywords' => %w[refrativa miopia astigmatismo hipermetropia] },
    { 'key' => 'outras', 'label' => 'Outras cirurgias', 'days_after' => 15, 'enabled' => true, 'keywords' => [] }
  ].freeze
  DEFAULT_CATCH_UP_DAYS = 7
  DEFAULT_REMINDER_HOURS = 6
  REMINDER_WINDOW_HOURS = (8...20)
  THANKS_BANDS = %w[9-10 7-8].freeze
  # texto do follow-up do N8N, com o link no lugar certo
  DEFAULT_THANKS_TEXT = ('Muito obrigado pela sua resposta! 💙 Saber como foi a sua experiência é fundamental para ' \
    "continuarmos melhorando o nosso atendimento na CEVICO.\n\nSe puder, deixe também a sua " \
    "avaliação no Google — é bem rápido, basta clicar neste link:\n{{link}}\n\n" \
    'Ficamos à disposição e desejamos um ótimo dia!').freeze

  BANDS = {
    '9-10' => { label: '9 a 10', score: 10, tag: 'nps-9-10' },
    '7-8' => { label: '7 a 8', score: 8, tag: 'nps-7-8' },
    '5-6' => { label: '5 a 6', score: 6, tag: 'nps-5-6' },
    '3-4' => { label: '3 a 4', score: 4, tag: 'nps-3-4' },
    '1-2' => { label: '1 a 2', score: 2, tag: 'nps-1-2' }
  }.freeze

  # ── configuração ────────────────────────────────────────────────────────
  # links que já estavam no fluxo do N8N (a clínica pode trocar no card)
  DEFAULT_LINKS = { 'google_review_url' => 'https://g.page/r/CQBUrvu4enAHEBM/review',
                    'complaint_form_url' => 'https://forms.gle/VBiBAQXLPWA4DgE66' }.freeze

  def self.config(account)
    raw = CrmSetting.find_by(account: account)&.agenda_config&.dig(CONFIG_KEY) || {}
    rules = Array(raw['rules']).presence || DEFAULT_RULES
    links = DEFAULT_LINKS.to_h { |key, url| [key, raw[key].presence || url] }
    raw.merge(links).merge('rules' => rules)
  end

  def self.normalize(text)
    text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
  end

  # regra da cirurgia pelas palavras do procedimento/título; a regra SEM
  # palavras é a de "outras" (pega o que sobrou)
  def self.rule_for(rules, task)
    text = normalize("#{task.procedure} #{task.title}")
    specific = rules.find do |r|
      words = Array(r['keywords']).map { |w| normalize(w).strip }.compact_blank
      words.any? && words.any? { |w| text.include?(w) }
    end
    specific || rules.find { |r| Array(r['keywords']).compact_blank.empty? }
  end

  # ── envio (cron a cada 15 min; só age na hora da conta) ────────────────
  def self.run_all(now = nil) # rubocop:disable Metrics/CyclomaticComplexity
    now_sp = (now || TZ.now).in_time_zone(TZ)
    CrmSetting.find_each do |settings|
      cfg = (settings.agenda_config || {})[CONFIG_KEY] || {}
      next unless cfg['enabled'] == true

      survey = new(settings.account, now_sp)
      survey.run if now_sp.hour == (cfg['hour'] || 10).to_i
      survey.send_reminders
    rescue StandardError => e
      Rails.logger.error "[CEVICO NPS] conta #{settings.account_id}: #{e.message}"
    end
  end

  def initialize(account, now_sp = TZ.now)
    @account = account
    @now = now_sp.in_time_zone(TZ)
    @cfg = self.class.config(account)
    @shadow = @cfg['mode'] != 'live'
    @run = { 'sent' => [], 'skipped' => [] }
  end

  def run # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    inbox = @account.inboxes.find_by(id: @cfg['inbox_id'])
    return if !@shadow && (inbox.nil? || @cfg['template_params'].blank?)

    rules = Array(@cfg['rules']).reject { |r| r['enabled'] == false }
    catch_up = (@cfg['catch_up_days'].presence || DEFAULT_CATCH_UP_DAYS).to_i.clamp(0, 30)
    rules.group_by { |r| r['days_after'].to_i }.each do |days, same_day|
      last = @now.to_date - days
      surgeries_between(last - catch_up, last).each do |task|
        rule = self.class.rule_for(@cfg['rules'], task)
        next unless same_day.include?(rule)

        send_for(inbox, task, rule)
      end
    end
    record_run
  end

  # ── lembrete para quem não respondeu (a cada rodada do cron, 8h–20h) ──
  def send_reminders # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    rem = @cfg['reminder'] || {}
    return unless rem['enabled'] == true && !@shadow && rem['template_params'].present?
    return unless REMINDER_WINDOW_HOURS.cover?(@now.hour)

    inbox = @account.inboxes.find_by(id: rem['inbox_id'].presence || @cfg['inbox_id'])
    return if inbox.nil?

    hours = (rem['hours'].presence || DEFAULT_REMINDER_HOURS).to_i.clamp(1, 72)
    sent = []
    pending_contacts.find_each do |contact|
      survey = contact.additional_attributes[MARK_KEY] || {}
      at = Time.zone.parse(survey['pending_at'].to_s)
      next if at > hours.hours.ago || at < REPLY_WINDOW.ago
      next if reminder_blocked?(contact, at)

      source = Crm::TemplateSource.new(@account, inbox, nil, reminder_params(rem, contact), rem['message_preview'].presence,
                                       'Pesquisa de satisfação (lembrete)')
      next if Crm::SendTemplateService.new(source: source, contact: contact).perform.nil?

      Cevico::AttributeMerge.merge!(contact) do |attrs|
        attrs.merge(MARK_KEY => (attrs[MARK_KEY] || {}).merge('reminded_at' => Time.current.iso8601))
      end
      sent << { 'at' => Time.current.iso8601, 'name' => contact.name.to_s.truncate(40), 'contact_id' => contact.id }
    rescue StandardError => e
      Rails.logger.warn "[CEVICO NPS] lembrete contato #{contact.id}: #{e.message}"
    end
    record_reminders(sent) if sent.any?
  end

  # ── resposta do paciente (CrmListener, a cada mensagem recebida) ───────
  def self.handle_reply(message, contact) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless message.message_type == 'incoming' && contact

    survey = (contact.additional_attributes || {})[MARK_KEY] || {}
    return nil if survey['pending_at'].blank? || survey['answered_at'].present?
    return nil if Time.zone.parse(survey['pending_at'].to_s) < REPLY_WINDOW.ago

    band = band_from(message.content)
    return nil if band.nil?

    record_answer!(message, contact, band)
    band
  rescue StandardError => e
    Rails.logger.error "[CEVICO NPS] resposta: #{e.message}"
    nil
  end

  # "🟢 9 a 10" (toque no botão: a faixa ABRE a mensagem), "9-10", "10", "nota 8",
  # "dou 7" → faixa. Número no meio de uma frase ("pingo de 3 a 4 vezes") NÃO
  # conta: fica para a IA / a equipe.
  def self.band_from(raw)
    text = normalize(raw).gsub(/[^\p{Alnum}\s]/, ' ').squeeze(' ').strip
    return nil if text.blank?

    if (m = text.match(/\A(10|[1-9])\s+(?:a\s+|ate\s+)?(10|[2-9])\b/)) && m[2].to_i == m[1].to_i + 1 && m[1].to_i.odd?
      return band_of(m[2].to_i)
    end

    m = text.match(/\A(?:nota\s+|dou\s+|e\s+)?(10|[0-9])(?:\s+de\s+10)?\z/)
    m ? band_of(m[1].to_i) : nil
  end

  def self.band_of(score)
    return '9-10' if score >= 9
    return '7-8' if score >= 7
    return '5-6' if score >= 5
    return '3-4' if score >= 3

    '1-2'
  end

  def self.record_answer!(message, contact, band) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    meta = BANDS[band]
    kept = contact.label_list.reject { |l| Crm::NpsService::NPS_LABELS.include?(l.to_s) }
    contact.update_labels(kept + [meta[:tag]])
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      survey = (attrs[MARK_KEY] || {}).merge('answered_at' => Time.current.iso8601, 'band' => band)
      attrs.merge(MARK_KEY => survey,
                  'nps' => { 'score' => meta[:score], 'band' => band, 'source' => 'pesquisa', 'at' => Time.current.iso8601 })
    end
    conversation = message.conversation
    conversation.messages.create!(
      account_id: contact.account_id, inbox_id: conversation.inbox_id, message_type: :activity, private: true,
      content: "📊 Pesquisa de satisfação respondida: nota #{meta[:label]} (etiqueta #{meta[:tag]})."
    )
    record_answer_state(contact, band)
    send_thanks(contact, conversation, band)
    return unless %w[5-6 3-4 1-2].include?(band)

    Crm::HandoffTask.open!(account: contact.account, contact: contact, conversation: conversation,
                           agent_key: 'atendente_pos_op',
                           motivo: "NPS #{meta[:label]} — paciente #{band == '5-6' ? 'pouco satisfeito' : 'insatisfeito'}",
                           detalhes: 'Resposta à pesquisa de satisfação pós-cirurgia. Falar com o paciente antes que vire reclamação pública.',
                           urgencia: band == '5-6' ? 'normal' : 'alta')
  end

  # 9–10 / 7–8: agradecimento + link do Google, SEM IA, só quando o Atendente de
  # Pós-operatório não vai responder (desligado, em sombra, fora da janela ou
  # pausado nesta conversa). A janela de 24h está aberta: a resposta acabou de chegar.
  def self.send_thanks(contact, conversation, band) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = config(contact.account)
    return if cfg['thanks_enabled'] == false || cfg['mode'] != 'live'
    return unless Array(cfg['thanks_bands'].presence || THANKS_BANDS).include?(band)
    return if pos_op_answers?(conversation)
    return if Crm::PartnerGuard.partner_conversation?(conversation)

    text = cfg['thanks_text'].presence || DEFAULT_THANKS_TEXT
    text = text.gsub('{{link}}', cfg['google_review_url'].to_s).gsub('{{nome}}', contact.name.to_s.split.first.to_s)
    conversation.messages.create!(account_id: contact.account_id, inbox_id: conversation.inbox_id, message_type: :outgoing,
                                  content: text.strip, additional_attributes: { 'cevico_nps_thanks' => band })
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs.merge(MARK_KEY => (attrs[MARK_KEY] || {}).merge('thanked_at' => Time.current.iso8601))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO NPS] agradecimento: #{e.message}"
  end

  # o Atendente de Pós-operatório vai responder nesta conversa?
  def self.pos_op_answers?(conversation) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    agent = (CrmSetting.find_by(account_id: conversation.account_id)&.ai_config || {}).dig('agents', 'atendente_pos_op') || {}
    return false unless agent['enabled'] == true && Array(agent['inbox_ids']).map(&:to_i).include?(conversation.inbox_id)
    return false unless Crm::ResponderAgentJob.live_mode?(agent)

    (conversation.additional_attributes || {}).dig(Crm::ResponderAgentJob::STATE_KEY, 'paused') != true
  end

  def self.record_answer_state(contact, band)
    settings = CrmSetting.find_by(account_id: contact.account_id)
    return if settings.blank?

    settings.with_lock do
      agenda = settings.agenda_config || {}
      state = agenda[STATE_KEY] || {}
      answers = Array(state['answers'])
      answers.unshift({ 'at' => Time.current.iso8601, 'band' => band, 'name' => contact.name.to_s.truncate(40), 'contact_id' => contact.id })
      state['answers'] = answers.first(LIST_CAP)
      settings.update!(agenda_config: agenda.merge(STATE_KEY => state))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO NPS] estado da resposta: #{e.message}"
  end

  # para o contexto do Atendente de Pós-operatório
  def self.context_text(contact)
    survey = (contact&.additional_attributes || {})[MARK_KEY] || {}
    return nil if survey['pending_at'].blank?

    sent = Time.zone.parse(survey['pending_at'].to_s).in_time_zone(TZ)
    answer = survey['band'].present? ? "respondeu #{BANDS.dig(survey['band'], :label)}" : 'ainda sem nota'
    "enviada em #{sent.strftime('%d/%m')} (#{answer})"
  rescue ArgumentError, TypeError
    nil
  end

  # pesquisa recente (enviada nos últimos REPLY_WINDOW) — o Pós-operatório atende
  def self.recent?(contact)
    at = (contact&.additional_attributes || {}).dig(MARK_KEY, 'pending_at')
    at.present? && Time.zone.parse(at.to_s) > REPLY_WINDOW.ago
  rescue ArgumentError, TypeError
    false
  end

  private

  # cirurgias dos dias na Agenda (a CEVICO e as do hub; parceiro sai na cerca)
  def surgeries_between(first, last)
    from = TZ.local(first.year, first.month, first.day)
    to = TZ.local(last.year, last.month, last.day).end_of_day
    @account.tasks.where(task_type: 'cirurgia', canceled_at: nil, archived_at: nil)
            .where(due_at: from..to)
            .where.not(contact_id: nil)
            .includes(:contact)
            .order(:due_at)
  end

  def send_for(inbox, task, rule)
    contact = task.contact
    why = skip_reason(task, contact)
    return if why == ALREADY_SENT # a janela de recuperação repassa pelos mesmos dias: não polui a lista
    return skip(task, rule, why) if why

    if @shadow
      @run['sent'] << entry(task, contact, rule)
      return
    end

    source = Crm::TemplateSource.new(@account, inbox, nil, personalized_params(task, rule), @cfg['message_preview'].presence,
                                     'Pesquisa de satisfação (NPS)')
    conversation = Crm::SendTemplateService.new(source: source, contact: contact).perform
    return skip(task, rule, 'envio não saiu (contato/caixa)') if conversation.nil?

    mark_sent!(contact, task)
    @run['sent'] << entry(task, contact, rule)
  rescue StandardError => e
    skip(task, rule, "erro: #{e.message.truncate(60)}")
  end

  def skip_reason(task, contact) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'sem telefone' if contact.nil? || contact.phone_number.blank?
    return 'cirurgia não marcada como realizada na Agenda' unless task.attendance == 'attended' || task.status == 'done'

    if Crm::PartnerGuard.partner_task?(task) || Crm::PartnerGuard.partner_contact?(contact)
      Crm::PartnerGuard.block!("pesquisa NPS (cirurgia #{task.id})", contact: contact)
      return 'paciente de parceiro (cerca)'
    end
    return 'pediu para não receber mensagens' if contact.label_list.any? { |l| QUIET_LABELS.include?(l) || l.start_with?('perda_') }

    survey = (contact.additional_attributes || {})[MARK_KEY] || {}
    return ALREADY_SENT if Array(survey['task_ids']).include?(task.id)

    last = survey['pending_at'].present? ? Time.zone.parse(survey['pending_at'].to_s) : nil
    interval = (@cfg['min_interval_days'].presence || 60).to_i
    return "já recebeu pesquisa há menos de #{interval} dias" if last && last > interval.days.ago

    nil
  end

  def personalized_params(task, rule) # rubocop:disable Metrics/AbcSize
    params = @cfg['template_params'].deep_dup
    at = task.due_at.in_time_zone(TZ)
    subs = {
      '{{nome}}' => task.contact&.name.to_s.split.first.presence || 'Paciente',
      '{{procedimento}}' => task.procedure.to_s.split('·').first.to_s.strip.presence || rule['label'].to_s,
      '{{data_cirurgia}}' => at.strftime('%d/%m/%Y'),
      '{{dias}}' => (@now.to_date - at.to_date).to_i.to_s
    }
    body = params.dig('processed_params', 'body')
    body&.transform_values! { |v| subs.reduce(v.to_s) { |text, (key, val)| text.gsub(key, val) } }
    params
  end

  def pending_contacts
    key = MARK_KEY
    @account.contacts
            .where("additional_attributes -> '#{key}' ->> 'pending_at' IS NOT NULL")
            .where("additional_attributes -> '#{key}' ->> 'answered_at' IS NULL")
            .where("additional_attributes -> '#{key}' ->> 'reminded_at' IS NULL")
  end

  # o paciente já escreveu algo depois da pesquisa (a conversa seguiu) ou pediu silêncio?
  def reminder_blocked?(contact, since)
    return true if contact.phone_number.blank?
    return true if contact.label_list.any? { |l| QUIET_LABELS.include?(l) || l.start_with?('perda_') }
    return true if Crm::PartnerGuard.partner_contact?(contact)

    Message.joins(:conversation).where(conversations: { contact_id: contact.id })
           .where(message_type: :incoming).exists?(['messages.created_at > ?', since])
  end

  def reminder_params(rem, contact)
    params = rem['template_params'].deep_dup
    first = contact.name.to_s.split.first.presence || 'Paciente'
    params.dig('processed_params', 'body')&.transform_values! { |v| v.to_s.gsub('{{nome}}', first) }
    params
  end

  def record_reminders(sent)
    settings = CrmSetting.find_by(account: @account)
    return if settings.blank?

    settings.with_lock do
      agenda = settings.agenda_config || {}
      state = agenda[STATE_KEY] || {}
      state['reminders'] = (sent + Array(state['reminders'])).first(LIST_CAP)
      state['last_reminder_at'] = Time.current.iso8601
      settings.update!(agenda_config: agenda.merge(STATE_KEY => state))
    end
  end

  def mark_sent!(contact, task)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      survey = attrs[MARK_KEY] || {}
      ids = (Array(survey['task_ids']) + [task.id]).last(20)
      attrs.merge(MARK_KEY => { 'pending_at' => Time.current.iso8601, 'task_ids' => ids, 'task_id' => task.id })
    end
  end

  def entry(task, contact, rule)
    { 'task_id' => task.id, 'name' => contact.name.to_s.truncate(40), 'phone_tail' => contact.phone_number.to_s.last(4),
      'surgery' => task.due_at.in_time_zone(TZ).strftime('%d/%m'), 'rule' => rule['label'], 'procedure' => task.procedure.to_s.truncate(50) }
  end

  def skip(task, rule, why)
    @run['skipped'] << { 'task_id' => task.id, 'name' => (task.contact&.name || task.title).to_s.truncate(40), 'why' => why,
                         'surgery' => task.due_at.in_time_zone(TZ).strftime('%d/%m'), 'rule' => rule&.dig('label') }
    nil
  end

  def record_run
    settings = CrmSetting.find_by(account: @account)
    return if settings.blank?

    settings.with_lock do
      agenda = settings.agenda_config || {}
      state = (agenda[STATE_KEY] || {}).merge(
        'last_run_at' => Time.current.iso8601, 'mode' => @shadow ? 'shadow' : 'live',
        'sent' => @run['sent'].first(LIST_CAP), 'skipped' => @run['skipped'].first(LIST_CAP)
      )
      settings.update!(agenda_config: agenda.merge(STATE_KEY => state))
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO NPS] registro da rodada: #{e.message}"
  end
end
