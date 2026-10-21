# 🔐 auditoria 12/10 (achados #19/#245/#299): criar, renomear, reordenar e
# apagar colunas só com a concessão "Funis e colunas" (crm.funis, editar).
class Api::V1::Accounts::Crm::StagesController < Api::V1::Accounts::BaseController
  before_action -> { require_access('crm.funis', :edit) }, only: [:create, :update, :destroy, :destroy_moving_to, :reorder]
  before_action :pipeline
  before_action :stage, only: [:update, :destroy, :destroy_moving_to]

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
    return if linked_robots_refused?

    @stage.destroy!
    head :no_content
  end

  # 🧹 auditoria 12/10 (achado #288): "Excluir coluna" com cards vira UMA
  # operação no servidor — move TODOS os cards da coluna (não só os carregados
  # na tela) para a coluna de destino e apaga a coluna, tudo numa transação.
  # Se qualquer passo falhar, nada muda.
  # · as automações da coluna de destino NÃO disparam (é arrumação de
  #   estrutura, ninguém "entrou" na coluna);
  # · o histórico de cada card ganha a entrada marcada como carga em massa
  #   (`bulk`, item 309), então os indicadores de "Entrou em…" não contam.
  def destroy_moving_to
    target = @pipeline.stages.find_by(id: params[:target_stage_id])
    if target.nil? || target.id == @stage.id
      return render json: { error: 'Escolha outra coluna deste funil para receber os cards.' }, status: :unprocessable_entity
    end
    return if linked_robots_refused?

    moved = 0
    ActiveRecord::Base.transaction do
      now = Time.current
      @stage.crm_contacts.find_each do |card|
        move_card_quietly(card, target, now)
        moved += 1
      end
      @stage.reload.destroy!
    end

    render json: { moved: moved, target_stage_id: target.id }
  end

  def reorder
    params[:stage_ids].each_with_index do |id, index|
      @pipeline.stages.where(id: id).update_all(position: index)
    end
    render json: @pipeline.stages.map { |s| stage_json(s) }
  end

  # 🤖 revisão 12/10: texto único de "tem robô ligado" para coluna e funil
  # (o PipelinesController reusa). nil = nada ligado, pode apagar.
  def self.linked_robots_message(bots:, automations:, what:)
    parts = []
    parts << "#{bots} robô(s) de follow-up" if bots.positive?
    parts << "#{automations} automação(ões) de mensagem" if automations.positive?
    return nil if parts.empty?

    "#{what} ainda tem #{parts.join(' e ')}. Desligue ou troque a coluna deles antes de excluir."
  end

  private

  def pipeline
    @pipeline ||= Current.account.crm_pipelines.find(params[:pipeline_id])
  end

  def stage
    @stage ||= @pipeline.stages.find(params[:id])
  end

  # 🤖 revisão 12/10: coluna com robô de follow-up ou automação de mensagem
  # amarrados a ela (chaves no banco, sem "soltar" automático) não pode ser
  # apagada — antes virava erro 500 mudo. Recusar é o lado seguro: soltar o
  # robô da coluna o transformaria num robô "de todas as colunas".
  # Devolve true quando já respondeu com 422.
  def linked_robots_refused?
    error = Api::V1::Accounts::Crm::StagesController.linked_robots_message(
      bots: Crm::FollowupBot.where(stage_id: @stage.id).count,
      automations: Crm::MessageAutomation.where(trigger_stage_id: @stage.id).count,
      what: 'Esta coluna'
    )
    return false if error.nil?

    render json: { error: error }, status: :unprocessable_entity
    true
  end

  # muda a coluna do card SEM os efeitos de "card entrou" (callbacks e
  # automações): fecha o log aberto, grava a entrada como `bulk` e troca a
  # coluna direto na tabela
  def move_card_quietly(card, target, now)
    card.stage_logs.where(stage_id: @stage.id, left_at: nil).find_each { |log| log.close!(now) }
    card.stage_logs.create!(stage_id: target.id, stage_name: target.name, stage_color: target.color,
                            event_type: Crm::StageLogBulk::BULK, entered_at: now)
    card.update_columns(stage_id: target.id, stage_moved_at: now, updated_at: now) # rubocop:disable Rails/SkipsModelValidations
  end

  def stage_params
    # settings.main_inbox_ids = caixas de entrada PRINCIPAIS da coluna
    # settings.task_owner_id = quem cuida da coluna (tarefas automáticas
    # de pacientes daqui nascem no nome dela — pedido 20/07)
    permitted = params.require(:stage).permit(:name, :color, :position, :description,
                                              settings: [:task_owner_id, { main_inbox_ids: [] }])
    if permitted[:settings]
      permitted[:settings] = (@stage&.settings || {}).merge(
        'main_inbox_ids' => Array(permitted[:settings][:main_inbox_ids]).map(&:to_i).reject(&:zero?),
        'task_owner_id' => permitted[:settings][:task_owner_id].presence&.to_i
      )
    end
    permitted
  end

  def stage_json(s)
    { id: s.id, name: s.name, color: s.color, position: s.position, pipeline_id: s.pipeline_id, description: s.description,
      main_inbox_ids: Array(s.settings&.[]('main_inbox_ids')).map(&:to_i),
      task_owner_id: s.settings&.[]('task_owner_id') }
  end
end
