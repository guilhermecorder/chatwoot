# 👓 PREPARO DA ÓTICA: monta numa conta a estrutura de config/otica/preparo.yml
# (funis e colunas, Agenda ligada às colunas, os 3 atendentes, etiqueta,
# Jornada do pós-venda) e, se vier, o CONTEÚDO exportado da bancada (roteiro
# das 6 seções, texto de cada atendente, textos da Jornada).
#
# Idempotente: tudo é achado pelo NOME; rodar de novo não duplica, só acerta.
# Nunca apaga funil, coluna, card, mensagem ou agente. Agente que já existe
# mantém o modo (não volta para sombra); agente novo nasce em sombra.
# Coluna que o dono renomeou na tela vira coluna nova na próxima rodada —
# por isso a receita manda rodar UMA vez na instalação e depois mexer pela tela.
class Otica::Preparo
  STRUCTURE = Rails.root.join('config/otica/preparo.yml')
  AGENT_BASE = { 'mode' => 'shadow', 'model' => '', 'effort' => '', 'enabled' => true, 'inbox_ids' => [],
                 'live_days' => [], 'hours_start' => '', 'hours_end' => '', 'shadow_daily_cap' => 30,
                 'reply_delay_seconds' => 6 }.freeze
  SCRIPT_KEYS = %w[persona form_rules official_data objections handoff doctor_videos].freeze

  attr_reader :lines

  def initialize(account, content: nil, dry: false)
    @account = account
    @content = content&.deep_stringify_keys
    @dry = dry
    @spec = YAML.safe_load_file(STRUCTURE)
    @lines = []
    @stages = {}
  end

  def call
    ActiveRecord::Base.transaction do
      company!
      funnels!
      agenda!
      agents!
      labels!
      journey!
      raise ActiveRecord::Rollback if @dry
    end
    Crm::Sources.forget!(@account) unless @dry
    @lines.unshift(@dry ? 'MODO DE TESTE (DRY=1): nada foi gravado.' : "Conta #{@account.id} \"#{@account.name}\" preparada.")
    self
  end

  private

  def company!
    company = Cevico::Company.for(@account)
    return if company.segment == 'otica'

    Cevico::Company.save!(@account, 'segment' => 'otica', 'name' => @account.name)
    @lines << 'Identidade da empresa: ramo ótica (vocabulário de cliente, óculos e loja).'
  end

  def funnels! # rubocop:disable Metrics/AbcSize
    @spec['funis'].each_with_index do |f, pos|
      pipeline = Crm::Pipeline.find_or_initialize_by(account_id: @account.id, name: f['nome'])
      novo = pipeline.new_record?
      pipeline.description = f['descricao']
      pipeline.position = pos
      pipeline.save!
      criadas = 0
      f['colunas'].each_with_index do |(nome, cor), i|
        stage = pipeline.stages.find_or_initialize_by(name: nome)
        criadas += 1 if stage.new_record?
        stage.color = cor
        stage.position = i
        stage.settings ||= {}
        stage.save!
        @stages[nome] = stage
      end
      @lines << "Funil \"#{f['nome']}\" #{novo ? 'criado' : 'conferido'} (#{criadas} coluna(s) nova(s) de #{f['colunas'].size})."
    end
  end

  def stage_id(name)
    @stages.fetch(name) { raise ArgumentError, "Coluna \"#{name}\" não está nos funis do preparo.yml." }.id
  end

  def setting
    @setting ||= CrmSetting.find_or_create_by!(account: @account)
  end

  def agenda!
    cfg = (setting.agenda_config || {}).deep_dup
    @spec['agenda'].each do |group, map|
      cfg[group] = (cfg[group] || {}).merge(map.transform_values { |name| stage_id(name) })
    end
    setting.update!(agenda_config: cfg)
    @lines << 'Agenda ligada às colunas (agendamento, confirmada, orçamento, compareceu, faltou).'
  end

  def agents! # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    cfg = (setting.ai_config || {}).deep_dup
    agents = cfg['agents'] || {}
    prompts = @content&.dig('prompts') || {}
    @spec['agentes'].each do |key, a|
      current = agents[key]
      agent = current ? current.dup : AGENT_BASE.dup
      agent['stage_ids'] = a['colunas'].map { |n| stage_id(n) }
      agent['no_card'] = true if a['sem_card']
      agent['after_booking_stage_id'] = stage_id(a['depois_de_agendar']) if a['depois_de_agendar']
      agent['recent_surgery_days'] = a['dias_pos_compra'] if a.key?('dias_pos_compra')
      agent['prompt'] = prompts[key] if prompts[key].present?
      agents[key] = agent
      @lines << "Atendente #{key}: #{current ? "mantido em #{agent['mode']}" : 'criado em modo sombra'}, " \
                "#{agent['stage_ids'].size} coluna(s)#{prompts[key].present? ? ', texto da etapa do arquivo' : ''}."
    end
    cfg['agents'] = agents
    script = @content&.dig('script')&.slice(*SCRIPT_KEYS)
    if script.present?
      cfg['script'] = (cfg['script'] || {}).merge(script).merge('updated_at' => Time.current.iso8601)
      @lines << "Roteiro: #{script.size} de #{SCRIPT_KEYS.size} seções gravadas do arquivo."
    elsif cfg.dig('script', 'persona').present?
      @lines << 'Roteiro: sem arquivo; o roteiro que já estava na conta foi mantido.'
    else
      @lines << 'Roteiro: sem arquivo de conteúdo (os atendentes ficam com o roteiro padrão até você colar o da loja).'
    end
    setting.update!(ai_config: cfg)
  end

  def labels!
    @spec['etiquetas'].each do |title, color, description|
      @account.labels.find_or_create_by!(title: title) do |l|
        l.color = color
        l.description = description
      end
    end
    @lines << "Etiqueta(s): #{@spec['etiquetas'].map(&:first).join(', ')}."
  end

  def journey! # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    texts = @content&.dig('journey') || {}
    novas = 0
    @spec['jornada'].each_with_index do |j, i|
      g = j['gatilho']
      trigger = if g['coluna']
                  { 'kind' => 'stage', 'stage_id' => stage_id(g['coluna']), 'offset_days' => g['dias'], 'at' => g['hora'] }
                else
                  { 'kind' => 'label', 'label' => g['etiqueta'], 'offset_days' => g['dias'], 'at' => g['hora'] }
                end
      message = Crm::JourneyMessage.find_or_initialize_by(account: @account, name: j['nome'])
      novas += 1 if message.new_record?
      text = texts[j['nome']].presence || (message.persisted? ? message.content&.dig('text') : nil) || j['texto']
      attrs = { step: j['etapa'], trigger: trigger, position: i, content: { 'mode' => 'text', 'text' => text },
                expects_reply: j['espera_resposta'] == true, confirm_label: j['etiqueta_confirmou'] }
      # nova: nasce com aprovação manual, ativa e respeitando o silêncio; existente mantém o que o dono escolheu
      attrs.merge!(active: true, audience: {}, approval: 'review', decline_alert: true, respect_quiet: true) if message.new_record?
      message.assign_attributes(attrs)
      message.save!
    end
    fonte = if texts.any?
              'textos do arquivo'
            elsif novas.zero?
              'textos atuais mantidos'
            else
              'textos neutros nas novas (troque pelos da loja)'
            end
    @lines << "Jornada do pós-venda: #{@spec['jornada'].size} mensagem(ns), #{novas} nova(s), #{fonte}, aprovação manual."
  end
end
