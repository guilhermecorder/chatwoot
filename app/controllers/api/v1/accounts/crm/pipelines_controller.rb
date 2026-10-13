# 🔐 auditoria 12/10 (achados #19/#245/#299): a ESTRUTURA do CRM (criar,
# renomear e apagar funis) só com a concessão "Funis e colunas" (crm.funis,
# editar) do catálogo de acessos — o mapa automático já cobre, a trava
# explícita garante mesmo que o mapa mude. Ver e listar continuam abertos.
class Api::V1::Accounts::Crm::PipelinesController < Api::V1::Accounts::BaseController
  before_action -> { require_access('crm.funis', :edit) }, only: [:create, :update, :destroy]
  before_action :pipeline, only: [:show, :update, :destroy]

  def index
    @pipelines = Current.account.crm_pipelines.order(:position).includes(:stages)
    render json: @pipelines.map { |p| pipeline_json(p) }
  end

  def show
    render json: pipeline_json(@pipeline)
  end

  def create
    @pipeline = Current.account.crm_pipelines.create!(pipeline_params)
    render json: pipeline_json(@pipeline), status: :created
  end

  def update
    @pipeline.update!(pipeline_params)
    render json: pipeline_json(@pipeline)
  end

  def destroy
    # funil com cards NÃO é apagado: o destroy cascateava colunas, automações,
    # todos os cards e o histórico de colunas de uma vez, sem lixeira
    cards = @pipeline.crm_contacts.count
    if cards.positive?
      return render json: { error: "Este funil ainda tem #{cards} card(s). Mova ou apague os cards antes de excluir o funil." },
                    status: :unprocessable_entity
    end

    # 🤖 revisão 12/10: robô de follow-up do funil (ou de uma coluna dele) e
    # automação de mensagem presa a uma coluna dele travam o apagar no banco
    # (chave estrangeira) — recusar explicando em vez de erro 500 mudo
    stage_ids = @pipeline.stages.pluck(:id)
    robots = Api::V1::Accounts::Crm::StagesController.linked_robots_message(
      bots: Crm::FollowupBot.where(pipeline_id: @pipeline.id).or(Crm::FollowupBot.where(stage_id: stage_ids)).count,
      automations: Crm::MessageAutomation.where(trigger_stage_id: stage_ids).count,
      what: 'Este funil'
    )
    return render json: { error: robots }, status: :unprocessable_entity if robots

    @pipeline.destroy!
    head :no_content
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:id])
  end

  def pipeline_params
    params.require(:pipeline).permit(:name, :description, :position)
  end

  def pipeline_json(p)
    {
      id: p.id,
      name: p.name,
      description: p.description,
      position: p.position,
      stages: p.stages.map { |s| stage_json(s) }
    }
  end

  def stage_json(s)
    { id: s.id, name: s.name, color: s.color, position: s.position, pipeline_id: s.pipeline_id,
      main_inbox_ids: Array(s.settings&.[]('main_inbox_ids')).map(&:to_i),
      task_owner_id: s.settings&.[]('task_owner_id') }
  end
end
