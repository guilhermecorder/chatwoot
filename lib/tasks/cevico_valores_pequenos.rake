# 💰 Rodada 5 da auditoria (#192): o leitor da planilha de fechamento (.xlsx)
# lia a célula de TEXTO "5.000" como R$ 5,00 (1000× menor). O conserto vale
# daqui para frente; o que JÁ foi importado precisa de conferência à mão.
# Esta tarefa SÓ LISTA (não muda nada) os cards em coluna de cirurgia com
# valor entre R$ 0,01 e R$ 99,99 — valor de cirurgia nunca é tão baixo.
#   bundle exec rake cevico:valores_pequenos ACCOUNT_ID=1 [LIMITE=100]
namespace :cevico do
  desc 'Lista (sem mudar nada) cards em coluna de cirurgia com valor suspeito de ter ficado 1000× menor'
  task valores_pequenos: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    limite = ENV.fetch('LIMITE', 100).to_f
    cards = Crm::Contact.joins(:stage, :pipeline)
                        .where(crm_pipelines: { account_id: account.id })
                        .where('crm_stages.name ILIKE ?', '%cirurgia%')
                        .where('crm_contacts.value > 0 AND crm_contacts.value < ?', limite)
                        .includes(:contact, :stage)
                        .order('crm_contacts.value')
    puts "conta #{account.id} · #{cards.size} card(s) em coluna de cirurgia com valor abaixo de R$ #{limite.round(2)}"
    cards.each do |card|
      puts "- card #{card.id} · #{card.contact&.name} · #{card.stage&.name} · R$ #{format('%.2f', card.value)} " \
           "(se for milhar, o certo seria R$ #{format('%.2f', card.value * 1000)})"
    end
    puts 'Nada foi alterado. Confira cada um na planilha original e corrija o valor no card.'
  end
end
