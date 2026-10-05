# 🏷️ CARIMBO DE ORIGEM (item 322, 04/10). Pedido do Guilherme: "o carimbo na
# hora de entrada é incrível; vamos fazer isso de forma organizada e eficiente".
#
# Até aqui o sistema DEDUZIA de onde veio cada dado na hora de mostrar (4
# pistas na cerca dos parceiros, rajada de 30 cartões na carga em massa), e
# cada tela precisava lembrar de aplicar o filtro. Agora cada registro nasce
# com duas marcas gravadas:
#
#   cevico_source_id  DE QUEM É — a fonte (Crm::Source): CEVICO, Oftalmofácil…
#   cevico_born_via   COMO NASCEU:
#       paciente    o paciente escreveu ou preencheu um formulário
#       equipe      uma pessoa logada fez na tela
#       robo        o sistema fez sozinho (automação, IA, lembrete, espelho)
#       sync        sincronização com o hub / planilha de cirurgias
#       carga       movimentação ou importação em lote
#       integracao  chamada de fora com chave de acesso (N8N)
#     vazio = registro anterior ao carimbo
#
# Quem carimba: os próprios modelos (CevicoSourceStamped), ao criar. Quem sabe
# o "como" avisa em volta do trabalho: `Crm::Stamp.with(via: 'sync') { … }`.
# Sem aviso: pessoa logada = equipe; sem ninguém logado = robo.
#
# PACIENTE (contacts): a primeira evidência carimba e NÃO muda mais — é a
# regra B do item 245 ("quem chegou primeiro") gravada em vez de recalculada.
# Evidência = 1ª conversa (caixa → fonte), 1º card (funil → fonte), 1º
# agendamento ou a sincronização do hub. Paciente antigo ainda sem carimbo é
# carimbado pelas regras da cerca de hoje, não pela evidência nova.
#
# Carimbar NUNCA derruba quem está salvando: erro aqui vira linha no log.
module Crm::Stamp
  module_function

  VIAS = %w[paciente equipe robo sync carga integracao].freeze
  FRESH = 10.minutes # paciente recém-criado: vale a primeira evidência

  # avisa o "como" (e, se souber, a fonte) para tudo o que nascer no bloco
  def with(via: nil, source: nil)
    previous = [Current.cevico_via, Current.cevico_source_id]
    Current.cevico_via = via.to_s if via.present?
    Current.cevico_source_id = source.respond_to?(:id) ? source.id : source if source.present?
    yield
  ensure
    Current.cevico_via, Current.cevico_source_id = previous
  end

  def via
    Current.cevico_via.presence || (Current.user.present? ? 'equipe' : 'robo')
  end

  def apply(record, refresh: false)
    case record
    when Crm::Contact then stamp_card(record)
    when Crm::StageLog then stamp_log(record)
    when Task then stamp_task(record, refresh)
    when Crm::OftalmofacilSurgery then stamp_surgery(record)
    when ::Contact then stamp_contact(record)
    end
  rescue StandardError => e
    Rails.logger.error "[carimbo] #{record.class.name} #{record.try(:id)}: #{e.class}: #{e.message}"
  end

  # card: a fonte é a dona do funil em que ele nasce
  def stamp_card(card)
    account = card.pipeline&.account
    return if account.nil?

    card.cevico_source_id ||= Crm::Sources.id_for_pipeline(account, card.pipeline_id)
    card.cevico_born_via ||= via
  end

  # entrada em coluna: a fonte do card + como ESTA movimentação aconteceu
  def stamp_log(log)
    card = log.crm_contact
    return if card.nil?

    log.cevico_source_id ||= card.cevico_source_id || Crm::Sources.id_for_pipeline(card.pipeline.account, card.pipeline_id)
    log.cevico_born_via ||= via
  end

  # agendamento: parceiro (origem escolhida no formulário ou item de parceiro
  # do hub) → Oftalmofácil; "CEVICO" escolhido → casa; sem escolha → a fonte
  # do paciente; sem paciente → casa. Trocar a origem depois recarimba.
  def stamp_task(task, refresh)
    account = task.account
    return if account.nil?

    task.cevico_source_id = nil if refresh
    task.cevico_source_id ||= task_source_id(account, task)
    task.cevico_born_via ||= task.source == 'oftalmofacil' ? 'sync' : via
  end

  def task_source_id(account, task)
    return Crm::Sources.partner_id(account) if Crm::PartnerGuard.partner_task?(task)
    return Crm::Sources.own_id(account) if task.origin == 'cevico'

    (task.contact_id && ::Contact.where(id: task.contact_id).pick(:cevico_source_id)) ||
      Current.cevico_source_id || Crm::Sources.own_id(account)
  end

  # item do espelho do hub: fornecedor da casa (CATARATA_SP) × parceiro
  def stamp_surgery(surgery)
    account = surgery.account
    return if account.nil?

    partner = Crm::PartnerGuard.partner_surgery?(surgery)
    surgery.cevico_source_id = partner ? Crm::Sources.partner_id(account) : Crm::Sources.own_id(account)
    surgery.cevico_born_via ||= 'sync'
  end

  # paciente: no nascimento só carimba a fonte quando ela já é certa (o bloco
  # avisou, ou veio de parceiro do hub). Senão espera a primeira evidência.
  def stamp_contact(contact) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    contact.cevico_born_via ||= Current.cevico_via.presence || (Current.user.present? ? 'equipe' : 'paciente')
    return if contact.cevico_source_id.present? || contact.account.nil?

    contact.cevico_source_id =
      if Current.cevico_source_id.present? then Current.cevico_source_id
      elsif (contact.additional_attributes || {})['parceiro'].present? then Crm::Sources.partner_id(contact.account)
      end
  end

  # PRIMEIRA EVIDÊNCIA: carimba o paciente que ainda não tem fonte. Devolve a
  # fonte que ficou. Paciente antigo (de antes do carimbo) segue as regras da
  # cerca de hoje — a evidência nova não reescreve a história dele.
  def claim_contact!(contact, source_id) # rubocop:disable Metrics/CyclomaticComplexity
    return contact&.cevico_source_id if contact.blank? || contact.cevico_source_id.present? || source_id.blank?

    source_id = legacy_source_id(contact) if contact.created_at.present? && contact.created_at < FRESH.ago
    ::Contact.where(id: contact.id, cevico_source_id: nil).update_all(cevico_source_id: source_id) # rubocop:disable Rails/SkipsModelValidations
    contact.cevico_source_id = ::Contact.where(id: contact.id).pick(:cevico_source_id)
    contact.clear_attribute_changes([:cevico_source_id])
    contact.cevico_source_id
  rescue StandardError => e
    Rails.logger.error "[carimbo] paciente #{contact&.id}: #{e.class}: #{e.message}"
    nil
  end

  def legacy_source_id(contact)
    account = contact.account
    Crm::PartnerGuard.partner_contact?(contact) ? Crm::Sources.partner_id(account) : Crm::Sources.own_id(account)
  end
end
