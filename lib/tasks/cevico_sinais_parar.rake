# 🚦 Saúde do WhatsApp (16/10/2026): motivo das marcações ANTIGAS de nao_perturbe.
#
# Até 16/10 o detector marcava nao_perturbe quando a mensagem só COMEÇAVA com
# "pare/sair/cancelar/remover…" — "Cancelar a consulta de amanhã" e "Sair de
# casa às 8h?" entravam. Esta tarefa NÃO tira etiqueta de ninguém: acha a
# mensagem que gerou cada marcação automática (a nota "🛑 Paciente pediu…" e a
# mensagem do paciente logo antes), grava o MOTIVO no contato e marca
# "revisar" quando o detector novo NÃO marcaria — a tela Saúde do WhatsApp
# mostra essas pessoas para a equipe decidir ("não é isso" tira a etiqueta).
#
#   ACCOUNT_ID=1 DRY=1 bundle exec rake cevico:sinais_parar:motivos_antigos   # só lista
#   ACCOUNT_ID=1 DRY=0 bundle exec rake cevico:sinais_parar:motivos_antigos   # grava o motivo
namespace :cevico do
  namespace :sinais_parar do
    desc 'Grava o motivo das marcações antigas de nao_perturbe e aponta as que o detector novo não marcaria (DRY=1 só lista)'
    task motivos_antigos: :environment do
      abort('❌ informe a conta: ACCOUNT_ID=1') if ENV['ACCOUNT_ID'].blank?

      account = Account.find(ENV.fetch('ACCOUNT_ID'))
      dry = ENV.fetch('DRY', '1') != '0'
      note_prefix = '🛑 Paciente pediu para não receber mais mensagens ativas'
      totals = Hash.new(0)

      account.contacts.tagged_with(Crm::OptOut::LABEL).find_each do |contact|
        totals[:marcados] += 1
        next totals[:ja_tinha_motivo] += 1 if Crm::StopSignals.evidence(contact)[Crm::OptOut::LABEL].present?

        note = Message.joins(:conversation).where(conversations: { contact_id: contact.id })
                      .where(message_type: :activity).where('messages.content LIKE ?', "#{note_prefix}%")
                      .reorder('messages.created_at ASC').first
        next totals[:marcado_a_mao] += 1 if note.nil? # etiqueta posta por pessoa — não há o que conferir

        trigger = note.conversation.messages.where(message_type: :incoming).where('created_at <= ?', note.created_at + 5.seconds)
                      .reorder(created_at: :desc).first
        next totals[:sem_mensagem] += 1 if trigger.nil?

        verdict = Crm::OptOut.classify(trigger.content)
        review = verdict != :certo
        totals[review ? :revisar : :confirmado] += 1
        puts "#{review ? '⚠️ REVISAR' : '✅ certo  '} contato #{contact.id} #{contact.name.to_s.truncate(28)} — “#{trigger.content.to_s.squish.truncate(70)}”"
        next if dry

        proof = { 'texto' => trigger.content.to_s.squish.truncate(200), 'message_id' => trigger.id, 'inbox_id' => trigger.inbox_id,
                  'conversa' => note.conversation.display_id, 'antigo' => true, 'revisar' => review,
                  'ultima_entregue' => Crm::StopSignals.last_delivered_summary(contact, before: trigger.created_at),
                  'at' => note.created_at.iso8601 }.compact
        Cevico::AttributeMerge.merge!(contact) do |attrs|
          signals = (attrs[Crm::StopSignals::ATTR_KEY] || {}).to_h
          signals[Crm::OptOut::LABEL] = proof
          attrs.merge(Crm::StopSignals::ATTR_KEY => signals)
        end
      end

      puts "\n#{dry ? 'DRY (nada gravado)' : 'GRAVADO'} — #{totals.map { |k, v| "#{k}: #{v}" }.join(' · ')}"
    end
  end
end
