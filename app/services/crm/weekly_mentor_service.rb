# Mentor do Time: o sistema capta os dados de uso de cada usuário (tempo de
# resposta ao paciente, conversas resolvidas, mensagens enviadas, tarefas) e
# gera um feedback SEMANAL individual: o ponto forte da semana, O ponto fraco
# a corrigir e soluções simples de implementar que geram grande resultado.
# O feedback aparece no Meu Painel de cada pessoa (admin vê o time inteiro).
#
# Dois modos:
# - PERENE: cron semanal (segunda de manhã) via Crm::WeeklyMentorJob,
#   analisando a semana que acabou (segunda a domingo).
# - PONTUAL: botão "Gerar feedback agora" (admin) — analisa os últimos 7 dias.
class Crm::WeeklyMentorService
  include Crm::AiAgentConfig

  AGENT_KEY = 'mentor'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      resumo: { type: 'string', description: 'Leitura geral da semana desta pessoa em 1-2 frases, tom acolhedor e concreto' },
      ponto_forte: { type: 'string', description: 'O destaque positivo da semana, citando o número que o comprova' },
      ponto_fraco: { type: 'string', description: 'O PONTO FRACO exato a corrigir (um só, o de maior impacto), citando o número' },
      solucoes: {
        type: 'array',
        description: '2 a 3 soluções SIMPLES de implementar que geram grande resultado no ponto fraco',
        items: {
          type: 'object',
          properties: {
            titulo: { type: 'string', description: 'Nome curto da solução (até 8 palavras)' },
            como_fazer: { type: 'string', description: 'Como implementar na prática, em 1-2 frases simples' }
          },
          required: %w[titulo como_fazer],
          additionalProperties: false
        }
      },
      incentivo: { type: 'string', description: 'Frase final de incentivo pessoal, 1 frase, sem clichê vazio' }
    },
    required: %w[resumo ponto_forte ponto_fraco solucoes incentivo],
    additionalProperties: false
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Mentor do Time da CEVICO (clínica de oftalmologia). Toda semana
    você recebe os números de uso do sistema de UMA pessoa do time de
    atendimento e devolve um feedback individual, como um mentor generoso e
    direto faria.

    Regras do bom feedback:
    - Fale COM a pessoa (use "você"), em português simples e caloroso.
    - Aponte UM ponto forte real, citando o número que o comprova.
    - Aponte UM ponto fraco só — o de MAIOR impacto no resultado da clínica
      (ex.: tempo de resposta acima da meta, % baixa dentro da meta, queda
      de conversas resolvidas). Cite o número. Sem rodeios, sem crueldade.
    - Dê 2-3 soluções SIMPLES de implementar já na segunda-feira, que geram
      grande resultado (ex.: "responda primeiro quem espera há mais tempo",
      "use as respostas prontas para as 3 perguntas mais comuns").
    - Use a mediana do time como régua justa (não exponha colegas pelo nome).
    - Se a semana foi excelente, o "ponto fraco" vira o próximo degrau de
      evolução (deixe isso claro no texto).
    - Se receber "meta_do_mes" (alvos, orientações e marcos do Painel de
      Metas), CONECTE as soluções à meta: mostre como o ajuste da pessoa
      ajuda o time a bater o alvo do mês.
  PROMPT

  def initialize(account, week_start: nil, rolling: false, cadence: 'weekly')
    @account = account
    # semanal: semana fechada (segunda a domingo) no cron; últimos 7 dias no
    # pontual. Mensal: o mês que acabou de fechar (visão de evolução).
    @rolling = rolling
    @cadence = cadence == 'monthly' ? 'monthly' : 'weekly'
    @week_start = week_start || default_start
  end

  def call
    return { error: 'O Mentor do Time está desligado.' } if agent_paused?
    return { error: 'Configure a chave da Anthropic em Integrações → Claude.' } if api_key.blank?

    active = active_team_stats
    return { generated: 0, week_start: @week_start.to_s } if active.empty?

    { generated: generate_feedbacks(active), week_start: @week_start.to_s }
  end

  private

  def default_start
    return (TZ.now.to_date - 1.month).beginning_of_month if @cadence == 'monthly'

    @rolling ? TZ.now.to_date - 6 : (TZ.now.to_date - 7).beginning_of_week
  end

  def period_days
    @cadence == 'monthly' ? (@week_start.end_of_month - @week_start).to_i + 1 : 7
  end

  # semana sem uso = sem feedback (quem não trabalhou não é cobrado)
  def active_team_stats
    @account.users.to_a
            .index_with { |user| collect_stats(user) }
            .select { |_u, s| s[:respostas].positive? || s[:mensagens_enviadas].positive? || s[:tarefas_concluidas].positive? }
  end

  def generate_feedbacks(active)
    medians = team_medians(active.values)
    active.count do |user, stats|
      verdict = ask_mentor(user, stats, medians)
      next false if verdict.blank? || verdict['error'].present?

      save_feedback(user, stats, verdict)
      true
    end
  end

  def range
    @range ||= begin
      from = @week_start.in_time_zone(TZ).beginning_of_day
      from..(from + period_days.days)
    end
  end

  def goal_minutes
    @goal_minutes ||= (ai_config.dig('agents', 'opportunity', 'response_goal_minutes').presence || 15).to_i
  end

  # os dados de uso da semana — só o que o sistema já grava sozinho
  def collect_stats(user) # rubocop:disable Metrics/AbcSize
    replies = @account.reporting_events.where(name: 'reply_time', user_id: user.id, created_at: range).where('value > 0')
    reply_count = replies.count
    {
      nome: user.available_name,
      respostas: reply_count,
      tempo_medio_resposta_min: reply_count.positive? ? (replies.average(:value).to_f / 60).round(1) : nil,
      respostas_dentro_da_meta_pct: reply_count.positive? ? ((replies.where(value: ..goal_minutes * 60).count * 100.0) / reply_count).round : nil,
      meta_minutos: goal_minutes,
      conversas_resolvidas: @account.reporting_events.where(name: 'conversation_resolved', user_id: user.id, created_at: range).count,
      mensagens_enviadas: @account.messages.where(sender: user, message_type: :outgoing, created_at: range).count,
      tarefas_concluidas: @account.tasks.where(assignee_id: user.id, status: :done, completed_at: range).count
    }
  end

  # mediana do time = régua justa para o mentor comparar sem expor ninguém
  def team_medians(stats_list)
    numeric_keys = %i[respostas tempo_medio_resposta_min respostas_dentro_da_meta_pct conversas_resolvidas mensagens_enviadas tarefas_concluidas]
    numeric_keys.index_with do |key|
      values = stats_list.filter_map { |s| s[key] }.sort
      values.empty? ? nil : values[values.size / 2]
    end
  end

  def ask_mentor(user, stats, medians)
    payload = {
      pessoa: stats,
      mediana_do_time: medians,
      periodo: "#{@week_start.strftime('%d/%m')} a #{(@week_start + period_days - 1).strftime('%d/%m/%Y')}",
      ciclo: @cadence == 'monthly' ? 'MENSAL (visão de evolução do mês inteiro — fale do mês, não da semana)' : 'semanal',
      # o Mentor orienta a equipe RUMO À META do mês (Painel de Metas)
      meta_do_mes: current_goal_payload
    }.compact
    message = client.messages.create(
      model: model,
      max_tokens: 2048,
      system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: JSON.pretty_generate(payload) }]
    )
    record_usage(message)
    parse_structured_response(message)
  rescue StandardError => e
    Rails.logger.error "[Crm::WeeklyMentor] #{user.id} #{e.class}: #{e.message}"
    nil
  end

  # metas + orientações do mês corrente: o mentor conecta o feedback
  # individual ao plano do Painel de Metas
  def current_goal_payload
    plan = @account.cevico_goal_plans.find_by(period_type: 'month', month: TZ.now.to_date.beginning_of_month)
    return nil if plan.nil?

    {
      alvos: (plan.targets || {}).map { |k, v| "#{CevicoGoalPlan::INDICATORS[k] || k}: #{v.to_i}" },
      orientacoes: plan.guidance.to_s.truncate(1500).presence,
      marcos_pendentes: Array(plan.milestones).reject { |m| m['done'] }.pluck('title').first(5)
    }.compact
  end

  def save_feedback(user, stats, verdict)
    row = Crm::WeeklyFeedback.find_or_initialize_by(account: @account, user: user,
                                                    week_start: @week_start, cadence: @cadence)
    row.update!(stats: stats, feedback: verdict)
  end
end
