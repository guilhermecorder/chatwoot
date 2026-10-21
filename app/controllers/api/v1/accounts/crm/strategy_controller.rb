# Painel Estratégico CEVICO (só admin): a empresa por pilares — cada um com
# responsáveis, semáforo de saúde, nota de desempenho e as estratégias/ações
# corretivas (dono, prazo, andamento). Os 3 pilares combinados nascem
# prontos na primeira visita.
class Api::V1::Accounts::Crm::StrategyController < Api::V1::Accounts::BaseController # rubocop:disable Metrics/ClassLength
  include Crm::AccessControl

  def show
    CevicoPillar.seed_defaults!(account)
    render json: board_json.merge(processes: processes_list, business: business_board, metrics: business_metrics)
  end

  # ── 🧭 PAINEL DO EMPRESÁRIO: o quadro de gestão do dono (kanban pessoal,
  # continuar/parar/começar, matrizes de prioridade e oportunidade, pessoas
  # estratégicas, objetivos do ano e problemas → solução). Só admin vê e
  # salva — é a mesa de trabalho do empresário, não do time. ──
  def save_business_board
    return render json: { error: 'Só administradores mexem no Painel do Empresário.' }, status: :forbidden unless Current.account_user.administrator?

    # Rodada 4 (#413/#414): grava só a chave business_board, sob trava. A tela
    # manda `version` (o updated_at do quadro que ela carregou); se o quadro
    # gravado for mais novo, recusa com 409 e devolve o quadro atual — quem
    # salvou por último perde o que digitou naquele instante, mas NÃO apaga
    # o que o outro escreveu (duas abas / dois administradores).
    # A tela nova SEMPRE manda a chave `version` (mesmo vazia: quadro antigo,
    # ainda sem updated_at). Por isso a conferência olha a PRESENÇA da chave:
    # versão vazia × quadro já versionado também é conflito (duas abas abertas
    # antes do 1º save novo). Só a tela de antes desta rodada (sem a chave)
    # grava sem conferir.
    check_version = params.key?(:version)
    base_version = params[:version].to_s
    conflict = nil
    saved = Cevico::SettingMerge.merge_key!(crm_settings, :agenda_config, 'business_board') do |current|
      if check_version && current['updated_at'].to_s != base_version
        conflict = current
        next current
      end
      sanitize_business_board.merge('updated_at' => Time.current.iso8601(6)) # microssegundos: dois saves no mesmo segundo ≠ mesma versão
    end
    if conflict
      return render json: { error: 'Alguém salvou o quadro depois de você. Recarreguei o quadro atual — confira e refaça a sua mudança.',
                            conflict: true, business: conflict }, status: :conflict
    end

    render json: { business: saved }
  end

  # ── 🏭 DESENHO DO PROCESSO (item 59): a máquina da clínica, etapa a
  # etapa, com responsável e PASSE DE BASTÃO — o time inteiro entende o
  # processo como o Guilherme entende. Admin desenha; todos veem. ──
  def save_processes
    return render json: { error: 'Só administradores desenham processos.' }, status: :forbidden unless Current.account_user.administrator?

    # Rodada 4 (#413): grava só esta chave, sob trava — nunca a coluna inteira
    list = sanitize_processes
    Cevico::SettingMerge.merge!(crm_settings, :agenda_config) { |cfg| cfg.merge('process_designs' => list) }
    render json: { processes: list }
  end

  def create_pillar
    pillar = account.cevico_pillars.create!(
      pillar_params.merge(position: (account.cevico_pillars.maximum(:position) || -1) + 1)
    )
    render json: pillar_json(pillar)
  end

  def update_pillar
    pillar = account.cevico_pillars.find(params[:pillar_id])
    pillar.update!(pillar_params)
    render json: pillar_json(pillar)
  end

  def delete_pillar
    account.cevico_pillars.find(params[:pillar_id]).destroy!
    head :ok
  end

  def create_item
    pillar = account.cevico_pillars.find(params[:pillar_id])
    item = pillar.strategies.create!(
      item_params.merge(account: account,
                        position: (pillar.strategies.maximum(:position) || -1) + 1)
    )
    render json: item_json(item)
  end

  def update_item
    item = account.cevico_strategies.find(params[:item_id])
    item.update!(item_params)
    render json: item_json(item)
  end

  def delete_item
    account.cevico_strategies.find(params[:item_id]).destroy!
    head :ok
  end

  private

  def account
    Current.account
  end

  def crm_settings
    @crm_settings ||= CrmSetting.find_or_create_by!(account: account)
  end

  # a jornada padrão nasce pronta na primeira visita — o conteúdo vem do
  # SEGMENTO (config/segmentos/<id>.yml → jornada; preset clínica = a
  # jornada do paciente de sempre)
  def default_process
    jornada = Segmento.jornada
    {
      'id' => jornada['id'] || 'jornada-padrao',
      'name' => jornada['nome'] || 'Jornada do cliente (padrão)',
      'emoji' => jornada['emoji'] || '🧭',
      'steps' => Array(jornada['etapas']).map do |etapa|
        { 'id' => etapa['id'], 'title' => etapa['titulo'], 'desc' => etapa['desc'],
          'owner_id' => nil, 'handoff' => etapa['handoff'] }
      end
    }
  end

  def processes_list
    list = (crm_settings.agenda_config || {})['process_designs']
    list.is_a?(Array) && list.any? ? list : [default_process]
  end

  def sanitize_processes # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    Array(params[:processes]).first(12).filter_map do |proc_raw|
      next if proc_raw[:name].blank?

      {
        'id' => proc_raw[:id].presence || SecureRandom.hex(4),
        'name' => proc_raw[:name].to_s[0, 120],
        'emoji' => proc_raw[:emoji].to_s[0, 8].presence || '🏭',
        'steps' => Array(proc_raw[:steps]).first(20).filter_map do |s|
          next if s[:title].blank?

          { 'id' => s[:id].presence || SecureRandom.hex(4),
            'title' => s[:title].to_s[0, 120],
            'desc' => s[:desc].to_s[0, 1000],
            'owner_id' => s[:owner_id].presence&.to_i,
            'handoff' => s[:handoff].to_s[0, 500] }
        end
      }
    end
  end

  # o quadro só existe para o admin; para o resto do time nem trafega
  def business_board
    return nil unless Current.account_user.administrator?

    board = (crm_settings.agenda_config || {})['business_board']
    board.is_a?(Hash) ? board : {}
  end

  BUSINESS_LISTS = { 'kanban' => %w[todo doing done], 'spc' => %w[continuar parar comecar],
                     'priorities' => %w[do schedule delegate drop], 'opportunities' => %w[first plan fit avoid] }.freeze
  # 27/09 (ambiente próprio): tudo nasce com data e pode ser ATUALIZADO (avanço,
  # conquista, pivô, ajuste) — o histórico fica no item e na linha do tempo
  ITEM_STATUSES = %w[aberto conquistado pivotado pausado].freeze
  HISTORY_KINDS = %w[criado acao conquista pivot ajuste concluido].freeze
  EVENT_KINDS = %w[criado acao conquista pivot ajuste concluido radar marco].freeze
  CARD_ID = /\A[a-z0-9_:-]{1,40}\z/
  RADAR_KEY = /\A[a-z0-9_]{1,24}\z/

  def sanitize_business_board # rubocop:disable Metrics/AbcSize
    raw = params[:business].presence || ActionController::Parameters.new
    board = BUSINESS_LISTS.to_h do |section, keys|
      [section, keys.index_with { |k| sanitize_board_items(raw.dig(section, k)) }]
    end
    %w[objectives goals activities].each { |k| board[k] = sanitize_year_items(raw[k]) }
    board.merge('people' => sanitize_people(raw[:people]), 'problems' => sanitize_problems(raw[:problems]),
                'core_activities' => sanitize_core_activities(raw[:core_activities]), 'estimates' => sanitize_estimates(raw[:estimates]),
                'layout' => sanitize_layout(raw[:layout]), 'radar' => sanitize_radar(raw[:radar]),
                'events' => sanitize_events(raw[:events]), 'locked' => ActiveModel::Type::Boolean.new.cast(raw[:locked]) == true)
  end

  def stamp(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)&.iso8601
  rescue ArgumentError, TypeError
    nil
  end

  # data de criação, última atualização, situação e histórico de cada anotação
  def item_meta(item)
    {
      'created_at' => stamp(item[:created_at]) || Time.current.iso8601,
      'updated_at' => stamp(item[:updated_at]),
      'status' => ITEM_STATUSES.include?(item[:status].to_s) ? item[:status].to_s : nil,
      'area' => item[:area].to_s[0, 40].presence,
      'history' => sanitize_history(item[:history]).presence
    }.compact
  end

  def sanitize_history(list)
    Array(list).last(20).filter_map do |h|
      next unless h.respond_to?(:[])

      kind = HISTORY_KINDS.include?(h[:kind].to_s) ? h[:kind].to_s : 'ajuste'
      { 'at' => stamp(h[:at]) || Time.current.iso8601, 'kind' => kind, 'note' => h[:note].to_s[0, 300] }
    end
  end

  # objetivos/metas/atividades: antes eram 5 textos soltos; agora anotações com
  # data e, nos objetivos, os campos SMART (measure/achievable/realistic/due)
  def sanitize_year_items(list) # rubocop:disable Metrics/AbcSize
    Array(list).first(8).filter_map do |item|
      if item.is_a?(String)
        next if item.blank?

        { 'id' => SecureRandom.hex(4), 'text' => item[0, 200], 'created_at' => Time.current.iso8601 }
      else
        next if item[:text].blank?

        { 'id' => item[:id].presence || SecureRandom.hex(4), 'text' => item[:text].to_s[0, 300],
          'measure' => item[:measure].to_s[0, 160].presence, 'achievable' => item[:achievable].to_s[0, 300].presence,
          'realistic' => item[:realistic].to_s[0, 300].presence, 'due' => item[:due].to_s[0, 10].presence }.compact.merge(item_meta(item))
      end
    end
  end

  # 27/09: atividades principais da empresa (ultra específicas; quantas quiser)
  def sanitize_core_activities(list)
    Array(list).first(20).filter_map do |a|
      next if a[:text].blank?

      { 'id' => a[:id].presence || SecureRandom.hex(4), 'text' => a[:text].to_s[0, 400], 'why' => a[:why].to_s[0, 300],
        'owner' => a[:owner].to_s[0, 60], 'cadence' => a[:cadence].to_s[0, 20] }.merge(item_meta(a))
    end
  end

  # estimativas do dono para as Métricas (faturamento, cirurgias, custo) + fonte escolhida
  def sanitize_estimates(raw)
    return {} unless raw.respond_to?(:[])

    { 'source' => %w[oftalmofacil financeiro estimativa].include?(raw[:source].to_s) ? raw[:source].to_s : 'oftalmofacil',
      'faturamento' => raw[:faturamento].to_s[0, 20], 'cirurgias' => raw[:cirurgias].to_s[0, 10], 'custo' => raw[:custo].to_s[0, 20],
      'updated_at' => stamp(raw[:updated_at]) }.compact
  end

  # 27/09: números do OFTALMOFÁCIL para as Métricas — só cirurgias da CEVICO
  # (parceiros do hub ficam fora), mês atual: realizadas (faturamento = soma
  # do valor), ainda agendadas, ticket médio
  MONTHS_PT = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze

  def business_metrics # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    return nil unless Current.account_user.administrator?

    # Rodada 5 (#151/#173): mês e "hoje" no fuso de São Paulo; realizada =
    # ativa com a data já passada (scope concluidas, régua do Financeiro) —
    # antes contava só o rótulo "realizada", que o hub nunca usa (dava R$ 0)
    today = ActiveSupport::TimeZone['America/Sao_Paulo'].today
    month = today.beginning_of_month
    scope = Crm::OftalmofacilSurgery.where(account_id: account.id).in_period(month, month.end_of_month)
    own = Crm::PartnerGuard.own_provider_name(account)
    # da casa = o nome do fornecedor CONTÉM o nome configurado — a mesma régua
    # do Crm::PartnerGuard.partner_surgery?, do Hub e do sync (em SQL)
    scope = scope.where('LOWER(provider_name) LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(own)}%") if own.present?
    done = scope.concluidas(today)
    faturamento = done.sum(:amount).to_f.round(2)
    cirurgias = done.count
    {
      oftalmofacil: {
        month_label: "#{MONTHS_PT[month.month - 1]} de #{month.year}",
        # ainda agendadas = de hoje em diante (a que já passou virou realizada)
        faturamento: faturamento, cirurgias: cirurgias, agendadas: scope.agendadas_por_vir(today).count,
        ticket: cirurgias.positive? ? (faturamento / cirurgias).round(2) : 0,
        available: Crm::OftalmofacilSurgery.exists?(account_id: account.id)
      }
    }
  rescue StandardError => e
    Rails.logger.warn "[Painel do empresário] métricas: #{e.message}"
    nil
  end

  def sanitize_people(list)
    Array(list).first(12).filter_map do |p|
      next if p[:name].blank?

      { 'id' => p[:id].presence || SecureRandom.hex(4),
        'name' => p[:name].to_s[0, 80], 'why' => p[:why].to_s[0, 200] }.merge(item_meta(p))
    end
  end

  def sanitize_problems(list)
    Array(list).first(12).filter_map do |pr|
      next if pr[:problem].blank? && pr[:solution].blank?

      { 'id' => pr[:id].presence || SecureRandom.hex(4),
        'problem' => pr[:problem].to_s[0, 300], 'solution' => pr[:solution].to_s[0, 300] }.merge(item_meta(pr))
    end
  end

  def sanitize_board_items(list)
    Array(list).first(30).filter_map do |item|
      next if item[:text].blank?

      { 'id' => item[:id].presence || SecureRandom.hex(4), 'text' => item[:text].to_s[0, 200] }.merge(item_meta(item))
    end
  end

  # posição e tamanho de cada quadro na grade de 12 colunas (o ímã)
  def sanitize_layout(list) # rubocop:disable Metrics/AbcSize
    cards = Array(list).first(30).filter_map do |c|
      next unless c[:id].to_s.match?(CARD_ID)

      w = c[:w].to_i.clamp(2, 12)
      { 'id' => c[:id].to_s, 'x' => c[:x].to_i.clamp(0, 12 - w), 'y' => c[:y].to_i.clamp(0, 800),
        'w' => w, 'h' => c[:h].to_i.clamp(3, 80),
        'hidden' => ActiveModel::Type::Boolean.new.cast(c[:hidden]) == true }
    end
    cards.uniq { |c| c['id'] }
  end

  # teia radar: estado atual × desejado por área (0–10) + retratos datados
  def sanitize_radar(raw) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil unless raw.respond_to?(:[])

    areas = Array(raw[:areas]).first(10).filter_map do |a|
      next unless a[:key].to_s.match?(RADAR_KEY) && a[:label].present?

      { 'key' => a[:key].to_s, 'label' => a[:label].to_s[0, 40] }
    end
    areas = areas.uniq { |a| a['key'] }
    keys = areas.pluck('key')
    snapshots = Array(raw[:snapshots]).first(60).filter_map do |snap|
      next unless snap.respond_to?(:[])

      { 'id' => snap[:id].presence || SecureRandom.hex(4), 'at' => stamp(snap[:at]) || Time.current.iso8601,
        'note' => snap[:note].to_s[0, 300], 'areas' => sanitize_snapshot_areas(snap[:areas]),
        'current' => radar_scores(snap[:current], nil), 'desired' => radar_scores(snap[:desired], nil) }
    end
    { 'areas' => areas, 'current' => radar_scores(raw[:current], keys), 'desired' => radar_scores(raw[:desired], keys),
      'notes' => keys.index_with { |k| raw.dig(:notes, k).to_s[0, 300] }.compact_blank,
      'updated_at' => stamp(raw[:updated_at]), 'snapshots' => snapshots }.compact
  end

  def sanitize_snapshot_areas(list)
    Array(list).first(10).filter_map do |a|
      { 'key' => a[:key].to_s, 'label' => a[:label].to_s[0, 40] } if a[:key].to_s.match?(RADAR_KEY)
    end
  end

  def radar_scores(raw, keys)
    return {} unless raw.respond_to?(:each_pair) || raw.respond_to?(:to_unsafe_h)

    hash = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    hash = hash.slice(*keys) if keys
    hash.select { |k, _| k.to_s.match?(RADAR_KEY) }
        .transform_values { |v| (v.to_f.clamp(0, 10) * 2).round / 2.0 }
  end

  # linha do tempo do quadro (mais nova primeiro)
  def sanitize_events(list)
    Array(list).first(400).filter_map do |e|
      next unless e.respond_to?(:[]) && EVENT_KINDS.include?(e[:kind].to_s)

      { 'id' => e[:id].presence || SecureRandom.hex(4), 'at' => stamp(e[:at]) || Time.current.iso8601,
        'kind' => e[:kind].to_s, 'card' => e[:card].to_s[0, 40], 'text' => e[:text].to_s[0, 300] }
    end
  end

  def pillar_params
    permitted = params.permit(:name, :subtitle, :emoji, :color, :status, :health_note, owner_ids: [])
    permitted[:owner_ids] = Array(permitted[:owner_ids]).map(&:to_i) if params.key?(:owner_ids)
    permitted
  end

  def item_params
    params.permit(:kind, :title, :description, :status, :owner_id, :due_on)
  end

  def board_json
    pillars = account.cevico_pillars.order(:position, :id).includes(:strategies)
    { pillars: pillars.map { |p| pillar_json(p) } }
  end

  def pillar_json(pillar)
    {
      id: pillar.id,
      name: pillar.name,
      subtitle: pillar.subtitle,
      emoji: pillar.emoji,
      color: pillar.color,
      status: pillar.status,
      health_note: pillar.health_note,
      owner_ids: Array(pillar.owner_ids).map(&:to_i),
      items: pillar.strategies.sort_by { |s| [s.position, s.id] }.map { |s| item_json(s) }
    }
  end

  def item_json(item)
    {
      id: item.id,
      pillar_id: item.pillar_id,
      kind: item.kind,
      title: item.title,
      description: item.description,
      status: item.status,
      owner_id: item.owner_id,
      due_on: item.due_on
    }
  end
end
