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
class Crm::CommentsAgentService
  include Crm::AiAgentConfig

  AGENT_KEY = 'comments'.freeze
  GRAPH = 'https://graph.facebook.com/v19.0'.freeze
  MEDIA_LIMIT = 10       # posts recentes olhados por rodada
  COMMENTS_LIMIT = 25    # comentários por post
  REPLIES_PER_RUN = 10   # teto de respostas por rodada (segurança)
  HANDLED_TTL = 30.days  # memória de "já respondi" (comentário some da lista de pendentes)
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
  PROMPT

  def initialize(account)
    @account = account
  end

  def call # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return { error: 'agente desligado' } if agent_paused?
    return { error: 'sem token da Página (conecte em Automações → Respondedor de Comentários)' } if token.blank?
    return { error: 'IA não configurada' } if api_key.blank?
    return { error: 'fora do horário (07h–22h SP)' } unless BUSINESS_HOURS.cover?(TZ.now.hour)

    handled = prune_handled
    prior_events = Array(state['events'])
    events = []
    replied = 0

    pending_comments.each do |comment|
      break if replied >= REPLIES_PER_RUN
      next if handled.key?(comment[:id])

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

  def ig_comments
    ig_id = config['ig_user_id'].presence
    return [] if ig_id.blank?

    media = graph_get("#{ig_id}/media", fields: 'id,caption', limit: MEDIA_LIMIT)
    Array(media['data']).flat_map do |m|
      comments = graph_get("#{m['id']}/comments", fields: 'id,text,username,timestamp', limit: COMMENTS_LIMIT)
      Array(comments['data']).map do |c|
        { id: c['id'], platform: 'instagram', author: c['username'].to_s,
          text: c['text'].to_s, post: m['caption'].to_s.truncate(120) }
      end
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::CommentsAgent] IG: #{e.message}"
    []
  end

  def fb_comments # rubocop:disable Metrics/AbcSize
    page_id = config['fb_page_id'].presence
    return [] if page_id.blank?

    posts = graph_get("#{page_id}/feed", fields: 'id,message', limit: MEDIA_LIMIT)
    Array(posts['data']).flat_map do |p|
      comments = graph_get("#{p['id']}/comments", fields: 'id,message,from,created_time', filter: 'stream', limit: COMMENTS_LIMIT)
      Array(comments['data']).reject { |c| c.dig('from', 'id').to_s == page_id.to_s }.map do |c|
        { id: c['id'], platform: 'facebook', author: c.dig('from', 'name').to_s,
          text: c['message'].to_s, post: p['message'].to_s.truncate(120) }
      end
    end
  rescue StandardError => e
    Rails.logger.error "[Crm::CommentsAgent] FB: #{e.message}"
    []
  end

  def graph_get(path, params)
    HTTParty.get("#{GRAPH}/#{path}", query: params.merge(access_token: token), timeout: 20).parsed_response || {}
  end

  def ask_ai(comment)
    message = client.messages.create(
      model: model,
      max_tokens: 512,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
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

  def prune_handled
    Hash(state['handled']).select do |_id, ts|
      t = begin
        Time.zone.parse(ts.to_s)
      rescue ArgumentError
        nil
      end
      t.present? && t > HANDLED_TTL.ago
    end
  end

  # events já vem pronto e cortado em 30 pelo chamador (persistência incremental)
  def save_state(handled, events)
    settings = CrmSetting.find_or_create_by!(account: @account)
    cfg = settings.ai_config || {}
    cfg['comments_state'] = {
      'handled' => handled,
      'events' => Array(events).first(30),
      'last_run_at' => Time.current.iso8601
    }
    settings.update!(ai_config: cfg)
    @ai_config = nil # limpa memo p/ a próxima leitura de state pegar o fresco
  end
end
