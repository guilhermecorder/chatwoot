# ⏱️ EQUIPE NO HORÁRIO COMERCIAL (27/11/2026 · LIFE, pedido do Guilherme): "quais são os maiores intervalos do dia
# em horário comercial dos envolvidos… o Fernando, que está sendo responsável… ficar exposto para mim e para ele".
#
# Só conta mensagem ESCRITA POR GENTE: saída, não privada, enviada por um usuário e SEM carimbo de automação
# (todo envio automático grava uma chave `cevico_*` em additional_attributes: IA, robôs de follow-up, orçamento
# automático, conteúdo guardado, retomada…). Exceção: `cevico_wa_billing` é a cobrança da Meta, gravada em TODA
# mensagem que sai pelo WhatsApp oficial, inclusive as escritas pela equipe (achado no ar em 27/11: 358 mensagens).
# Os robôs mandam em nome do Fernando; sem esse filtro ele pareceria ativo às 8h em ponto todos os dias.
# Também conta o que sai do CELULAR (app do WhatsApp Business no mesmo número): chega como "eco" (external_echo),
# sem usuário; aparece à parte, como "Celular (app do WhatsApp)", porque o sistema não sabe quem digitou.
#
# Horário comercial da LIFE: seg–sex 8h–18h, sáb 8h–12h, fora feriados nacionais (Crm::BusinessHours).
# Por pessoa:
#   · mensagens dela no período (e quantas no horário comercial)
#   · resposta ao cliente: quando o cliente escreve e quem responde é ela, quanto tempo de horário comercial passou
#     (e a mesma conta separada pela hora em que o cliente escreveu)
#   · maiores intervalos: em cada dia útil, o maior buraco sem nenhuma mensagem dela (contando da abertura até a
#     1ª mensagem e da última até o fechamento); devolve os maiores do período e a média do maior de cada dia
#   · presença por hora: em quantos dias úteis ela mandou ao menos 1 mensagem em cada faixa de hora
#   · 27/11 (2º pedido): "entender os horários que ele trabalhou, não só os que não trabalhou… os horários que ele
#     mais responde e menos responde… visão do mês, do dia e da semana":
#       heat  = mensagens por dia da semana × hora (o mapa da semana)
#       dias  = cada dia do período: mensagens por hora, 1ª e última, blocos de trabalho e maior intervalo
#       bloco = mensagens com até 30 min entre uma e outra; o tempo do bloco vai da 1ª à última + 5 min
# E da equipe toda: pedidos de ATENDIMENTO HUMANO da IA → primeira mensagem de gente na conversa, com o MOTIVO que
# a IA deixou na tarefa (nota "abriu/complementou a tarefa #N para X: motivo"), a última fala do cliente antes do
# pedido, a coluna do cartão e um assunto (preço, pagamento, técnico…) para ver por que ela pede gente.
class Crm::TeamResponse # rubocop:disable Metrics/ClassLength
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HUMAN_REQUEST = '%pediu ATENDIMENTO HUMANO%'.freeze
  AUTOMATED_SQL = "EXISTS (SELECT 1 FROM jsonb_object_keys(COALESCE(messages.additional_attributes, '{}'::jsonb)) k " \
                  "WHERE k LIKE 'cevico%' AND k NOT IN (#{%w[cevico_wa_billing].map { |k| "'#{k}'" }.join(', ')}))".freeze
  # content_attributes é `store … coder: JSON`: no banco pode estar como texto JSON (string) ou como objeto
  ECHO_SQL = 'COALESCE((CASE json_typeof(messages.content_attributes) ' \
             "WHEN 'string' THEN (messages.content_attributes #>> '{}')::jsonb " \
             "WHEN 'object' THEN messages.content_attributes::jsonb END) ->> 'external_echo', '') = 'true'".freeze
  HUMAN_SQL = "((messages.sender_type = 'User' AND NOT #{AUTOMATED_SQL}) OR #{ECHO_SQL})".freeze
  PHONE = 'celular'.freeze
  PHONE_NAME = 'Celular (app do WhatsApp)'.freeze
  TOP_GAPS = 8
  SESSION_GAP = 30.minutes
  SESSION_PAD = 5 # minutos que uma mensagem sozinha "vale"
  WAITING_LIST = 150
  TASK_NOTE = /#\d+ para [^:\n]+: (.+?)\.?\s*\[Ver tarefas\]/m
  # assunto do pedido (motivo da IA primeiro; sem assunto, a última fala do cliente). A ordem importa: o 1º que
  # casar vence ("quer fechar no cartão" é fechamento, não pagamento).
  TOPICS = [
    ['fechar', 'Quer fechar ou pediu o contrato',
     /fechar|fechamento|contrato|assinar|quero (comprar|instalar|fazer)|vamos (fazer|fechar)|bora/],
    ['pagamento', 'Pagamento, financiamento ou crédito',
     /financ|parcel|cartao|boleto|\bpix\b|credito|\bcpf\b|negativ|entrada|a vista|juros|simulac|pagamento/],
    ['preco', 'Preço, desconto ou contraproposta',
     /desconto|negoci|mais barato|contraproposta|contra proposta|preco|caro|concorr|outro orcamento|melhor valor|diretoria/],
    ['tecnico', 'Dúvida técnica (bateria, híbrido, telhado, inversor)',
     /bateria|hibrid|off.?grid|isolad|inversor|telhad|estrutura|kwp|potencia|engenheir|marca|geracao|sombra|laje|metalic|tecnic/],
    ['visita', 'Visita técnica, vistoria ou endereço', /visita|vistoria|endereco|pessoalmente|ir ate/],
    ['ligacao', 'Pediu ligação ou falar com uma pessoa',
     /ligar|ligac|ligue|telefon|falar com|atendente|humano|pessoa|robo|golpe|fernando|anderson/],
    ['cliente', 'Já é cliente: manutenção, garantia, CPFL',
     /ja (sou|tenho|instalei|comprei)|manutenc|limpeza|garantia|defeito|nao (esta|ta) gerando|homologa|cpfl|medidor/],
    ['fora', 'Fora do perfil (fornecedor, outra cidade, emprego)',
     /fornecedor|parceria|revend|cidade|fora da area|regiao|curriculo|emprego|vaga/]
  ].freeze
  OTHER_TOPIC = %w[outro Outros].freeze

  def initialize(account, since:, until_at:)
    @account = account
    @since = since
    @until = [until_at, Time.current].min
  end

  def call
    people = user_ids.filter_map { |uid| person_json(uid) }.sort_by { |p| -p[:messages] }
    { hours: 'seg a sex 8h–18h · sáb 8h–12h', people: people, human_requests: human_requests_json }
  end

  # ── janela comercial de um dia: [abre, fecha] ou nil ──────────────────────
  def self.window(date)
    return nil if Crm::BusinessHours.national_holidays(date.year).include?(date)

    hours = case date.wday
            when 1..5 then [8, 18]
            when 6 then [8, 12]
            end
    hours && [TZ.local(date.year, date.month, date.day, hours[0]), TZ.local(date.year, date.month, date.day, hours[1])]
  end

  # minutos de horário comercial entre dois instantes
  def self.business_minutes(from, to)
    return 0 if to <= from

    (from.in_time_zone(TZ).to_date..to.in_time_zone(TZ).to_date).sum do |day|
      open, close = window(day)
      next 0 unless open

      lo = [from, open].max
      hi = [to, close].min
      hi > lo ? ((hi - lo) / 60.0) : 0
    end.round
  end

  def self.topic_for(*texts)
    texts.each do |text|
      plain = I18n.transliterate(text.to_s).downcase
      next if plain.blank?

      found = TOPICS.find { |_k, _l, re| plain.match?(re) }
      return found.first(2) if found
    end
    OTHER_TOPIC
  end

  private

  def messages
    Message.where(account_id: @account.id, created_at: @since..@until)
  end

  # [conversation_id, created_at, quem] das mensagens escritas por gente (quem = id do usuário ou PHONE)
  def human_rows
    @human_rows ||= messages.where(message_type: :outgoing, private: false).where(HUMAN_SQL).order(:created_at)
                            .pluck(:conversation_id, :created_at,
                                   Arel.sql("CASE WHEN messages.sender_type = 'User' AND NOT #{ECHO_SQL} " \
                                            'THEN messages.sender_id END'))
                            .map { |cid, at, uid| [cid, at, uid || PHONE] }
  end

  def user_ids
    ids = human_rows.map(&:last).uniq
    ids |= [owner_id] if owner_id
    ids
  end

  # o responsável pelo atendimento: quem recebe as tarefas da IA (o mesmo que o Meu Painel usa)
  def owner_id
    @owner_id ||= Crm::Contact.where(pipeline_id: Crm::Pipeline.where(account: @account).select(:id))
                              .where.not(assignee_id: nil).group(:assignee_id).count.max_by(&:last)&.first
  end

  def person_json(uid)
    name = uid == PHONE ? PHONE_NAME : User.find_by(id: uid)&.name
    return nil unless name

    times = human_rows.select { |r| r[2] == uid }.pluck(1)
    in_hours = times.select { |t| business?(t) }
    gaps = day_gaps(in_hours)
    {
      id: uid, name: name, messages: times.size, in_hours: in_hours.size, owner: uid == owner_id, phone: uid == PHONE,
      reply: reply_stats(uid), gaps: gaps[:top], avg_max_gap: gaps[:avg_max], days: gaps[:days], days_absent: gaps[:absent],
      presence: presence(in_hours), heat: heat(times), days_detail: days_detail(times, gaps[:max_by_day])
    }
  end

  def business?(time)
    open, close = self.class.window(time.in_time_zone(TZ).to_date)
    open && time >= open && time < close
  end

  # dias úteis do período, até agora
  def business_days
    @business_days ||= (@since.in_time_zone(TZ).to_date..@until.in_time_zone(TZ).to_date).select { |d| self.class.window(d) }
  end

  def day_gaps(times) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    by_day = times.group_by { |t| t.in_time_zone(TZ).to_date }
    all = []
    maxes = []
    max_by_day = {}
    absent = 0
    business_days.each do |day|
      open, close = self.class.window(day)
      close = [close, @until].min
      next if close <= open

      # dia útil inteiro sem nenhuma mensagem: conta à parte (folga, visita, outro trabalho), não vira "intervalo"
      if by_day.fetch(day, []).empty?
        absent += 1 if close == self.class.window(day).last
        next
      end

      points = [open, *by_day.fetch(day, []).sort, close]
      day_gaps = points.each_cons(2).map do |a, b|
        { day: day.iso8601, from: a.in_time_zone(TZ).strftime('%H:%M'),
          to: b.in_time_zone(TZ).strftime('%H:%M'), minutes: ((b - a) / 60).round }
      end
      biggest = day_gaps.max_by { |g| g[:minutes] }
      if biggest
        maxes << biggest[:minutes]
        max_by_day[day] = biggest
      end
      all.concat(day_gaps)
    end
    { top: all.sort_by { |g| -g[:minutes] }.first(TOP_GAPS), max_by_day: max_by_day,
      avg_max: maxes.any? ? (maxes.sum / maxes.size.to_f).round : nil, days: business_days.size, absent: absent }
  end

  # em quantos dias úteis houve mensagem em cada hora (8h…17h)
  def presence(times)
    days = business_days.size
    hits = times.group_by { |t| t.in_time_zone(TZ).hour }.transform_values { |list| list.map { |t| t.in_time_zone(TZ).to_date }.uniq.size }
    (8..17).map { |h| { hour: h, days: hits[h].to_i, of: days } }
  end

  # mapa da semana: mensagens por dia da semana (0 = domingo) × hora (0…23), a qualquer hora
  def heat(times)
    grid = Array.new(7) { Array.new(24, 0) }
    times.each do |t|
      local = t.in_time_zone(TZ)
      grid[local.wday][local.hour] += 1
    end
    grid
  end

  # cada dia do período (corridos), do mais antigo ao mais novo
  def days_detail(times, max_by_day) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    by_day = times.map { |t| t.in_time_zone(TZ) }.group_by(&:to_date)
    (@since.in_time_zone(TZ).to_date..@until.in_time_zone(TZ).to_date).map do |day|
      list = by_day.fetch(day, []).sort
      blocks = sessions(list)
      {
        day: day.iso8601, business: !self.class.window(day).nil?, today: day == Time.current.in_time_zone(TZ).to_date,
        msgs: list.size,
        in_hours: list.count { |t| business?(t) }, first: list.first&.strftime('%H:%M'), last: list.last&.strftime('%H:%M'),
        by_hour: (0..23).map { |h| list.count { |t| t.hour == h } }, sessions: blocks,
        active_min: blocks.sum { |b| b[:minutes] }, max_gap: max_by_day[day]
      }
    end
  end

  # blocos de trabalho: mensagens com até SESSION_GAP entre uma e outra
  def sessions(list)
    list.slice_when { |a, b| b - a > SESSION_GAP }.map do |block|
      { from: block.first.strftime('%H:%M'), to: block.last.strftime('%H:%M'), n: block.size,
        minutes: ((block.last - block.first) / 60).round + SESSION_PAD }
    end
  end

  # cliente escreveu → a próxima mensagem nossa (de gente ou de robô) foi desta pessoa: quanto tempo comercial passou
  def reply_stats(uid) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    waits = conversation_streams.flat_map do |stream|
      stream.each_cons(2).filter_map do |a, b|
        next unless a[:who] == :client && b[:who] == uid

        [a[:at].in_time_zone(TZ).hour, self.class.business_minutes(a[:at], b[:at])]
      end
    end
    minutes = waits.map(&:last)
    by_hour = waits.group_by(&:first).sort.map { |hour, list| { hour: hour, n: list.size, mediana_min: median(list.map(&:last)) } }
    { n: minutes.size, mediana_min: median(minutes), ate_30_min: minutes.count { |w| w <= 30 },
      acima_4h: minutes.count { |w| w > 240 }, by_hour: by_hour }
  end

  # por conversa, a sequência de "turnos": a 1ª mensagem do cliente depois de uma nossa e a 1ª nossa depois dele
  def conversation_streams # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @conversation_streams ||= begin
      rows = messages.where(message_type: %i[incoming outgoing], private: false)
                     .order(:conversation_id, :created_at)
                     .pluck(:conversation_id, :created_at, :message_type, :sender_type, :sender_id,
                            Arel.sql("CASE WHEN #{AUTOMATED_SQL} THEN 1 ELSE 0 END"),
                            Arel.sql("CASE WHEN #{ECHO_SQL} THEN 1 ELSE 0 END"))
      rows.group_by(&:first).values.map do |list|
        turns = list.map do |_c, at, type, s_type, s_id, auto, echo| # rubocop:disable Metrics/ParameterLists
          who = if type.to_s == 'incoming' then :client
                elsif echo.to_i == 1 then PHONE
                elsif s_type == 'User' && auto.to_i.zero? then s_id
                else
                  :auto
                end
          { at: at, who: who }
        end
        turns.chunk_while { |a, b| a[:who] == :client && b[:who] == :client }.map(&:first)
      end
    end
  end

  # IA pediu gente → primeira mensagem de gente na conversa (horário comercial), com o porquê
  def human_requests_json # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    requests = messages.where(message_type: :activity).where('content ILIKE ?', HUMAN_REQUEST)
                       .order(:created_at).pluck(:conversation_id, :created_at)
    cids = requests.map(&:first).uniq
    first_human = Message.where(account_id: @account.id, conversation_id: cids, message_type: :outgoing, private: false)
                         .where(HUMAN_SQL).where(created_at: @since..)
                         .order(:created_at).pluck(:conversation_id, :created_at).group_by(&:first)
    why = RequestReasons.new(@account, cids, @since, @until)
    waits = []
    open = []
    topics = Hash.new { |h, k| h[k] = { total: 0, open: 0 } }
    requests.each do |cid, at|
      reason = why.at(cid, at)
      topics[reason[:topic]][:total] += 1
      answer = first_human[cid]&.find { |_c, t| t > at }
      if answer then waits << self.class.business_minutes(at, answer[1])
      else
        topics[reason[:topic]][:open] += 1
        open << reason.merge(conversation_id: cid, since: at, minutes: self.class.business_minutes(at, Time.current))
      end
    end
    open = open.group_by { |o| o[:conversation_id] }.map { |_cid, list| list.first.merge(pedidos: list.size) }
    open.each { |o| o.merge!(why.card(o[:conversation_id])) }
    labels = (TOPICS.map { |k, l, _re| [k, l] } + [OTHER_TOPIC]).to_h
    { total: requests.size, answered: waits.size, mediana_min: median(waits), ate_30_min: waits.count { |w| w <= 30 },
      acima_4h: waits.count { |w| w > 240 }, sem_resposta: open.size,
      motivos: topics.map { |key, n| { key: key, label: labels[key], total: n[:total], sem_resposta: n[:open] } }
                     .sort_by { |t| [-t[:total], t[:label]] },
      sem_resposta_lista: open.sort_by { |o| -o[:minutes] }.first(WAITING_LIST) }
  end

  def median(values)
    list = values.compact.sort
    return nil if list.empty?

    mid = list.size / 2
    (list.size.odd? ? list[mid] : (list[mid - 1] + list[mid]) / 2.0).round
  end
end
