# Feedback de bugs do TIME: qualquer pessoa reporta um problema do sistema
# e ele vira um card 🐞 no board de tarefas do Guilherme (primeiro admin).
# Quando o card é concluído, quem reportou recebe o aviso no Meu Painel.
class Api::V1::Accounts::Crm::BugReportsController < Api::V1::Accounts::BaseController
  def create
    title = params[:title].to_s.strip
    return render json: { error: 'Descreva o problema em uma frase.' }, status: :unprocessable_entity if title.blank?

    owner = Current.account.administrators.first || Current.user
    task = Current.account.tasks.create!(
      title: "🐞 #{title.truncate(120)}",
      description: build_description,
      task_type: 'bug',
      priority: :high,
      status: :todo,
      assignee: owner,
      creator: Current.user
    )
    render json: { id: task.id, ok: true }
  end

  private

  def build_description
    [
      params[:description].to_s.strip.presence,
      params[:screen].present? ? "Tela: #{params[:screen]}" : nil,
      "Reportado por: #{Current.user.name}"
    ].compact.join("\n\n")
  end
end
