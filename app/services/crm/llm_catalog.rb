# 🧠 LIBERDADE DE MODELO (22/11/2026): todo agente de IA do sistema pode rodar
# em qualquer modelo de qualquer um dos 3 fornecedores oficiais:
#   Anthropic (Claude) · OpenAI (ChatGPT) · Google (Gemini)
#
# Quem decide o fornecedor é o próprio nome do modelo escolhido no cartão do
# agente (claude-… = Anthropic, gpt-…/o3… = OpenAI, gemini-… = Google). Um id
# que não siga esse padrão pode ir com o fornecedor na frente, ex.:
# "openai:meu-modelo-ajustado" ou "google:gemma-4".
#
# A lista NÃO é fechada: além dos modelos recomendados abaixo (com preço), a
# tela busca na hora a lista que a chave de cada fornecedor enxerga (/models)
# e aceita qualquer id digitado à mão. Modelo sem preço conhecido roda normal;
# só o "Gasto da IA" registra US$ 0 e avisa no log.
#
# Chaves (ai_config): api_key = Anthropic · openai_api_key = OpenAI ·
# gemini_api_key = Google (a mesma que já lê áudio/imagem).
module Crm::LlmCatalog # rubocop:disable Metrics/ModuleLength
  module_function

  PROVIDERS = {
    'anthropic' => { label: 'Anthropic · Claude', key: 'api_key', site: 'console.anthropic.com' },
    'openai' => { label: 'OpenAI · ChatGPT', key: 'openai_api_key', site: 'platform.openai.com' },
    'google' => { label: 'Google · Gemini', key: 'gemini_api_key', site: 'aistudio.google.com' }
  }.freeze

  # preços de LISTA conferidos na documentação oficial em 22/11/2026, US$ por
  # milhão de tokens: [entrada, saída, entrada lida do cache, gravação no cache 1h].
  # `from` = preço que passa a valer na data (anunciado pelo fornecedor).
  PRICING_TABLE_DATE = '2026-11-22'.freeze
  MODELS = {
    # ── Anthropic ──
    'claude-fable-5-2' => { provider: 'anthropic', label: 'Claude Fable 5.2', hint: 'o mais forte (o mais caro)', price: [8.0, 40.0, 0.20, 16.0] },
    'claude-opus-5-5' => { provider: 'anthropic', label: 'Claude Opus 5.5', hint: 'muito forte', price: [4.0, 20.0, 0.20, 8.0] },
    'claude-sonnet-5-5' => { provider: 'anthropic', label: 'Claude Sonnet 5.5', hint: 'equilíbrio', price: [2.0, 10.0, 0.10, 4.0] },
    'claude-haiku-5-5' => { provider: 'anthropic', label: 'Claude Haiku 5.5', hint: 'rápido e muito barato', price: [0.10, 0.50, 0.01, 0.20] },
    'claude-opus-4-8' => { provider: 'anthropic', label: 'Claude Opus 4.8', hint: 'o padrão de sempre', price: [5.0, 25.0, 0.50, 10.0] },
    'claude-sonnet-5' => { provider: 'anthropic', label: 'Claude Sonnet 5', hint: 'equilíbrio', price: [2.0, 10.0, 0.20, 4.0] },
    'claude-haiku-4-5' => { provider: 'anthropic', label: 'Claude Haiku 4.5', hint: 'rápido', price: [1.0, 5.0, 0.10, 2.0], no_effort: true },
    # ── OpenAI ──
    'gpt-6.2-astra' => { provider: 'openai', label: 'GPT-6.2 Astra', hint: 'o mais forte da OpenAI', price: [8.0, 40.0, 0.40, 0] },
    'gpt-6.2-sol' => { provider: 'openai', label: 'GPT-6.2 Sol', hint: 'equilíbrio', price: [2.0, 10.0, 0.10, 0] },
    'gpt-6.1-terra' => { provider: 'openai', label: 'GPT-6.1 Terra', hint: 'mais barato', price: [1.0, 5.0, 0.05, 0] },
    'gpt-6-luna' => { provider: 'openai', label: 'GPT-6 Luna', hint: 'o mais barato e rápido', price: [0.10, 0.50, 0.01, 0] },
    # ── Google ──
    'gemini-4-neon' => { provider: 'google', label: 'Gemini 4 Neon', hint: 'o mais caro do Gemini 4', price: [3.0, 15.0, 0.15, 0] },
    'gemini-4-carbon' => { provider: 'google', label: 'Gemini 4 Carbon', hint: 'Gemini 4', price: [2.0, 10.0, 0.10, 0],
                           from: { '2026-12-01' => [4.0, 20.0, 0.20, 0] } },
    'gemini-4-argon' => { provider: 'google', label: 'Gemini 4 Argon', hint: 'Gemini 4', price: [2.0, 10.0, 0.10, 0],
                          from: { '2026-12-01' => [4.0, 20.0, 0.20, 0] } },
    'gemini-4-hydrogen' => { provider: 'google', label: 'Gemini 4 Hydrogen', hint: 'Gemini 4 mais barato', price: [1.5, 7.5, 0.075, 0] },
    'gemini-3.8-flash' => { provider: 'google', label: 'Gemini 3.8 Flash', hint: 'rápido', price: [0.75, 3.75, 0.075, 0],
                            from: { '2027-01-01' => [1.5, 7.5, 0.15, 0] } },
    'gemini-3.6-flash' => { provider: 'google', label: 'Gemini 3.6 Flash', hint: 'rápido', price: [0.75, 3.75, 0.075, 0],
                            from: { '2027-01-01' => [1.5, 7.5, 0.15, 0] } },
    'gemini-3.5-flash-lite' => { provider: 'google', label: 'Gemini 3.5 Flash-Lite', hint: 'o mais barato', price: [0.30, 2.50, 0.03, 0] }
  }.freeze

  ID_FORMAT = %r{\A[a-zA-Z0-9][\w.\-:/@]{1,99}\z}
  LIVE_CACHE_KEY = 'crm:llm_catalog:%<account>s:%<provider>s'.freeze
  LIVE_TTL = 6.hours

  # 'anthropic' | 'openai' | 'google' | nil (id que não dá para reconhecer)
  def provider(model)
    id = model.to_s.strip
    prefix = id.split(':', 2).first if id.include?(':')
    return prefix if PROVIDERS.key?(prefix)
    return MODELS[id][:provider] if MODELS.key?(id)

    case id
    when /\Aclaude/i then 'anthropic'
    when /\A(gpt|chatgpt|o\d|codex)/i then 'openai'
    when /\A(gemini|gemma|learnlm)/i then 'google'
    end
  end

  # o id que vai para a API do fornecedor (sem o "openai:" da frente)
  def api_id(model)
    id = model.to_s.strip
    prefix, rest = id.split(':', 2)
    PROVIDERS.key?(prefix) && rest.present? ? rest : id
  end

  def anthropic?(model)
    provider(model) == 'anthropic'
  end

  def valid_id?(model)
    model.to_s.match?(ID_FORMAT) && provider(model).present?
  end

  def key_name(provider)
    PROVIDERS.dig(provider, :key)
  end

  def key_for(ai_config, model)
    name = key_name(provider(model))
    name ? (ai_config || {})[name].presence : nil
  end

  # o modelo pode rodar AGORA nesta conta? (id reconhecível + chave do fornecedor salva)
  def usable?(ai_config, model)
    valid_id?(model) && key_for(ai_config, model).present?
  end

  # "pensa mais/menos": os níveis de sempre (low…max); o tradutor de cada
  # fornecedor ajusta ao que aquele modelo aceita
  def effort_supported?(model)
    !MODELS.dig(model.to_s, :no_effort)
  end

  def label(model)
    MODELS.dig(model.to_s, :label) || api_id(model)
  end

  def price(model, at: Time.current)
    meta = MODELS[model.to_s] || MODELS[api_id(model)]
    return nil unless meta

    day = at.to_date.to_s
    changed = (meta[:from] || {}).select { |date, _| date <= day }.max_by(&:first)
    changed ? changed.last : meta[:price]
  end

  # custo de uma chamada a partir do uso no formato da Anthropic (o tradutor
  # converte o uso da OpenAI/Google para esse mesmo formato)
  def cost(model, fresh:, written:, read:, output:)
    price_in, price_out, price_read, price_write = price(model) || [0, 0, 0, 0]
    ((fresh * price_in) + (written * price_write) + (read * price_read) + (output * price_out)) / 1_000_000.0
  end

  # ── LISTA PARA A TELA ────────────────────────────────────────────────────
  # fornecedores, se a chave está salva e os modelos (recomendados + os que a
  # chave enxerga na hora, quando já buscados)
  # fetch: false (padrão) = só o que já está guardado, sem chamar ninguém
  # (a tela de configurações abre rápido); fetch: true busca nos fornecedores
  def catalog(account, ai_config: nil, fetch: false, refresh: false)
    cfg = ai_config || CrmSetting.find_by(account: account)&.ai_config || {}
    PROVIDERS.map do |id, meta|
      key = cfg[meta[:key]].presence
      live = key ? live_models(account, id, key, fetch: fetch, refresh: refresh) : []
      { id: id, label: meta[:label], key_set: key.present?, site: meta[:site], models: merged_models(id, live) }
    end
  end

  def merged_models(provider, live)
    curated = MODELS.select { |_, meta| meta[:provider] == provider }.map do |id, meta|
      { value: id, label: meta[:label], hint: meta[:hint], price_in: price(id)[0], price_out: price(id)[1], recommended: true }
    end
    known = curated.pluck(:value)
    labels = curated.pluck(:label)
    # o mesmo modelo com data no nome (ex.: claude-haiku-4-5-20251001) não aparece duas vezes
    extra = Array(live).reject { |row| known.include?(row[:value]) || labels.include?(row[:label]) }.sort_by { |row| row[:value] }
    curated + extra.map { |row| row.merge(recommended: false) }
  end

  # o que a chave enxerga no fornecedor (guardado 6 h; refresh: true busca de novo)
  def live_models(account, provider, key, fetch: true, refresh: false)
    cache_key = format(LIVE_CACHE_KEY, account: account&.id, provider: provider)
    Rails.cache.delete(cache_key) if refresh
    return Rails.cache.read(cache_key) || [] unless fetch

    Rails.cache.fetch(cache_key, expires_in: LIVE_TTL) { fetch_live(provider, key) }
  rescue StandardError => e
    Rails.logger.warn("[Crm::LlmCatalog] lista de modelos #{provider} falhou: #{e.message}")
    []
  end

  def fetch_live(provider, key)
    case provider
    when 'anthropic' then anthropic_models(key)
    when 'openai' then openai_models(key)
    when 'google' then google_models(key)
    else []
    end
  end

  def anthropic_models(key)
    response = HTTParty.get('https://api.anthropic.com/v1/models', query: { limit: 100 }, timeout: 20,
                                                                   headers: { 'x-api-key' => key, 'anthropic-version' => '2023-06-01' })
    return [] unless response.code.to_i == 200

    Array(response.parsed_response['data']).map { |row| { value: row['id'], label: row['display_name'].presence || row['id'] } }
  end

  # só modelos de conversa (tira imagem, voz, embeddings, moderação…)
  OPENAI_SKIP = /embedding|whisper|tts|dall-e|image|audio|realtime|transcribe|moderation|search|davinci|babbage|instruct|sora/i
  def openai_models(key)
    response = HTTParty.get('https://api.openai.com/v1/models', headers: { 'Authorization' => "Bearer #{key}" }, timeout: 20)
    return [] unless response.code.to_i == 200

    Array(response.parsed_response['data']).pluck('id')
                                           .select { |id| id.match?(/\A(gpt|o\d|chatgpt|codex)/i) && !id.match?(OPENAI_SKIP) }
                                           .map { |id| { value: id, label: id } }
  end

  GOOGLE_SKIP = /embedding|imagen|veo|tts|image|audio|live|aqa|robotics/i
  def google_models(key)
    response = HTTParty.get('https://generativelanguage.googleapis.com/v1beta/models', query: { key: key, pageSize: 200 }, timeout: 20)
    return [] unless response.code.to_i == 200

    Array(response.parsed_response['models']).filter_map do |row|
      id = row['name'].to_s.delete_prefix('models/')
      next unless id.match?(/\A(gemini|gemma)/i) && !id.match?(GOOGLE_SKIP)
      next unless Array(row['supportedGenerationMethods']).include?('generateContent')

      { value: id, label: row['displayName'].presence || id }
    end
  end
end
