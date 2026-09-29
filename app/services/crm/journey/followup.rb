# 🔁 REFORÇO das mensagens da jornada (item 288, 29/09 — pedido do Guilherme:
# "enviamos a confirmação de cirurgia e ele passa 6 horas e não responde;
# precisamos poder enviar outra mensagem de lembrete").
#
# Vale para as mensagens do DIA DA CIRURGIA e do DIA DA CONSULTA que tenham o
# reforço ligado (content['followup'], desligado por padrão). N horas depois
# do envio, se o paciente não escreveu nada e a cirurgia/consulta continua de
# pé (não confirmou, não recusou, não cancelou, não mudou de data), sai a
# mensagem modelo do reforço. O 2º reforço conta as horas a partir do 1º.
#
# Só entre 07h e 20h (São Paulo) e dentro do horário da jornada: o que venceria
# de madrugada sai na primeira rodada depois das 07h. Nunca depois do horário
# da cirurgia/consulta.
#
# NUNCA DUAS VEZES: o reforço é um Crm::JourneySend próprio, com a chave do
# envio original + ":f1"/":f2". O índice único do banco (mensagem × chave) faz
# a segunda tentativa falhar antes de qualquer envio. Reforço que falhou não é
# tentado de novo sozinho (fica no histórico, com "reenviar").
#
# Paciente de parceiro do Oftalmofácil: a jornada não manda nada para eles
# (cerca do item 231) — o reforço passa pelo mesmo bloqueio do Dispatcher.
class Crm::Journey::Followup
  TZ = Crm::Journey::Settings::TZ
  WINDOW_HOURS = (7...20)
  # reforço "vencido" há mais de um dia não sai (ligar o reforço hoje não vira rajada)
  STALE_AFTER = 24.hours

  attr_reader :account, :now, :settings

  def initialize(account:, now: nil)
    @account = account
    @now = (now || TZ.now).in_time_zone(TZ)
    @settings = Crm::Journey::Settings.new(account)
  end

  # devolve quantos reforços saíram
  def perform
    return 0 unless window?

    budget = settings.daily_cap - sent_today
    sent = 0
    Crm::JourneyMessage.where(account: account).active.select(&:followup?).each do |message|
      candidates(message).find_each do |parent|
        break if budget - sent <= 0

        sent += 1 if followup!(parent, message) == :sent
      rescue StandardError => e
        Rails.logger.error("[CEVICO jornada] reforço do envio #{parent.id}: #{e.message}")
      end
    end
    sent
  end

  # por que ESTE reforço não deve sair (nil = pode sair). Usado antes de criar
  # o envio e de novo pelo Dispatcher na hora de mandar.
  def blocker_for(send) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    message = send.journey_message
    parent = send.parent
    return 'Reforço desligado nesta mensagem' unless message&.followup?
    return 'Envio original não encontrado' if parent.nil? || parent.status != 'sent' || parent.sent_at.nil?
    return 'Passou do número de reforços desta mensagem' if send.followup_number > message.followup_max
    return 'Fora do horário de envio (07h às 20h)' unless window?
    return 'Paciente já respondeu' if replied?(parent)

    event_blocker(parent)
  end

  private

  def window?
    WINDOW_HOURS.cover?(now.hour) && settings.within_hours?(now)
  end

  def dispatcher
    @dispatcher ||= Crm::Journey::Dispatcher.new(account: account, now: now)
  end

  # envios originais (não reforço, não teste) sem resposta, já com as horas vencidas
  def candidates(message)
    oldest = now - ((message.followup_hours * Crm::JourneyMessage::FOLLOWUP_MAX).hours + STALE_AFTER)
    message.sends.where(account_id: account.id, status: 'sent', reply: nil)
           .where(sent_at: oldest..(now - message.followup_hours.hours))
           .where.not('event_key ~ ?', ':f[0-9]+$')
           .where.not('event_key LIKE ?', 'teste:%')
           .includes(:contact, :source)
  end

  def followup!(parent, message)
    number = next_number(parent, message)
    return nil if number.nil?

    draft = Crm::JourneySend.new(account: account, journey_message: message, contact_id: parent.contact_id, source: parent.source,
                                 event_key: Crm::JourneySend.followup_key(parent.event_key, number),
                                 scheduled_for: now, status: 'queued')
    return nil if blocker_for(draft)
    return nil unless claim(draft)

    dispatcher.dispatch(draft)
  end

  # o INSERT é a trava: a segunda tentativa do mesmo reforço bate no índice único
  def claim(draft)
    draft.save!
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # qual reforço é o da vez (1 ou 2) — nil quando não é hora de nenhum
  def next_number(parent, message) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    keys = (1..Crm::JourneyMessage::FOLLOWUP_MAX).map { |n| Crm::JourneySend.followup_key(parent.event_key, n) }
    rows = message.sends.where(event_key: keys).index_by(&:event_key)
    done = keys.take_while { |k| rows[k] }.size
    return nil if done >= message.followup_max

    last = done.zero? ? parent : rows[keys[done - 1]]
    return nil if last.status != 'sent' || last.sent_at.nil?

    due_at = last.sent_at + message.followup_hours.hours
    due_at.between?(now - STALE_AFTER, now) ? done + 1 : nil
  end

  # respondeu pelo botão/palavra (reply) OU escreveu qualquer coisa depois do envio
  def replied?(parent)
    return true if parent.reply.present?

    Message.joins(:conversation).where(conversations: { contact_id: parent.contact_id, account_id: account.id })
           .where(message_type: :incoming).exists?(['messages.created_at > ?', parent.sent_at])
  end

  def event_blocker(parent)
    source = parent.source
    why, at = case source
              when Crm::OftalmofacilSurgery then [surgery_blocker(source), surgery_time(source)]
              when Task then [task_blocker(source), source.due_at]
              else ['Envio sem cirurgia ou consulta ligada', nil]
              end
    return why if why
    return 'A data ou a hora mudou depois do envio' if moved?(parent, source)
    return 'O horário da cirurgia/consulta já passou' if at.nil? || at <= now

    nil
  end

  def surgery_blocker(surgery)
    surgery.status_kind == 'agendada' ? nil : 'A cirurgia não está mais agendada'
  end

  def task_blocker(task)
    return 'A consulta foi cancelada' if task.canceled_at.present? || task.archived_at.present?
    return 'A consulta já foi confirmada' if task.confirmed_at.present?
    return 'O paciente já avisou que não vem' if task.declined_at.present?
    return 'A consulta já aconteceu' if task.attendance.present?

    nil
  end

  # cirurgia sem hora no hub: vale o começo do dia (no dia da cirurgia não sai reforço)
  def surgery_time(surgery)
    date = surgery.surgery_date
    return nil if date.nil?

    hour, minute = surgery.surgery_hour.to_s.match(/(\d{1,2}):(\d{2})/)&.captures&.map(&:to_i)
    TZ.local(date.year, date.month, date.day, (hour || 0).clamp(0, 23), (minute || 0).clamp(0, 59))
  end

  # compara a data e a hora de HOJE com as que foram no envio original
  def moved?(parent, source)
    before = (parent.variables || {}).slice('data', 'hora')
    return false if before.empty?

    current = Crm::Journey::Variables.build(source, parent.contact, settings).slice('data', 'hora')
    before.any? { |key, value| current[key].to_s != value.to_s }
  end

  def sent_today
    day_start = TZ.local(now.year, now.month, now.day)
    Crm::JourneySend.where(account: account, status: 'sent', sent_at: day_start..now).count
  end
end
