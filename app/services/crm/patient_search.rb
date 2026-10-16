# 🔎 ITEM 346 — etapa 4 (16/10): a busca que PUXA O PACIENTE. Pedido do
# Guilherme: "na barra de pesquisa ele puxe os contatos, para que quando
# existir, seja possível já selecionar a pessoa e fazer tudo no contato dela".
#
# Uma busca só para todas as barras (Agenda, CRM, Agendamentos, Chamadas, Hub,
# Nova conversa): nome sem acento (todas as palavras), telefone com ou sem o 9
# e com ou sem +55, e-mail. Cada resultado já vem com o que a equipe precisa
# para escolher a pessoa certa: telefone, etapa do funil, última e próxima
# consulta, se é CEVICO ou Oftalmofácil e se o cadastro tem alerta de conferência.
class Crm::PatientSearch
  LIMIT = 8
  ACCENTS = "'áàâãäéèêëíìîïóòôõöúùûüçñ', 'aaaaaeeeeiiiiooooouuuucn'".freeze

  def initialize(account:, query:, limit: LIMIT)
    @account = account
    @query = query.to_s.strip
    @limit = limit.to_i.clamp(1, 20)
  end

  def call
    return [] if @query.length < 2

    contacts.map { |contact| present(contact) }
  end

  # o mesmo celular (com/sem 9) de um cadastro que já existe — para o aviso
  # "este telefone já é de X" do formulário
  def self.phone_owner(account, phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.length < 10

    Task.match_contact(account, digits)
  end

  private

  def contacts
    scope = phone_query? ? by_phone : by_text
    scope.order(updated_at: :desc).limit(@limit).to_a
  end

  def digits
    @digits ||= @query.gsub(/\D/, '')
  end

  # "11 98888", "(35) 8701-7046", "+55…" — busca por telefone
  def phone_query?
    digits.length >= 4 && @query.gsub(/[\d\s()+\-.]/, '').empty?
  end

  def by_phone
    base = @account.contacts.where.not(phone_number: [nil, ''])
    return base.where("regexp_replace(phone_number, '\\D', '', 'g') LIKE ?", "%#{digits}%") if digits.length < 8

    # com 8+ dígitos: candidatos pelos 8 finais, e a mesma linha decide
    # (o celular sem o 9 do WhatsApp acha o com 9 e vice-versa)
    ids = base.where("regexp_replace(phone_number, '\\D', '', 'g') LIKE ?", "%#{digits.last(8)}")
              .select { |c| c.phone_number.gsub(/\D/, '').include?(digits) || Crm::AppointmentRecorder.same_phone_line?(digits, c.phone_number) }
              .map(&:id)
    @account.contacts.where(id: ids)
  end

  # todas as palavras, sem acento ("francis borg" acha "Francislene Pereira Borges")
  def by_text
    words = I18n.transliterate(@query).downcase.scan(/[a-z0-9@._-]+/).first(5)
    return @account.contacts.none if words.empty?

    words.reduce(@account.contacts) do |scope, word|
      like = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
      scope.where("translate(LOWER(contacts.name), #{ACCENTS}) LIKE :w OR LOWER(contacts.email) LIKE :w", w: like)
    end
  end

  def present(contact) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    card = contact.crm_contacts.includes(:pipeline, :stage).max_by { |c| c.stage_moved_at || c.updated_at }
    {
      id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email,
      thumbnail: contact.avatar_url,
      stage: card && { pipeline: card.pipeline&.name, name: card.stage&.name, color: card.stage&.color },
      next_appointment: appointment(contact, :next), last_appointment: appointment(contact, :last),
      origin: Crm::PartnerGuard.partner_contact?(contact) ? 'oftalmofacil' : 'cevico',
      review: Crm::PatientReview.list(contact).size,
      scheduled_by: contact.additional_attributes&.dig('agendado_por', 'name')
    }
  end

  def appointment(contact, which)
    now = Time.current
    scope = Task.where(contact_id: contact.id, canceled_at: nil).where.not(due_at: nil)
    task = which == :next ? scope.where('due_at >= ?', now).order(:due_at).first : scope.where('due_at < ?', now).order(due_at: :desc).first
    task && { id: task.id, due_at: task.due_at.iso8601, type: task.task_type, title: task.title, unit: task.unit }
  end
end
