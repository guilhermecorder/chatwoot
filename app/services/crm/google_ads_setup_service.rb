# 🎯 item 371 (27/10): PREPARA a conta do Google Ads para receber as
# conversões do CRM — cria (uma vez) uma ação de conversão por ETAPA do
# funil e as variáveis personalizadas `procedimento` e `pagina`, e guarda
# os endereços em google_ads_config. Rodar de novo só confere e completa o
# que faltar (nunca duplica: procura pelo nome antes de criar).
#
# Por que UMA ação por etapa e o procedimento em variável (não uma ação por
# procedimento): o Google Ads aprende com volume — 5 ações cheias ensinam
# mais que 25 vazias; a variável deixa o gestor segmentar o relatório por
# procedimento e, se quiser, criar regra de valor por ela.
class Crm::GoogleAdsSetupService
  ACTION_PREFIX = 'CEVICO · '.freeze

  # etapa do funil → o que a ação de conversão é para o Google
  ACTIONS = {
    'lead_whatsapp' => { name: 'Lead chegou no WhatsApp', category: 'CONTACT', counting: 'ONE_PER_CLICK' },
    'orcamento_enviado' => { name: 'Recebeu orçamento', category: 'REQUEST_QUOTE', counting: 'ONE_PER_CLICK' },
    'agendou_consulta' => { name: 'Agendou consulta', category: 'BOOK_APPOINTMENT', counting: 'ONE_PER_CLICK' },
    'compareceu_consulta' => { name: 'Compareceu à consulta', category: 'QUALIFIED_LEAD', counting: 'ONE_PER_CLICK' },
    'fechou_cirurgia' => { name: 'Fechou cirurgia', category: 'PURCHASE', counting: 'MANY_PER_CLICK' }
  }.freeze

  # variáveis personalizadas da conversão (tag = como viaja na API)
  VARIABLES = { 'procedimento' => 'Procedimento', 'pagina' => 'Página de origem' }.freeze

  # janela de clique máxima que o Google deixa para conversão importada:
  # cirurgia fecha semanas depois do clique
  LOOKBACK_DAYS = 90

  def initialize(account)
    @account = account
  end

  def call
    settings = CrmSetting.find_by(account: @account)
    cfg = settings&.google_ads_config || {}
    api = Cevico::GoogleAdsApi.new(cfg)
    unless api.configured?
      return { success: false,
               error: 'Faltam dados do Google Ads (developer token, ID da conta e acesso OAuth ou conta de serviço)' }
    end

    actions = ensure_actions(api)
    return failure(api) if actions.nil?

    variables = ensure_variables(api)
    return failure(api) if variables.nil?

    save!(settings, actions, variables)
    { success: true, actions: actions, variables: variables, created: @created }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  private

  def failure(api)
    { success: false, error: api.last_error.presence || 'O Google Ads não respondeu' }
  end

  # ações de conversão do tipo "importação de cliques" que já existem
  def ensure_actions(api)
    rows = api.search('SELECT conversion_action.resource_name, conversion_action.name, conversion_action.status ' \
                      "FROM conversion_action WHERE conversion_action.type = 'UPLOAD_CLICKS'")
    return nil if rows.nil?

    existing = rows.to_h { |r| [r.dig('conversionAction', 'name').to_s, r.dig('conversionAction', 'resourceName')] }
    @created = []
    ACTIONS.to_h do |event, spec|
      name = ACTION_PREFIX + spec[:name]
      resource = existing[name] || existing[spec[:name]] || create_action(api, name, spec)
      return nil if resource.nil?

      [event, resource]
    end
  end

  def create_action(api, name, spec)
    action = { name: name, type: 'UPLOAD_CLICKS', category: spec[:category], status: 'ENABLED', countingType: spec[:counting],
               clickThroughLookbackWindowDays: LOOKBACK_DAYS, valueSettings: { defaultValue: 0, alwaysUseDefaultValue: false } }
    response = api.mutate_conversion_actions([{ create: action }])
    resource = response&.dig('results', 0, 'resourceName')
    @created << name if resource.present?
    resource
  end

  def ensure_variables(api)
    rows = api.search('SELECT conversion_custom_variable.resource_name, conversion_custom_variable.tag, ' \
                      'conversion_custom_variable.status FROM conversion_custom_variable')
    return nil if rows.nil?

    existing = rows.to_h { |r| [r.dig('conversionCustomVariable', 'tag').to_s, r.dig('conversionCustomVariable', 'resourceName')] }
    VARIABLES.to_h do |tag, label|
      resource = existing[tag] || create_variable(api, tag, label)
      return nil if resource.nil?

      [tag, resource]
    end
  end

  def create_variable(api, tag, label)
    response = api.mutate_conversion_custom_variables([{ create: { name: label, tag: tag, status: 'ENABLED' } }])
    resource = response&.dig('results', 0, 'resourceName')
    @created << "variável #{tag}" if resource.present?
    resource
  end

  # grava sob trava, só as chaves do preparo (o sent_log e o resto não são tocados)
  def save!(settings, actions, variables)
    Cevico::SettingMerge.merge!(settings, :google_ads_config) do |cfg|
      cfg.merge('ads_conversion_actions' => actions, 'ads_custom_variables' => variables,
                'ads_prepared_at' => Time.current.iso8601, 'ads_last_error' => nil)
    end
  end
end
