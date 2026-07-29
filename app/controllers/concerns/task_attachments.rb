# 📎 Anexos da tarefa (imagem/PDF/documento — pedido de exame, print, guia).
# Quem pode ver a tarefa no board já recebe os anexos no task_json;
# ADICIONAR/REMOVER = criador, responsável ou admin (mesma regra do chat da
# tarefa). Arquivos ficam no ActiveStorage (storage compartilhado — backup!).
module TaskAttachments
  extend ActiveSupport::Concern

  MAX_FILES_PER_TASK = 10
  MAX_FILE_SIZE = 10.megabytes
  ALLOWED_FILE_TYPES = %w[
    image/jpeg image/png image/webp image/gif image/heic image/heif
    application/pdf
    application/msword application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.ms-excel application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
  ].freeze

  # POST /tasks/:id/attachments (multipart files[])
  def attachments
    return render json: { error: 'Sem acesso a esta tarefa.' }, status: :forbidden unless can_collaborate?

    incoming = Array(params[:files]).select { |f| f.respond_to?(:content_type) }
    return render json: { error: 'Escolha ao menos um arquivo.' }, status: :unprocessable_entity if incoming.blank?

    error = attachment_error(incoming)
    return render json: { error: error }, status: :unprocessable_entity if error

    task.files.attach(incoming)
    render json: task_json(task)
  end

  # DELETE /tasks/:id/attachments/:attachment_id
  def destroy_attachment
    return render json: { error: 'Sem acesso a esta tarefa.' }, status: :forbidden unless can_collaborate?

    task.files_attachments.find(params[:attachment_id]).purge
    render json: task_json(task.reload)
  end

  private

  def attachment_error(incoming)
    return "Máximo de #{MAX_FILES_PER_TASK} arquivos por tarefa." if task.files.count + incoming.size > MAX_FILES_PER_TASK

    incoming.each do |file|
      return 'Tipo de arquivo não aceito — use imagem, PDF, Word ou Excel.' unless ALLOWED_FILE_TYPES.include?(file.content_type)
      return 'Arquivo acima de 10 MB.' if file.size > MAX_FILE_SIZE
    end
    nil
  end

  # anexos prontos pra tela: imagem vira miniatura, o resto vira chip de download
  def task_files_json(record)
    record.files_attachments.map do |att|
      {
        id: att.id,
        filename: att.filename.to_s,
        content_type: att.content_type,
        byte_size: att.byte_size,
        is_image: att.content_type.to_s.start_with?('image/'),
        url: Rails.application.routes.url_helpers.rails_blob_path(att, only_path: true)
      }
    end
  rescue StandardError
    []
  end
end
