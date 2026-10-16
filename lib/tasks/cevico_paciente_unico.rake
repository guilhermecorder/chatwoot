# 🧹 item 346 — etapa 2: junta os duplicados de certeza ALTA (celular com/sem 9
# + mesmo primeiro nome), tira a etiqueta oftalmofacil de quem também tem a
# cevico e deixa alerta de conferência no resto. BACKUP antes do DRY=0.
#   bundle exec rake cevico:paciente_unico ACCOUNT_ID=1 DRY=1   (simula, não muda nada)
#   bundle exec rake cevico:paciente_unico ACCOUNT_ID=1 DRY=0   (aplica)
namespace :cevico do
  task paciente_unico: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', '1'))
    dry = ENV.fetch('DRY', '1') != '0'
    r = Crm::PatientCleanup.new(account: account, dry: dry).call

    puts "=== PACIENTE ÚNICO — conta #{account.id} — #{dry ? 'SIMULAÇÃO (nada mudou)' : 'APLICADO'} ==="
    puts "Juntar (certeza alta): #{r[:merges].size} grupo(s)#{" · juntados: #{r[:merged]}" unless dry}"
    r[:merges].each do |m|
      puts "  fica ##{m[:base_id]} #{m[:phone]} ← sai #{m[:merge_ids].map { |i| "##{i}" }.join(', ')} · nome final: #{m[:final_name]}"
    end
    puts "Etiqueta oftalmofacil sai de: #{r[:labels]} contato(s) (têm também a cevico)"
    puts "Alertas de conferência: #{r[:flags].map { |k, v| "#{k} #{v}" }.join(' · ').presence || 'nenhum'}"
    r[:failures].each { |f| puts "  ⚠️ falhou #{f[:ids].join(',')}: #{f[:reason]}" }
    puts(dry ? 'Para aplicar: DRY=0 (faça o BACKUP antes)' : '=== fim ===')
  end
end
