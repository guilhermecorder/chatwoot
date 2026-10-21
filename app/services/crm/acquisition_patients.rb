# 🩺 "Cliente conquistado" do CAC (item 318, 03/10/2026) = paciente cuja
# PRIMEIRA cirurgia REALIZADA caiu no período. Mesma régua do funil por
# anúncio (Crm::AdFunnelSteps, item 289), agora COM DATA:
#   CRM          → 1ª entrada do card em "Cirurgia Realizada"/2º olho/pós-op
#   Agenda       → cirurgia com presença marcada (dia da cirurgia)
#   Oftalmofácil → cirurgia ativa/realizada com a data já passada (lá nunca
#                  marcam "realizada" — ver o cabeçalho do AdFunnelSteps);
#                  só cirurgia (exame/consulta/pós-op do espelho ficam fora)
# A data que vale é a MAIS ANTIGA entre as três — o 2º olho meses depois não
# vira cliente novo. Cirurgia do Oftalmofácil sem contato no sistema conta
# pelo CPF (ou nome). Entrada de CARGA EM MASSA no CRM (item 309) não tem
# data confiável: o paciente fica fora da contagem e aparece no aviso.
# Pacientes de PARCEIRO (cerca do item 231 + fornecedor que não é a CEVICO)
# vão para o bloco separado do Oftalmofácil — nunca entram no CAC.
#   receita = cirurgias do Oftalmofácil realizadas no período (pago; senão o
#             cobrado) + valor do card de quem é novo e não tem valor lá
class Crm::AcquisitionPatients
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  NOT_SURGERY = /exam|consult|p[o]s.?op|pos.?operat|retorno/

  Patient = Struct.new(:key, :contact_id, :name, :first_on, :source, :partner, keyword_init: true)

  attr_reader :firsts, :partner_result

  def initialize(account, from:, to:)
    @account = account
    @from = from.to_date
    @to = to.to_date
    @partner_ids = Crm::PartnerGuard.excluded_contact_ids(account).to_set
    @own = Crm::PartnerGuard.own_provider_name(account)
    @firsts = {}
    @revenue = Hash.new(0.0)
    @partner_result = 0.0
    load_crm
    load_agenda
    load_oftalmofacil
    add_card_values
  end

  # pacientes cuja 1ª cirurgia realizada caiu no período
  def new_in_period
    @new_in_period ||= firsts.values.select { |p| p.first_on.between?(@from, @to) && p.source != 'crm_carga' }
  end

  def cevico
    new_in_period.reject(&:partner)
  end

  def partner
    new_in_period.select(&:partner)
  end

  # cartões que entraram em "Cirurgia Realizada" por carga em massa no período
  def bulk_skipped
    firsts.values.count { |p| p.first_on.between?(@from, @to) && p.source == 'crm_carga' }
  end

  def revenue_of(key)
    @revenue[key]
  end

  # receita do período por paciente (inclui 2º olho de quem já era paciente)
  def revenue_keys
    @revenue.keys
  end

  def partner?(key)
    firsts[key]&.partner || false
  end

  private

  def add(key, on, source, contact_id: nil, name: nil, partner: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/ParameterLists
    return if key.blank? || on.blank?

    on = on.respond_to?(:in_time_zone) && !on.is_a?(Date) ? on.in_time_zone(TZ).to_date : on.to_date
    partner ||= contact_id.present? && @partner_ids.include?(contact_id)
    current = firsts[key]
    if current.nil? || on < current.first_on
      firsts[key] = Patient.new(key: key, contact_id: contact_id, name: name || current&.name, first_on: on,
                                source: source, partner: partner || current&.partner || false)
    elsif partner
      current.partner = true
    end
  end

  # CRM: 1ª entrada numa coluna de cirurgia realizada (com e sem carga em massa)
  def load_crm # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    done = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }).to_a
                     .select { |s| s.name.match?(Crm::AdFunnelSteps::SURGERY_DONE) }.map(&:id)
    return if done.empty?

    logs = Crm::StageLog.joins(:crm_contact).where(stage_id: done)
                        .group('crm_contacts.contact_id')
                        .pluck('crm_contacts.contact_id', Arel.sql('MIN(crm_contact_stage_logs.entered_at)'),
                               Arel.sql("MIN(CASE WHEN crm_contact_stage_logs.event_type = 'bulk' " \
                                        'THEN crm_contact_stage_logs.entered_at END)'))
    logs.each { |cid, first, bulk| add(cid, first, bulk && bulk <= first ? 'crm_carga' : 'crm', contact_id: cid) }

    # card que está na coluna sem histórico nenhum (antigo): vale a criação do card
    seen = logs.to_set(&:first)
    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, stage_id: done)
                .where.not(contact_id: nil).group(:contact_id).minimum(:created_at)
                .each { |cid, at| add(cid, at, 'crm', contact_id: cid) unless seen.include?(cid) }
  end

  def load_agenda
    @account.tasks.not_partner_origin.where(task_type: 'cirurgia', attendance: 'attended', canceled_at: nil)
            .where.not(contact_id: nil).group(:contact_id).minimum(:due_at)
            .each { |cid, at| add(cid, at, 'agenda', contact_id: cid) }
  end

  def load_oftalmofacil # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    Crm::OftalmofacilSurgery.where(account_id: @account.id, status_kind: Crm::AdFunnelSteps::OF_DONE)
                            .where(surgery_date: ...Time.zone.today)
                            .pluck(:contact_id, :patient_cpf, :patient_name, :surgery_date, :provider_name,
                                   :procedure_type, :paid_amount, :amount, :clinic_price, :profit)
                            .each do |cid, cpf, name, on, provider, type, paid, amount, clinic, profit| # rubocop:disable Metrics/ParameterLists
      next if surgery_type?(type) == false

      key = cid || of_key(cpf, name)
      partner = @own.present? && provider.to_s.downcase.exclude?(@own)
      add(key, on, 'oftalmofacil', contact_id: cid, name: name, partner: partner)
      next unless on.between?(@from, @to)

      value = paid.to_f.positive? ? paid.to_f : amount.to_f
      @revenue[key] += value
      @partner_result += amount.to_f - clinic.to_f - profit.to_f if partner
    end
  end

  # sem valor no Oftalmofácil: o valor do card (quem é novo no período)
  def add_card_values
    ids = new_in_period.filter_map { |p| p.contact_id if @revenue[p.key].zero? }
    return if ids.empty?

    Crm::Contact.joins(:pipeline).where(crm_pipelines: { account_id: @account.id }, contact_id: ids)
                .group(:contact_id).maximum(:value)
                .each { |cid, value| @revenue[cid] += value.to_f }
  end

  def surgery_type?(type)
    t = type.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase
    t.blank? || !t.match?(NOT_SURGERY)
  end

  def of_key(cpf, name)
    digits = cpf.to_s.gsub(/\D/, '')
    return "of:#{digits}" if digits.present?

    name.present? ? "of:#{name.to_s.downcase.squish}" : nil
  end
end
