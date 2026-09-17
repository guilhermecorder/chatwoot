# 📞 Simulação local das ligações (item 167) — sem Meta, sem WebRTC: dispara
# o MESMO caminho do webhook com uma chamada marcada simulated, para ver
# popup, card na conversa e dashboard funcionando.
#
#   bundle exec rails cevico:calls_simulate ACCOUNT_ID=3                       # toca até alguém atender/encerrar
#   bundle exec rails cevico:calls_simulate ACCOUNT_ID=3 CONTACT_ID=12         # paciente existente
#   bundle exec rails cevico:calls_simulate ACCOUNT_ID=3 PHONE=5511999990000   # telefone avulso
#   bundle exec rails cevico:calls_simulate ACCOUNT_ID=3 SCENARIO=missed       # ninguém atende: terminate em 20 s
#   bundle exec rails cevico:calls_end CALL_ID=45 [DURATION=90] [STATUS=FAILED] # simula o terminate da Meta
fake_sdp = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=simulated\r\n"
business_digits = ->(inbox) { inbox.channel.try(:phone_number).to_s.delete('+') }
# caixa: INBOX_ID= > a configurada em Ligações > 1ª caixa WhatsApp (API oficial) > 1ª caixa
pick_inbox = lambda do |account|
  next account.inboxes.find(ENV['INBOX_ID']) if ENV['INBOX_ID'].present?

  Crm::Calls::Settings.new(account).inbox ||
    account.inboxes.where(channel_type: 'Channel::Whatsapp').detect { |i| i.channel.provider == 'whatsapp_cloud' } ||
    account.inboxes.find_by(channel_type: 'Channel::Whatsapp') || account.inboxes.first
end

desc 'Simula uma ligação recebida no WhatsApp (sem Meta) — ACCOUNT_ID= [CONTACT_ID=|PHONE=] [INBOX_ID=] [SCENARIO=ringing|missed]'
task 'cevico:calls_simulate' => :environment do
  account = Account.find(ENV.fetch('ACCOUNT_ID'))
  inbox = pick_inbox.call(account)
  abort 'nenhuma caixa encontrada (use INBOX_ID=)' unless inbox
  contact = ENV['CONTACT_ID'].present? ? account.contacts.find(ENV['CONTACT_ID']) : nil
  wa_id = (ENV['PHONE'].presence || contact&.phone_number || '5511999990000').to_s.gsub(/\D/, '')
  call_id = "sim-#{SecureRandom.hex(6)}"
  value = {
    'contacts' => [{ 'wa_id' => wa_id, 'profile' => { 'name' => contact&.name.presence || 'Paciente Simulado' } }],
    'calls' => [{ 'id' => call_id, 'from' => wa_id, 'to' => business_digits.call(inbox), 'event' => 'connect',
                  'direction' => 'USER_INITIATED', 'timestamp' => Time.current.to_i.to_s,
                  'session' => { 'sdp_type' => 'offer', 'sdp' => fake_sdp } }]
  }
  Crm::Calls::WebhookService.new(channel: inbox.channel, value: value, simulated: true).perform
  call = Crm::Call.find_by!(account: account, meta_call_id: call_id)
  puts "📞 ligação ##{call.id} (#{call.status}) — caixa #{inbox.name} · paciente #{call.contact&.name} (#{wa_id}) " \
       "· conversa ##{call.conversation&.display_id}"
  settings = Crm::Calls::Settings.new(account)
  unless settings.enabled? && settings.inbox_id == inbox.id
    puts '   ⚠️ o popup só aparece com Ligações ativas e esta caixa escolhida (Configurações → Ligações)'
  end
  if ENV['SCENARIO'] == 'missed'
    puts '   ninguém atende… terminate em 20 s'
    sleep 20
    ENV['CALL_ID'] = call.id.to_s
    Rake::Task['cevico:calls_end'].invoke
  else
    puts "   para encerrar: bundle exec rails cevico:calls_end CALL_ID=#{call.id}"
  end
end

desc 'Simula o terminate da Meta para uma ligação — CALL_ID= [DURATION=segundos] [STATUS=COMPLETED|FAILED]'
task 'cevico:calls_end' => :environment do
  call = Crm::Call.find(ENV.fetch('CALL_ID'))
  now = Time.current
  duration = ENV['DURATION'].presence&.to_i || (call.answered_at ? (now - call.answered_at).to_i : 0)
  value = {
    'calls' => [{ 'id' => call.meta_call_id, 'from' => call.wa_id, 'to' => business_digits.call(call.inbox),
                  'event' => 'terminate', 'direction' => call.inbound? ? 'USER_INITIATED' : 'BUSINESS_INITIATED',
                  'timestamp' => now.to_i.to_s, 'status' => ENV.fetch('STATUS', 'COMPLETED'),
                  'start_time' => call.started_at&.to_i&.to_s, 'end_time' => now.to_i.to_s, 'duration' => duration }]
  }
  Crm::Calls::WebhookService.new(channel: call.inbox.channel, value: value, simulated: true).perform
  call.reload
  puts "📵 ligação ##{call.id} encerrada: #{call.status} (#{call.end_reason}) · #{call.talk_seconds} s falados · card ##{call.message_id}"
end
