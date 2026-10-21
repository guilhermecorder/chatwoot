# 🏢 Meus negócios (21/10/2026): autoriza o lançador a entrar NESTE sistema.
# Roda no sistema de DESTINO (ex.: na CEVICO, para o botão da CEVICO funcionar
# lá no sistema da LIFE). Cria o app de plataforma "Meus negócios" e autoriza
# o usuário do dono; imprime o token e o id que vão no MEUS_NEGOCIOS do outro.
#
#   bundle exec rake "cevico:negocios:autorizar[email@do.dono]"
#   bundle exec rake cevico:negocios:conferir   → lê MEUS_NEGOCIOS daqui, sem tokens
namespace :cevico do
  namespace :negocios do
    desc 'Cria o app de plataforma "Meus negócios" e autoriza o dono (imprime token e user_id)'
    task :autorizar, [:email] => :environment do |_t, args|
      email = args[:email].presence || ENV.fetch('EMAIL', '')
      user = User.from_email(email)
      abort "usuário não encontrado: #{email.inspect}" if user.nil?

      app = PlatformApp.find_or_create_by!(name: 'Meus negócios (lançador)')
      app.platform_app_permissibles.find_or_create_by!(permissible: user)
      puts "app de plataforma: #{app.name} (id #{app.id})"
      puts "user_id: #{user.id}"
      puts "contas: #{user.accounts.map { |a| "#{a.id}=#{a.name}" }.join(' · ')}"
      puts "token: #{app.access_token.token}"
      puts 'Guarde o token no MEUS_NEGOCIOS do sistema que vai ter o botão (nunca no código).'
    end

    desc 'Confere a configuração MEUS_NEGOCIOS deste sistema (sem mostrar tokens)'
    task conferir: :environment do
      puts "donos: #{Cevico::Negocios.donos.join(', ').presence || '(nenhum)'}"
      lista = Cevico::Negocios.publicos
      puts "negócios: #{lista.size}"
      lista.each { |n| puts "- #{n['chave']}: #{n['nome']} #{n['local'] ? '(este sistema)' : n['url']} conta=#{n['account_id']}" }
    end
  end
end
