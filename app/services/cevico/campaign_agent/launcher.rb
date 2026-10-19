# 🚀 FICHA DE SUBIR CAMPANHA (item 352): a partir de uma ficha curta (nome,
# objetivo, verba diária, público, página ou WhatsApp, anúncios a reaproveitar)
# o agente monta o PLANO — nomes no padrão da casa, sufixo de UTM, estrutura
# campanha → conjunto → anúncios — e, com a chavinha "executar pela API"
# ligada, CRIA tudo PAUSADO na Meta para a pessoa conferir no Gerenciador e
# ligar. Sem a chavinha, a ficha fica guardada com o roteiro de subida.
# As fichas moram em agenda_config['campaign_briefs'] (até MAX).
class Cevico::CampaignAgent::Launcher
  KEY = 'campaign_briefs'.freeze
  MAX = 50
  OBJECTIVES = {
    'leads_whatsapp' => { label: 'Leads pelo WhatsApp (clique no anúncio abre a conversa)', objective: 'OUTCOME_LEADS',
                          optimization_goal: 'CONVERSATIONS', destination_type: 'WHATSAPP' },
    'leads_page' => { label: 'Leads pela página (clique leva à landing page)', objective: 'OUTCOME_LEADS',
                      optimization_goal: 'LINK_CLICKS', destination_type: 'WEBSITE' }
  }.freeze

  def initialize(account:, params: nil, user: nil)
    @account = account
    @params = params || Cevico::CampaignAgent::Params.for(@account)
    @user = user
  end

  def list
    Array((settings.agenda_config || {})[KEY])
  end

  # monta o plano (sem tocar na Meta) e guarda a ficha
  def plan!(raw)
    ficha = clean(raw)
    return { ok: false, error: 'Dê um nome à campanha e uma verba diária.' } if ficha['name'].blank? || ficha['daily_budget'].to_f <= 0

    ficha['plan'] = plan_for(ficha)
    ficha['status'] = 'ficha'
    save!(ficha)
    { ok: true, brief: ficha }
  end

  # cria PAUSADA na Meta (campanha → conjunto → anúncios dos criativos escolhidos)
  def launch!(id) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    ficha = list.find { |b| b['id'] == id.to_s }
    return { ok: false, error: 'Ficha não encontrada.' } if ficha.nil?

    unless @params['execute_api']
      return { ok: false,
               error: 'Ligue "executar pela API" nos parâmetros para criar na Meta; por enquanto siga o roteiro da ficha.' }
    end
    return { ok: false, error: 'Só a Meta por enquanto (o Google entra quando ligarmos a API do Google Ads).' } unless ficha['channel'] == 'meta'

    graph = Crm::MetaGraph.new(account: @account)
    return { ok: false, error: 'Conta de anúncios da Meta não configurada.' } unless graph.configured?

    plan = ficha['plan']
    obj = OBJECTIVES[ficha['objective']]
    campaign, error = graph.create_object('campaigns', { name: plan['campaign_name'], objective: obj[:objective], status: 'PAUSED',
                                                         special_ad_categories: '[]', buying_type: 'AUCTION' })
    return refused(ficha, "campanha: #{error}") if error

    adset, error = graph.create_object('adsets', adset_fields(ficha, plan, obj, campaign['id']))
    return refused(ficha, "conjunto: #{error}") if error

    ads = Array(ficha['creative_ad_ids']).filter_map do |source_ad_id|
      creative = Crm::AdCreative.find_by(account_id: @account.id, ad_id: source_ad_id)
      next if creative.nil? || creative.creative['id'].blank?

      ad, ad_error = graph.create_object('ads', { name: "#{plan['prefix']} · #{creative.ad_name}", adset_id: adset['id'], status: 'PAUSED',
                                                  creative: { creative_id: creative.creative['id'] }.to_json })
      ad_error ? { source: source_ad_id, error: ad_error } : { source: source_ad_id, id: ad['id'] }
    end
    ficha.merge!('status' => 'criada', 'meta' => { 'campaign_id' => campaign['id'], 'adset_id' => adset['id'], 'ads' => ads },
                 'launched_at' => Time.current.iso8601)
    save!(ficha)
    { ok: true, brief: ficha }
  end

  def remove!(id)
    write { |all| all.reject { |b| b['id'] == id.to_s } }
  end

  private

  def refused(ficha, error)
    ficha['error'] = error
    save!(ficha)
    { ok: false, error: "A Meta recusou (#{error}). A ficha ficou guardada com o roteiro para subir à mão." }
  end

  def clean(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    h = (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h).deep_stringify_keys
    {
      'id' => h['id'].presence || SecureRandom.hex(4),
      'channel' => %w[meta google].include?(h['channel']) ? h['channel'] : 'meta',
      'name' => h['name'].to_s.strip[0, 80],
      'objective' => OBJECTIVES.key?(h['objective']) ? h['objective'] : 'leads_whatsapp',
      'daily_budget' => h['daily_budget'].to_s.tr(',', '.').to_f.round(2),
      'page_url' => h['page_url'].to_s.strip[0, 300],
      'whatsapp' => h['whatsapp'].to_s.gsub(/\D/, '')[0, 15],
      'page_id' => h['page_id'].to_s.gsub(/\D/, '')[0, 25],
      'audience' => { 'countries' => Array(h.dig('audience', 'countries')).presence || ['BR'],
                      'age_min' => h.dig('audience', 'age_min').to_i.clamp(18, 65).then { |v| v.zero? ? 25 : v },
                      'age_max' => h.dig('audience', 'age_max').to_i.clamp(18, 65).then { |v| v.zero? ? 65 : v },
                      'cities' => h.dig('audience', 'cities').to_s.strip[0, 200] },
      'creative_ad_ids' => Array(h['creative_ad_ids']).map(&:to_s).compact_blank.first(10),
      'notes' => h['notes'].to_s.strip[0, 1000],
      'created_at' => h['created_at'].presence || Time.current.iso8601,
      'created_by' => @user&.name.to_s
    }
  end

  # o plano: nomes no padrão CV, sufixo de rastreio e o roteiro de subida
  def plan_for(ficha) # rubocop:disable Metrics/AbcSize
    month = Date.current.strftime('%Y-%m')
    slug = I18n.transliterate(ficha['name']).downcase.gsub(/[^a-z0-9]+/, '-').delete_prefix('-').delete_suffix('-')[0, 40]
    prefix = "CV · #{ficha['name']}"
    obj = OBJECTIVES[ficha['objective']]
    monthly = ficha['daily_budget'] * 30
    cap = @params.dig('budget', ficha['channel']).to_f
    {
      'prefix' => prefix,
      'campaign_name' => "#{prefix} · #{obj[:label].split(' (').first} · #{month}",
      'adset_name' => "#{prefix} · #{audience_text(ficha)}",
      'utm' => "utm_source=#{ficha['channel'] == 'meta' ? 'meta' : 'google'}&utm_medium=cpc&utm_campaign=#{slug}&utm_content={{ad.name}}",
      'monthly_estimate' => monthly.round(2),
      'budget_note' => budget_note(monthly, cap),
      'steps' => steps_for(ficha, prefix, month, obj)
    }.compact
  end

  def budget_note(monthly, cap)
    return nil unless cap.positive? && monthly > cap

    "Atenção: R$ #{monthly.round} por mês passa da verba combinada do canal (R$ #{cap.round})."
  end

  def audience_text(ficha)
    aud = ficha['audience']
    "#{aud['cities'].presence || aud['countries'].join('+')} · #{aud['age_min']}-#{aud['age_max']}"
  end

  def steps_for(ficha, prefix, month, obj)
    aud = ficha['audience']
    budget = format('%.2f', ficha['daily_budget']).tr('.', ',')
    place = aud['cities'].present? ? " (#{aud['cities']})" : ''
    creatives = if ficha['creative_ad_ids'].any?
                  "#{ficha['creative_ad_ids'].size} criativo(s) reaproveitado(s) da Central"
                else
                  'subir as peças do núcleo criativo (nomes CV-0xx)'
                end
    [
      "Campanha: #{obj[:label]} · nome \"#{prefix} · … · #{month}\" · PAUSADA ao criar.",
      "Conjunto: verba diária R$ #{budget} · público #{aud['countries'].join('+')}#{place} · #{aud['age_min']} a #{aud['age_max']} anos.",
      destination_text(ficha),
      "Anúncios: #{creatives}; UTM utm_content={{ad.name}}.",
      'Conferir no Gerenciador, ligar, e o agente passa a acompanhar na próxima leitura.'
    ]
  end

  def destination_text(ficha)
    if ficha['objective'] == 'leads_whatsapp'
      "Destino: WhatsApp #{ficha['whatsapp'].presence || '(informar o número)'} com a mensagem pronta e o Protocolo."
    else
      "Destino: #{ficha['page_url'].presence || '(informar a página)'} com o sufixo de rastreio."
    end
  end

  def adset_fields(ficha, plan, obj, campaign_id)
    aud = ficha['audience']
    targeting = { geo_locations: { countries: aud['countries'] }, age_min: aud['age_min'], age_max: aud['age_max'] }
    fields = { name: plan['adset_name'], campaign_id: campaign_id, status: 'PAUSED', daily_budget: (ficha['daily_budget'] * 100).round,
               billing_event: 'IMPRESSIONS', optimization_goal: obj[:optimization_goal], destination_type: obj[:destination_type],
               targeting: targeting.to_json, start_time: Time.current.iso8601 }
    if ficha['objective'] == 'leads_whatsapp' && ficha['page_id'].present?
      fields[:promoted_object] = { page_id: ficha['page_id'], whatsapp_phone_number: ficha['whatsapp'] }.compact.to_json
    end
    fields
  end

  def settings
    @settings ||= CrmSetting.find_or_create_by!(account: @account)
  end

  def save!(ficha)
    write do |all|
      rest = all.reject { |b| b['id'] == ficha['id'] }
      [ficha] + rest.first(MAX - 1)
    end
  end

  def write
    Cevico::SettingMerge.merge!(settings, :agenda_config) { |cfg| cfg.merge(KEY => yield(Array(cfg[KEY]).map(&:dup))) }
    list
  end
end
