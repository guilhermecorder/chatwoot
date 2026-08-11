# 🎨 CRIATIVO PERPÉTUO (item 131): toda semana, encontra os VENCEDORES reais
# (termos do Google e anúncios do Meta que mais viraram consulta/cirurgia na
# jornada do banco — não em métrica de plataforma) e gera variações de copy
# para o Guilherme só APROVAR. O resultado de ontem escreve o anúncio de
# amanhã, sem ninguém pedir.
#
# Estado em ai_config['creative_state']:
#   { 'week_key' => '2026-08-10', 'generated_at' =>, 'winners' => [
#       { 'kind' => 'google_term'|'meta_ad', 'name' =>, 'stats' => {...},
#         'variations' => [{ 'angulo','gancho','texto','cta','status' }] }],
#     'approved_log' => [últimos aprovados p/ o estúdio] }
class Crm::CreativeService
  include Crm::AiAgentConfig

  AGENT_KEY = 'creative'.freeze
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']

  LOOKBACK_DAYS = 90
  DEFAULT_WINNERS = 3
  DEFAULT_VARIATIONS = 3
  APPROVED_LOG_CAP = 100

  SYSTEM_PROMPT = <<~PROMPT.freeze
    Você é o Criativo Perpétuo de uma clínica oftalmológica high-ticket:
    copywriter de resposta direta que só escreve variações de VENCEDORES
    comprovados. Você recebe um vencedor (termo de pesquisa do Google ou
    anúncio do Meta) com os números reais da jornada (leads → consultas →
    cirurgias) e as objeções reais dos pacientes. Gere variações de anúncio
    seguindo as regras da casa:
    - 1 frase por linha, frases curtas, alto contraste emocional;
    - gancho (headline) com no máximo 40 caracteres;
    - texto primário com no máximo 350 caracteres, terminando em CTA claro;
    - rapport primeiro (a dor/desejo real do paciente), oferta depois;
    - proibido prometer resultado médico garantido, proibido "digite";
    - tom: tecnologia de ponta, acolhimento humano e clareza visual;
    - cada variação ataca um ÂNGULO diferente (dor, desejo, prova, objeção).
    Escreva em português do Brasil, natural e específico — nada genérico.
  PROMPT

  OUTPUT_SCHEMA = {
    type: 'object',
    properties: {
      variations: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            angulo: { type: 'string', description: 'ângulo da variação (dor, desejo, prova, objeção…)' },
            gancho: { type: 'string', description: 'headline, máx 40 caracteres' },
            texto: { type: 'string', description: 'texto primário, máx 350 caracteres, 1 frase por linha' },
            cta: { type: 'string', description: 'chamada final curta' }
          },
          required: %w[angulo gancho texto cta]
        }
      }
    },
    required: ['variations']
  }.freeze

  def initialize(account:)
    @account = account
  end

  attr_reader :account

  def call(force: false)
    return { skipped: 'desligado' } if agent_paused?
    return { skipped: 'sem chave de IA' } if api_key.blank?
    return { skipped: 'semana já gerada' } if !force && state['week_key'] == week_key

    winners = collect_winners
    return { skipped: 'sem vencedores com jornada no período' } if winners.empty?

    winners.each do |winner|
      winner['variations'] = generate_variations(winner)
    end
    winners.reject! { |w| w['variations'].empty? }
    return { error: 'a geração de variações falhou para todos os vencedores' } if winners.empty?

    write_state(
      'week_key' => week_key,
      'generated_at' => Time.current.iso8601,
      'winners' => winners,
      'approved_log' => Array(state['approved_log'])
    )
    create_approval_task(winners)
    { ok: true, winners: winners.size, variations: winners.sum { |w| w['variations'].size } }
  end

  # aprovar/recusar uma variação (tela): aprovadas entram no approved_log —
  # a despensa do Estúdio Criativo
  def review!(winner_index, variation_index, status, user)
    return { error: 'Status inválido.' } unless %w[approved rejected].include?(status)

    settings = CrmSetting.find_by(account: account)
    result = nil
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      st = ai['creative_state'] || {}
      variation = st.dig('winners', winner_index.to_i, 'variations', variation_index.to_i)
      next result = { error: 'Variação não encontrada.' } unless variation

      variation['status'] = status
      variation['reviewed_by'] = user&.name
      if status == 'approved'
        winner = st['winners'][winner_index.to_i]
        st['approved_log'] = ([{
          'week_key' => st['week_key'],
          'source' => winner['name'],
          'kind' => winner['kind'],
          'gancho' => variation['gancho'],
          'texto' => variation['texto'],
          'cta' => variation['cta'],
          'approved_at' => Time.current.iso8601
        }] + Array(st['approved_log'])).first(APPROVED_LOG_CAP)
      end
      ai['creative_state'] = st
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
      result = { ok: true, status: status }
    end
    @ai_config = nil
    result
  end

  def state
    (ai_config || {})['creative_state'] || {}
  end

  # segunda-feira da semana corrente (SP) — chave de idempotência
  def week_key
    today = TZ.today
    (today - ((today.wday + 6) % 7)).iso8601
  end

  private

  # ── VENCEDORES: jornada real do banco, 90 dias ────────────────────────
  def collect_winners
    top = config_int('winners_count', DEFAULT_WINNERS).clamp(1, 6)
    since = LOOKBACK_DAYS.days.ago

    rows = google_term_rows(since) + meta_ad_rows(since)
    rows.sort_by { |r| [-r['stats']['surgeries'], -r['stats']['attended'], -r['stats']['booked'], -r['stats']['leads']] }
        .first(top)
  end

  def google_term_rows(since)
    leads = account.contacts
                   .where("additional_attributes -> 'page_ads' ->> 'source' = 'google_ads'")
                   .where("(additional_attributes -> 'page_ads' ->> 'captured_at')::timestamptz >= ?", since)
                   .pluck(:id, Arel.sql("additional_attributes -> 'page_ads' ->> 'utm_term'"))
    grouped = leads.select { |_id, term| term.present? }.group_by { |_id, term| term }
    build_rows(grouped, 'google_term', 'termo do Google')
  end

  def meta_ad_rows(since)
    leads = account.contacts
                   .where("additional_attributes -> 'meta_ads' ->> 'ad_name' IS NOT NULL")
                   .where('contacts.created_at >= ?', since)
                   .pluck(:id, Arel.sql("additional_attributes -> 'meta_ads' ->> 'ad_name'"))
    grouped = leads.select { |_id, name| name.present? }.group_by { |_id, name| name }
    build_rows(grouped, 'meta_ad', 'anúncio do Meta')
  end

  def build_rows(grouped, kind, kind_label)
    all_ids = grouped.values.flatten(1).map(&:first)
    return [] if all_ids.empty?

    booked = account.tasks.where(task_type: 'consulta', contact_id: all_ids).distinct.pluck(:contact_id).to_set
    attended = account.tasks.where(task_type: 'consulta', attendance: 'attended', contact_id: all_ids)
                      .distinct.pluck(:contact_id).to_set
    converted = converted_values(all_ids)

    grouped.filter_map do |name, pairs|
      ids = pairs.map(&:first)
      stats = {
        'leads' => ids.size,
        'booked' => ids.count { |id| booked.include?(id) },
        'attended' => ids.count { |id| attended.include?(id) },
        'surgeries' => ids.count { |id| converted.key?(id) },
        'revenue' => ids.sum { |id| converted[id].to_f }.round(2)
      }
      # vencedor precisa de jornada de verdade: pelo menos 1 consulta marcada
      next if stats['booked'].zero?

      { 'kind' => kind, 'kind_label' => kind_label, 'name' => name.to_s.truncate(120), 'stats' => stats }
    end
  end

  # mesma régua do dashboard Google: chegou numa etapa de cirurgia = fechou
  def surgery_stage_ids
    @surgery_stage_ids ||= begin
      base = Crm::Stage.joins(:pipeline)
                       .where(crm_pipelines: { account_id: account.id })
                       .where('crm_stages.name ILIKE ?', '%cirurgia%')
      strict = base.where.not('crm_stages.name ILIKE ?', '%indica%').pluck(:id)
      strict.any? ? strict : base.pluck(:id)
    end
  end

  def converted_values(contact_ids)
    return {} if contact_ids.empty? || surgery_stage_ids.empty?

    cards = Crm::Contact.joins(:pipeline)
                        .where(crm_pipelines: { account_id: account.id })
                        .where(contact_id: contact_ids)
    converted_ids = cards.where(stage_id: surgery_stage_ids).pluck(:id) |
                    Crm::StageLog.where(crm_contact_id: cards.select(:id), stage_id: surgery_stage_ids)
                                 .pluck(:crm_contact_id)
    cards.where(id: converted_ids).pluck(:contact_id, :value).to_h
  end

  # ── GERAÇÃO ───────────────────────────────────────────────────────────
  def generate_variations(winner)
    count = config_int('variations_count', DEFAULT_VARIATIONS).clamp(1, 5)
    stats = winner['stats']
    prompt = <<~TXT
      VENCEDOR (#{winner['kind_label']}): "#{winner['name']}"
      Jornada real (últimos #{LOOKBACK_DAYS} dias): #{stats['leads']} leads →
      #{stats['booked']} consultas marcadas → #{stats['attended']} compareceram →
      #{stats['surgeries']} cirurgias (R$ #{stats['revenue'].to_i}).
      #{objections_block}
      Gere #{count} variações de anúncio para escalar este vencedor.
    TXT

    message = client.messages.create(
      model: model, max_tokens: 2048, system_: system_prompt,
      output_config: output_config_for({ type: 'json_schema', schema: OUTPUT_SCHEMA }),
      messages: [{ role: 'user', content: prompt }]
    )
    record_usage(message)
    parsed = JSON.parse(message.content.find { |b| b.type == :text }&.text || '{}')
    Array(parsed['variations']).first(count).map do |v|
      {
        'angulo' => v['angulo'].to_s.truncate(40),
        'gancho' => v['gancho'].to_s.truncate(60),
        'texto' => v['texto'].to_s.truncate(500),
        'cta' => v['cta'].to_s.truncate(60),
        'status' => 'pending'
      }
    end
  rescue StandardError => e
    Rails.logger.error("[Criativo] geração falhou conta=#{account.id} vencedor=#{winner['name']}: #{e.message}")
    []
  end

  # objeções REAIS do Mapa de Objeções (Consultor Comercial), quando existem
  def objections_block
    map = (ai_config.dig('agents', 'sales', 'objection_map') || {})
    items = Array(map['objections'] || map['items']).first(4)
    return '' if items.blank?

    lines = items.map do |o|
      texto = o['objecao'] || o['objection'] || o['title'] || o.to_s
      "- #{texto.to_s.truncate(100)}"
    end
    "Objeções reais dos pacientes (use nos ângulos de objeção):\n#{lines.join("\n")}"
  end

  def create_approval_task(winners)
    total = winners.sum { |w| w['variations'].size }
    title = "🎨 Criativos da semana prontos — #{total} variações de #{winners.size} vencedores p/ aprovar (#{TZ.today.strftime('%d/%m')})"
    return if account.tasks.where(title: title).exists?

    account.tasks.create!(
      title: title,
      description: 'O Criativo Perpétuo encontrou os vencedores da semana (jornada real: consultas e cirurgias) ' \
                   'e escreveu variações para escalar. Revise e aprove em Automações → Agentes → Criativo Perpétuo.',
      task_type: 'gestao', priority: :medium, status: :todo,
      due_at: 3.days.from_now,
      creator: account.administrators.first
    )
  rescue StandardError => e
    Rails.logger.error("[Criativo] tarefa falhou conta=#{account.id}: #{e.message}")
  end

  def config_int(key, default)
    v = agent_config[key].to_i
    v.positive? ? v : default
  end

  def write_state(new_state)
    settings = CrmSetting.find_by(account: account)
    settings.with_lock do
      ai = (settings.reload.ai_config || {}).deep_dup
      ai['creative_state'] = new_state
      settings.update_column(:ai_config, ai) # rubocop:disable Rails/SkipsModelValidations
    end
    @ai_config = nil
  end
end
