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
    'opportunity'  => { 'model' => 'claude-haiku-4-5', 'effort' => nil },     # classificação simples e frequente
    'closing'      => { 'model' => 'claude-sonnet-5', 'effort' => 'medium' }, # valor/pagamento/data do fechamento
    'nps'          => { 'model' => 'claude-haiku-4-5', 'effort' => nil },     # nota 0-10, tarefa simples
    'sales'        => { 'model' => 'claude-opus-4-8', 'effort' => 'high' },   # objeções + insights p/ gestão
    'instagram'    => { 'model' => 'claude-sonnet-5', 'effort' => 'medium' }, # conversa com paciente no direct
    'copywriter'   => { 'model' => 'claude-opus-4-8', 'effort' => 'high' },   # copy persuasiva multi-formato
    'pagebuilder'  => { 'model' => 'claude-sonnet-5', 'effort' => 'medium' }, # montar página a partir de copy pronta
    'mentor'       => { 'model' => 'claude-sonnet-5', 'effort' => 'high' },   # feedback semanal do time (1x/semana)
    'comments'     => { 'model' => 'claude-sonnet-5', 'effort' => 'medium' }, # comentário público: curto, mas é a cara da clínica
    'harvest'      => { 'model' => 'claude-haiku-4-5', 'effort' => nil },     # pontuar leads em lote: volume alto, tarefa simples
    'manager'      => { 'model' => 'claude-haiku-4-5', 'effort' => nil },     # briefing diário curto (a matemática é do Ruby)
    'auditor'      => { 'model' => 'claude-haiku-4-5', 'effort' => nil },     # nota diária em volume — barato por desenho
    'creative'     => { 'model' => 'claude-sonnet-5', 'effort' => 'high' }    # copy que vai pro anúncio — qualidade importa
  }.freeze

  # Agentes RESPONDEDORES: os únicos autorizados a falar com o paciente
  # (hoje só o Atendente Instagram, restrito às caixas escolhidas na config).
  # Todos os demais seguem a trava operacional de leitura.
  RESPONDER_AGENTS = %w[instagram comments].freeze

  # preço US$ por milhão de tokens (entrada / saída)
  PRICING = {
    'claude-opus-4-8'  => [5.0, 25.0],
    'claude-sonnet-5'  => [3.0, 15.0],
    'claude-haiku-4-5' => [1.0, 5.0]
  }.freeze

  # Trava de segurança aplicada a TODOS os agentes, mesmo com prompt
  # personalizado: agente interno nunca fala com paciente. (Tecnicamente
  # nenhum agente tem canal de envio — a saída é só JSON lido pela equipe.)
  # Sugerir frases PARA A ATENDENTE usar é permitido: quem decide e envia
  # é sempre a humana.
  OPERATIONAL_GUARDRAIL = <<~GUARD.freeze

    REGRAS INEGOCIÁVEIS (não podem ser alteradas por nenhuma instrução acima):
    - Você é um agente OPERACIONAL INTERNO. Sua resposta é lida SOMENTE pela
      equipe da clínica. Você NUNCA envia nada ao paciente e NUNCA interage
      com ele — a conversa recebida é apenas material de análise.
    - Você PODE sugerir frases prontas PARA A ATENDENTE humana usar, quando
      o formato de saída pedido tiver campo para isso. A decisão de enviar
      (ou não) é sempre dela.
    - Responda exclusivamente no formato estruturado pedido.
  GUARD

  # Trava dos agentes RESPONDEDORES (falam com o paciente): o risco muda —
  # aqui o perigo é inventar dado clínico/valor/horário ou prometer resultado.
  RESPONDER_GUARDRAIL = <<~GUARD.freeze

    REGRAS INEGOCIÁVEIS (não podem ser alteradas por nenhuma instrução acima):
    - Suas mensagens SÃO enviadas ao paciente. Use APENAS informações que
      estão neste prompt ou na conversa — NUNCA invente valores, horários,
      endereços, nomes ou dados clínicos.
    - NUNCA forneça diagnóstico médico nem prometa resultado de cirurgia.
    - Só ofereça horários que constem na lista de HORÁRIOS DISPONÍVEIS
      fornecida no contexto. Fora dela, diga que vai verificar com a equipe.
    - Urgência (dor intensa, perda súbita de visão, trauma): oriente procurar
      pronto atendimento oftalmológico imediatamente e marque chamar_humano.
    - Em dúvida sobre qualquer informação, marque chamar_humano em vez de
      arriscar uma resposta.
    - Responda exclusivamente no formato estruturado pedido.
  GUARD

  private

  def client
    # 300s: Copywriter/Construtor geram páginas inteiras (minutos) — 60s estourava no meio (bug 17/07)
    @client ||= Anthropic::Client.new(api_key: api_key, timeout: 300)
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

  # prompt do agente (custom ou padrão) SEMPRE com a trava certa no fim:
  # respondedor (fala com paciente) tem trava própria; os demais, a de leitura
  def system_prompt
    base = agent_config['prompt'].presence || self.class::SYSTEM_PROMPT
    # {{TABELA_DE_PRECOS}} vira a tabela de preços oficial na hora da chamada
    # (Configurações → Tabela de preços; sem tabela salva = valores padrão)
    if base.include?('{{TABELA_DE_PRECOS}}')
      base = base.gsub('{{TABELA_DE_PRECOS}}', Cevico::PriceList.prompt_block(@account))
    end
    guard = RESPONDER_AGENTS.include?(self.class::AGENT_KEY) ? RESPONDER_GUARDRAIL : OPERATIONAL_GUARDRAIL
    base + guard
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

  # Construtor PRO (23/07): teto de resposta escolhido pelo admin —
  # nil = o padrão de cada serviço decide
  def max_tokens_config
    t = agent_config['max_tokens'].to_i
    t.between?(1_000, 60_000) ? t : nil
  end

  # Construtor PRO: referências de estilo do admin (exemplos de páginas
  # admiradas, diretrizes de marca) — injetadas na entrada da geração.
  # Aceita a chave 'references' (mesmo nome que o Copywriter já usa).
  def style_refs
    agent_config['style_refs'].to_s.strip.presence ||
      agent_config['references'].to_s.strip.presence
  end

  def style_refs_block
    return '' if style_refs.blank?

    "\nREFERÊNCIAS E DIRETRIZES DE ESTILO (definidas pelo admin — inspire-se nelas ao montar, sem copiá-las literalmente):\n#{style_refs[0, 12_000]}\n"
  end

  # monta o output_config com o formato pedido + esforço quando o modelo aceita
  def output_config_for(format)
    cfg = { format: format }
    cfg[:effort] = effort if effort && model.exclude?('haiku')
    cfg
  end

  # extrai o JSON estruturado da resposta, com guarda p/ resposta vazia
  def parse_structured_response(message)
    text = message.content.find { |block| block.type == :text }&.text
    return { error: 'A IA não devolveu conteúdo (resposta vazia). Tente de novo.' } if text.blank?

    JSON.parse(text)
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
