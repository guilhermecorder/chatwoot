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
    params.require(:stage).permit(:name, :color, :position, :description)
  end

  def stage_json(s)
    { id: s.id, name: s.name, color: s.color, position: s.position, pipeline_id: s.pipeline_id, description: s.description }
  end
end
