class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create, :reorder]
  before_action :check_authorization

  def index
    @labels = policy_scope(Current.account.labels)
  end

  def show; end

  def create
    @label = Current.account.labels.create!(permitted_params)
  end

  def update
    @label.update!(permitted_params)
  end

  # ordem definida pelo admin (setinhas na tela de Etiquetas): recebe os ids
  # na ordem final e grava position 1..N — vale para o time inteiro
  def reorder
    ids = Array(params[:ordered_ids]).map(&:to_i)
    labels = Current.account.labels.where(id: ids).index_by(&:id)
    ActiveRecord::Base.transaction do
      ids.each_with_index do |id, index|
        labels[id]&.update!(position: index + 1)
      end
    end
    head :ok
  end

  def destroy
    label_title = @label.title
    account_id = Current.account.id
    label_deleted_at = Time.current

    @label.destroy!
    Labels::RemoveAssociationsJob.perform_later(
      label_title: label_title,
      account_id: account_id,
      label_deleted_at: label_deleted_at
    )
    head :ok
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar)
  end
end
