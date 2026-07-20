# FERRAMENTAS da Academia (item 77): leitura aberta ao time logado
# (só as publicadas; admin vê rascunhos também); escrever é só admin.
class Api::V1::Accounts::Crm::TeamToolsController < Api::V1::Accounts::BaseController
  include Crm::AccessControl
  before_action :require_administrator!, except: [:index]

  def index
    scope = Current.account.cevico_tools.ordered
    scope = scope.published unless Current.account_user.administrator?
    render json: { tools: scope.map { |t| tool_json(t) }, can_edit: Current.account_user.administrator? }
  end

  def create
    tool = Current.account.cevico_tools.new(tool_params.merge(created_by_id: Current.user.id))
    return render json: { error: tool.errors.full_messages.first }, status: :unprocessable_entity unless tool.save

    render json: tool_json(tool)
  end

  def update
    tool = Current.account.cevico_tools.find(params[:id])
    return render json: { error: tool.errors.full_messages.first }, status: :unprocessable_entity unless tool.update(tool_params)

    render json: tool_json(tool)
  end

  def destroy
    Current.account.cevico_tools.find(params[:id]).destroy!
    head :ok
  end

  private

  # auditoria T1: só atualiza as chaves PRESENTES no request — um PATCH
  # parcial não apaga campos nem publica rascunho sem querer (o create
  # sem campo cai nos defaults do banco)
  def tool_params # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    permitted = {}
    permitted[:title] = params[:title].to_s.strip[0, 160] if params.key?(:title)
    permitted[:emoji] = params[:emoji].to_s.strip.presence || '🧰' if params.key?(:emoji)
    permitted[:category] = params[:category].to_s.strip[0, 60] if params.key?(:category)
    permitted[:content] = params[:content].to_s[0, 30_000] if params.key?(:content)
    permitted[:position] = params[:position].to_i if params.key?(:position)
    permitted[:published] = ActiveModel::Type::Boolean.new.cast(params[:published]).present? if params.key?(:published)
    permitted
  end

  def tool_json(tool)
    {
      id: tool.id,
      title: tool.title,
      emoji: tool.emoji,
      category: tool.category,
      content: tool.content,
      position: tool.position,
      published: tool.published,
      updated_at: tool.updated_at.iso8601
    }
  end
end
