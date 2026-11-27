# 🧭 EQUIPE COMERCIAL · COM QUEM E COM QUE RESULTADO (27/11/2026 · LIFE, 3º pedido do Guilherme): "quantas
# movimentações de fase ele conseguiu fazer, das respostas que ele deu, em quais etapas a pessoa estava… com quem que
# ele conversou primeiro, com pessoas de quais grupos ele fala primeiro, ele prioriza, se ele consegue mudar de estágio
# as pessoas… e no dia eu preciso entender que tipo de conversa teve".
#
# Para cada pessoa da equipe, a partir das mensagens escritas por ela (Crm::TeamResponse#human_rows):
#   · etapa NA HORA da resposta: a coluna em que o cartão estava quando ela respondeu (histórico Crm::StageLog; sem
#     histórico, a coluna de hoje)
#   · andou depois: o cartão foi para uma coluna MAIS ADIANTE (posição maior, sem contar "Sem Interesse") até 48 h depois
#     de uma resposta dela
#   · primeira do dia: a 1ª conversa que ela respondeu em cada dia (mostra quem ela prioriza)
#   · cada etapa ganha uma chave de cor igual à da Jornada (leads, sondagem, conta, enviado, pagamento, proposta…)
class Crm::TeamResponse::ConversationMap
  MOVE_WINDOW = 48.hours
  LOST = /sem interesse|perdid/
  KEYS = [
    ['leads', /novos contatos/], ['sondagem', /solicitacao da conta|sondagem/], ['conta', /orcamento a fazer|orcamento pronto|recebimento da conta/],
    ['enviado', /orcamento enviado/], ['pagamento', /vistoria|visita/], ['proposta', /negociacao|proposta/],
    ['fechado', /contrato|homologacao/], ['instalado', /instalacao|pos.?venda|nps/], ['perdido', LOST]
  ].freeze

  # chave de cor de uma coluna pelo nome (a mesma régua da tela)
  def self.key_for(stage_name)
    return 'sem' if stage_name.blank?

    name = I18n.transliterate(stage_name.to_s).downcase.squish
    KEYS.find { |_k, re| name.match?(re) }&.first || 'outro'
  end

  # rows = [[conversation_id, created_at, quem], …] (só gente)
  def initialize(account, rows)
    @account = account
    @rows = rows
  end

  # tudo de uma pessoa: { mix:, firsts:, moves:, by_day: { Date => [conversa, …] } }
  def for(uid, tz) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Naming/MethodParameterName
    mine = @rows.select { |r| r[2] == uid }
    by_conv = mine.group_by(&:first)
    convs = by_conv.filter_map { |cid, list| conversation_json(cid, list.map { |r| r[1] }.sort) }
    {
      mix: tally(convs.pluck(:stage)),
      firsts: tally(first_of_each_day(mine, tz).filter_map { |cid| convs.find { |c| c[:cid] == cid }&.dig(:stage) }),
      moves: convs.select { |c| c[:moved] }.sort_by { |c| c[:moved][:at] }.last(40).reverse.map { |c| public_json(c) },
      moved_count: convs.count { |c| c[:moved] }, conversations: convs.size,
      by_day: by_day(mine, convs, tz)
    }
  end

  private

  def conversation_json(cid, times)
    contact_id, display_id, name = conversations[cid]
    return nil unless contact_id

    card_id, current = cards[contact_id]
    stage_id = card_id ? stage_at(card_id, current, times.first) : nil
    { cid: cid, display_id: display_id, name: name, msgs: times.size, first_at: times.first,
      stage: stage_info(stage_id), moved: card_id ? moved_after(card_id, times) : nil }
  end

  def public_json(conv)
    { display_id: conv[:display_id], name: conv[:name], msgs: conv[:msgs], stage: conv[:stage],
      moved: conv[:moved]&.merge(at: conv[:moved][:at].iso8601) }
  end

  def by_day(mine, convs, tz) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Naming/MethodParameterName
    index = convs.index_by { |c| c[:cid] }
    mine.group_by { |r| r[1].in_time_zone(tz).to_date }.transform_values do |list|
      list.group_by(&:first).filter_map do |cid, rows|
        conv = index[cid]
        next unless conv

        first = rows.map { |r| r[1] }.min
        { display_id: conv[:display_id], name: conv[:name], msgs: rows.size, first: first.in_time_zone(tz).strftime('%H:%M'),
          stage: conv[:stage], moved: conv[:moved].present? }
      end.sort_by { |c| c[:first] }.first(25) # rubocop:disable Style/MultilineBlockChain
    end
  end

  def first_of_each_day(mine, tz) # rubocop:disable Naming/MethodParameterName
    mine.group_by { |r| r[1].in_time_zone(tz).to_date }.values.map { |list| list.min_by { |r| r[1] }.first }
  end

  def tally(stages)
    stages.compact.group_by { |s| s[:key] }.map do |key, list|
      { key: key, label: list.first[:label], n: list.size }
    end.sort_by { |row| [-row[:n], row[:label]] } # rubocop:disable Style/MultilineBlockChain
  end

  # ── dados ────────────────────────────────────────────────────────────────
  def conversations
    @conversations ||= Conversation.where(id: @rows.map(&:first).uniq).includes(:contact)
                                   .to_h { |c| [c.id, [c.contact_id, c.display_id, c.contact&.name]] }
  end

  def pipeline
    @pipeline ||= Crm::Pipeline.where(account: @account).order(:position, :id).first
  end

  def stages
    @stages ||= (pipeline ? pipeline.stages.to_a : []).index_by(&:id)
  end

  def cards
    @cards ||= Crm::Contact.where(pipeline_id: pipeline&.id, contact_id: conversations.values.map(&:first))
                           .pluck(:contact_id, :id, :stage_id).to_h { |c, id, s| [c, [id, s]] }
  end

  def logs
    @logs ||= Crm::StageLog.where(crm_contact_id: cards.values.map(&:first)).order(:entered_at)
                           .pluck(:crm_contact_id, :stage_id, :entered_at).group_by(&:first)
  end

  def stage_at(card_id, current, time)
    (logs[card_id] || []).reverse.find { |_c, _s, at| at <= time }&.dig(1) || current
  end

  # entrou numa coluna mais adiante (sem contar "Sem Interesse") até 48 h depois de uma resposta
  def moved_after(card_id, times) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    list = logs[card_id] || []
    times.each do |t|
      before = stage_at(card_id, nil, t)
      from_pos = position(before)
      next if from_pos.nil?

      hit = list.find do |_c, s, at|
        at > t && at <= t + MOVE_WINDOW && !lost?(s) && position(s).to_i > from_pos
      end
      return { from: stage_info(before)[:label], to: stage_info(hit[1])[:label], at: hit[2] } if hit
    end
    nil
  end

  def position(stage_id)
    stages[stage_id]&.position
  end

  def lost?(stage_id)
    norm(stages[stage_id]&.name).match?(LOST)
  end

  def stage_info(stage_id)
    stage = stages[stage_id]
    return { key: 'sem', label: 'Sem cartão' } unless stage

    { key: self.class.key_for(stage.name), label: stage.name }
  end

  def norm(text)
    I18n.transliterate(text.to_s).downcase.squish
  end
end
