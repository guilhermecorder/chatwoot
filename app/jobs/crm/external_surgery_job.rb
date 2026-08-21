# Tratamento de dados: "Cirurgias feitas FORA do sistema" — pacientes que
# operaram fora do CRM e nunca chegaram na coluna "Cirurgia Realizada".
# Recebe a lista já casada (contact_id → valor) e, para cada paciente:
#   - card já existe no funil da coluna-alvo → move via update! direto no
#     model (os callbacks registram o StageLog normal); NENHUMA automação é
#     chamada — mover cirurgia antiga não pode disparar automação de coluna
#     nem conversão de anúncio
#   - card não existe naquele funil → cria com origin 'cirurgia externa'
# Valor do card: preenche quando veio na lista e o card não tem valor (ou
# quando o admin mandou sobrescrever). Em card EXISTENTE o valor entra por
# update_column, sem callbacks — senão o gatilho "valor adicionado" do model
# dispararia automações para uma cirurgia do passado. Na criação pode ir
# junto: fire_value_automations é after_update, não roda no create.
# Etiqueta no contato: modo LEVE, direto em taggings (como o RetroLabelJob).
class Crm::ExternalSurgeryJob < ApplicationJob
  queue_as :low

  def perform(account_id, matched_pairs, stage_id, label_title, options = {})
    account = Account.find_by(id: account_id)
    return if account.blank?

    stage = Crm::Stage.joins(:pipeline)
                      .where(crm_pipelines: { account_id: account.id })
                      .find_by(id: stage_id)
    return if stage.blank?

    label_title = label_title.to_s.strip.downcase.presence
    account.labels.find_or_create_by!(title: label_title) if label_title

    set_value = options['set_value'] != false
    overwrite_value = options['overwrite_value'] == true
    processed = 0
    preserved = 0 # 🛡️ já adiante da coluna-alvo (ex.: Pós Operatório) — intocados
    undo_entries = [] # ↩️ recibo de tudo que mudou — alimenta o "Desfazer"

    Array(matched_pairs).each_slice(200) do |batch|
      contacts = account.contacts.where(id: batch.map(&:first)).index_by(&:id)

      # entrada nova (item 132): [contact_id, valor, data_iso, procedimento] —
      # o formato antigo [contact_id, valor] continua valendo (data/proc nil)
      batch.each do |contact_id, value, date, procedure|
        contact = contacts[contact_id]
        next if contact.blank?

        entry = place_in_stage(stage, contact, value, set_value, overwrite_value, date, procedure)
        # 🛡️ paciente já ADIANTE da coluna-alvo (ex.: Pós Operatório):
        # fica exatamente como está — sem mover, sem valor, sem etiqueta
        if entry == :ahead
          preserved += 1
          next
        end
        undo_entries << entry if entry
        fast_add_label(contact, label_title) if label_title
        processed += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::ExternalSurgeryJob] contato #{contact_id}: #{e.message}"
      end

      # respira entre lotes para não saturar a CPU em bases grandes
      sleep 0.05
    end

    # 📄 planilha de fechamento (item 132): pacientes que NÃO existem na base
    # (nunca passaram pelo WhatsApp) — cria o contato (sem telefone) e o card
    # direto na coluna, com valor e DATA REAL. O histórico entra inteiro.
    created = 0
    Array(options['create_rows']).each_slice(200) do |batch|
      batch.each do |row|
        name = row['name'].to_s.strip
        next if name.blank?

        contact = account.contacts.create!(
          name: name,
          additional_attributes: { 'origem' => 'planilha_fechamento' }
        )
        entry = place_in_stage(stage, contact, row['value'], set_value, overwrite_value, row['date'], row['procedure'])
        (entry ||= {})['created_contact_id'] = contact.id
        undo_entries << entry
        fast_add_label(contact, label_title) if label_title
        created += 1
      rescue StandardError => e
        Rails.logger.error "[Crm::ExternalSurgeryJob] criar '#{row['name']}': #{e.message}"
      end
      sleep 0.05
    end

    save_undo_receipt(account, stage, label_title, undo_entries)
    Rails.logger.info "[Crm::ExternalSurgeryJob] #{processed} pacientes colocados em #{stage.name} " \
                      "(+#{created} criados da planilha; #{preserved} já adiante preservados)"
  end

  private

  # cria o card na coluna-alvo, ou move se já existir no funil dela —
  # preenche valor/procedimento e RETRODATA a entrada na coluna quando a
  # linha traz a data real (item 132): funis, PRO MAX e faturamento passam
  # a contar a cirurgia no MÊS em que ela aconteceu, não no dia do import.
  # Devolve o RECIBO da mudança (item 133: alimenta o botão Desfazer).
  def place_in_stage(stage, contact, value, set_value, overwrite_value, date = nil, procedure = nil)
    card = Crm::Contact.find_or_initialize_by(contact_id: contact.id, pipeline_id: stage.pipeline_id)
    new_value = value if set_value && value.to_f.positive?
    moved = false
    entry = { 'contact_id' => contact.id }

    if card.persisted?
      # 🛡️ card numa coluna DEPOIS do alvo (ex.: Pós Operatório quando o
      # alvo é Cirurgia Realizada): a jornada dele já passou desse ponto —
      # não volta o card nem mexe em nada (pedido 20/08, rodada 137)
      return :ahead if card.stage_id != stage.id && card.stage&.position.to_i > stage.position.to_i

      entry['prev_stage_id'] = card.stage_id
      entry['prev_value'] = card.value&.to_f
      entry['prev_stage_moved_at'] = card.stage_moved_at&.iso8601
      if card.stage_id != stage.id
        card.update!(stage_id: stage.id)
        moved = true
      end
      # sem callbacks: valor de cirurgia antiga não dispara "valor adicionado"
      card.update_column(:value, new_value) if new_value && (card.value.to_f <= 0 || overwrite_value)
    else
      card.origin = 'cirurgia externa'
      card.stage_id = stage.id
      card.value = new_value if new_value
      card.save!
      entry['created_card'] = true
      moved = true
    end

    card.update_column(:procedure_of_interest, procedure.to_s.truncate(120)) if procedure.present? && card.procedure_of_interest.blank?
    backdate!(card, stage, date) if moved && date.present?

    entry['card_id'] = card.id
    entry['moved'] = moved
    entry['new_log_id'] = card.stage_logs.where(stage_id: stage.id).order(:id).last&.id if moved
    entry
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # ↩️ recibo da importação (só a ÚLTIMA fica guardada) — o Desfazer lê daqui
  def save_undo_receipt(account, stage, label_title, entries)
    settings = CrmSetting.find_by(account: account)
    return if settings.blank?

    settings.with_lock do
      cfg = (settings.reload.agenda_config || {}).deep_dup
      cfg['surgery_import_undo'] = {
        'id' => SecureRandom.hex(6),
        'at' => Time.current.iso8601,
        'stage_id' => stage.id,
        'stage_name' => stage.name,
        'label' => label_title,
        'entries' => entries.first(5000)
      }
      settings.update_column(:agenda_config, cfg) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # retrodata o registro de movimentação RECÉM-criado (só ele — histórico
  # antigo do card não é tocado) e o stage_moved_at do card
  def backdate!(card, stage, date_iso)
    real_date = Time.zone.parse("#{date_iso} 12:00")
    return if real_date.blank? || real_date > Time.current

    log = Crm::StageLog.where(crm_contact_id: card.id, stage_id: stage.id)
                       .order(entered_at: :desc).first
    log&.update_columns(entered_at: real_date) # rubocop:disable Rails/SkipsModelValidations
    card.update_column(:stage_moved_at, real_date)
  rescue ArgumentError
    nil
  end

  # etiqueta LEVE e sem duplicar: direto na tabela de taggings + cache
  # (sem webhook/automação/ActionCable por registro — igual ao RetroLabelJob)
  def fast_add_label(taggable, tag_name)
    return if taggable.blank?

    tag = ActsAsTaggableOn::Tag.find_or_create_by!(name: tag_name)
    ActsAsTaggableOn::Tagging.find_or_create_by!(
      tag_id: tag.id,
      taggable_type: taggable.class.name,
      taggable_id: taggable.id,
      context: 'labels'
    )

    return unless taggable.has_attribute?(:cached_label_list)

    list = (taggable.cached_label_list || '').split(',').map(&:strip).reject(&:blank?)
    return if list.include?(tag_name)

    taggable.update_column(:cached_label_list, (list + [tag_name]).join(', '))
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
