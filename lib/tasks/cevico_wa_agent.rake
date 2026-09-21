# 🗣️ SIMULADOR DO ATENDENTE DE AGENDAMENTO (rodada 188) — teste SEGURO com a IA
# de verdade, sem WhatsApp real: cria um paciente de teste numa conversa da
# caixa configurada, manda as mensagens que você escrever como se fosse ele e
# imprime o que o agente TERIA respondido (modo sombra: nada sai para ninguém).
#
#   docker exec -e MSGS="oi, quero fazer refrativa|quanto custa?|pode ser na terça" \
#     chatwoot-rails-1 bundle exec rails 'cevico:wa_agent_simulate[3]'
#   (as mensagens do paciente vão em MSGS, separadas por | — vírgulas dentro delas
#   são livres; na VPS troque o nome do container pelo do sistema_cevico web)
#
# Requisitos: chave da Claude em CRM → Integrações → Claude; Atendente de
# Agendamento LIGADO com uma caixa marcada (Automações → Agentes de IA).
# A conversa fica na caixa (com as notas 🕶️) e entra na tela Sombra.
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Simula um paciente conversando com o Atendente de Agendamento (sombra), com a IA de verdade'
  task :wa_agent_simulate, [:account_id, :messages] => :environment do |_t, args| # rubocop:disable Metrics/BlockLength
    account = Account.find(args[:account_id] || 3)
    cfg = CrmSetting.find_by(account: account)&.ai_config || {}
    agent = cfg.dig('agents', 'atendente_agendamento') || {}
    abort '⛔ Configure a chave da API em CRM → Integrações → Claude (nesta conta).' if cfg['api_key'].blank?
    unless agent['enabled'] == true && Array(agent['inbox_ids']).any?
      abort '⛔ Ligue o Atendente de Agendamento e marque uma caixa de WhatsApp (Automações → Agentes de IA → Publicar).'
    end

    inbox = account.inboxes.find(Array(agent['inbox_ids']).first)
    phone = "+5511#{rand(900_000_000..999_999_999)}"
    contact = account.contacts.create!(name: "Paciente Simulado #{Time.zone.now.strftime('%d/%m %H:%M')}", phone_number: phone)
    contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: phone.delete('+'))
    conversation = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox,
                                        additional_attributes: { 'cevico_simulado' => true }) # notas viram falas da clínica

    messages = (ENV['MSGS'].presence || args[:messages]).to_s.split('|').map(&:strip).compact_blank
    messages = ['oi, quero saber sobre cirurgia refrativa'] if messages.empty?

    mode = Crm::ResponderAgentJob.live_mode?(agent) ? 'AO VIVO' : 'sombra'
    puts "Conversa ##{conversation.display_id} · #{contact.name} · caixa #{inbox.name} · modo: #{mode}"
    messages.each do |text|
      message = conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :incoming, content: text, sender: contact)
      puts "\n🧑 PACIENTE: #{text}"
      Crm::ResponderAgentJob.perform_now(conversation.id, message.id, 'atendente_agendamento')

      note = conversation.messages.where(message_type: :activity).reorder(:id).last
      shadow = note&.additional_attributes&.dig('cevico_ia_shadow')
      if shadow && shadow['trigger_message_id'].to_i == message.id
        puts "🕶️ INTERNO (etapa #{shadow['etapa']}):"
        Array(shadow['mensagens']).each_with_index { |t, i| puts "   #{i + 1}) #{t}" }
        if shadow['agendar']
          ag = shadow['agendamento'] || {}
          valid = shadow['slot_valid'] ? 'vaga válida ✓' : 'vaga NÃO validou ✗'
          puts "   📅 agendaria #{ag['dia']} #{ag['hora']} · #{ag['unidade']} · #{ag['nome']} · #{valid}"
        end
        puts '   🙋 chamaria humano' if shadow['chamar_humano']
        puts '   ⏸ encerraria (pausar)' if shadow['pausar']
        Array(shadow['acoes']).each { |a| puts "   🔧 #{a['resumo']}" } # ferramentas (rodada 192)
        puts "   💭 #{shadow['leitura']}" if shadow['leitura'].present?
      else
        last = Array(CrmSetting.find_by(account: account)&.ai_config&.dig('atendente_agendamento_state', 'events')).first || {}
        puts "⚠️ sem nota — último registro: #{last['type']} #{last['note']}"
      end
    end
    puts "\n✅ Fim. Abra a conversa ##{conversation.display_id} na caixa ou a tela Sombra (card do agente) para ver lado a lado."
  end
end
