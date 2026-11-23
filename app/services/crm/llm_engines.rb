# 🧠 MOTORES DE IA DOS ATENDENTES (item 399, 22/11): além do Claude (Anthropic,
# o motor de sempre), os atendentes do WhatsApp podem rodar no ChatGPT (OpenAI)
# para experimento. Quem decide o motor é o MODELO escolhido no cartão do
# agente: modelo "gpt-…" = OpenAI; qualquer outro = Claude, como sempre foi.
#
# Só os agentes de OPENAI_AGENT_KEYS aceitam o ChatGPT. Todos os outros agentes
# (analistas, copywriter, gestor…) continuam no Claude: se alguém gravar um
# modelo "gpt-…" neles, o Crm::AiAgentConfig#model ignora e usa o recomendado.
#
# A chave fica em ai_config['openai_api_key'] (CRM → Integrações → ChatGPT).
# A API da OpenAI é PRÉ-PAGA à parte (platform.openai.com → Billing); a
# assinatura do ChatGPT Plus/Pro não vale para ela.
module Crm::LlmEngines
  module_function

  OPENAI_KEY = 'openai_api_key'.freeze
  # atendentes do WhatsApp (o Agente de Ligação fala pela ElevenLabs; Instagram
  # e Comentários têm serviço próprio — ficam de fora por enquanto)
  OPENAI_AGENT_KEYS = %w[atendente_agendamento atendente_pos atendente_pos_op].freeze

  # Modelos conferidos na documentação oficial em 22/11/2026
  # (developers.openai.com/api/docs/models e /pricing). Preço de LISTA em US$
  # por milhão de tokens: entrada / saída / entrada lida do cache (o cache da
  # OpenAI é automático; gravar não tem preço à parte).
  # Mudou preço ou entrou modelo novo? Atualize aqui E a data.
  OPENAI_PRICING_TABLE_DATE = '2026-11-22'.freeze
  OPENAI_MODELS = {
    'gpt-6.2-sol' => { label: 'GPT-6.2 Sol', hint: 'equilíbrio (mesmo preço do Sonnet 5)', price: [2.0, 10.0, 0.10] },
    'gpt-6.1-terra' => { label: 'GPT-6.1 Terra', hint: 'mais barato (mesmo preço do Haiku 4.5)', price: [1.0, 5.0, 0.05] },
    'gpt-6-luna' => { label: 'GPT-6 Luna', hint: 'o mais barato e rápido', price: [0.10, 0.50, 0.01] },
    'gpt-6.2-astra' => { label: 'GPT-6.2 Astra', hint: 'o mais forte (4x o preço do Sol)', price: [8.0, 40.0, 0.40] }
  }.freeze
  # "quanto pensa": os quatro modelos aceitam os mesmos níveis do Claude
  OPENAI_EFFORTS = %w[low medium high xhigh max].freeze

  def openai?(model)
    OPENAI_MODELS.key?(model.to_s)
  end

  def openai_agent?(agent_key)
    OPENAI_AGENT_KEYS.include?(agent_key.to_s)
  end

  def openai_key(account)
    CrmSetting.find_by(account: account)&.ai_config&.dig(OPENAI_KEY).presence
  end

  # lista para a tela (cartão do agente e 🧪 Testar agente)
  def openai_catalog
    OPENAI_MODELS.map do |id, meta|
      { value: id, label: meta[:label], hint: meta[:hint], price_in: meta[:price][0], price_out: meta[:price][1] }
    end
  end

  # tokens + custo de UMA chamada. Na OpenAI o input_tokens JÁ inclui o que foi
  # lido do cache (cached_tokens é um pedaço dele), diferente da Anthropic.
  def openai_cost(model, usage)
    usage ||= {}
    input = usage['input_tokens'].to_i
    read = [usage.dig('input_tokens_details', 'cached_tokens').to_i, input].min
    written = usage.dig('input_tokens_details', 'cache_write_tokens').to_i
    output = usage['output_tokens'].to_i
    price_in, price_out, price_cached = OPENAI_MODELS.fetch(model.to_s)[:price]
    cost = (((input - read) * price_in) + (read * price_cached) + (output * price_out)) / 1_000_000.0
    { input: input, output: output, read: read, written: written, cost: cost }
  end
end
