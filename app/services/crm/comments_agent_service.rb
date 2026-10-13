# RESPONDEDOR DE COMENTÁRIOS (Instagram + Facebook): varre os comentários
# recentes dos posts/anúncios das contas conectadas e responde em PÚBLICO
# com tom CEVICO — curto, acolhedor, convidando pro direct/WhatsApp. Nunca
# fala preço/dado clínico em comentário aberto; na dúvida, não responde e
# marca para o humano. Corrige o gargalo de atendimento dos comentários.
#
# Config (Automações → Agentes de IA → Respondedor de Comentários):
# page_access_token (token da Página com permissões de comentários),
# fb_page_id (Página do Facebook) e/ou ig_user_id (conta IG Business).
# Sem token o agente fica pronto porém adormecido (mesmo caso do canal
# Instagram — depende do app da Meta).
class Crm::CommentsAgentService # rubocop:disable Metrics/ClassLength
  include Crm::AiAgentConfig

  AGENT_KEY = 'comments'.freeze
  GRAPH = 'https://graph.facebook.com/v19.0'.freeze
  MEDIA_LIMIT = 10       # posts recentes olhados por rodada
  COMMENTS_LIMIT = 25    # comentários por post
  REPLIES_PER_RUN = 10   # teto de respostas por rodada (segurança)
  # memória de "já respondi": um comentário que AINDA aparece nos posts olhados
  # nunca é esquecido (#117: antes, depois de 30 dias a IA respondia de novo em
  # público o mesmo comentário de um post que seguia entre os recentes); o
  # prazo só poda quem já sumiu da lista, para a memória não crescer sem fim
  HANDLED_TTL = 30.days
  RUN_OVERLAP = 1.hour         # folga sobre a última rodada: não perde comentário que chegou durante ela
  FIRST_RUN_WINDOW = 7.days    # primeira rodada: só comentários recentes (ligar o agente não responde coisa de meses)
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  BUSINESS_HOURS = (7...22) # comentário público só em horário de gente (SP)

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      responder: { type: 'boolean', description: 'true se vale responder este comentário em público' },
      resposta: { type: 'string',
                  description: 'Resposta curta e calorosa (1-2 frases), tom CEVICO, sem preço/dado clínico; ' \
                               'convide pro direct ou WhatsApp quando fizer sentido' },
      chamar_humano: { type: 'boolean', description: 'true se o comentário precisa de um humano (reclamação séria, urgência médica, caso delicado)' }
    },
    required: %w[responder resposta chamar_humano],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você responde os COMENTÁRIOS PÚBLICOS do Instagram e Facebook da CEVICO
    (clínica de oftalmologia). Regras do comentário público:
    - Curto (1-2 frases), caloroso e humano — nada de texto de robô.
    - NUNCA fale valores, horários específicos ou dados clínicos em público:
      convide para o direct ("te chamamos no privado 💙") ou WhatsApp.
    - Elogio/emoji → agradeça com carinho. Dúvida sobre procedimento →
      resposta breve + convite pro direct. Marcação de amigo → acolha os dois.
    - Reclamação séria, urgência (dor, perda de visão) ou caso delicado →
      chamar_humano=true e NÃO responda em público.
    - Spam/ofensa → responder=false.
    - Você é a assistente virtual da CEVICO: se perguntarem se é robô,
      diga com honestidade que é a assistente virtual e que a equipe
      humana continua no direct. Nunca finja ser uma pessoa específica.
  PROMPT

  # 🏢 rodada 334: clínica = SYSTEM_PROMPT de sempre; outro ramo = genérico da empresa
  def default_system_prompt
    Crm::CompanyPrompts.pick(@account, SYSTEM_PROMPT, :comments)
  end

  def initialize(account)
    @account = account
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return { error: 'agente desligado' } if agent_paused?
    return { error: 'sem token da Página (conecte em Automações → Respondedor de Comentários)' } if token.blank?
    return { error: 'IA não configurada' } if api_key.blank?
    return { error: 'fora do horário (07h–22h SP)' } unless BUSINESS_HOURS.cover?(TZ.now.hour)

    pending = pending_comments
    handled = prune_handled(pending.pluck(:id))
    prior_events = Array(state['events'])
    events = []
    replied = 0

    pending.each do |comment|
      break if replied >= REPLIES_PER_RUN
      next if skip?(comment, handled)

      verdict = ask_ai(comment)
      next if verdict.blank? # IA falhou → NÃO marca; tenta de novo na próxima rodada

      # decidiu → marca ANTES de responder e PERSISTE já: um crash depois do
      # POST não faz o comentário ser respondido de novo em público na rodada seguinte
      handled[comment[:id]] = Time.current.iso8601
      events << handle_verdict(comment, verdict)
      replied += 1 if events.last&.dig('status') == 'respondido'
      save_state(handled, (events + prior_events).first(30))
    end

    save_state(handled, (events + prior_events).first(30))
    { success: true, replied: replied, seen: events.size }
  end

  private

  def config
    agent_config
  end

  def token
    config['page_access_token']
  end

  # comentários recentes de IG + FB que ainda não foram tratados
  def pending_comments
    ig_comments + fb_comments
  end

  def ig_comments # rubocop:disable Metrics/AbcSize
    ig_id = config['ig_user_id'].presence
    return [] if ig_id.blank?

    media = graph_get("#{ig_id}/media", fields: 'id,caption', limit: MEDIA_LIMIT)
    Array(media['data']).flat_map do |m|
      comments = graph_get("#{m['id']}/comments", fields: 'id,text,username,timestamp', limit: COMMENTS_LIMIT)
      Array(comments['data']).map do |c|
        { id: c['id'], platform: 'instagram', author: c['username'].to_s, at: parse_time(c['timestamp']),
          text: c['text'].to_s, post: m['caption'].to_s.truncate(120) }
      end
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::CommentsAgent] IG: #{e.message}"
    @fetch_failed = true
    []
  end

  def fb_comments # rubocop:disable Metrics/AbcSize
    page_id = config['fb_page_id'].presence
    return [] if page_id.blank?

    posts = graph_get("#{page_id}/feed", fields: 'id,message', limit: MEDIA_LIMIT)
    Array(posts['data']).flat_map do |p|
      comments = graph_get("#{p['id']}/comments", fields: 'id,message,from,created_time', filter: 'stream', limit: COMMENTS_LIMIT)
      Array(comments['data']).reject { |c| c.dig('from', 'id').to_s == page_id.to_s }.map do |c|
        { id: c['id'], platform: 'facebook', author: c.dig('from', 'name').to_s, at: parse_time(c['created_time']),
          text: c['message'].to_s, post: p['message'].to_s.truncate(120) }
      end
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::CommentsAgent] FB: #{e.message}"
    @fetch_failed = true
    []
  end

  # ── (#117) o que NÃO vai para a IA ───────────────────────────────────────
  # pula: já tratado; antigo (de antes da última rodada); ou já respondido pela
  # Página (alguém da equipe respondeu, ou a memória de uma rodada se perdeu) —
  # aí lembra, para não consultar de novo
  def skip?(comment, handled)
    return true if handled.key?(comment[:id])
    return true if stale?(comment)
    return false unless already_answered?(comment)

    handled[comment[:id]] = Time.current.iso8601
    true
  end

  # comentário de antes da última rodada (com folga) não é "da vez". O corte é
  # fixado na 1ª leitura da rodada (o save_state no meio muda o last_run_at).
  def stale?(comment)
    @cutoff ||= run_cutoff
    comment[:at].present? && comment[:at] < @cutoff
  end

  # nunca olha mais de FIRST_RUN_WINDOW para trás, mesmo com last_run_at
  # antigo (agente semanas desligado/sem token: ao religar, não responde em
  # público os comentários velhos de 10 em 10 a cada rodada)
  def run_cutoff
    last = parse_time(state['last_run_at'])
    floor = FIRST_RUN_WINDOW.ago
    last ? [last - RUN_OVERLAP, floor].max : floor
  end

  # as respostas do comentário têm alguma da própria Página/conta?
  def already_answered?(comment)
    instagram = comment[:platform] == 'instagram'
    own_id = instagram ? config['ig_user_id'] : config['fb_page_id']
    replies = graph_get("#{comment[:id]}/#{instagram ? 'replies' : 'comments'}", fields: 'id,from', limit: 50)
    Array(replies['data']).any? { |r| r.dig('from', 'id').to_s == own_id.to_s }
  rescue StandardError => e
    Rails.logger.warn "[Crm::CommentsAgent] respostas de #{comment[:id]}: #{e.message}"
    false
  end

  def parse_time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end

  def graph_get(path, params)
    HTTParty.get("#{GRAPH}/#{path}", query: params.merge(access_token: token), timeout: 20).parsed_response || {}
  end

  def ask_ai(comment)
    message = client.messages.create(
      model: model,
      max_tokens: 512,
      system_: cached_system,
      output_config: output_config_for({ type: 'json_schema', schema: company_schema(OUTPUT_SCHEMA) }),
      messages: [{ role: 'user', content: "Post: #{comment[:post]}\nComentário de @#{comment[:author]} (#{comment[:platform]}): #{comment[:text]}" }]
    )
    record_usage(message)
    parse_structured_response(message)
  rescue StandardError => e
    Rails.logger.error "[Crm::CommentsAgent] IA: #{e.class}: #{e.message}"
    nil
  end

  def handle_verdict(comment, verdict)
    status =
      if verdict['chamar_humano']
        'humano'
      elsif verdict['responder'] && verdict['resposta'].present?
        post_reply(comment, verdict['resposta']) ? 'respondido' : 'erro'
      else
        'ignorado'
      end
    { 'at' => Time.current.iso8601, 'platform' => comment[:platform], 'author' => comment[:author],
      'comment' => comment[:text].truncate(200), 'reply' => verdict['resposta'].to_s.truncate(300),
      'status' => status }
  end

  def post_reply(comment, text)
    path = comment[:platform] == 'instagram' ? "#{comment[:id]}/replies" : "#{comment[:id]}/comments"
    response = HTTParty.post("#{GRAPH}/#{path}", body: { message: text, access_token: token }, timeout: 20)
    response.success?
  rescue StandardError => e
    Rails.logger.error "[Crm::CommentsAgent] reply: #{e.message}"
    false
  end

  def state
    (ai_config['comments_state'] || {})
  end

  # (#117) comentário que ainda está na lista fica na memória sempre; o que
  # sumiu é podado depois do prazo. Se a busca falhou, não poda nada (a lista
  # vazia não prova que o comentário sumiu).
  def prune_handled(visible_ids)
    handled = Hash(state['handled'])
    return handled if @fetch_failed

    kept = handled.select do |id, ts|
      next true if visible_ids.include?(id)

      t = parse_time(ts)
      t.present? && t > HANDLED_TTL.ago
    end
    @pruned_ids = handled.keys - kept.keys # o save_state não traz estes de volta
    kept
  end

  # events já vem pronto e cortado em 30 pelo chamador (persistência incremental)
  # 🔒 Rodada 4 da auditoria (#102): sob a trava da linha, só na chave
  # comments_state (Cevico::SettingMerge) — não encosta no resto do ai_config
  # Junta com o que já está gravado (não troca pela foto do começo da rodada):
  # se outra rodada marcou "já respondi" em algum comentário nesse meio-tempo,
  # a marca dela fica. Só sai da memória o que esta rodada podou por prazo.
  def save_state(handled, events)
    Cevico::SettingMerge.merge_key!(@account, :ai_config, 'comments_state') do |state|
      stored = Hash(state['handled']).except(*Array(@pruned_ids))
      state.merge(
        'handled' => stored.merge(handled),
        'events' => merge_events(events, state['events']),
        'last_run_at' => Time.current.iso8601
      )
    end
    @ai_config = nil # limpa memo p/ a próxima leitura de state pegar o fresco
  end

  # eventos desta rodada + os gravados (de outra rodada), sem repetir, do mais
  # novo para o mais antigo, no máximo 30
  def merge_events(events, stored)
    (Array(events) + Array(stored))
      .uniq { |e| [e['at'], e['author'], e['comment'], e['status']] }
      .each_with_index.sort_by { |e, i| [e['at'].to_s, -i] }.reverse.map(&:first)
      .first(30)
  end
end
