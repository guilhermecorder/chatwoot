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

  class << self
    def apply(account:, task:)
      return nil unless Task::ORIGINS.include?(task.origin)

      contact = task.contact || create_contact(account, task)
      return nil if contact.blank?

      task.update_column(:contact_id, contact.id) if task.contact_id != contact.id # rubocop:disable Rails/SkipsModelValidations
      apply_labels(account, contact, task.origin)
      place_card(account, contact, task)
      contact
    rescue StandardError => e
      Rails.logger.error "[Crm::AppointmentOrigin] agendamento #{task&.id}: #{e.class}: #{e.message}"
      nil
    end

    private

    def create_contact(account, task)
      digits = task.phone.to_s.gsub(/\D/, '')
      return nil if digits.length < 10

      attrs = { 'origem' => task.partner_origin? ? 'oftalmofacil' : 'agenda' }
      account.contacts.create!(name: patient_name(task), phone_number: e164(digits), additional_attributes: attrs)
    rescue ActiveRecord::RecordInvalid
      # telefone já existe com outra máscara — acha de novo antes de desistir
      Task.match_contact(account, task.phone)
    end

    def patient_name(task)
      task.title.to_s.sub(/\A(Consulta|Teleconsulta|Exame|Cirurgia|Retorno|P[oó]s-operat[oó]rio):\s*/i, '')
          .delete('✅').strip.presence || 'Paciente'
    end

    def e164(digits)
      digits.start_with?('55') && digits.length >= 12 ? "+#{digits}" : "+55#{digits}"
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
      return Crm::PartnerFunnel.place!(account, contact, :booked) if task.partner_origin?

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
