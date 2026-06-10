class Api::V1::Accounts::Crm::PipelinesController < Api::V1::Accounts::BaseController
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
    { id: s.id, name: s.name, color: s.color, position: s.position, pipeline_id: s.pipeline_id }
  end
end
