# Painel Estratégico CEVICO (só admin): a empresa por pilares — cada um com
# responsáveis, semáforo de saúde, nota de desempenho e as estratégias/ações
# corretivas (dono, prazo, andamento). Os 3 pilares combinados nascem
# prontos na primeira visita.
class Api::V1::Accounts::Crm::StrategyController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action -> { require_capability(:strategy) }

  def show
    CevicoPillar.seed_defaults!(account)
    render json: board_json.merge(processes: processes_list)
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

  # o exemplo do Guilherme nasce pronto na primeira visita
  DEFAULT_PROCESS = {
    'id' => 'jornada-padrao',
    'name' => 'Jornada do paciente (padrão)',
    'emoji' => '🏥',
    'steps' => [
      { 'id' => 'p1', 'title' => 'Agendamento', 'desc' => 'Lead atendido no WhatsApp e consulta marcada na Agenda.', 'owner_id' => nil,
        'handoff' => 'Confirmação enviada; card vai para "Consulta Confirmada".' },
      { 'id' => 'p2', 'title' => 'Comparecimento', 'desc' => 'Recepção confirma a chegada; conferência do dia marca Compareceu/Faltou.',
        'owner_id' => nil, 'handoff' => 'Quem faltou entra na régua de reagendamento.' },
      { 'id' => 'p3', 'title' => 'Consulta', 'desc' => 'Avaliação com o médico; anotações clínicas no Espaço do Paciente.', 'owner_id' => nil,
        'handoff' => 'Médico registra a conduta: indicação de cirurgia ou não.' },
      { 'id' => 'p4', 'title' => 'Indicação de cirurgia (ou não)',
        'desc' => 'Com indicação: orçamento oficial pela tabela de preços. Sem indicação: orientação e retorno.',
        'owner_id' => nil, 'handoff' => 'Card vai para "Indicação de Cirurgia" e o fechamento assume.' },
      { 'id' => 'p5', 'title' => 'Fechamento (ou não)', 'desc' => 'Negociação com o mapa de objeções e o script validado; agendar a cirurgia.',
        'owner_id' => nil, 'handoff' => 'Fechou: Agenda de Cirurgias. Não fechou: régua "Não Fechou Ainda".' }
    ]
  }.freeze

  def processes_list
    list = (crm_settings.agenda_config || {})['process_designs']
    list.is_a?(Array) && list.any? ? list : [DEFAULT_PROCESS]
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
