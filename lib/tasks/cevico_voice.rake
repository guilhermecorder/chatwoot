# 🤖📞 Agente de Ligação (item 169) — utilitários locais, sem ElevenLabs:
#
#   bundle exec rails cevico:voice_simulate ACCOUNT_ID=3                              # ligação recebida, atendida pela IA
#   bundle exec rails cevico:voice_simulate ACCOUNT_ID=3 PHONE=5511999990000 OUTCOME=remarcou
#   bundle exec rails cevico:voice_simulate ACCOUNT_ID=3 DIRECTION=outbound CAMPAIGN_ID=1  # fecha um contato "calling" da campanha
#   bundle exec rails cevico:voice_tools ACCOUNT_ID=3 PHONE=5511999990000               # roda as 6 ferramentas e imprime
#   bundle exec rails cevico:voice_sync ACCOUNT_ID=3                                    # SyncService (CEVICO_VOICE_SIMULATE=1 = sem rede)
#
# A simulação monta um payload post_call_transcription realista e passa
# pelo MESMO Crm::VoiceAgent::PostCallService do webhook — dá para ver o
# card na conversa, o Espaço do Paciente e o Dashboard sem a ElevenLabs.
def voice_simulated_transcript(name, outcome)
  first = name.to_s.split(/\s+/).first.presence || 'paciente'
  closing = 'Consulta marcada. Vou te mandar a confirmação pelo WhatsApp. A CEVICO agradece, até logo!'
  closing = 'Sem problemas. A CEVICO agradece a ligação, até logo!' if outcome == 'sem_interesse'
  closing_tools = %w[marcar_consulta enviar_whatsapp registrar_resultado].map { |t| { 'tool_name' => t } }
  [
    { 'role' => 'agent', 'time_in_call_secs' => 0, 'message' => Crm::VoiceAgent::Script::FIRST_MESSAGE },
    { 'role' => 'user', 'time_in_call_secs' => 4, 'message' => "Oi, aqui é #{first}. Queria marcar uma consulta de avaliação." },
    { 'role' => 'agent', 'time_in_call_secs' => 8, 'tool_calls' => [{ 'tool_name' => 'buscar_paciente' }],
      'message' => 'Claro! Você prefere a unidade Paulista ou Tatuapé?' },
    { 'role' => 'user', 'time_in_call_secs' => 12, 'message' => 'Tatuapé, de manhã.' },
    { 'role' => 'agent', 'time_in_call_secs' => 16, 'tool_calls' => [{ 'tool_name' => 'horarios_livres' }],
      'message' => 'Tenho sexta-feira às dez e meia da manhã ou às dez e quarenta. Qual fica melhor?' },
    { 'role' => 'user', 'time_in_call_secs' => 21, 'message' => 'Dez e meia.' },
    { 'role' => 'agent', 'time_in_call_secs' => 25, 'message' => 'Confirmando: sexta-feira às dez e meia da manhã, na unidade Tatuapé. Está certo?' },
    { 'role' => 'user', 'time_in_call_secs' => 29, 'message' => 'Certo.' },
    { 'role' => 'agent', 'time_in_call_secs' => 33, 'message' => closing, 'tool_calls' => closing_tools }
  ]
end

# payload post_call_transcription no formato da ElevenLabs
def voice_simulated_payload(conversation_id:, name:, phone:, direction:, outcome:)
  {
    'type' => 'post_call_transcription', 'event_timestamp' => Time.current.to_i,
    'data' => {
      'agent_id' => 'sim_agent', 'conversation_id' => conversation_id, 'status' => 'done',
      'transcript' => voice_simulated_transcript(name, outcome),
      'metadata' => { 'start_time_unix_secs' => 3.minutes.ago.to_i, 'call_duration_secs' => 130, 'cost' => 260, 'cost_fiat' => 0.0312,
                      'termination_reason' => 'end_call tool was called.',
                      'whatsapp' => { 'direction' => direction, 'whatsapp_user_id' => phone, 'whatsapp_phone_number_id' => 'sim_phone' } },
      'analysis' => { 'transcript_summary' => "#{name} ligou para marcar consulta de avaliação; ficou para sexta às 10h30 na unidade Tatuapé.",
                      'call_successful' => 'success',
                      'data_collection_results' => { 'resultado' => { 'value' => outcome, 'rationale' => 'simulação' } } },
      'conversation_initiation_client_data' => {
        'dynamic_variables' => { 'paciente_nome' => name, 'telefone' => phone, 'system__caller_id' => "+#{phone}" }
      }
    }
  }
end

# PHONE= > telefone do contato da campanha > 1º contato com telefone > número fictício
def voice_pick_phone(account, campaign_contact = nil)
  raw = ENV['PHONE'].presence || campaign_contact&.contact&.phone_number ||
        account.contacts.where.not(phone_number: [nil, '']).order(:id).pick(:phone_number) || '5511999990000'
  raw.to_s.gsub(/\D/, '')
end

# contato da campanha a fechar (calling, senão queued), já marcado como calling
def voice_pick_campaign_contact(account)
  return nil unless ENV.fetch('DIRECTION', 'inbound') == 'outbound' && ENV['CAMPAIGN_ID'].present?

  campaign = Crm::CallCampaign.where(account: account).find(ENV.fetch('CAMPAIGN_ID'))
  row = campaign.campaign_contacts.calling.first || campaign.campaign_contacts.queued.first
  abort 'campanha sem contato em calling/queued' unless row

  row.update!(status: 'calling', called_at: row.called_at || Time.current,
              provider_conversation_id: row.provider_conversation_id || "sim_conv_#{SecureRandom.hex(4)}")
  row
end

desc 'Simula o pós-chamada de uma ligação da assistente virtual — ACCOUNT_ID= [PHONE=] [OUTCOME=agendou] [DIRECTION=inbound|outbound] [CAMPAIGN_ID=]'
task 'cevico:voice_simulate' => :environment do
  account = Account.find(ENV.fetch('ACCOUNT_ID'))
  campaign_contact = voice_pick_campaign_contact(account)
  phone = voice_pick_phone(account, campaign_contact)
  contact = campaign_contact&.contact || Task.match_contact(account, phone)
  payload = voice_simulated_payload(
    conversation_id: campaign_contact&.provider_conversation_id || "sim_conv_#{SecureRandom.hex(4)}",
    name: contact&.name.presence || 'Paciente Simulado', phone: phone,
    direction: ENV.fetch('DIRECTION', 'inbound'), outcome: ENV.fetch('OUTCOME', 'agendou')
  )
  call = Crm::VoiceAgent::PostCallService.new(account: account, payload: payload).perform
  abort 'nenhuma caixa WhatsApp na conta — configure a caixa de handoff (Configurações → Agente de Ligação)' unless call

  puts "🤖 ligação ##{call.id} (#{call.direction}/#{call.status}) — #{call.card_content}"
  puts "   paciente #{call.contact&.name} (#{phone}) · conversa ##{call.conversation&.display_id} · card ##{call.message_id} " \
       "· custo US$ #{call.cost_usd}"
  puts "   contato da campanha ##{campaign_contact.id}: #{campaign_contact.reload.status} / #{campaign_contact.outcome}" if campaign_contact
  puts '   dashboard: Relatórios → Dashboard de Ligações · painel: Automações → Painel dos agentes → Agente de Ligação'
end

desc 'Roda as 6 ferramentas da assistente localmente e imprime — ACCOUNT_ID= [PHONE=]'
task 'cevico:voice_tools' => :environment do
  account = Account.find(ENV.fetch('ACCOUNT_ID'))
  phone = voice_pick_phone(account)
  conversation_id = "sim_tools_#{SecureRandom.hex(3)}"
  run = lambda do |tool, params|
    result = Crm::VoiceAgent::ToolsService.new(account: account, tool: tool, params: params.merge('telefone' => phone),
                                               conversation_id: conversation_id).perform
    puts "▶ #{tool}: #{result.to_json}"
    result
  end
  run.call('buscar_paciente', {})
  first = (run.call('horarios_livres', { 'dias' => 7 })[:horarios] || []).first
  if first
    run.call('marcar_consulta', { 'nome' => 'Paciente Simulado', 'data' => first[:data], 'hora' => first[:hora],
                                  'unidade' => first[:unidade_codigo], 'medico' => first[:medico], 'procedimento' => 'consulta de avaliação' })
  end
  run.call('minha_consulta', {})
  run.call('enviar_whatsapp', { 'tipo' => 'confirmacao' })
  run.call('registrar_resultado', { 'resultado' => 'agendou', 'resumo' => 'Consulta marcada na simulação das ferramentas.' })
end

desc 'Sincroniza o agente com a ElevenLabs — ACCOUNT_ID= (CEVICO_VOICE_SIMULATE=1 não chama a rede)'
task 'cevico:voice_sync' => :environment do
  account = Account.find(ENV.fetch('ACCOUNT_ID'))
  result = Crm::VoiceAgent::SyncService.new(account).perform
  result[:log].each { |line| puts "   #{line}" }
  puts result[:ok] ? '✅ sincronizado' : "❌ #{result[:error]}"
end
