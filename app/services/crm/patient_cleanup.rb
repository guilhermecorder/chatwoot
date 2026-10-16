# 🧹 ITEM 346 — ETAPA 2 (limpeza dos duplicados que JÁ existem). Decisões do
# Guilherme (15/10):
#   - junta SOZINHO só com certeza ALTA: mesmo celular (com/sem o 9) e o
#     primeiro nome compatível, sem nome de duas pessoas e sem CPFs diferentes;
#   - fica o cadastro do WhatsApp (o que conversa) — o número principal é o
#     dele; nome, e-mail e CPF vêm do cadastro do OftalmoFácil (mais atuais);
#   - o card fica na etapa atual do CRM (Cevico::ContactMergeRecords: vence o
#     que mexeu por último);
#   - quem tem as etiquetas cevico + oftalmofacil perde a oftalmofacil;
#   - o resto (nome diferente no mesmo celular, mesmo CPF, duas pessoas no
#     cadastro, mesmo nome completo) NÃO é juntado: vira alerta de conferência.
#
# Uso: rake cevico:paciente_unico ACCOUNT_ID=1 DRY=1 (simula) → DRY=0 (aplica).
class Crm::PatientCleanup
  attr_reader :account, :report

  ORIGIN_LABEL = 'oftalmofacil'.freeze
  CEVICO_LABEL = 'cevico'.freeze

  def initialize(account:, dry: true)
    @account = account
    @dry = dry
    @report = { merges: [], merged: 0, failures: [], labels: 0, flags: Hash.new(0) }
  end

  def call
    Contact.without_label_triggers do
      mobile_groups.each { |group| handle_mobile_group(group) }
      # os juntados saem da lista: o resto das conferências não fala deles
      merged_away = @report[:merges].flat_map { |m| m[:merge_ids] }.to_set
      @contacts = contacts.reject { |c| merged_away.include?(c.id) }
      clean_labels!
      flag_same_cpf!
      flag_same_name!
      flag_two_people!
    end
    report
  end

  private

  def contacts
    @contacts ||= account.contacts.select(:id, :name, :phone_number, :email, :custom_attributes, :additional_attributes, :created_at).to_a
  end

  # mesmo celular com e sem o 9 (dígitos diferentes, mesma chave)
  def mobile_groups
    contacts.select { |c| c.phone_number.present? }
            .group_by { |c| Crm::AppointmentRecorder.mobile_key(c.phone_number) }
            .reject { |key, group| key.nil? || group.size < 2 }
            .values
  end

  def handle_mobile_group(group)
    reason = doubt(group)
    return flag_group(group, *reason) if reason

    @report[:merges] << plan_for(group)
    merge_group!(group) unless @dry
  end

  # por que NÃO juntar sozinho (nil = certeza alta)
  def doubt(group)
    return ['duas_pessoas', 'Nome de duas pessoas no cadastro'] if group.any? { |c| Crm::PatientReview.two_people?(c.name) }

    cpfs = group.filter_map { |c| cpf(c) }.uniq
    return ['cpf_diferente', 'Mesmo celular com CPFs diferentes'] if cpfs.size > 1
    return nil if group.combination(2).all? { |a, b| Crm::PatientReview.compatible_names?(a.name, b.name) }

    ['nome_diferente', 'Mesmo celular (com/sem 9) com outro nome']
  end

  def plan_for(group)
    base = pick_base(group)
    source = of_source(group)
    { base_id: base.id, phone: base.phone_number, merge_ids: (group - [base]).map(&:id),
      names: group.map(&:name), final_name: source&.name.presence || base.name }
  end

  # fica o cadastro que conversa (WhatsApp); empate → o que NÃO veio do hub → o mais antigo
  def pick_base(group)
    counts = Conversation.where(contact_id: group.map(&:id)).group(:contact_id).count
    group.min_by { |c| [-(counts[c.id] || 0), of_origin?(c) ? 1 : 0, c.created_at] }
  end

  # o cadastro com os dados do OftalmoFácil (o mais novo, se houver mais de um)
  def of_source(group)
    group.select { |c| of_origin?(c) }.max_by(&:created_at)
  end

  def of_origin?(contact)
    contact.additional_attributes.to_h['origem'] == 'oftalmofacil'
  end

  def cpf(contact)
    contact.custom_attributes.to_h['cpf'].to_s.gsub(/\D/, '').presence
  end

  def merge_group!(group) # rubocop:disable Metrics/AbcSize
    base = account.contacts.find(pick_base(group).id)
    source = of_source(group)
    data = source && { name: source.name, email: source.email, cpf: cpf(source) }
    (group.map(&:id) - [base.id]).each { |id| merge_pair!(base, id) }
    apply_of_data!(base.reload, data) if data
    @report[:merged] += 1
  rescue StandardError => e
    @report[:failures] << { ids: group.map(&:id), reason: "#{e.class.name.demodulize}: #{e.message.truncate(160)}" }
  end

  def merge_pair!(base, mergee_id)
    mergee = account.contacts.find(mergee_id)
    labels = mergee.label_list
    ContactMergeAction.new(account: account, base_contact: base, mergee_contact: mergee).perform
    base.add_labels(labels)
  end

  # os dados do OftalmoFácil mandam (o duplicado já saiu: o e-mail ficou livre)
  def apply_of_data!(base, data)
    changes = {}
    changes[:name] = data[:name] if data[:name].present?
    changes[:email] = data[:email] if data[:email].present? && !account.contacts.where.not(id: base.id).exists?(email: data[:email])
    changes[:custom_attributes] = base.custom_attributes.to_h.merge('cpf' => data[:cpf]) if data[:cpf].present?
    base.update_columns(changes) if changes.any? # rubocop:disable Rails/SkipsModelValidations
  end

  # cevico + oftalmofacil → fica só a cevico (a etiqueta que chegou primeiro)
  def clean_labels!
    ids = tagged_ids(CEVICO_LABEL) & tagged_ids(ORIGIN_LABEL)
    @report[:labels] = ids.size
    return if @dry

    account.contacts.where(id: ids).find_each { |c| c.update!(label_list: c.label_list - [ORIGIN_LABEL]) }
  end

  def tagged_ids(name)
    ActsAsTaggableOn::Tagging.joins(:tag).where(tags: { name: name }, taggable_type: 'Contact', context: 'labels',
                                                taggable_id: account.contacts.select(:id)).pluck(:taggable_id)
  end

  def flag_same_cpf!
    contacts.select { |c| cpf(c).to_s.length >= 11 }.group_by { |c| cpf(c) }.each_value do |group|
      flag_group(group, 'possivel_duplicado', 'Mesmo CPF') if group.size > 1
    end
  end

  def flag_same_name!
    contacts.group_by { |c| Crm::AppointmentRecorder.name_words(c.name).sort }.each do |words, group|
      next if words.size < 2 || group.size < 2

      flag_group(group, 'possivel_duplicado', 'Mesmo nome completo') if Crm::PatientReview.strong_name?(group.first.name, group.map(&:id))
    end
  end

  def flag_two_people!
    contacts.each { |c| flag(c, 'duas_pessoas', c.name) if Crm::PatientReview.two_people?(c.name) }
  end

  def flag_group(group, type, why)
    group.each do |contact|
      (group - [contact]).each do |other|
        flag(contact, type, "#{why}: #{other.name}#{" (#{other.phone_number})" if other.phone_number.present?}", other.id)
      end
    end
  end

  def flag(contact, type, detail, other_id = nil)
    @report[:flags][type] += 1
    return if @dry

    fresh = account.contacts.find_by(id: contact.id)
    Crm::PatientReview.flag!(fresh, type, detail, other_id: other_id) if fresh
  end
end
