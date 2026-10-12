# 🏢 Cria uma EMPRESA IRMÃ no mesmo sistema (rodada 334): a Account nova, o
# CrmSetting dela com a identidade (nome + ramo) e os administradores — só
# usuários que JÁ existem (quem não existe é listado, não criado).
#
# É a lógica do `rake cevico:company:create`, separada para ser testada:
#   Cevico::CompanyCreator.new(name: 'Sua Ótica', segment: 'otica',
#                              admin_emails: ['a@b.com'], dry: true).call
# → Result(account, created, admins_added, admins_already, missing, lines)
class Cevico::CompanyCreator
  Result = Struct.new(:account, :created, :admins_added, :admins_already, :missing, :lines, keyword_init: true)

  attr_reader :name, :segment, :admin_emails, :dry

  def initialize(name:, segment: 'otica', admin_emails: [], dry: false)
    @name = name.to_s.strip
    @segment = Cevico::Company::SEGMENTS.include?(segment.to_s) ? segment.to_s : 'otica'
    @admin_emails = Array(admin_emails).flat_map { |e| e.to_s.split(',') }.map { |e| e.strip.downcase }.compact_blank.uniq
    @dry = dry
    @added = []
    @already = []
  end

  def call
    raise ArgumentError, 'Informe o nome da empresa (NAME="Sua Ótica").' if name.blank?

    @existing = Account.find_by(name: name)
    @account = @existing
    @users = admin_emails.index_with { |email| User.from_email(email) }
    dry ? preview_admins : persist!

    Result.new(account: @account, created: @existing.nil? && !dry, admins_added: @added, admins_already: @already,
               missing: missing, lines: summary)
  end

  private

  def missing
    @users.select { |_, u| u.nil? }.keys
  end

  def found_users
    @users.values.compact
  end

  # grava tudo de uma vez: conta (se não existir), identidade e admins
  def persist!
    ActiveRecord::Base.transaction do
      @account ||= Account.create!(name: name, locale: 'pt_BR') # a empresa nova já nasce em português
      Cevico::Company.save!(@account, 'name' => name, 'segment' => segment)
      found_users.each { |user| add_admin!(user) }
    end
  end

  def add_admin!(user)
    au = AccountUser.find_or_initialize_by(account: @account, user: user)
    return @already << user.email if au.persisted? && au.administrator?

    au.role = :administrator
    au.save!
    @added << user.email
  end

  # DRY: só classifica quem entraria e quem já é admin
  def preview_admins
    found_users.each do |user|
      au = @existing && AccountUser.find_by(account: @existing, user: user)
      (au&.administrator? ? @already : @added) << user.email
    end
  end

  def summary # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    lines = [dry ? '🔎 MODO DE TESTE (DRY=1): nada foi gravado.' : '✅ GRAVADO:']
    lines << if @existing
               "- Conta \"#{name}\" já existe (id #{@existing.id}); só completo o que falta."
             else
               "- Conta nova: \"#{name}\" (ramo #{Cevico::Company::SEGMENT_LABELS[segment]})."
             end
    lines << "- Administradores #{dry ? 'que entrariam' : 'adicionados'}: #{@added.presence&.join(', ') || 'nenhum'}."
    lines << "- Já eram administradores: #{@already.join(', ')}." if @already.any?
    lines << "- ⚠️ Não existem no sistema (crie em Configurações → Equipe e rode de novo): #{missing.join(', ')}." if missing.any?
    lines << "- Vocabulário do ramo: #{Cevico::Company::VOCABULARY[segment].values_at('paciente', 'consulta', 'medico', 'unidade').join(', ')}."
    lines << '- Próximo passo: entrar na conta nova e preencher Configurações → Identidade da empresa (lojas, assistente, site).' unless dry
    lines
  end
end
