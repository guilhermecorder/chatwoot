# 📬 FOLLOW-UP DA VENDA NO MEU PAINEL (22/11/2026 · LIFE, levado para a ótica no mesmo dia; pedido do Guilherme): "vou querer um dashboard aqui no
# meu painel da Life, com os envios das mensagens de follow-up… fazer esse tipo de acompanhamento aqui pelo painel".
#
# Uma régua só, no período escolhido (a mesma régua de período da Jornada da venda):
#   · por MOMENTO da venda (= cada robô de follow-up da conta, ligado ou não) e por MENSAGEM (cada etapa do robô):
#       enviadas      → mensagens que o robô mandou
#       pessoas       → conversas diferentes que receberam
#       lidas         → mensagens com status "lida" no WhatsApp
#       falharam      → mensagens que voltaram como "falhou" (número inválido, bloqueio, modelo recusado)
#       responderam   → conversas em que o cliente escreveu até 48 h depois de uma mensagem do robô
#       andaram       → conversas cujo cartão foi para uma coluna mais adiante do funil até 7 dias depois
#   · mais a RETOMADA (modelo para quem pediu tempo e chegou o dia combinado), na mesma conta.
# A etapa de cada mensagem vem do carimbo `cevico_followup_step` (nº da etapa no robô); a coluna na hora do envio,
# de `cevico_followup_stage_id` (Crm::FollowupBotJob#send_nudge). O resultado por coluna continua no
# Crm::FollowupResults (tela de Automações); aqui a leitura é por momento e por mensagem.
class Crm::FollowupPanel
  REPLY_WINDOW = 48.hours
  MOVE_WINDOW = 7.days
  REACTIVATION_KEY = 'retomada'.freeze

  def initialize(account, since:, until_at:)
    @account = account
    @since = since
    @until = until_at
  end

  def call
    moments = bots.map { |bot| moment_json(bot) }
    moments << reactivation_json
    moments.select! { |m| m[:active] || m[:sent].positive? }
    moments.sort_by! { |m| [m[:order], m[:name]] }
    { since: @since, until: @until, total: totals(moments), moments: moments, daily: daily }
  end

  private

  def bots
    @bots ||= Crm::FollowupBot.where(account_id: @account.id).order(:id).to_a
  end

  # ── envios do período ─────────────────────────────────────────────────────
  # [[conversation_id, created_at, status, bot_id, step_index, stage_id], …]
  def nudges
    @nudges ||= outgoing('cevico_followup_bot_id')
                .pluck(:conversation_id, :created_at, :status,
                       Arel.sql("messages.additional_attributes ->> 'cevico_followup_bot_id'"),
                       Arel.sql("messages.additional_attributes ->> 'cevico_followup_step'"),
                       Arel.sql("messages.additional_attributes ->> 'cevico_followup_stage_id'"))
                .map { |c, at, st, bot, step, stage| [c, at, st.to_s, bot.to_i, step.presence&.to_i, stage.presence&.to_i] } # rubocop:disable Metrics/ParameterLists
  end

  def reactivations
    @reactivations ||= outgoing('cevico_followup_reativacao').pluck(:conversation_id, :created_at, :status)
                                                             .map { |c, at, st| [c, at, st.to_s, nil, nil, nil] }
  end

  def outgoing(flag)
    Message.where(account_id: @account.id, message_type: :outgoing, created_at: @since..@until)
           .where("messages.additional_attributes ->> '#{flag}' IS NOT NULL")
  end

  # ── um momento (robô) ─────────────────────────────────────────────────────
  def moment_json(bot) # rubocop:disable Metrics/AbcSize
    rows = nudges.select { |n| n[3] == bot.id }
    steps = bot.ordered_steps
    by_step = rows.group_by { |n| n[4] }
    step_rows = Array(bot.steps).each_with_index.map do |step, index|
      count_rows(Array(by_step[index])).merge(index: index, when: when_text(step), text: step_text(step), ai: ai_step?(step))
    end
    step_rows.sort_by! { |s| steps.index(bot.steps[s[:index]]) || s[:index] }
    unknown = Array(by_step[nil])
    step_rows << count_rows(unknown).merge(index: nil, when: 'sem etapa', text: 'mensagens antigas, sem o nº da etapa', ai: false) if unknown.any?
    count_rows(rows).merge(key: "bot-#{bot.id}", name: moment_name(bot), where: columns_text(bot), active: bot.active,
                           order: order_of(bot), steps: step_rows)
  end

  def reactivation_json
    count_rows(reactivations).merge(key: REACTIVATION_KEY, name: 'Retomada combinada', where: 'quem pediu tempo, no dia combinado',
                                    active: true, order: 90, steps: [])
  end

  def count_rows(rows) # rubocop:disable Metrics/CyclomaticComplexity
    convs = rows.map(&:first).uniq
    { sent: rows.size, people: convs.size,
      read: rows.count { |r| r[2] == 'read' },
      failed: rows.count { |r| r[2] == 'failed' },
      replied: rows.select { |r| replied_after?(r[0], r[1]) }.map(&:first).uniq.size,
      moved: rows.select { |r| moved_after?(r[0], r[1], r[5]) }.map(&:first).uniq.size }
  end

  # ── resposta e avanço ─────────────────────────────────────────────────────
  def replied_after?(conversation_id, at)
    Array(incoming[conversation_id]).any? { |t| t > at && t <= at + REPLY_WINDOW }
  end

  def incoming
    @incoming ||= Message.where(conversation_id: all_conversation_ids, message_type: :incoming, private: false)
                         .where(created_at: @since..(@until + REPLY_WINDOW))
                         .pluck(:conversation_id, :created_at)
                         .group_by(&:first).transform_values { |list| list.map(&:last) }
  end

  def all_conversation_ids
    @all_conversation_ids ||= (nudges + reactivations).map(&:first).uniq
  end

  # o cartão entrou numa coluna mais adiante (mesmo funil) até 7 dias depois da mensagem
  def moved_after?(conversation_id, at, stage_at_send) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    contact_id = contact_of[conversation_id]
    from = position[stage_at_send] || current_position(contact_id)
    return false if contact_id.nil? || from.nil?

    Array(entries[contact_id]).any? do |stage_id, entered|
      pos = position[stage_id]
      entered > at && entered <= at + MOVE_WINDOW && pos && pos[0] == from[0] && pos[1] > from[1]
    end
  end

  def contact_of
    @contact_of ||= Conversation.where(id: all_conversation_ids).pluck(:id, :contact_id).to_h
  end

  # { stage_id => [pipeline_id, position] }
  def position
    @position ||= Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
                            .pluck(:id, :pipeline_id, :position).to_h { |id, pipe, pos| [id, [pipe, pos]] }
  end

  def current_position(contact_id)
    position[cards[contact_id]&.last]
  end

  # { contact_id => [crm_contact_id, stage_id atual] } — o card mais recente
  def cards
    @cards ||= Crm::Contact.where(contact_id: contact_of.values.compact.uniq).order(:updated_at)
                           .pluck(:contact_id, :id, :stage_id).to_h { |contact, card, stage| [contact, [card, stage]] }
  end

  # { contact_id => [[stage_id, entered_at], …] }
  def entries
    @entries ||= begin
      by_card = cards.to_h { |contact, (card, _)| [card, contact] }
      Crm::StageLog.where(crm_contact_id: by_card.keys).where(entered_at: @since..(@until + MOVE_WINDOW))
                   .pluck(:crm_contact_id, :stage_id, :entered_at)
                   .group_by { |card, _, _| by_card[card] }
                   .transform_values { |list| list.map { |_, stage, at| [stage, at] } }
    end
  end

  # ── textos ────────────────────────────────────────────────────────────────
  # "LIFE · Orçamento sem resposta (1, 2, 3 dias)" → "Orçamento sem resposta"; na ótica, "Ótica · PIX do exame (24h)" → "PIX do exame"
  def moment_name(bot)
    bot.name.to_s.sub(/\A\s*(life|ótica|otica)\s*·\s*/i, '').sub(/\s*\(.*\)\s*\z/, '').strip.presence || "Robô #{bot.id}"
  end

  def columns_text(bot)
    ids = Array(bot.stage_ids).map(&:to_i).presence || [bot.stage_id].compact
    names = ids.filter_map { |id| stage_names[id] }
    names.any? ? names.join(', ') : 'todas as conversas da caixa'
  end

  def stage_names
    @stage_names ||= Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).pluck(:id, :name).to_h
  end

  # ordem na jornada: a primeira coluna do robô no funil
  def order_of(bot)
    ids = Array(bot.stage_ids).map(&:to_i).presence || [bot.stage_id].compact
    first = ids.filter_map { |id| position[id]&.last }.min || 80
    # robô de "conversa parada" (várias colunas soltas pelo funil) vai para o fim da lista
    ids.size > 2 ? first + 50 : first
  end

  def when_text(step)
    hours = Crm::FollowupBot.step_delay_hours(step)
    text = if hours < 1 then "#{(hours * 60).round} min"
           elsif hours < 24 then "#{hours.round} h"
           else
             days = (hours / 24).round
             days == 1 ? '1 dia' : "#{days} dias"
           end
    step['delay_from'] == 'stage_entry' ? "#{text} do envio" : "#{text} sem resposta"
  end

  def step_text(step)
    raw = ai_step?(step) ? 'escrita pela IA na hora, a partir da conversa' : step['message']
    raw.to_s.gsub(/\[nome\]/i, 'Fulano').squish.truncate(110)
  end

  def ai_step?(step)
    Crm::FollowupBot.ai_step?(step)
  end

  # ── totais e linha do tempo ──────────────────────────────────────────────
  def totals(moments) # rubocop:disable Metrics/AbcSize
    keys = %i[sent people read failed replied moved]
    sums = keys.index_with { |k| moments.sum { |m| m[k] } }
    all = nudges + reactivations
    sums[:people] = all.map(&:first).uniq.size
    sums[:replied] = all.select { |r| replied_after?(r[0], r[1]) }.map(&:first).uniq.size
    sums[:moved] = all.select { |r| moved_after?(r[0], r[1], r[5]) }.map(&:first).uniq.size
    sums
  end

  # envios por dia (no fuso do painel), para o gráfico de barras
  def daily
    tz = Crm::ResolvesPeriod::PERIOD_TZ
    counts = (nudges + reactivations).group_by { |r| r[1].in_time_zone(tz).to_date }.transform_values(&:size)
    first = @since.in_time_zone(tz).to_date
    last = [@until.in_time_zone(tz).to_date, tz.today].min
    return [] if last < first || (last - first) > 120

    (first..last).map { |day| { day: day.iso8601, sent: counts[day] || 0 } }
  end
end
