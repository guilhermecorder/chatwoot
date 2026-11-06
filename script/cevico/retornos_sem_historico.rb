# rubocop:disable Rails/Output, Metrics/AbcSize, Style/FormatStringToken
# relatório de leitura, roda por rails runner
# RETORNOS SEM HISTÓRICO — SÓ LEITURA (não grava nada no banco).
#
# Caso 19/10 (Vaneide): paciente nova marcada pelo robô nasceu como RETORNO e a
# confirmação saiu "Valor da avaliação: R$sem custo à vista". Este script lista,
# para a equipe corrigir na Agenda (tipo → Avaliação, valor → o da avaliação):
#
#   1) O DIAGNÓSTICO de um paciente (PHONE=... ou CONVERSA=...): todas as
#      consultas que o sistema enxerga como dele e qual delas fez a regra antiga
#      dizer "já tinha consulta antes".
#   2) A LISTA dos agendamentos criados nos últimos DIAS (padrão 14) com tipo
#      retorno + valor em texto ("sem custo") cujo paciente NÃO tem consulta
#      anterior que aconteceu (não cancelada, não arquivada, sem falta, já
#      passada). Mostra se a confirmação já saiu com esse valor.
#
# Rodar na VPS (Guilherme) — não precisa do deploy novo, roda no código que está no ar:
#   C=$(docker ps --format '{{.Names}}' | grep -E 'sistema_cevico_(web|chatwoot)' | head -1)
#   docker exec -i -e PHONE=1199016825 -e CONVERSA=18371 "$C" bundle exec rails runner - < retornos_sem_historico.rb
#
# Variáveis (todas opcionais): ACCOUNT_ID (padrão: a 1ª conta), DIAS (14),
# PHONE (telefone do paciente a diagnosticar), CONVERSA (nº da conversa).
ACCOUNT_ID = (ENV['ACCOUNT_ID'] || Account.order(:id).pick(:id)).to_i
DIAS = (ENV['DIAS'] || 14).to_i
TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
account = Account.find(ACCOUNT_ID)
price_cfg = Crm::AppointmentPrice.config(account)

def hora(time)
  time ? time.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M') : '—'
end

def quem_marcou(task)
  text = task.description.to_s
  return "robô (conversa ##{text[/Conversa #(\d+)/, 1]})" if text.match?(/agendado pela IA/i)
  return 'Oftalmofácil' if task.partner_origin? || task.external_ref.present?

  "equipe (#{task.creator&.name || '?'})"
end

def linha(task)
  flags = []
  flags << "CANCELADA #{hora(task.canceled_at)}" if task.canceled_at
  flags << 'arquivada' if task.archived_at
  flags << "presença: #{task.attendance}" if task.attendance.present?
  flags << 'lançada (registro)' if task.booking_kind == 'registro'
  format('    #%-7d %-16s %-11s %-10s %-9s contato=%-7s criada %s por %s %s',
         task.id, hora(task.due_at), task.task_type, task.modality.to_s.presence || '(sem tipo)', task.unit.to_s,
         task.contact_id.to_s.presence || '—', hora(task.created_at), quem_marcou(task), flags.join(' · '))
end

# consultas anteriores que ACONTECERAM (regra nova) e as que só "existiam" (regra antiga)
def anteriores(account, task)
  before = [task.due_at, Time.current].compact.min
  scope = account.tasks.where(task_type: 'consulta').where('due_at < ?', before).where.not(id: task.id).order(:due_at)
  digits = task.phone.to_s.gsub(/\D/, '')
  todas = if task.contact
            scope.merge(Task.for_patient(account, task.contact)).to_a
          elsif digits.length >= 8
            scope.where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
                 .select { |t| Crm::AppointmentRecorder.same_phone_line?(digits, t.phone) }
          else
            []
          end
  reais = todas.select { |t| t.canceled_at.nil? && t.archived_at.nil? && t.attendance != 'missed' }
  [reais, todas - reais]
end

def confirmacao_enviada(task)
  marks = (task.contact&.additional_attributes || {}).dig('cevico_appt_reminders', task.id.to_s) || {}
  marks.keys.grep(/\Ad\d\z/).map { |regua| "#{regua.upcase} em #{hora(Time.zone.parse(marks[regua].to_s))}" }.join(', ')
rescue StandardError
  marks.keys.grep(/\Ad\d\z/).join(', ')
end

puts "Conta #{account.id} (#{account.name}) · agora #{hora(Time.current)} · regra: consulta anterior só conta se aconteceu"
puts

# ── 1) diagnóstico de um paciente ───────────────────────────────────────
phone = ENV['PHONE'].to_s.gsub(/\D/, '')
conversa = ENV['CONVERSA'].presence && account.conversations.find_by(display_id: ENV['CONVERSA'].to_i)
contact = conversa&.contact || (phone.length >= 8 && Task.match_contact(account, phone))
if phone.present? || conversa
  puts "═══ 1) DIAGNÓSTICO · telefone #{phone.presence || '—'} · conversa ##{conversa&.display_id || '—'}"
  if contact
    puts "  contato ##{contact.id} #{contact.name} · #{contact.phone_number} · etiquetas: #{contact.label_list.join(', ').presence || '—'}"
    outros = account.contacts.where.not(id: contact.id).select do |c|
      Crm::AppointmentRecorder.same_phone_line?(contact.phone_number.to_s.gsub(/\D/, ''), c.phone_number)
    end
    outros.each { |c| puts "  ⚠ outro cadastro da MESMA linha: ##{c.id} #{c.name} · #{c.phone_number}" }
    puts '  consultas que o sistema enxerga como deste paciente (Task.for_patient):'
    Task.for_patient(account, contact).where(task_type: %w[consulta cirurgia]).order(:due_at).each { |t| puts linha(t) }
  else
    puts '  nenhum contato encontrado para esse telefone/conversa'
    if phone.length >= 8
      puts '  consultas SEM contato com esse final de telefone:'
      account.tasks.where(contact_id: nil).where("regexp_replace(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{phone.last(8)}")
             .order(:due_at).each { |t| puts linha(t) }
    end
  end
  puts
end

# ── 2) retornos recentes sem consulta anterior que aconteceu ─────────────
puts "═══ 2) RETORNOS criados nos últimos #{DIAS} dias com valor em texto e SEM consulta anterior que aconteceu"
recentes = account.tasks.where(task_type: 'consulta', modality: 'retorno', canceled_at: nil)
                  .where('created_at >= ?', DIAS.days.ago).includes(:contact, :creator).order(:created_at)
achados = 0
recentes.each do |task|
  price = Crm::AppointmentPrice.resolve(price_cfg, task)
  valor = price&.dig(:text).to_s
  next if Crm::AppointmentPrice.to_number(valor) # valor em número: não é o caso deste erro

  reais, fantasmas = anteriores(account, task)
  next if reais.any? # tem consulta anterior de verdade: retorno legítimo

  achados += 1
  puts
  puts "▶ ##{task.id} #{task.title} · #{hora(task.due_at)} · #{task.unit} · #{task.doctor}"
  puts "   valor na confirmação: \"#{valor}\" (#{price&.dig(:label)}) · confirmou? #{task.confirmed_at ? 'sim' : 'não'}"
  puts "   marcada #{hora(task.created_at)} por #{quem_marcou(task)} · contato ##{task.contact_id || '—'} · tel #{task.phone}"
  enviada = confirmacao_enviada(task)
  puts "   ⚠ confirmação JÁ SAIU com esse valor: #{enviada}" if enviada.present?
  if fantasmas.any?
    puts '   o que enganou a regra antiga (consulta que não aconteceu):'
    fantasmas.each { |t| puts linha(t) }
  else
    puts '   (nenhuma consulta anterior — tipo escolhido à mão ou herdado de remarcação)'
  end
  puts '   → corrigir na Agenda: tipo = Avaliação, valor = o da avaliação'
end
puts
puts "#{achados} agendamento(s) para corrigir de #{recentes.size} retorno(s) criados no período."
# rubocop:enable Rails/Output, Metrics/AbcSize, Style/FormatStringToken
