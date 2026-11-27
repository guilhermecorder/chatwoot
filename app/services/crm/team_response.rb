# ⏱️ EQUIPE NO HORÁRIO COMERCIAL (27/11/2026 · LIFE, pedido do Guilherme): "quais são os maiores intervalos do dia
# em horário comercial dos envolvidos… o Fernando, que está sendo responsável… ficar exposto para mim e para ele".
#
# Só conta mensagem ESCRITA POR GENTE: saída, não privada, enviada por um usuário e SEM carimbo de automação
# (todo envio automático grava uma chave `cevico_*` em additional_attributes: IA, robôs de follow-up, orçamento
# automático, conteúdo guardado, retomada…). Exceção: `cevico_wa_billing` é a cobrança da Meta, gravada em TODA
# mensagem que sai pelo WhatsApp oficial, inclusive as escritas pela equipe (achado no ar em 27/11: 358 mensagens). Os robôs mandam em nome do Fernando; sem esse filtro ele pareceria
# ativo às 8h em ponto todos os dias.
#
# Horário comercial da LIFE: seg–sex 8h–18h, sáb 8h–12h, fora feriados nacionais (Crm::BusinessHours).
# Por pessoa:
#   · mensagens dela no período (e quantas no horário comercial)
#   · resposta ao cliente: quando o cliente escreve e quem responde é ela, quanto tempo de horário comercial passou
#   · maiores intervalos: em cada dia útil, o maior buraco sem nenhuma mensagem dela (contando da abertura até a
#     1ª mensagem e da última até o fechamento); devolve os maiores do período e a média do maior de cada dia
#   · presença por hora: em quantos dias úteis ela mandou ao menos 1 mensagem em cada faixa de hora
# E da equipe toda: pedidos de ATENDIMENTO HUMANO da IA → primeira mensagem de gente na conversa.
class Crm::TeamResponse
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  HUMAN_REQUEST = '%pediu ATENDIMENTO HUMANO%'.freeze
  AUTOMATED_SQL = "EXISTS (SELECT 1 FROM jsonb_object_keys(COALESCE(messages.additional_attributes, '{}'::jsonb)) k " \
                  "WHERE k LIKE 'cevico%' AND k NOT IN (#{%w[cevico_wa_billing].map { |k| "'#{k}'" }.join(', ')}))".freeze
  TOP_GAPS = 8

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

  private

  def messages
    Message.where(account_id: @account.id, created_at: @since..@until)
  end

  # [conversation_id, created_at, sender_id] das mensagens escritas por gente
  def human_rows
    @human_rows ||= messages.where(message_type: :outgoing, private: false, sender_type: 'User')
                            .where.not(AUTOMATED_SQL).order(:created_at)
                            .pluck(:conversation_id, :created_at, :sender_id)
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
    user = User.find_by(id: uid)
    return nil unless user

    times = human_rows.select { |r| r[2] == uid }.pluck(1)
    in_hours = times.select { |t| business?(t) }
    gaps = day_gaps(in_hours)
    {
      id: uid, name: user.name, messages: times.size, in_hours: in_hours.size, owner: uid == owner_id,
      reply: reply_stats(uid), gaps: gaps[:top], avg_max_gap: gaps[:avg_max], days: gaps[:days], days_absent: gaps[:absent],
      presence: presence(in_hours)
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
      maxes << biggest[:minutes] if biggest
      all.concat(day_gaps)
    end
    { top: all.sort_by { |g| -g[:minutes] }.first(TOP_GAPS),
      avg_max: maxes.any? ? (maxes.sum / maxes.size.to_f).round : nil, days: business_days.size, absent: absent }
  end

  # em quantos dias úteis houve mensagem em cada hora (8h…17h)
  def presence(times)
    days = business_days.size
    hits = times.group_by { |t| t.in_time_zone(TZ).hour }.transform_values { |list| list.map { |t| t.in_time_zone(TZ).to_date }.uniq.size }
    (8..17).map { |h| { hour: h, days: hits[h].to_i, of: days } }
  end

  # cliente escreveu → a próxima mensagem nossa (de gente ou de robô) foi desta pessoa: quanto tempo comercial passou
  def reply_stats(uid)
    waits = conversation_streams.flat_map do |stream|
      stream.each_cons(2).filter_map do |a, b|
        next unless a[:who] == :client && b[:who] == uid

        self.class.business_minutes(a[:at], b[:at])
      end
    end
    { n: waits.size, mediana_min: median(waits), ate_30_min: waits.count { |w| w <= 30 },
      acima_4h: waits.count { |w| w > 240 } }
  end

  # por conversa, a sequência de "turnos": a 1ª mensagem do cliente depois de uma nossa e a 1ª nossa depois dele
  def conversation_streams # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    @conversation_streams ||= begin
      rows = messages.where(message_type: %i[incoming outgoing], private: false)
                     .order(:conversation_id, :created_at)
                     .pluck(:conversation_id, :created_at, :message_type, :sender_type, :sender_id,
                            Arel.sql("CASE WHEN #{AUTOMATED_SQL} THEN 1 ELSE 0 END"))
      rows.group_by(&:first).values.map do |list|
        turns = list.map do |_c, at, type, s_type, s_id, auto| # rubocop:disable Metrics/ParameterLists
          who = if type.to_s == 'incoming' then :client
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

  # IA pediu gente → primeira mensagem de gente na conversa (horário comercial)
  def human_requests_json # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    requests = messages.where(message_type: :activity).where('content ILIKE ?', HUMAN_REQUEST)
                       .order(:created_at).pluck(:conversation_id, :created_at)
    first_human = Message.where(account_id: @account.id, conversation_id: requests.map(&:first).uniq,
                                message_type: :outgoing, private: false, sender_type: 'User')
                         .where.not(AUTOMATED_SQL).where(created_at: @since..)
                         .order(:created_at).pluck(:conversation_id, :created_at).group_by(&:first)
    waits = []
    open = []
    requests.each do |cid, at|
      answer = first_human[cid]&.find { |_c, t| t > at }
      if answer then waits << self.class.business_minutes(at, answer[1])
      else
        open << { conversation_id: cid, since: at, minutes: self.class.business_minutes(at, Time.current) }
      end
    end
    open = open.group_by { |o| o[:conversation_id] }.map { |_cid, list| list.first }
    named = Conversation.where(id: open.pluck(:conversation_id)).includes(:contact).index_by(&:id)
    open.each do |o|
      conv = named[o[:conversation_id]]
      o.merge!(display_id: conv&.display_id, name: conv&.contact&.name)
    end
    { total: requests.size, answered: waits.size, mediana_min: median(waits), ate_30_min: waits.count { |w| w <= 30 },
      acima_4h: waits.count { |w| w > 240 }, sem_resposta: open.size,
      sem_resposta_lista: open.sort_by { |o| -o[:minutes] }.first(10) }
  end

  def median(values)
    list = values.compact.sort
    return nil if list.empty?

    mid = list.size / 2
    (list.size.odd? ? list[mid] : (list[mid - 1] + list[mid]) / 2.0).round
  end
end
