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
  LOCK_TTL = 10.minutes

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

  # 🏢 rodada 334: o agradecimento padrão fala o nome da empresa da conta
  # (na clínica continua "na CEVICO", idêntico)
  def self.default_thanks_text(account)
    Crm::CompanyPrompts.rebrand(Cevico::Company.for(account), DEFAULT_THANKS_TEXT)
  end

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
  def self.run_all(now = nil)
    now_sp = (now || TZ.now).in_time_zone(TZ)
    CrmSetting.find_each do |settings|
      cfg = (settings.agenda_config || {})[CONFIG_KEY] || {}
      next unless cfg['enabled'] == true

      run_account(settings, cfg, now_sp)
    end
    Crm::CronHealth.ran!('nps') # 🚨 #217: sinal de vida da rodada (o vigia confere)
  end

  # 🔒 auditoria 10/2026 (NPS sem trava de rodada): o cron dispara 4x por hora e,
  # com a fila presa, as rodadas acumuladas rodavam AO MESMO TEMPO e cada uma
  # mandava a pesquisa. Trava por conta no Redis (como a Jornada): quem chega
  # com a trava ocupada sai sem fazer nada — a próxima rodada de 15 min cobre.
  # A trava leva uma senha própria e só é solta por quem a pegou: se a rodada
  # passar do tempo e a seguinte entrar, a primeira não apaga a trava da segunda.
  # Redis fora do ar vira erro só desta conta (log); as outras contas seguem.
  def self.run_account(settings, cfg, now_sp)
    lock_key = "CRM_NPS_LOCK::#{settings.account_id}"
    token = nil
    begin
      token = SecureRandom.uuid
      unless Redis::Alfred.set(lock_key, token, nx: true, ex: LOCK_TTL.to_i)
        token = nil
        Rails.logger.info "[CEVICO NPS] conta #{settings.account_id}: rodada anterior ainda rodando, esta foi pulada"
        return
      end

      survey = new(settings.account, now_sp)
      survey.reconcile_refused # 🚫 #45: pesquisa/lembrete que a Meta recusou deixa de contar como enviada
      survey.run if now_sp.hour == (cfg['hour'] || 10).to_i
      survey.send_reminders
    rescue StandardError => e
      Rails.logger.error "[CEVICO NPS] conta #{settings.account_id}: #{e.message}"
      Crm::CronHealth.failed!('nps', e, account: settings.account) # 🚨 #217: avisa se repetir
    ensure
      Redis::Alfred.delete_if_equals(lock_key, token) if token
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
      next if survey['reminder_refused'].present? # #45: a Meta recusou o lembrete desta pesquisa; não repete
      # marca ANTES de enviar, dentro da trava: outra rodada não manda o mesmo lembrete
      next unless claim_reminder!(contact)

      reserved_at = Time.current
      source = Crm::TemplateSource.new(@account, inbox, nil, reminder_params(rem, contact), rem['message_preview'].presence,
                                       'Pesquisa de satisfação (lembrete)')
      sender = Crm::SendTemplateService.new(source: source, contact: contact)
      conversation = begin
        sender.perform
      rescue StandardError
        # deu erro no meio do envio: só solta a marca se a mensagem NÃO chegou a ser gravada
        release_reminder!(contact) unless template_sent_since?(contact, rem['template_params'], reserved_at)
        raise
      end
      if conversation.nil?
        release_reminder!(contact)
        next
      end

      remember_message!(contact, 'reminder_message_id', sender.message&.id)
      sent << { 'at' => Time.current.iso8601, 'name' => contact.name.to_s.truncate(40), 'contact_id' => contact.id,
                'message_id' => sender.message&.id }.compact
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

    text = cfg['thanks_text'].presence || default_thanks_text(contact.account)
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

    # Rodada 4 (achado #383): sob a trava da linha, só o estado do NPS muda
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, STATE_KEY) do |state|
      answers = Array(state['answers'])
      answers.unshift({ 'at' => Time.current.iso8601, 'band' => band, 'name' => contact.name.to_s.truncate(40), 'contact_id' => contact.id })
      state.merge('answers' => answers.first(LIST_CAP))
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

  # ── a Meta recusou (#45, auditoria 10/2026) ────────────────────────────
  # A pesquisa (e o lembrete dela) é dada como enviada quando a mensagem é
  # gravada; a Meta responde DEPOIS e a mensagem fica `status: failed`. A cada
  # rodada do cron: pesquisa recusada → a marca é devolvida (a cirurgia deixa
  # de contar como pesquisada, o Pós-operatório não trata a pessoa como "com
  # pesquisa recente", nenhum lembrete sai de uma pesquisa que não chegou) e
  # fica a nota da recusa nesta cirurgia para NÃO reenviar sozinho — ela
  # aparece nas "puladas" com o erro. Lembrete recusado → só a nota (não há
  # o que repetir). Sem reenvio automático: a causa (modelo pausado, número
  # inválido) costuma ser a mesma; a equipe corrige e, se quiser, ajusta a
  # cirurgia na Agenda para a pesquisa sair de novo.
  def reconcile_refused
    reconcile_refused_surveys
    reconcile_refused_reminders
  rescue StandardError => e
    Rails.logger.warn "[CEVICO NPS] conferência das recusas conta #{@account.id}: #{e.message}"
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

    # marca ANTES de enviar, dentro da trava (como o lembrete de consulta): outra
    # rodada em paralelo, ou a marca falhando depois do envio, não mandam 2 vezes
    before = claim_sent!(contact, task)
    return if before == :taken # outra rodada já reservou esta cirurgia (ou esta pessoa, no intervalo)

    if deliver_survey(inbox, task, rule, contact, before).nil?
      release_sent!(contact, before)
      return skip(task, rule, 'envio não saiu (contato/caixa)')
    end

    @run['sent'] << sent_entry(task, contact, rule)
  rescue StandardError => e
    skip(task, rule, "erro: #{e.message.truncate(60)}")
  end

  # manda a pesquisa já reservada; devolve a conversa ou nil. Se o envio LEVANTAR
  # erro (caixa errada, validação…), a marca só volta ao que era quando a
  # mensagem NÃO chegou a ser gravada — assim a cirurgia continua candidata sem
  # risco de sair 2 vezes, e não fica "enviada" sem pesquisa (o que faria sair
  # o lembrete de uma pesquisa que nunca chegou)
  def deliver_survey(inbox, task, rule, contact, before)
    reserved_at = Time.current
    source = Crm::TemplateSource.new(@account, inbox, nil, personalized_params(task, rule), @cfg['message_preview'].presence,
                                     'Pesquisa de satisfação (NPS)')
    sender = Crm::SendTemplateService.new(source: source, contact: contact)
    @sent_message = nil
    conversation = sender.perform
    @sent_message = sender.message # #45: conferido na rodada seguinte
    conversation
  rescue StandardError
    release_sent!(contact, before) unless template_sent_since?(contact, @cfg['template_params'], reserved_at)
    raise
  end

  def skip_reason(task, contact) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return 'sem telefone' if contact.nil? || contact.phone_number.blank?
    return 'cirurgia não marcada como realizada na Agenda' unless task.attendance == 'attended' || task.status == 'done'

    if Crm::PartnerGuard.partner_task?(task) || Crm::PartnerGuard.partner_contact?(contact)
      Crm::PartnerGuard.block!("pesquisa NPS (cirurgia #{task.id})", contact: contact)
      return 'paciente de parceiro (cerca)'
    end
    return 'pediu para não receber mensagens' if quiet_contact?(contact)

    survey = (contact.additional_attributes || {})[MARK_KEY] || {}
    return ALREADY_SENT if Array(survey['task_ids']).include?(task.id)

    refused = refused_reason(survey, task) # #45: a Meta recusou a pesquisa desta cirurgia → listada, sem reenvio automático
    return refused if refused

    return "já recebeu pesquisa há menos de #{min_interval_days} dias" if within_interval?(survey)

    nil
  end

  def min_interval_days
    (@cfg['min_interval_days'].presence || 60).to_i
  end

  # a pessoa recebeu uma pesquisa há menos de `min_interval_days` (segundo olho)?
  def within_interval?(survey)
    survey['pending_at'].present? && Time.zone.parse(survey['pending_at'].to_s) > min_interval_days.days.ago
  end

  # a mensagem modelo deste envio já foi gravada para o contato depois da reserva?
  # (prova física de que a pesquisa/lembrete saiu, mesmo que o envio tenha
  # levantado erro logo depois de gravar)
  def template_sent_since?(contact, template_params, since)
    name = template_params.to_h['name'].to_s
    return false if name.blank?

    Message.joins(:conversation).where(conversations: { contact_id: contact.id }, message_type: :outgoing)
           .where("messages.additional_attributes -> 'template_params' ->> 'name' = ?", name)
           .exists?(['messages.created_at >= ?', since])
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
  # nao_perturbe / perda_* + sinais de quem não quer receber com a chavinha ligada (16/10)
  def quiet_contact?(contact)
    quiet = QUIET_LABELS + Crm::StopSignals.robot_stop_labels(contact.account)
    contact.label_list.any? { |l| quiet.include?(l) || l.start_with?('perda_') }
  end

  def reminder_blocked?(contact, since)
    return true if contact.phone_number.blank?
    return true if quiet_contact?(contact)
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

    Cevico::SettingMerge.merge_key!(settings, :agenda_config, STATE_KEY) do |state|
      state.merge('reminders' => (sent + Array(state['reminders'])).first(LIST_CAP), 'last_reminder_at' => Time.current.iso8601)
    end
  end

  # reserva a cirurgia para esta rodada, dentro da trava do contato. Devolve a
  # marca como estava ANTES (para desfazer se o envio não sair) ou :taken quando
  # outra rodada já gravou esta cirurgia — ou outra pesquisa para esta pessoa
  # dentro do intervalo (segundo olho) — entre o skip_reason e aqui.
  def claim_sent!(contact, task)
    before = :taken
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      survey = attrs[MARK_KEY] || {}
      next attrs if Array(survey['task_ids']).include?(task.id) || within_interval?(survey)

      before = survey
      ids = (Array(survey['task_ids']) + [task.id]).last(20)
      attrs.merge(MARK_KEY => { 'pending_at' => Time.current.iso8601, 'task_ids' => ids, 'task_id' => task.id })
    end
    before
  end

  # envio não saiu: a marca volta a ser o que era (a cirurgia continua candidata)
  def release_sent!(contact, before)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      before.blank? ? attrs.except(MARK_KEY) : attrs.merge(MARK_KEY => before)
    end
  end

  # reserva o lembrete dentro da trava; false = já lembrado (por outra rodada)
  def claim_reminder!(contact)
    claimed = false
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      survey = attrs[MARK_KEY] || {}
      next attrs if survey['reminded_at'].present?

      claimed = true
      attrs.merge(MARK_KEY => survey.merge('reminded_at' => Time.current.iso8601))
    end
    claimed
  end

  def release_reminder!(contact)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs.merge(MARK_KEY => (attrs[MARK_KEY] || {}).except('reminded_at'))
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

    Cevico::SettingMerge.merge_key!(settings, :agenda_config, STATE_KEY) do |state|
      state.merge(
        'last_run_at' => Time.current.iso8601, 'mode' => @shadow ? 'shadow' : 'live',
        'sent' => @run['sent'].first(LIST_CAP), 'skipped' => @run['skipped'].first(LIST_CAP)
      )
    end
  rescue StandardError => e
    Rails.logger.warn "[CEVICO NPS] registro da rodada: #{e.message}"
  end

  # ── conferência das recusas da Meta (#45): ajudantes ───────────────────
  # [contato, erro] de cada marca `key` cuja mensagem a Meta recusou
  def refused_by_mark(key)
    contacts = contacts_with_mark(key)
    refused = Crm::SendTemplateService.refused(contacts.map { |c| c.additional_attributes.dig(MARK_KEY, key) })
    contacts.filter_map { |c| (error = refused[c.additional_attributes.dig(MARK_KEY, key)]) && [c, error] }
  end

  def reconcile_refused_surveys
    moved = refused_by_mark('message_id').map do |contact, error|
      task_id = release_refused!(contact, error)
      { 'task_id' => task_id, 'name' => contact.name.to_s.truncate(40), 'why' => "a Meta recusou: #{error}",
        'surgery' => surgery_day(task_id) }.compact
    end
    record_refused('sent', moved) if moved.any?
  end

  def reconcile_refused_reminders
    moved = refused_by_mark('reminder_message_id').map do |contact, error|
      Cevico::AttributeMerge.merge!(contact) do |attrs|
        attrs.merge(MARK_KEY => (attrs[MARK_KEY] || {}).except('reminder_message_id').merge('reminder_refused' => error.truncate(160)))
      end
      { 'contact_id' => contact.id, 'name' => contact.name.to_s.truncate(40), 'why' => "a Meta recusou: #{error}" }
    end
    record_refused('reminders', moved) if moved.any?
  end

  def surgery_day(task_id)
    @account.tasks.find_by(id: task_id)&.due_at&.in_time_zone(TZ)&.strftime('%d/%m')
  end

  def refused_reason(survey, task)
    return nil unless survey.dig('refused', 'task_id') == task.id

    "a Meta recusou (#{survey.dig('refused', 'error').to_s.truncate(80)})"
  end

  # a mensagem gravada fica na marca e na lista — a rodada seguinte confere se a Meta recusou (#45)
  def sent_entry(task, contact, rule)
    message_id = @sent_message&.id
    remember_message!(contact, 'message_id', message_id)
    entry(task, contact, rule).merge('message_id' => message_id).compact
  end

  # só pesquisas ainda dentro da janela de resposta: message_id fica na marca
  # de quem recebeu bem, e sem este corte a varredura carregaria TODOS os
  # contatos já pesquisados a cada rodada (revisão da Rodada 3). pending_at
  # e o limite são ISO 8601 em UTC — comparam como texto.
  def contacts_with_mark(key)
    @account.contacts.where("additional_attributes -> '#{MARK_KEY}' ->> '#{key}' IS NOT NULL")
            .where("additional_attributes -> '#{MARK_KEY}' ->> 'pending_at' > ?", REPLY_WINDOW.ago.utc.iso8601).to_a
  end

  # devolve a marca da pesquisa recusada e guarda a nota; devolve o id da cirurgia
  def release_refused!(contact, error)
    task_id = nil
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      survey = attrs[MARK_KEY] || {}
      task_id = survey['task_id']
      kept = survey.except('pending_at', 'task_id', 'message_id', 'reminded_at', 'reminder_message_id')
                   .merge('task_ids' => Array(survey['task_ids']) - [task_id],
                          'refused' => { 'task_id' => task_id, 'error' => error.truncate(160), 'at' => Time.current.iso8601 })
      attrs.merge(MARK_KEY => kept)
    end
    task_id
  end

  # a lista da rodada: sai das "enviadas" (ou "lembretes") e entra nas "puladas" com o erro
  def record_refused(list, moved)
    settings = CrmSetting.find_by(account: @account)
    return if settings.blank?

    key = ->(e) { e['task_id'] || e['contact_id'] }
    ids = moved.map(&key)
    Cevico::SettingMerge.merge_key!(settings, :agenda_config, STATE_KEY) do |state|
      state.merge(list => Array(state[list]).reject { |e| ids.include?(key.call(e)) },
                  'skipped' => (moved + Array(state['skipped'])).first(LIST_CAP))
    end
  end

  def remember_message!(contact, key, message_id)
    return if message_id.blank?

    Cevico::AttributeMerge.merge!(contact) do |attrs|
      attrs.merge(MARK_KEY => (attrs[MARK_KEY] || {}).merge(key => message_id))
    end
  end
end
