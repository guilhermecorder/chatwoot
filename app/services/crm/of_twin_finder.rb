# 👯 PONTA 2 (22/10): paciente que o sync do OftalmoFácil CRIOU (telefone,
# CPF e nome+e-mail do hub não bateram com ninguém) mas que provavelmente já
# existia aqui — e aí a cirurgia some do funil do lead (Central, Campanhas,
# CAC). NUNCA junta sozinho (item 346): lista o provável gêmeo com o motivo e
# a força; a equipe confere e junta pela mesma ação das Notificações.
#   alta  → mesmo CPF; telefone quase igual (DDD ou um dígito trocado) com o
#           1º nome compatível; mesmo nome completo com 3+ palavras
#   média → mesmo nome completo de 2 palavras
#   baixa → nome curto contido no do hub ("Eliana Carvalho" × "Eliana Campos
#           de Carvalho"), só quando o outro já conversou com a gente
# Quem a equipe já disse que são pessoas diferentes não volta.
class Crm::OfTwinFinder
  Twin = Struct.new(:created_id, :other_id, :reasons, :strength, keyword_init: true)
  STRENGTH = { 'alta' => 0, 'media' => 1, 'baixa' => 2 }.freeze
  MAX_WEAK = 3

  def initialize(account, own_provider:)
    @account = account
    @own = own_provider.to_s.strip.downcase
  end

  # contatos criados pelo sync para cirurgias da CEVICO
  def created_ids
    return [] if @own.blank?

    Crm::OftalmofacilSurgery.where(account_id: @account.id, match_via: 'created').where.not(contact_id: nil)
                            .where('LOWER(provider_name) LIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(@own)}%")
                            .distinct.pluck(:contact_id)
  end

  def call
    ids = created_ids
    return [] if ids.empty?

    index!
    ids.flat_map { |id| twins_for(@people[id]) if @people[id] }.compact
       .sort_by { |t| [STRENGTH[t.strength], t.created_id] }
  end

  private

  Person = Struct.new(:id, :name, :words, :phone, :cpf, :not_same, :talked, keyword_init: true)

  def index! # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
    talked = @account.conversations.distinct.pluck(:contact_id).to_set
    @people = {}
    @by_cpf = Hash.new { |h, k| h[k] = [] }
    @by_last8 = Hash.new { |h, k| h[k] = [] }
    @by_first = Hash.new { |h, k| h[k] = [] }
    @by_half = Hash.new { |h, k| h[k] = [] }
    @account.contacts.pluck(:id, :name, :phone_number, Arel.sql("custom_attributes->>'cpf'"),
                            Arel.sql("additional_attributes->'#{Crm::PatientReview::NOT_SAME_KEY}'")).each do |id, name, phone, cpf, not_same|
      words = Crm::AppointmentRecorder.name_words(name)
      person = Person.new(id: id, name: name, words: words, phone: national(phone), cpf: cpf.to_s.gsub(/\D/, '').presence,
                          not_same: Array(not_same.is_a?(String) ? JSON.parse(not_same) : not_same).map(&:to_i), talked: talked.include?(id))
      @people[id] = person
      @by_cpf[person.cpf] << person if person.cpf&.length == 11
      if person.phone.to_s.length >= 8
        last8 = person.phone.last(8)
        @by_last8[last8] << person
        @by_half[[:head, last8[0, 4]]] << person
        @by_half[[:tail, last8[4, 4]]] << person
      end
      @by_first[words.first] << person if words.any?
    end
  end

  def twins_for(person)
    candidates = (@by_cpf[person.cpf] + @by_last8[person.phone.to_s.last(8)] + near_phones(person) + @by_first[person.words.first]).uniq(&:id)
    found = candidates.filter_map { |other| compare(person, other) }
    strong, weak = found.partition { |t| t.strength != 'baixa' }
    strong + weak.first(MAX_WEAK)
  end

  def compare(person, other) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return nil if other.id == person.id || person.not_same.include?(other.id) || other.not_same.include?(person.id)

    reasons = []
    reasons << 'mesmo CPF' if person.cpf && person.cpf == other.cpf
    reasons << 'telefone quase igual' if near_phone?(person.phone, other.phone) && first_name_ok?(person, other)
    same_name = person.words.size >= 2 && person.words == other.words
    reasons << 'mesmo nome' if same_name
    return Twin.new(created_id: person.id, other_id: other.id, reasons: reasons, strength: strong_or_medium(reasons, person)) if reasons.any?
    return nil unless other.talked && contained?(other.words, person.words)

    Twin.new(created_id: person.id, other_id: other.id, reasons: ['nome curto contido'], strength: 'baixa')
  end

  def strong_or_medium(reasons, person)
    return 'alta' if reasons.any? { |r| r != 'mesmo nome' } || person.words.size >= 3

    'media'
  end

  # "Eliana Carvalho" está dentro de "Eliana Campos de Carvalho" (1º nome igual)
  def contained?(short, long)
    short.size >= 2 && short.size < long.size && short.first == long.first && (short - long).empty?
  end

  def first_name_ok?(one, other)
    Crm::PatientReview.compatible_names?(one.name, other.name)
  end

  # o mesmo número com o DDD trocado ou o 9 a mais/menos (mesmos 8 finais),
  # ou um dígito diferente / dois vizinhos trocados no mesmo DDD
  def near_phone?(one, other) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return false if one.to_s.length < 10 || other.to_s.length < 10 || one == other
    return true if one.last(8) == other.last(8)
    return false if one.length != other.length || one[0, 2] != other[0, 2]

    diff = (0...one.length).reject { |i| one[i] == other[i] }
    diff.size == 1 || (diff.size == 2 && diff[1] == diff[0] + 1 && one[diff[0]] == other[diff[1]] && one[diff[1]] == other[diff[0]])
  end

  # candidatos por telefone com UM dígito diferente: mesmos 4 últimos ou 4 primeiros dos 8 finais
  def near_phones(person)
    last8 = person.phone.to_s.last(8)
    return [] if last8.length < 8

    @by_half[[:head, last8[0, 4]]] + @by_half[[:tail, last8[4, 4]]]
  end

  # só os dígitos nacionais (DDD + número), sem o +55
  def national(phone)
    d = phone.to_s.gsub(/\D/, '')
    d = d[2..] if d.start_with?('55') && d.length >= 12
    d.presence
  end
end
