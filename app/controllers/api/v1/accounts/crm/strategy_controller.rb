# Painel Estratégico CEVICO (só admin): a empresa por pilares — cada um com
# responsáveis, semáforo de saúde, nota de desempenho e as estratégias/ações
# corretivas (dono, prazo, andamento). Os 3 pilares combinados nascem
# prontos na primeira visita.
class Api::V1::Accounts::Crm::StrategyController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:strategy) }

  def show
    CevicoPillar.seed_defaults!(account)
    render json: board_json.merge(processes: processes_list, business: business_board)
  end

  # ── 🧭 PAINEL DO EMPRESÁRIO: o quadro de gestão do dono (kanban pessoal,
  # continuar/parar/começar, matrizes de prioridade e oportunidade, pessoas
  # estratégicas, objetivos do ano e problemas → solução). Só admin vê e
  # salva — é a mesa de trabalho do empresário, não do time. ──
  def save_business_board
    return render json: { error: 'Só administradores mexem no Painel do Empresário.' }, status: :forbidden unless Current.account_user.administrator?

    cfg = crm_settings.agenda_config || {}
    cfg['business_board'] = sanitize_business_board
    crm_settings.update!(agenda_config: cfg)
    render json: { business: cfg['business_board'] }
  end

  # ── 🏭 DESENHO DO PROCESSO (item 59): a máquina da clínica, etapa a
  # etapa, com responsável e PASSE DE BASTÃO — o time inteiro entende o
  # processo como o Guilherme entende. Admin desenha; todos veem. ──
  def save_processes
    return render json: { error: 'Só administradores desenham processos.' }, status: :forbidden unless Current.account_user.administrator?

    cfg = crm_settings.agenda_config || {}
    cfg['process_designs'] = sanitize_processes
    crm_settings.update!(agenda_config: cfg)
    render json: { processes: cfg['process_designs'] }
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

  def sanitize_business_board
    raw = params[:business].presence || {}
    board = BUSINESS_LISTS.to_h do |section, keys|
      [section, keys.index_with { |k| sanitize_board_items(raw.dig(section, k)) }]
    end
    %w[objectives goals activities].each do |k|
      board[k] = Array(raw[k]).first(5).map { |t| t.to_s[0, 160] }
    end
    board.merge('people' => sanitize_people(raw[:people]), 'problems' => sanitize_problems(raw[:problems]))
  end

  def sanitize_people(list)
    Array(list).first(12).filter_map do |p|
      next if p[:name].blank?

      { 'id' => p[:id].presence || SecureRandom.hex(4),
        'name' => p[:name].to_s[0, 80], 'why' => p[:why].to_s[0, 200] }
    end
  end

  def sanitize_problems(list)
    Array(list).first(12).filter_map do |pr|
      next if pr[:problem].blank? && pr[:solution].blank?

      { 'id' => pr[:id].presence || SecureRandom.hex(4),
        'problem' => pr[:problem].to_s[0, 300], 'solution' => pr[:solution].to_s[0, 300] }
    end
  end

  def sanitize_board_items(list)
    Array(list).first(30).filter_map do |item|
      next if item[:text].blank?

      { 'id' => item[:id].presence || SecureRandom.hex(4), 'text' => item[:text].to_s[0, 200] }
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
