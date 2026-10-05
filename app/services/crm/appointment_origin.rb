# 🏥 DE QUEM É O PACIENTE: CEVICO × OFTALMOFÁCIL (item 300, 30/09). Pedido do
# Guilherme: no formulário da Agenda "precisa ser obrigatório ela escolher se a
# pessoa é da CEVICO ou da OFTALMOFÁCIL; então já gera a etiqueta e já direciona
# para o ambiente certo".
#
# Ao salvar o agendamento com a origem escolhida:
#   1. o CONTATO passa a existir (antes o formulário só achava quem já existia
#      pelo telefone) — nasce com nome + telefone; sem telefone válido não cria;
#   2. o contato ganha a ETIQUETA da origem e perde a contrária (`cevico` ×
#      `of_agenda`):
#        CEVICO        → `cevico`
#        Oftalmofácil  → `oftalmofacil` + `of_agenda` (é o prefixo `of_` que
#                        liga a cerca dos parceiros: nenhuma IA, nenhum robô,
#                        lembrete só pela caixa do Oftalmofácil)
#   3. o CARD nasce no funil certo, em silêncio (sem disparar automação):
#        CEVICO        → coluna de agendamento da CEVICO, só se o paciente
#                        ainda não tem card lá (quem já tem fica onde está)
#        Oftalmofácil  → "Consulta Agendada" do funil do Oftalmofácil
# Nunca levanta exceção para quem chama: um erro aqui não desfaz o agendamento.
class Crm::AppointmentOrigin
  LABELS = { 'cevico' => %w[cevico], 'oftalmofacil' => %w[oftalmofacil of_agenda] }.freeze
  LABEL_COLORS = { 'cevico' => '#152C61', 'oftalmofacil' => '#0D9488', 'of_agenda' => '#0D9488' }.freeze
  # item 319: telefone digitado SEM DDD (8 ou 9 dígitos) ganha o DDD da clínica
  DEFAULT_DDD = '11'.freeze

  class << self
    def apply(account:, task:)
      return nil unless Task::ORIGINS.include?(task.origin)

      contact = task.contact || create_contact(account, task)
      return nil if contact.blank?

      task.update_column(:contact_id, contact.id) if task.contact_id != contact.id # rubocop:disable Rails/SkipsModelValidations
      Crm::Stamp.claim_contact!(contact, task.cevico_source_id) # 🏷️ item 322: o agendamento é evidência de quem é o paciente
      apply_labels(account, contact, task.origin)
      place_card(account, contact, task)
      contact
    rescue StandardError => e
      Rails.logger.error "[Crm::AppointmentOrigin] agendamento #{task&.id}: #{e.class}: #{e.message}"
      nil
    end

    # 📞 Item 319 (03/10; "precisamos normalizar a forma como o telefone é
    # compreendido… precisa poder sem o +55"): agendamento COM telefone e SEM
    # paciente vinculado. Acha o cadastro pelo telefone (últimos 8 dígitos) —
    # ele pode ter nascido DEPOIS do agendamento — ou cria (nome + telefone do
    # agendamento), amarra ao agendamento e põe o card no funil certo. É o que
    # o lembrete de confirmação chama antes de desistir ("telefone sem cadastro").
    # create: false = só procura (modo sombra não cria nada).
    def ensure_contact(account:, task:, create: true) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      return task.contact if task.contact.present?
      return nil if task.phone.blank?

      contact = Task.match_contact(account, task.phone) || (create ? create_contact(account, task) : nil)
      return nil if contact.blank?

      task.update_column(:contact_id, contact.id) # rubocop:disable Rails/SkipsModelValidations
      task.contact = contact
      Crm::Stamp.claim_contact!(contact, task.cevico_source_id) # 🏷️ item 322
      apply_labels(account, contact, task.origin) if Task::ORIGINS.include?(task.origin)
      place_card(account, contact, task)
      contact
    rescue StandardError => e
      Rails.logger.error "[Crm::AppointmentOrigin] cadastro do agendamento #{task&.id}: #{e.class}: #{e.message}"
      nil
    end

    # telefone como a equipe digita → +55DDDnúmero. Aceita com ou sem +55, com
    # zero na frente, com máscara; 8 ou 9 dígitos (sem DDD) ganham o DDD da
    # clínica. Não dá para entender = nil.
    def normalize_phone(raw)
      digits = raw.to_s.gsub(/\D/, '').sub(/\A0+/, '')
      digits = digits[2..] if digits.start_with?('55') && digits.length >= 12
      digits = "#{DEFAULT_DDD}#{digits}" if digits.length.between?(8, 9)
      digits.length.between?(10, 11) ? "+55#{digits}" : nil
    end

    private

    def create_contact(account, task)
      phone = normalize_phone(task.phone)
      return nil if phone.nil?

      attrs = { 'origem' => task.partner_origin? ? 'oftalmofacil' : 'agenda' }
      # 🏷️ item 322: paciente que nasce de um agendamento já nasce com a fonte do agendamento
      Crm::Stamp.with(via: Crm::Stamp.via, source: task.cevico_source_id) do
        account.contacts.create!(name: patient_name(task), phone_number: phone, additional_attributes: attrs)
      end
    rescue ActiveRecord::RecordInvalid
      # telefone já existe com outra máscara — acha de novo antes de desistir
      Task.match_contact(account, task.phone)
    end

    def patient_name(task)
      task.title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia|Retorno|P[oó]s-operat[oó]rio):\s*/i, '')
          .delete('✅').strip.presence || 'Paciente'
    end

    def apply_labels(account, contact, origin)
      wanted = LABELS[origin]
      # `oftalmofacil` fica: o sync também dá essa etiqueta a paciente da CEVICO (CATARATA_SP)
      others = LABELS.except(origin).values.flatten - %w[oftalmofacil]
      current = contact.label_list.map(&:to_s)
      target = (current - others + wanted).uniq
      return if target.sort == current.sort

      wanted.each { |title| ensure_label!(account, title) }
      contact.update!(label_list: target)
      Crm::PartnerGuard.forget!(account)
    end

    # a etiqueta precisa existir no cadastro da conta (senão some da tela)
    def ensure_label!(account, title)
      return if account.labels.exists?(title: title)

      account.labels.create!(title: title, color: LABEL_COLORS[title] || '#1f93ff', show_on_sidebar: true)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[Crm::AppointmentOrigin] etiqueta '#{title}': #{e.message}"
    end

    def place_card(account, contact, task)
      return unless task.task_type == 'consulta' && task.canceled_at.nil?
      # agendamento de parceiro (origem escolhida ou vindo do sync do hub) → funil do Oftalmofácil
      return Crm::PartnerFunnel.place!(account, contact, :booked) if Crm::PartnerGuard.partner_task?(task)

      place_own_card(account, contact)
    end

    def place_own_card(account, contact)
      stage_id = Crm::BookingSideEffects.booking_stage_id(account)
      stage = stage_id && Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).find_by(id: stage_id)
      return if stage.nil? || stage.pipeline_id == Crm::PartnerGuard.partner_pipeline_id(account)
      return if Crm::Contact.exists?(contact_id: contact.id, pipeline_id: stage.pipeline_id)

      Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id, origin: 'agenda')
    end
  end
end
