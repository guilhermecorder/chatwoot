# Caminho ÚNICO do Secretário da Agenda (rodada 148 — "agendamento 100%"):
# lê a conversa (Crm::AppointmentExtractionService) e escreve o resultado na
# Agenda — cria, REAGENDA ou CANCELA a consulta — com nota privada na conversa
# e linha no registro de atividade do agente. Usado pela automação de coluna
# (CrmAutomationFireJob) e pela releitura automática (SchedulerRecheckJob):
# um código só = mesmo comportamento em qualquer gatilho.
class Crm::AppointmentApplier
  # duas leituras quase simultâneas (card entrou + mensagem da cadeia) não
  # gastam IA duas vezes nem duplicam nota: a segunda dentro desta janela
  # vira no-op silencioso
  MIN_GAP = 2.minutes

  class << self
    def call(account:, contact:, conversation:, default_unit: nil)
      return :no_conversation if conversation.blank? || contact.blank?
      return :throttled if read_recently?(contact)

      stamp_read(contact)
      result = Crm::AppointmentExtractionService.new(conversation: conversation).call
      if result[:error]
        Rails.logger.warn("[Crm::AppointmentApplier] #{result[:error]}")
        # erro NÃO fica invisível: entra no registro do agente (antes só ia
        # pro log do servidor e o paciente escapava sem ninguém ver)
        Crm::AppointmentRecorder.log_activity(account, result, contact, conversation, :erro)
        return :error
      end

      name = display_name(result, contact)
      booked = result[:found] && result[:starts_at].present?

      # cancelamento SEM novo horário → tira a consulta futura da agenda;
      # "remarcou para quinta" (novo horário confirmado) segue o caminho
      # normal, que já REAGENDA a consulta futura em vez de duplicar
      return apply_cancel(account, result, contact, conversation, name) if result[:cancel] && !booked
      return apply_booking(account, result, contact, conversation, name, default_unit) if booked

      apply_revision(account, result, contact, conversation, name)
    end

    private

    def apply_booking(account, result, contact, conversation, name, default_unit)
      outcome = Crm::AppointmentRecorder.record(
        account: account, result: result, contact: contact,
        conversation: conversation, default_unit: default_unit
      )
      return outcome if outcome == :already # nada mudou — sem nota repetida

      unit = result[:unit].presence || default_unit
      local_time = result[:starts_at].in_time_zone('America/Sao_Paulo')
      when_str = local_time.strftime('%d/%m/%Y às %H:%M')
      verb = outcome == :rescheduled ? 'REAGENDADA' : 'agendada'
      agenda_url = "/app/accounts/#{account.id}/agenda?date=#{local_time.strftime('%Y-%m-%d')}"
      note = "📅 Consulta #{verb} pela IA: #{name} — #{when_str}" \
             "#{unit ? " (#{unit == 'tatuape' ? 'Tatuapé' : 'Av. Paulista'})" : ''}. " \
             "Registrada na Agenda. [📆 Ver na agenda](#{agenda_url})"
      private_note(account, conversation, note)
      outcome
    end

    def apply_cancel(account, result, contact, conversation, name)
      outcome = Crm::AppointmentRecorder.cancel_future(
        account: account, result: result, contact: contact, conversation: conversation
      )
      if outcome == :canceled
        private_note(account, conversation,
                     "📅 Consulta de #{name} CANCELADA a pedido do paciente (Secretário da Agenda). " \
                     'Saiu da agenda — vale um contato para reagendar.')
      else
        # pediu cancelar/remarcar mas não achei consulta futura no sistema →
        # tarefa para a equipe conferir (pode estar só no Google Calendar)
        create_revision_task(account, result, contact, name,
                             title: "⚠️ Pediu cancelar/remarcar: #{name}",
                             description: "O paciente pediu cancelamento/remarcação na conversa, mas não " \
                                          "encontrei consulta futura dele na Agenda do sistema.\n#{revision_notes(result, conversation)}")
        private_note(account, conversation,
                     "📅 #{name} pediu cancelamento/remarcação, mas não encontrei a consulta na Agenda — " \
                     'criei uma tarefa para a equipe conferir.')
        Crm::AppointmentRecorder.log_activity(account, result, contact, conversation, :cancel_no_match)
      end
      outcome
    end

    def apply_revision(account, result, contact, conversation, name)
      created = create_revision_task(account, result, contact, name,
                                     title: "⚠️ Confirmar consulta: #{name}",
                                     description: "A IA não encontrou dia e hora confirmados na conversa.\n" \
                                                  "#{revision_notes(result, conversation)}")
      if created
        private_note(account, conversation,
                     "📅 A IA não conseguiu confirmar dia e hora da consulta de #{name} — " \
                     'criei uma tarefa de revisão para a equipe.')
        # a leitura "sem dados" aparece no registro do agente na PRIMEIRA
        # detecção (tarefa criada) — é assim que se enxerga quem escapou;
        # releituras seguintes sem novidade não poluem o registro
        Crm::AppointmentRecorder.log_activity(account, result, contact, conversation, :skipped)
      end
      :skipped
    end

    # tarefa de revisão SEM duplicar: 1 aberta por PACIENTE (antes o freio era
    # pelo título — dois pacientes sem nome viravam "Paciente" e o segundo era
    # pulado em silêncio). O título exato só segura tarefas ANTIGAS sem
    # contact_id — pacientes diferentes de mesmo nome não se bloqueiam mais.
    # Devolve true se criou.
    def create_revision_task(account, result, contact, name, title:, description:)
      open_tasks = account.tasks.where(status: %i[todo doing])
      return false if open_tasks.where(contact_id: contact.id)
                                .where("title LIKE '⚠️ Confirmar consulta%' OR title LIKE '⚠️ Pediu cancelar%'")
                                .exists?
      return false if open_tasks.where(contact_id: nil).exists?(title: title)

      creator = account.administrators.first || account.users.first
      return false unless creator

      account.tasks.create!(
        title: title,
        description: description,
        unit: result[:unit].presence,
        phone: result[:phone].presence || contact.phone_number,
        contact: contact,
        procedure: result[:procedure].presence,
        doctor: result[:doctor].presence,
        task_type: 'consulta',
        priority: :high,
        status: :todo,
        creator: creator,
        assignee: Crm::TaskOwner.resolve(account, contact: contact, task_type: 'consulta')
      )
      true
    end

    def revision_notes(result, conversation)
      [result[:notes].presence, conversation && "Conversa ##{conversation.display_id} — Secretário da Agenda"].compact.join("\n")
    end

    def private_note(account, conversation, content)
      conversation.messages.create!(
        account: account,
        inbox: conversation.inbox,
        message_type: :activity,
        content: content,
        private: true
      )
    end

    def display_name(result, contact)
      result[:name].presence || contact&.name.presence || 'Paciente'
    end

    def read_recently?(contact)
      last = contact.additional_attributes&.dig('cevico_scheduler_last_read_at')
      return false if last.blank?

      Time.zone.parse(last.to_s) > MIN_GAP.ago
    rescue ArgumentError, TypeError
      false
    end

    def stamp_read(contact)
      Cevico::AttributeMerge.merge!(contact) do |attrs|
        attrs.merge('cevico_scheduler_last_read_at' => Time.current.iso8601)
      end
    rescue StandardError => e
      Rails.logger.warn "[Crm::AppointmentApplier] stamp: #{e.message}"
    end
  end
end
