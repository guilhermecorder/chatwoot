# ESPAÇO NOBRE DO MÉDICO (Central do Paciente — Fase 2): anotações de
# consulta com campos rápidos + fotos de exames.
#
# Permissões (agenda_config.clinical_access):
#   - EDITAM: admin + usuários marcados como médicos (doctor_user_ids)
#   - VISUALIZAM: os de cima; a equipe só se team_view estiver ligado
# ⚠️ LGPD: dado de saúde é sensível — todo acesso fica registrado no log.
class Api::V1::Accounts::Crm::ClinicalNotesController < Api::V1::Accounts::BaseController
  before_action :check_view_permission, only: [:index]
  before_action :check_edit_permission, only: [:create, :update, :destroy]

  def index
    notes = Crm::ClinicalNote.where(account_id: Current.account.id)
                             .for_patient(patient.id)
                             .includes(:author, photos_attachments: :blob)
    audit("leu as anotações do paciente #{patient.id}")
    render json: { can_edit: can_edit?, notes: notes.map { |n| note_json(n) } }
  end

  def create # rubocop:disable Metrics/AbcSize
    note = Crm::ClinicalNote.create!(
      account_id: Current.account.id,
      contact_id: patient.id,
      author: Current.user,
      task_id: linked_task_id,
      doctor: params[:doctor].presence,
      performed_at: params[:performed_at].presence || Time.current,
      fields: fields_param,
      observations: params[:observations].presence
    )
    attach_photos(note)
    reflect_conduct(note)
    audit("criou a anotação #{note.id} do paciente #{patient.id}")
    render json: note_json(note), status: :created
  end

  def update # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    note = find_note
    # médico só edita a PRÓPRIA anotação (admin edita todas)
    return render_forbidden unless Current.account_user.administrator? || note.author_id == Current.user.id

    note.update!(
      doctor: params.key?(:doctor) ? params[:doctor].presence : note.doctor,
      performed_at: params[:performed_at].presence || note.performed_at,
      fields: params.key?(:fields) ? fields_param : note.fields,
      observations: params.key?(:observations) ? params[:observations].presence : note.observations
    )
    attach_photos(note)
    Array(params[:remove_photo_ids]).each { |pid| note.photos.find_by(id: pid)&.purge }
    reflect_conduct(note)
    audit("editou a anotação #{note.id} do paciente #{patient.id}")
    render json: note_json(note)
  end

  def destroy
    note = find_note
    return render_forbidden unless Current.account_user.administrator? || note.author_id == Current.user.id

    note.destroy!
    audit("excluiu a anotação #{note.id} do paciente #{patient.id}")
    head :no_content
  end

  private

  def patient
    @patient ||= Current.account.contacts.find(params[:patient_id])
  end

  def find_note
    Crm::ClinicalNote.where(account_id: Current.account.id, contact_id: patient.id).find(params[:id])
  end

  def clinical_access
    @clinical_access ||= (CrmSetting.find_by(account: Current.account)&.agenda_config || {})['clinical_access'] || {}
  end

  def can_edit?
    Current.account_user.administrator? ||
      Array(clinical_access['doctor_user_ids']).include?(Current.user.id)
  end

  def can_view?
    can_edit? || clinical_access['team_view'] == true
  end

  def check_view_permission
    render_forbidden unless can_view?
  end

  def check_edit_permission
    render_forbidden unless can_edit?
  end

  def render_forbidden
    render json: { error: 'Sem acesso às anotações clínicas.' }, status: :forbidden
  end

  # trilha de auditoria (LGPD): quem fez o quê, quando
  def audit(action)
    Rails.logger.info("[CEVICO clínico] #{Current.user.name} (##{Current.user.id}) #{action}")
  end

  def fields_param
    return {} if params[:fields].blank?

    params.require(:fields).permit(
      :procedure_type, :technique, :lens_type, :eye,
      :refraction_od, :refraction_oe, :acuity_od, :acuity_oe,
      :pio_od, :pio_oe, :biomicroscopy, :fundoscopy,
      :surgery_indicated, :indicated_procedure, :indicated_value, :procedure_option,
      conduct: [], exams_requested: []
    ).to_h
  end

  # consulta da Agenda ligada — precisa ser do mesmo paciente
  def linked_task_id
    return nil if params[:task_id].blank?

    Task.for_patient(Current.account, patient).find_by(id: params[:task_id])&.id
  end

  def attach_photos(note)
    Array(params[:photos]).each do |file|
      note.photos.attach(file) if file.respond_to?(:tempfile)
    end
  end

  # Conduta do médico alimenta o CRM: indicação de cirurgia marcada na
  # anotação vira indicação na consulta ligada e move o card (mesmo reflexo
  # da conferência do dia). O ORÇAMENTO DE INDICAÇÃO (preço oficial do
  # procedimento escolhido) entra no valor do card se ainda estiver vazio —
  # no fechamento a IA atualiza, e a diferença vira a taxa de performance.
  def reflect_conduct(note)
    return unless note.fields['surgery_indicated'].to_s == 'true'

    fill_card_value(note)
    return if note.task.blank?

    task = note.task
    changed = task.surgery_indication != 'indicated'
    task.update!(
      surgery_indication: 'indicated',
      indicated_procedure: note.fields['indicated_procedure'].presence || task.indicated_procedure
    )
    Crm::AttendanceReflector.call(account: Current.account, task: task) if changed
  rescue StandardError => e
    Rails.logger.error "[CEVICO clínico] reflexo da conduta: #{e.message}"
  end

  def fill_card_value(note)
    value = note.fields['indicated_value'].to_f
    return unless value.positive?

    card = Crm::Contact.joins(:pipeline)
                       .where(crm_pipelines: { account_id: Current.account.id }, contact_id: note.contact_id)
                       .order('crm_pipelines.position').first
    card.update!(value: value) if card && card.value.to_f.zero?
  end

  def note_json(note)
    {
      id: note.id,
      performed_at: note.performed_at,
      doctor: note.doctor,
      task_id: note.task_id,
      fields: note.fields,
      observations: note.observations,
      author: { id: note.author.id, name: note.author.name },
      created_at: note.created_at,
      updated_at: note.updated_at,
      photos: note.photos.map do |photo|
        {
          id: photo.id,
          filename: photo.filename.to_s,
          url: Rails.application.routes.url_helpers.rails_blob_url(photo, only_path: true)
        }
      end
    }
  end
end
