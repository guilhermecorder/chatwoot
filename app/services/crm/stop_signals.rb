# 🚦 SINAIS DE QUEM NÃO QUER MAIS RECEBER (Saúde do WhatsApp, 16/10/2026)
#
# A Meta NÃO informa quem bloqueou a clínica. O que dá para saber com
# precisão vem em dois níveis, e a ETIQUETA diz qual é:
#
#   CERTO (a pessoa ou a Meta disse com todas as letras)
#     • nao_perturbe ........ o paciente ESCREVEU pedindo para parar ("PARE",
#                             "SAIR", "não quero mais receber mensagens") —
#                             detector em Crm::OptOut (mensagem inteira, sem
#                             margem para "sair de casa às 8h").
#     • certo_sem_marketing . a Meta devolveu o erro 131050: a pessoa parou de
#                             receber MARKETING desta empresa. Confirmação e
#                             lembrete da consulta (utilidade) continuam.
#
#   SUSPEITA (sinal indireto — confira antes de concluir)
#     • suspeita_bloqueio ... as últimas mensagens nossas por um número ficaram
#                             só em "enviado" (nunca "entregue") por mais de 48h,
#                             depois de ela já ter recebido por esse número
#                             antes. Celular desligado/sem internet dá o mesmo
#                             sinal. Varredura de hora em hora em
#                             Crm::BlockSuspicionScan; sai sozinha quando volta a
#                             entregar ou a pessoa escreve.
#     • suspeita_nao_quer ... escreveu algo como "vou bloquear", "isso é spam",
#                             "me tira da lista" no meio de uma frase maior.
#
# O MOTIVO de cada marcação fica no contato (additional_attributes
# 'cevico_stop_signals') e é o que a tela Saúde do WhatsApp mostra no cartão
# da pessoa. Quem tira a marcação à mão fica registrado e a varredura não
# remarca pelo MESMO sinal (só por um sinal novo, depois disso).
#
# ROBÔS: nao_perturbe sempre tira a pessoa dos robôs (regra de 20/09). As
# outras três têm chavinha própria em agenda_config['stop_signals']['robos']
# (tela Saúde do WhatsApp → "O que os robôs fazem") — robot_stop_labels é a
# lista que Crm::OptOut, follow-up, jornada, NPS e Colheitadeira leem.
module Crm::StopSignals
  module_function

  ATTR_KEY = 'cevico_stop_signals'.freeze
  SETTINGS_KEY = 'stop_signals'.freeze
  HISTORY_CAP = 15

  SIGNALS = {
    'nao_perturbe' => {
      certeza: 'certo', titulo: 'Pediu para parar', color: '#DC2626', icon: 'i-lucide-hand',
      description: 'CERTO — o paciente escreveu pedindo para não receber mais mensagens (PARE, SAIR, ' \
                   '"não quero mais receber"). Nenhum robô, campanha ou jornada manda nada.'
    },
    'certo_sem_marketing' => {
      certeza: 'certo', titulo: 'Parou o marketing (aviso da Meta)', color: '#E11D48', icon: 'i-lucide-megaphone-off',
      description: 'CERTO — a Meta avisou (erro 131050) que a pessoa parou de receber mensagens de marketing ' \
                   'desta empresa. Confirmação e lembrete da consulta continuam chegando.'
    },
    'suspeita_bloqueio' => {
      certeza: 'suspeita', titulo: 'Suspeita de bloqueio', color: '#D97706', icon: 'i-lucide-shield-question',
      description: 'SUSPEITA — nossas últimas mensagens ficaram só em "enviado" por mais de 48h, depois de ela já ter ' \
                   'recebido antes pelo mesmo número. Celular desligado dá o mesmo sinal; a Meta não informa quem bloqueou.'
    },
    'suspeita_nao_quer' => {
      certeza: 'suspeita', titulo: 'Frase de quem não quer', color: '#F59E0B', icon: 'i-lucide-message-circle-warning',
      description: 'SUSPEITA — escreveu algo como "vou bloquear", "isso é spam" ou "me tira da lista" no meio de uma ' \
                   'frase. Confira a conversa antes de concluir.'
    }
  }.freeze
  KEYS = SIGNALS.keys.freeze
  # chavinhas dos robôs (nao_perturbe não tem: sempre para)
  ROBOT_DEFAULTS = { 'certo_sem_marketing' => true, 'suspeita_bloqueio' => false, 'suspeita_nao_quer' => false }.freeze
  SCAN_DEFAULTS = { 'horas' => 48, 'presas' => 2 }.freeze
  SCAN_LIMITS = { 'horas' => (24..240), 'presas' => (1..5) }.freeze

  # código de erro da Meta dentro do texto guardado na mensagem:
  # "131050: Unable to deliver…" (webhook) ou "(#131050) …" (recusa no envio)
  ERROR_CODE = /(?<![0-9])(13[0-9]{4})(?![0-9])/
  STOP_MARKETING_CODE = '131050'.freeze

  # quem mandou a mensagem (mesma convenção do Gasto do WhatsApp, item 303),
  # com o número do robô de follow-up para o ranking "o que mais gera silêncio"
  ORIGIN_SQL = <<~SQL.squish.freeze
    CASE
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_followup_bot_id') THEN 'followup:' || (messages.additional_attributes ->> 'cevico_followup_bot_id')
      WHEN messages.additional_attributes ->> 'cevico_followup_reativacao' = 'true' THEN 'reativacao'
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_ia_agent') THEN 'ia:' || (messages.additional_attributes ->> 'cevico_ia_agent')
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_journey') THEN 'jornada'
      WHEN jsonb_exists(messages.additional_attributes, 'cevico_auto') THEN 'auto:' || (messages.additional_attributes ->> 'cevico_auto')
      WHEN jsonb_exists(messages.additional_attributes, 'campaign_id') THEN 'campanha'
      WHEN messages.sender_type = 'User' THEN 'equipe'
      ELSE 'sistema'
    END
  SQL
  TEMPLATE_SQL = "messages.additional_attributes -> 'template_params' ->> 'name'".freeze

  # ── configuração (chavinhas) ─────────────────────────────────────────────
  def settings(account)
    raw = ((CrmSetting.find_by(account_id: account.id)&.agenda_config || {})[SETTINGS_KEY] || {}).to_h
    robots = ROBOT_DEFAULTS.merge((raw['robos'] || {}).to_h.slice(*ROBOT_DEFAULTS.keys).transform_values { |v| v == true || v.to_s == 'true' })
    scan = SCAN_DEFAULTS.to_h { |k, d| [k, (raw[k].presence || d).to_i.clamp(SCAN_LIMITS[k].min, SCAN_LIMITS[k].max)] }
    { 'robos' => robots }.merge(scan)
  end

  def save_settings!(account, attrs)
    attrs = attrs.to_h.stringify_keys
    Cevico::SettingMerge.merge!(account, :agenda_config) do |cfg|
      current = (cfg[SETTINGS_KEY] || {}).to_h
      robots = (current['robos'] || {}).to_h
      (attrs['robos'] || {}).to_h.each { |k, v| robots[k.to_s] = (v == true || v.to_s == 'true') if ROBOT_DEFAULTS.key?(k.to_s) }
      current['robos'] = robots
      SCAN_LIMITS.each_key { |k| current[k] = attrs[k].to_i.clamp(SCAN_LIMITS[k].min, SCAN_LIMITS[k].max) if attrs[k].present? }
      cfg[SETTINGS_KEY] = current
      cfg
    end
    settings(account)
  end

  # etiquetas desta família que tiram a pessoa dos robôs AGORA (fora a
  # nao_perturbe, que Crm::OptOut e cada robô já tratam como fixa)
  def robot_stop_labels(account)
    return [] if account.blank?

    settings(account)['robos'].select { |_k, on| on }.keys
  rescue StandardError
    ['certo_sem_marketing']
  end

  # ── marcar / desmarcar ───────────────────────────────────────────────────
  def evidence(contact)
    (contact.additional_attributes || {})[ATTR_KEY] || {}
  end

  def marked?(contact, key)
    contact.label_list.include?(key)
  end

  # marca a pessoa com o sinal `key` e guarda o MOTIVO. Devolve true quando a
  # marcação é nova (a nota na conversa só sai nessa hora).
  # since: quando o sinal começou — se alguém já tirou esta marcação à mão
  # DEPOIS disso, a varredura não remarca pelo mesmo sinal.
  def mark!(contact, key, proof, conversation: nil, since: nil)
    return false unless KEYS.include?(key) && contact.present?
    return false if dismissed_after?(contact, key, since)

    ensure_label!(contact.account, key)
    fresh = !marked?(contact, key)
    add_label!(contact, key) if fresh
    stamp = proof.to_h.stringify_keys.merge('at' => (evidence(contact).dig(key, 'at') unless fresh) || Time.current.iso8601,
                                            'visto_em' => Time.current.iso8601)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      signals = (attrs[ATTR_KEY] || {}).to_h
      signals[key] = stamp
      signals['_historico'] = history(signals, 'marcou' => key, 'em' => Time.current.iso8601) if fresh
      attrs.merge(ATTR_KEY => signals)
    end
    note!(conversation, key, proof) if fresh && conversation
    fresh
  end

  # tira a marcação. dismiss: true = uma PESSOA disse "não é isso" — a
  # varredura não remarca pelo mesmo sinal (só por um sinal mais novo)
  def unmark!(contact, key, motivo:, by: nil, dismiss: false)
    return false unless KEYS.include?(key) && contact.present? && marked?(contact, key)

    remove_label!(contact, key)
    Cevico::AttributeMerge.merge!(contact) do |attrs|
      signals = (attrs[ATTR_KEY] || {}).to_h
      signals.delete(key)
      signals['_dispensados'] = (signals['_dispensados'] || {}).to_h.merge(key => Time.current.iso8601) if dismiss
      signals['_historico'] = history(signals, 'tirou' => key, 'em' => Time.current.iso8601, 'motivo' => motivo, 'por' => by&.name)
      attrs.merge(ATTR_KEY => signals)
    end
    true
  end

  def dismissed_after?(contact, key, since)
    at = evidence(contact).dig('_dispensados', key)
    return false if at.blank?
    return true if since.blank?

    Time.zone.parse(at.to_s) >= Time.zone.parse(since.to_s)
  rescue ArgumentError, TypeError
    false
  end

  # ── ganchos dos avisos de status da Meta ─────────────────────────────────
  # chamado depois que o status de uma mensagem nossa muda (webhook) ou o
  # envio volta recusado. Leve: só olha a etiqueta quando o status pede.
  def on_status_change(message)
    return unless message&.outgoing? && message.inbox&.channel_type == 'Channel::Whatsapp'

    contact = message.conversation&.contact
    return if contact.blank?

    if message.status.to_s == 'failed'
      stop_marketing!(message, contact) if error_code(message.external_error) == STOP_MARKETING_CODE
    elsif %w[delivered read].include?(message.status.to_s)
      delivered!(message, contact)
    end
  rescue StandardError => e
    Rails.logger.warn("[CEVICO sinais] status da mensagem #{message&.id}: #{e.message}")
  end

  # o paciente escreveu → não bloqueou ninguém
  def on_incoming(message, contact)
    return unless message&.incoming? && contact.present? && marked?(contact, 'suspeita_bloqueio')

    unmark!(contact, 'suspeita_bloqueio', motivo: 'o paciente escreveu para a clínica')
  rescue StandardError => e
    Rails.logger.warn("[CEVICO sinais] mensagem recebida #{message&.id}: #{e.message}")
  end

  def error_code(text)
    text.to_s[ERROR_CODE, 1]
  end

  def stop_marketing!(message, contact)
    mark!(contact, 'certo_sem_marketing',
          { 'codigo' => STOP_MARKETING_CODE, 'erro' => message.external_error.to_s.truncate(160),
            'inbox_id' => message.inbox_id, 'message_id' => message.id,
            'mensagem' => message_summary(message),
            'ultima_entregue' => last_delivered_summary(contact, before: message.created_at, inbox_id: message.inbox_id) },
          conversation: message.conversation, since: message.created_at.iso8601)
  end

  def delivered!(message, contact)
    labels = contact.label_list
    unmark!(contact, 'suspeita_bloqueio', motivo: "voltou a receber (mensagem #{message.id} entregue)") if labels.include?('suspeita_bloqueio')
    return unless labels.include?('certo_sem_marketing')
    return unless message.additional_attributes&.dig('cevico_wa_billing', 'category').to_s == 'marketing'

    unmark!(contact, 'certo_sem_marketing', motivo: "voltou a receber marketing (mensagem #{message.id} entregue)")
  end

  # ── origem da mensagem (quem mandou) ─────────────────────────────────────
  def origin_key(message)
    attrs = message.additional_attributes || {}
    return "followup:#{attrs['cevico_followup_bot_id']}" if attrs['cevico_followup_bot_id'].present?
    return 'reativacao' if attrs['cevico_followup_reativacao'].to_s == 'true'
    return "ia:#{attrs['cevico_ia_agent']}" if attrs['cevico_ia_agent'].present?
    return 'jornada' if attrs.key?('cevico_journey')
    return "auto:#{attrs['cevico_auto']}" if attrs['cevico_auto'].present?
    return 'campanha' if attrs.key?('campaign_id')

    message.sender_type == 'User' ? 'equipe' : 'sistema'
  end

  def origin_label(key, bot_names = nil)
    kind, value = key.to_s.split(':', 2)
    case kind
    when 'followup'
      name = (bot_names || {})[value.to_i] || Crm::FollowupBot.find_by(id: value)&.name
      "Robô de follow-up ##{value}#{" · #{name}" if name.present?}"
    when 'reativacao' then 'Reativação de quem adiou'
    when 'ia' then "#{value.to_s.tr('_', ' ').capitalize} (IA)"
    when 'jornada' then 'Jornada do paciente'
    when 'auto' then "#{value.to_s.tr('_', ' ')} (automático)"
    when 'campanha' then 'Campanha WhatsApp'
    when 'equipe' then 'Equipe (conversa)'
    else 'Sistema (sem autor)'
    end
  end

  def message_summary(message)
    return nil if message.blank?

    { 'id' => message.id, 'em' => message.created_at.iso8601, 'inbox_id' => message.inbox_id,
      'origem' => origin_key(message), 'modelo' => message.additional_attributes&.dig('template_params', 'name'),
      'texto' => message.content.to_s.squish.truncate(140), 'conversa' => message.conversation&.display_id }.compact
  end

  def last_delivered_summary(contact, before:, inbox_id: nil)
    scope = Message.joins(:conversation).where(conversations: { contact_id: contact.id })
                   .where(message_type: :outgoing, private: false, status: %i[delivered read])
                   .where('messages.created_at < ?', before)
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    message_summary(scope.reorder('messages.created_at DESC').first)
  end

  # ── miúdos ───────────────────────────────────────────────────────────────
  def ensure_label!(account, key)
    meta = SIGNALS[key]
    label = account.labels.find_or_initialize_by(title: key)
    return label if label.persisted? && label.description.present?

    label.color = meta[:color] if label.new_record?
    label.description = meta[:description]
    label.show_on_sidebar = false if label.new_record?
    label.save!
    label
  rescue ActiveRecord::RecordNotUnique
    account.labels.find_by(title: key)
  end

  # etiqueta no contato sem depender do cadastro passar na validação (e-mail
  # antigo fora do formato não pode impedir a marcação)
  def add_label!(contact, key)
    contact.add_labels([key])
  rescue ActiveRecord::RecordInvalid
    contact.reload.label_list.add(key)
    contact.save!(validate: false)
  end

  def remove_label!(contact, key)
    contact.update!(label_list: contact.label_list - [key])
  rescue ActiveRecord::RecordInvalid
    contact.reload.label_list.remove(key)
    contact.save!(validate: false)
  end

  def history(signals, entry)
    (Array(signals['_historico']) + [entry.compact]).last(HISTORY_CAP)
  end

  NOTE_TEXT = {
    'certo_sem_marketing' => '🚦 A Meta avisou que este paciente parou de receber mensagens de MARKETING da clínica (erro 131050) — ' \
                             'etiqueta certo_sem_marketing. Confirmação e lembrete da consulta continuam.',
    'suspeita_bloqueio' => '🟠 SUSPEITA de bloqueio neste número: nossas últimas mensagens ficaram só em "enviado" por mais de 48h. ' \
                           'Pode ser celular desligado — etiqueta suspeita_bloqueio (sai sozinha se voltar a entregar).',
    'suspeita_nao_quer' => '🟠 Possível pedido para parar nesta mensagem — etiqueta suspeita_nao_quer. Confira e, se for, ' \
                           'aplique nao_perturbe; se não for, tire a marcação em Relatórios → Saúde do WhatsApp.'
  }.freeze

  def note!(conversation, key, _proof)
    text = NOTE_TEXT[key]
    return if text.blank?

    conversation.messages.create!(account_id: conversation.account_id, inbox_id: conversation.inbox_id,
                                  message_type: :activity, private: true, content: text)
  rescue StandardError => e
    Rails.logger.warn("[CEVICO sinais] nota na conversa #{conversation&.id}: #{e.message}")
  end
end
