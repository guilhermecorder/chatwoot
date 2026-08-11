# DASHBOARD DOS AGENTES DE IA (item 85, só admin): o que cada agente
# (Secretário, Analista, Radar, Copywriter, Atendente…) está fazendo e
# os principais indicadores — ligado/desligado, modelo em uso, chamadas
# e custo no período, última atividade e o ritmo diário (14 dias).
# Fonte: crm_ai_usages (uma linha por chamada) + config em crm_settings.
class Api::V1::Accounts::Crm::AiDashboardsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  include Crm::ResolvesPeriod
  before_action :require_administrator!

  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  DAILY_DAYS = 14

  # quem é quem (nomenclatura oficial) + o que cada um faz, em uma linha
  AGENT_META = {
    'scheduler' => { name: 'Secretário da Agenda', icon: 'i-lucide-calendar-check', color: '#0F5FA6',
                     what: 'lê confirmações de agendamento e anota as consultas na Agenda' },
    'conversation' => { name: 'Analista de Conversas', icon: 'i-lucide-messages-square', color: '#7C3AED',
                        what: 'lê a conversa, mede interesse e sugere frases para a atendente' },
    'form' => { name: 'Analista de Formulários', icon: 'i-lucide-clipboard-list', color: '#0E7490',
                what: 'resume as respostas dos formulários no card do paciente' },
    'opportunity' => { name: 'Radar de Oportunidades', icon: 'i-lucide-radar', color: '#DC2626',
                       what: 'vigia colunas do CRM e avisa o painel quando um lead esfria' },
    'closing' => { name: 'Monitor de Fechamento', icon: 'i-lucide-handshake', color: '#B8860B',
                   what: 'detecta fechamentos (valor, pagamento, data) e move o card' },
    'nps' => { name: 'Agente de NPS', icon: 'i-lucide-star', color: '#D97706',
               what: 'lê a nota do paciente no pós-operatório e registra o NPS' },
    'sales' => { name: 'Consultor Comercial', icon: 'i-lucide-briefcase', color: '#065F46',
                 what: 'analisa objeções e gera insights de vendas para a gestão' },
    'mentor' => { name: 'Mentor do Time', icon: 'i-lucide-graduation-cap', color: '#0F766E',
                  what: 'escreve o feedback semanal e mensal de cada pessoa do time' },
    'instagram' => { name: 'Atendente Instagram', icon: 'i-lucide-instagram', color: '#DB2777',
                     what: 'responde pacientes no direct (caixas escolhidas) e agenda' },
    'comments' => { name: 'Respondedor de Comentários', icon: 'i-lucide-message-circle-heart', color: '#E1306C',
                    what: 'responde comentários públicos no Instagram e Facebook' },
    'copywriter' => { name: 'Copywriter', icon: 'i-lucide-pen-tool', color: '#5B21B6',
                      what: 'escreve copies multi-formato com os valores da marca' },
    'pagebuilder' => { name: 'Construtor de Páginas', icon: 'i-lucide-layout-template', color: '#1D4ED8',
                       what: 'monta páginas públicas inteiras a partir de uma copy pronta' },
    'harvest' => { name: 'Colheitadeira da Base', icon: 'i-lucide-wheat', color: '#CA8A04',
                   what: 'pontua a base fria todo mês e reativa os leads mais propensos' },
    'manager' => { name: 'Gestor Autônomo', icon: 'i-lucide-gauge', color: '#0F5FA6',
                   what: 'lê o funil todo dia, abre tarefas nos desvios e escreve o briefing' },
    'auditor' => { name: 'Auditor de Conversas', icon: 'i-lucide-clipboard-check', color: '#0F766E',
                   what: 'dá nota diária nas conversas contra o script — coaching contínuo por atendente' },
    'creative' => { name: 'Criativo Perpétuo', icon: 'i-lucide-wand-sparkles', color: '#DB2777',
                    what: 'toda semana escreve variações dos anúncios e termos que mais viram cirurgia' }
  }.freeze

  def show # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    from, to = period_range
    usages = all_usages.where(created_at: from..to)
    # aliases distintos: 3 SUMs sem alias viram colunas homônimas "sum" e
    # o cast do pluck mistura os tipos (custo virava 0)
    by_agent = usages.group(:agent_key).pluck(:agent_key, Arel.sql('COUNT(*) AS calls'), Arel.sql('SUM(cost_usd) AS sum_cost'),
                                              Arel.sql('SUM(input_tokens) AS sum_in'), Arel.sql('SUM(output_tokens) AS sum_out'))
                     .index_by(&:first)
    last_calls = all_usages.group(:agent_key).maximum(:created_at)
    daily = daily_series

    agents = AGENT_META.map do |key, meta|
      row = by_agent[key]
      {
        key: key, name: meta[:name], icon: meta[:icon], color: meta[:color], what: meta[:what],
        enabled: agent_enabled?(key),
        responder: Crm::AiAgentConfig::RESPONDER_AGENTS.include?(key),
        model: resolved_model(key),
        calls: row ? row[1] : 0,
        cost_usd: row ? row[2].to_f.round(4) : 0,
        tokens: row ? row[3].to_i + row[4].to_i : 0,
        last_call_at: last_calls[key]&.iso8601,
        daily: daily[key] || []
      }
    end

    render json: {
      period: { preset: params[:preset].presence || 'last7', from: from.iso8601, to: to.iso8601 },
      totals: {
        calls: usages.count,
        cost_usd: usages.sum(:cost_usd).to_f.round(4),
        active_agents: agents.count { |a| a[:enabled] },
        top_agent: agents.max_by { |a| a[:calls] }&.then { |a| a[:calls].positive? ? a[:name] : nil }
      },
      agents: agents.sort_by { |a| [a[:enabled] ? 0 : 1, -a[:calls]] },
      extras: {
        mentor_feedbacks_30d: Crm::WeeklyFeedback.where(account: Current.account, created_at: 30.days.ago..).count,
        radar_last_run: crm_setting&.ai_config&.dig('opportunity_last_run')
      }
    }
  end

  private

  def all_usages
    Crm::AiUsage.where(account_id: Current.account.id)
  end

  # régua padrão CEVICO (06/08) via concern; presets antigos (7d/30d)
  # continuam valendo por compatibilidade
  def period_range
    @period_range ||= standard_period_range || legacy_range
  end

  def legacy_range
    now = TZ.now
    case params[:preset]
    when 'today' then [now.beginning_of_day, now.end_of_day]
    when '30d' then [30.days.ago, now]
    else [7.days.ago, now] # '7d' (padrão)
    end
  end

  def crm_setting
    @crm_setting ||= CrmSetting.find_by(account: Current.account)
  end

  def ai_config
    @ai_config ||= crm_setting&.ai_config || {}
  end

  def agent_enabled?(key)
    (ai_config['agents'] || {}).dig(key, 'enabled') == true
  end

  # mesma resolução do runtime: escolha do agente > recomendado > global > padrão
  def resolved_model(key)
    m = (ai_config['agents'] || {}).dig(key, 'model').presence ||
        Crm::AiAgentConfig::RECOMMENDED.dig(key, 'model') ||
        ai_config['model'].presence
    Crm::AiAgentConfig::MODELS.include?(m) ? m : Crm::AiAgentConfig::DEFAULT_MODEL
  end

  # chamadas por dia (14 dias) por agente — vira o mini-gráfico do card.
  # Auditoria I85: o dia é calculado no fuso de SP (antes era UTC e a
  # chamada das 22h caía na barra do dia seguinte).
  def daily_series # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    rows = all_usages
           .where(created_at: DAILY_DAYS.days.ago.beginning_of_day..)
           .group(:agent_key, Arel.sql("DATE(created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')"))
           .count
    days = (0...DAILY_DAYS).map { |i| (TZ.now.to_date - (DAILY_DAYS - 1 - i)) }
    rows.each_with_object({}) do |((key, _day), _count), acc|
      acc[key] ||= days.map do |d|
        rows.find { |(k, day), _v| k == key && day.to_date == d }&.last || 0
      end
    end
  end
end
