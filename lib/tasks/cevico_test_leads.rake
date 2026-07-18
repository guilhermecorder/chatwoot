# CEVICO — massa de teste para o ambiente local (pedido 17/07):
# a cada rodada de testes, criamos 20 leads variados para o CRM ter dados
# de verdade (colunas diferentes, datas espalhadas, etiquetas, valores).
#
# Rodar: bundle exec rails cevico:seed_test_leads ACCOUNT_ID=3
# (pode rodar de novo à vontade — cada rodada cria 20 leads novos)
namespace :cevico do
  desc 'Cria 20 leads de teste no CRM (só para ambiente local!)'
  task seed_test_leads: :environment do # rubocop:disable Metrics/BlockLength
    abort('❌ seed_test_leads é SÓ para desenvolvimento local (RAILS_ENV=development).') unless Rails.env.development?
    account = Account.find(ENV.fetch('ACCOUNT_ID', 3).to_i)
    pipeline = Crm::Pipeline.where(account_id: account.id).first || abort('Sem pipeline nessa conta.')

    stages = pipeline.stages.to_a
    first_names = %w[Ana Bruno Carla Diego Elisa Fabio Gabriela Hugo Iara Joao
                     Karen Lucas Marina Nelson Olivia Paulo Renata Sergio Tania Vitor]
    last_names = %w[Silva Souza Oliveira Santos Pereira Costa Almeida Nunes Rocha Lima]
    labels = %w[refrativa catarata artisan orcamento-refrativa agendamento teste-lote]
    values = [0, 0, 0, 5000, 5000, 2800, 8490, 11_900, 3200, 5600]

    batch = Time.current.strftime('%d%m%H%M')
    created = 0
    20.times do |i|
      name = "#{first_names[i]} #{last_names[i % last_names.size]} (teste #{batch})"
      phone = "+55119#{format('%08d', rand(10**8))}"
      contact = account.contacts.create!(name: name, phone_number: phone)

      arrived = rand(0..45).days.ago - rand(0..23).hours
      card = Crm::Contact.create!(
        contact_id: contact.id,
        pipeline: pipeline,
        stage: stages.sample,
        value: values.sample,
        created_at: arrived,
        updated_at: arrived
      )
      contact.update(label_list: (labels.sample(rand(1..2)) + ['teste-lote']).uniq)
      created += 1 if card.persisted?
    end

    puts "#{created} leads de teste criados na conta #{account.id} (lote #{batch}, etiqueta teste-lote)."
  end
end
