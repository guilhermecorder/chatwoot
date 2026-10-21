# 📊 RESULTADO DO FOLLOW-UP (13/10 — "medir: quantos leads por etapa recebem
# mensagem e quantos bloqueiam, pra ver se o ajuste funciona"). Por coluna do
# CRM, no período:
#   cutucados       → conversas que receberam cutucada de robô
#   cutucadas       → mensagens de cutucada enviadas
#   responderam     → conversas em que o paciente escreveu até 48h depois de uma cutucada
#   nao_entregues   → cutucadas que voltaram como "falhou" (número inválido, bloqueio)
#   pararam         → pacientes cutucados que hoje têm nao_perturbe/perda_* (pediram para parar ou recusaram)
#   seguradas       → conversas que a LEITURA segurou (encerrada / adiada / recusou)
#   reativacoes     → mensagens modelo para quem tinha adiado (e quantos responderam)
# Coluna = a do card NA HORA da cutucada (cutucadas antigas, sem o carimbo,
# usam a coluna atual do card).
class Crm::FollowupResults
  REPLY_WINDOW = 48.hours

  # from/to = a régua de período padrão (Crm::ResolvesPeriod no controlador)
  def initialize(account, from:, to:)
    @account = account
    @since = from
    @until = to
  end

  def call
    rows = Hash.new { |h, k| h[k] = blank_row }
    count_nudges(rows)
    count_reads(rows)
    count_reactivations(rows)
    list = rows.map { |stage_id, row| row.merge(stage_label(stage_id)) }
    list.sort_by! { |r| [-r[:cutucadas], -r[:seguradas_total]] }
    { from: @since.iso8601, to: @until.iso8601, rows: list, total: totals(list) }
  end

  private

  def blank_row
    { cutucados: 0, cutucadas: 0, responderam: 0, nao_entregues: 0, pararam: 0,
      seguradas: { 'encerrada' => 0, 'adiada' => 0, 'recusou' => 0 }, seguradas_total: 0, abertas: 0,
      reativacoes: 0, reativacoes_responderam: 0 }
  end

  def scope_outgoing(flag)
    Message.where(account_id: @account.id, message_type: :outgoing)
           .where("messages.additional_attributes ->> '#{flag}' IS NOT NULL")
           .where(messages: { created_at: @since..@until })
  end

  def count_nudges(rows) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
    nudges = scope_outgoing('cevico_followup_bot_id')
             .pluck(:conversation_id, :created_at, :status, Arel.sql("messages.additional_attributes ->> 'cevico_followup_stage_id'"))
    return if nudges.empty?

    conv_ids = nudges.map(&:first).uniq
    replies = incoming_times(conv_ids)
    contact_of = Conversation.where(id: conv_ids).pluck(:id, :contact_id).to_h
    quiet = Crm::OptOut.excluded_contact_ids(@account).to_set
    seen = Hash.new { |h, k| h[k] = Set.new }
    replied = Hash.new { |h, k| h[k] = Set.new }

    nudges.each do |conv_id, at, status, stage_raw|
      stage_id = stage_raw.presence&.to_i || current_stage(contact_of[conv_id])
      row = rows[stage_id]
      row[:cutucadas] += 1
      row[:nao_entregues] += 1 if status.to_s == 'failed'
      seen[stage_id] << conv_id
      replied[stage_id] << conv_id if Array(replies[conv_id]).any? { |t| t > at && t <= at + REPLY_WINDOW }
    end
    seen.each do |stage_id, convs|
      rows[stage_id][:cutucados] = convs.size
      rows[stage_id][:responderam] = replied[stage_id].size
      rows[stage_id][:pararam] = convs.count { |c| quiet.include?(contact_of[c]) }
    end
  end

  # leituras feitas no período (a última de cada conversa), pela coluna atual do card
  def count_reads(rows)
    attr = Crm::FollowupClosure::ATTR
    @account.conversations
            .where("(conversations.additional_attributes -> '#{attr}' ->> 'at')::timestamptz BETWEEN ? AND ?", @since, @until)
            .pluck(:contact_id, Arel.sql("conversations.additional_attributes -> '#{attr}' ->> 'situacao'"))
            .each do |contact_id, situacao|
      row = rows[current_stage(contact_id)]
      if row[:seguradas].key?(situacao)
        row[:seguradas][situacao] += 1
        row[:seguradas_total] += 1
      elsif situacao == 'aberta'
        row[:abertas] += 1
      end
    end
  end

  def count_reactivations(rows) # rubocop:disable Metrics/CyclomaticComplexity
    sent = scope_outgoing('cevico_followup_reativacao').pluck(:conversation_id, :created_at)
    return if sent.empty?

    replies = incoming_times(sent.map(&:first).uniq)
    contact_of = Conversation.where(id: sent.map(&:first)).pluck(:id, :contact_id).to_h
    sent.each do |conv_id, at|
      row = rows[current_stage(contact_of[conv_id])]
      row[:reativacoes] += 1
      row[:reativacoes_responderam] += 1 if Array(replies[conv_id]).any? { |t| t > at && t <= at + REPLY_WINDOW }
    end
  end

  def incoming_times(conv_ids)
    Message.where(conversation_id: conv_ids, message_type: :incoming, private: false)
           .where('created_at >= ?', @since)
           .pluck(:conversation_id, :created_at)
           .group_by(&:first).transform_values { |list| list.map(&:last) }
  end

  # coluna atual do card do contato (o card mais recente, se houver mais de um funil)
  def current_stage(contact_id)
    return nil if contact_id.nil?

    @stage_by_contact ||= {}
    return @stage_by_contact[contact_id] if @stage_by_contact.key?(contact_id)

    @stage_by_contact[contact_id] = Crm::Contact.where(contact_id: contact_id).order(updated_at: :desc).pick(:stage_id)
  end

  def stage_label(stage_id)
    @stages ||= Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id })
                          .pluck(:id, :name, :color, 'crm_pipelines.name').to_h { |id, n, c, p| [id, { name: n, color: c, pipeline: p }] }
    info = @stages[stage_id] || { name: 'Sem card no CRM', color: '#94A3B8', pipeline: nil }
    { stage_id: stage_id, stage_name: info[:name], stage_color: info[:color], pipeline_name: info[:pipeline] }
  end

  def totals(list)
    keys = %i[cutucados cutucadas responderam nao_entregues pararam seguradas_total abertas reativacoes reativacoes_responderam]
    sums = keys.index_with { |k| list.sum { |r| r[k] } }
    sums[:seguradas] = %w[encerrada adiada recusou].index_with { |s| list.sum { |r| r[:seguradas][s] } }
    sums
  end
end
