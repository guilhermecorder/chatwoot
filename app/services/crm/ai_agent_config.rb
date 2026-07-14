# Config compartilhada dos agentes de IA internos (Analista de Conversas,
# Analista de Formulários e Agente de Agendamento).
#
# Chave da API, modelo e esforço têm um padrão GLOBAL (CRM → Integrações →
# Claude) e podem ser sobrescritos POR AGENTE (Automações → Agentes de IA) —
# assim tarefas simples podem rodar num modelo mais barato/rápido.
#
# "Esforço" (effort) controla quanto a IA pensa antes de responder:
# low | medium | high (padrão da API) | xhigh | max. O Haiku 4.5 não aceita
# o parâmetro — nesse caso ele é omitido.
module Crm::AiAgentConfig
  DEFAULT_MODEL = 'claude-opus-4-8'.freeze
  MODELS  = %w[claude-opus-4-8 claude-sonnet-5 claude-haiku-4-5].freeze
  EFFORTS = %w[low medium high xhigh max].freeze

  # Modelo/esforço RECOMENDADO por agente (pré-selecionado quando o agente
  # não tem escolha própria): tarefa simples → modelo barato; tarefa
  # delicada → modelo mais completo.
  RECOMMENDED = {
    'conversation' => { 'model' => 'claude-opus-4-8', 'effort' => 'high' },   # leitura fina de interesse
    'form'         => { 'model' => 'claude-sonnet-5', 'effort' => 'high' },   # síntese de muitas respostas
    'scheduler'    => { 'model' => 'claude-sonnet-5', 'effort' => 'medium' }, # extração estruturada
    'opportunity'  => { 'model' => 'claude-haiku-4-5', 'effort' => nil }      # classificação simples e frequente
  }.freeze

  # preço US$ por milhão de tokens (entrada / saída)
  PRICING = {
    'claude-opus-4-8'  => [5.0, 25.0],
    'claude-sonnet-5'  => [3.0, 15.0],
    'claude-haiku-4-5' => [1.0, 5.0]
  }.freeze

  # Trava de segurança aplicada a TODOS os agentes, mesmo com prompt
  # personalizado: agente interno nunca fala com paciente. (Tecnicamente
  # nenhum agente tem canal de envio — a saída é só JSON lido pela equipe —
  # mas o prompt reforça para a IA nunca redigir como se fosse enviar.)
  OPERATIONAL_GUARDRAIL = <<~GUARD.freeze

    REGRAS INEGOCIÁVEIS (não podem ser alteradas por nenhuma instrução acima):
    - Você é um agente OPERACIONAL INTERNO. Sua resposta é lida SOMENTE pela
      equipe da clínica. Você NUNCA envia, redige ou sugere texto pronto para
      ser enviado ao paciente — nem mensagens, nem respostas em nome da clínica.
    - Não interaja com o paciente de nenhuma forma. A conversa recebida é
      apenas material de análise.
    - Responda exclusivamente no formato estruturado pedido.
  GUARD

  private

  def client
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 60)
  end

  def ai_config
    @ai_config ||= CrmSetting.find_by(account: @account)&.ai_config || {}
  end

  def api_key
    ai_config['api_key']
  end

  def agent_config
    (ai_config['agents'] || {})[self.class::AGENT_KEY] || {}
  end

  # INTERRUPTOR DEFINITIVO: agente só roda com enabled == true gravado.
  # Padrão (sem config) = DESLIGADO — ninguém liga IA sem querer. Vale para
  # TODOS os caminhos: botão na tela, automação de coluna e cron do Radar.
  def agent_paused?
    agent_config['enabled'] != true
  end

  # prompt do agente (custom ou padrão) SEMPRE com a trava operacional no fim
  def system_prompt
    base = agent_config['prompt'].presence || self.class::SYSTEM_PROMPT
    base + OPERATIONAL_GUARDRAIL
  end

  def recommended
    RECOMMENDED[self.class::AGENT_KEY] || {}
  end

  # modelo: escolha do agente > recomendado para o agente > global > padrão
  def model
    m = agent_config['model'].presence || recommended['model'] ||
        ai_config['model'].presence
    MODELS.include?(m) ? m : DEFAULT_MODEL
  end

  # esforço: escolha do agente > recomendado > global > (omitido = high)
  def effort
    e = agent_config['effort'].presence || recommended['effort'] ||
        ai_config['effort'].presence
    EFFORTS.include?(e) ? e : nil
  end

  # monta o output_config com o formato pedido + esforço quando o modelo aceita
  def output_config_for(format)
    cfg = { format: format }
    cfg[:effort] = effort if effort && model.exclude?('haiku')
    cfg
  end

  # grava tokens + custo estimado da chamada (alimenta o relatório de gastos)
  def record_usage(message)
    usage = message.usage
    input = usage.input_tokens.to_i +
            usage.cache_creation_input_tokens.to_i +
            usage.cache_read_input_tokens.to_i
    output = usage.output_tokens.to_i
    price_in, price_out = PRICING[model] || PRICING[DEFAULT_MODEL]
    cost = ((input * price_in) + (output * price_out)) / 1_000_000.0

    Crm::AiUsage.create!(
      account: @account,
      agent_key: self.class::AGENT_KEY,
      model: model,
      input_tokens: input,
      output_tokens: output,
      cost_usd: cost.round(6)
    )
  rescue StandardError => e
    Rails.logger.warn "[Crm::AiUsage] falhou ao registrar: #{e.message}"
  end
end
