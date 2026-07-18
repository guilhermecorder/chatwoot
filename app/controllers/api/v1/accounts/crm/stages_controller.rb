class Api::V1::Accounts::Crm::StagesController < Api::V1::Accounts::BaseController
  before_action :pipeline
  before_action :stage, only: [:update, :destroy]

  def index
    render json: @pipeline.stages.map { |s| stage_json(s) }
  end

  def create
    @stage = @pipeline.stages.create!(stage_params)
    render json: stage_json(@stage), status: :created
  end

  def update
    @stage.update!(stage_params)
    render json: stage_json(@stage)
  end

  def destroy
    # coluna com cards: bloqueia (o dependent: :nullify batia no NOT NULL do
    # stage_id e virava erro 500 seco na cara do admin)
    if @stage.crm_contacts.exists?
      return render json: { error: 'Mova os cards desta coluna antes de excluí-la.' }, status: :unprocessable_entity
    end

    @stage.destroy!
    head :no_content
  end

  def reorder
    params[:stage_ids].each_with_index do |id, index|
      @pipeline.stages.where(id: id).update_all(position: index)
    end
    render json: @pipeline.stages.map { |s| stage_json(s) }
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
  end

  def stage
    @stage ||= @pipeline.stages.find(params[:id])
  end

  def stage_params
    # settings.main_inbox_ids = caixas de entrada PRINCIPAIS da coluna
    permitted = params.require(:stage).permit(:name, :color, :position, :description, settings: { main_inbox_ids: [] })
    if permitted[:settings]
      permitted[:settings] = (@stage&.settings || {}).merge(
        'main_inbox_ids' => Array(permitted[:settings][:main_inbox_ids]).map(&:to_i).reject(&:zero?)
      )
    end
    permitted
  end

  def stage_json(s)
    { id: s.id, name: s.name, color: s.color, position: s.position, pipeline_id: s.pipeline_id, description: s.description,
      main_inbox_ids: Array(s.settings&.[]('main_inbox_ids')).map(&:to_i) }
  end
end
