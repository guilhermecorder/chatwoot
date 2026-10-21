# 🏢 rodada 334: EMPRESA IRMÃ no mesmo sistema (ex.: a Sua Ótica ao lado da
# CEVICO). Cria a conta, a identidade (nome + ramo) e coloca os usuários que
# JÁ existem como administradores dela (quem não existe é listado, não criado).
#
#   bundle exec rake "cevico:company:create[Sua Ótica,otica,a@b.com c@d.com]"
#   NAME="Sua Ótica" SEGMENT=otica ADMINS="a@b.com,c@d.com" bundle exec rake cevico:company:create
#   DRY=1 → só mostra o que faria (nada é gravado)
namespace :cevico do
  namespace :company do
    desc 'Cria uma empresa irmã (conta nova) com nome, ramo (clinica|otica|outro) e administradores já existentes'
    task :create, [:name, :segment, :admins] => :environment do |_t, args|
      name = args[:name].presence || ENV.fetch('NAME', '')
      segment = args[:segment].presence || ENV.fetch('SEGMENT', 'otica')
      admins = (args[:admins].presence || ENV.fetch('ADMINS', '')).to_s.split(/[,\s;]+/)
      dry = ENV.fetch('DRY', '0') == '1'

      result = Cevico::CompanyCreator.new(name: name, segment: segment, admin_emails: admins, dry: dry).call
      puts result.lines.join("\n")
      puts "- id da conta: #{result.account.id}" if result.account
    end
  end
end
