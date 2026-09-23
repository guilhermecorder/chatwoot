# 📝 NOTAS DOS PACIENTES (item 211, 23/09): recado rápido sobre um paciente
# ("ligar semana que vem", "pediu orçamento de trifocal") escrito de
# Tarefas ou do Meu Painel. É a MESMA nota do contato do Chatwoot (Note):
# aparece na ficha do paciente, no Espaço do Paciente ("Notas da equipe")
# e no painel da conversa. Aqui a lista é da clínica inteira, mais recente
# primeiro, com o nome do paciente e de quem escreveu.
class Api::V1::Accounts::Crm::PatientNotesController < Api::V1::Accounts::BaseController
  LIMIT = 60

  # GET /crm/patient_notes?limit=&q=
  def index
    notes = Current.account.notes.includes(:user, :contact).order(created_at: :desc)
    notes = notes.where(user_id: Current.user.id) if params[:mine].to_s == '1'
    render json: notes.limit([params[:limit].to_i, LIMIT].min.clamp(1, LIMIT)).map { |n| note_json(n) }
  end

  # POST /crm/patient_notes { contact_id, content }
  def create
    contact = Current.account.contacts.find(params[:contact_id])
    note = contact.notes.create!(content: params[:content].to_s.strip, user_id: Current.user.id)
    render json: note_json(note), status: :created
  end

  # DELETE /crm/patient_notes/:id — quem escreveu ou admin
  def destroy
    note = Current.account.notes.find(params[:id])
    return render json: { error: 'Só quem escreveu (ou um admin) pode apagar a nota.' }, status: :forbidden unless can_touch?(note)

    note.destroy!
    head :ok
  end

  private

  def can_touch?(note)
    Current.account_user.administrator? || note.user_id == Current.user.id
  end

  def note_json(note)
    contact = note.contact
    {
      id: note.id,
      content: note.content,
      created_at: note.created_at,
      author: note.user ? { id: note.user.id, name: note.user.name } : nil,
      mine: note.user_id == Current.user.id,
      contact: contact && { id: contact.id, name: contact.name, phone: contact.phone_number, thumbnail: contact.avatar_url }
    }
  end
end
