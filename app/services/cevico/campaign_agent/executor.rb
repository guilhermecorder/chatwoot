# 🖐️ EXECUTOR do Agente de Campanhas (item 352): aplica uma recomendação
# APROVADA. Por enquanto a autonomia é "sugere → alguém aprova → aplica":
#   • Meta + chavinha "executar pela API" ligada → pausa o item ou muda a verba
#     diária do conjunto pela Marketing API (precisa de token com ads_management);
#   • Google (até ligarmos a API do Google Ads) e Meta sem a chavinha → devolve
#     o PASSO A PASSO para fazer no Gerenciador; a pessoa marca "fiz à mão".
# As recomendações que não mudam nada na plataforma (criativo novo, público,
# página, qualidade do lead) são sempre "à mão": marcar como feita quando
# fizer, para o antes × depois começar a contar.
class Cevico::CampaignAgent::Executor
  def initialize(account:, params: nil, user: nil)
    @account = account
    @params = params || Cevico::CampaignAgent::Params.for(@account)
    @user = user
  end

  # { ok: true, mode: 'api' } | { ok: true, mode: 'manual', steps: [...] } | { ok: false, error: }
  def apply(action)
    return { ok: false, error: 'Esta recomendação não está aprovada.' } unless action.status == 'approved'
    return manual(action) unless action.platform? && action.channel == 'meta' && @params['execute_api']

    fields = fields_for(action)
    return manual(action) if fields.nil?

    _response, error = graph.post_object(action.ref_id, fields)
    if error
      action.update!(error: error)
      return { ok: false, error: "A Meta recusou: #{error}", steps: steps_for(action) }
    end

    mark_applied!(action, 'api')
    { ok: true, mode: 'api' }
  end

  # a pessoa fez no Gerenciador: começa a contar o antes × depois
  def mark_manual(action)
    return { ok: false, error: 'Aprove antes de marcar como feita.' } unless action.status == 'approved'

    mark_applied!(action, 'manual')
    { ok: true, mode: 'manual' }
  end

  def steps_for(action) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
    return Cevico::PageAgent::Executor.steps_for(action) if action.channel == 'pages'

    where = action.channel == 'meta' ? 'Gerenciador de Anúncios da Meta' : 'painel do Google Ads'
    item = "#{level_label(action.level)} \"#{action.ref_name}\""
    case action.kind
    when 'pause'
      ["Abrir o #{where} e localizar #{item}.", 'Desligar a chavinha (status → Pausado).', 'Voltar aqui e marcar "Fiz à mão".']
    when 'budget_up', 'budget_down'
      change = if action.payload['budget_to']
                 "para R$ #{format('%.2f', action.payload['budget_to']).tr('.',
                                                                           ',')} por dia"
               else
                 "em #{action.payload['pct'].to_i.abs}%"
               end
      ["Abrir o #{where} e localizar #{item}.", "Editar a verba diária: #{action.kind == 'budget_up' ? 'subir' : 'reduzir'} #{change}.",
       'Salvar e voltar aqui para marcar "Fiz à mão".']
    when 'new_creative'
      ['Pedir ao núcleo criativo 2 ou 3 variações (gancho novo, mesma promessa).',
       "Subir as variações no #{where} dentro do mesmo conjunto, pausando o anúncio cansado.",
       'Marcar "Fiz à mão" quando as variações estiverem no ar.']
    when 'audience'
      ["No #{where}, abrir #{item} e rever público e posicionamentos (abrir o público, tirar posicionamentos caros).", 'Salvar e marcar "Fiz à mão".']
    when 'page'
      ['Abrir Marketing → Resultados de tráfego → Otimizar e aplicar os insights da página desta campanha.',
       'Marcar "Fiz à mão" quando a página for republicada.']
    when 'quality'
      ['Ler as conversas dos leads desta campanha (Conversas → filtro por origem).',
       "No #{where}, apertar o público e alinhar o texto do anúncio com o Roteiro.", 'Marcar "Fiz à mão".']
    when 'pacing'
      ['Redistribuir a verba entre as campanhas (subir nas campeãs, reduzir nas piores) ou subir campanha nova pela ficha.',
       'Marcar "Fiz à mão" quando ajustar.']
    else
      ['Só acompanhar: nada a fazer agora.']
    end
  end

  private

  def graph
    @graph ||= Crm::MetaGraph.new(account: @account)
  end

  def fields_for(action)
    case action.kind
    when 'pause' then { status: 'PAUSED' }
    when 'budget_up', 'budget_down'
      to = action.payload['budget_to'].to_f
      to.positive? && action.level == 'adset' ? { daily_budget: (to * 100).round } : nil
    end
  end

  def manual(action)
    { ok: true, mode: 'manual', steps: steps_for(action) }
  end

  def mark_applied!(action, mode)
    action.update!(status: 'applied', applied_at: Time.current, applied_mode: mode, error: nil,
                   decided_by_id: action.decided_by_id || @user&.id)
  end

  def level_label(level)
    { 'campaign' => 'a campanha', 'adset' => 'o conjunto', 'ad' => 'o anúncio', 'channel' => 'o canal' }[level] || 'o item'
  end
end
