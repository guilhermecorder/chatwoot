# 🎯 item 371 (27/10): conversões DIRETO no Google Ads (gclid + valor + procedimento).
#   ACCOUNT_ID=1 bundle exec rake cevico:google_ads_prepare          cria/confere as ações de conversão e as variáveis no Ads
#   ACCOUNT_ID=1 bundle exec rake cevico:google_ads_test             envio de TESTE (validateOnly: o Google confere e não grava)
#   ACCOUNT_ID=1 CONTACT_ID=123 EVENT=agendou_consulta VALUE=350 REAL=1 bundle exec rake cevico:google_ads_test
#       envio DE VERDADE de um paciente (REAL=1 grava no Google Ads; sem REAL=1 só valida)
namespace :cevico do
  desc 'Prepara a conta do Google Ads: ações de conversão por etapa + variáveis procedimento/pagina'
  task google_ads_prepare: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    result = Crm::GoogleAdsSetupService.new(account).call
    if result[:success]
      puts "OK. Criadas agora: #{result[:created].presence&.join(', ') || 'nada (já existiam)'}"
      result[:actions].each { |event, resource| puts "  #{event} → #{resource}" }
      result[:variables].each { |tag, resource| puts "  variável #{tag} → #{resource}" }
    else
      puts "ERRO: #{result[:error]}"
    end
  end

  desc 'Envio de teste de uma conversão ao Google Ads (validateOnly por padrão; REAL=1 grava)'
  task google_ads_test: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', 1))
    contact = ENV['CONTACT_ID'].present? ? account.contacts.find(ENV['CONTACT_ID']) : nil
    event = ENV.fetch('EVENT', 'agendou_consulta')
    service = Crm::GoogleAdsClickConversionService.new(
      account: account, event_name: event, contact: contact, value: ENV['VALUE'].presence&.to_f,
      procedure: ENV['PROCEDURE'].presence || 'refrativa', page: ENV['PAGE'].presence,
      order_id: "teste_#{Time.current.to_i}", validate_only: ENV['REAL'] != '1'
    )
    result = service.call
    puts "modo: #{result[:mode]} · amarrada ao clique: #{result[:tied]} · validateOnly: #{result[:validate_only]}"
    puts result[:success] ? 'OK: o Google Ads aceitou a conversão' : "ERRO: #{result[:error]}"
  end
end
