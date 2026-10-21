# 🧭 CERCA DO AMBIENTE NO CARD (item 341, 13/10). Pedido do Guilherme: a caixa
# 12 (Oftalmofácil) NUNCA pode acessar o CRM da CEVICO — e havia uns dez
# caminhos que criavam card no funil da CEVICO sem olhar a caixa (Agenda,
# confirmação, comparecimento, agendamento da IA, automação de etiqueta,
# botão "adicionar ao funil", lote, planilha, ligação, formulário…).
#
# Em vez de remendar cada um, a regra mora no PRÓPRIO card: antes de nascer,
# se o paciente está ancorado em OUTRO ambiente (Crm::Environments) e o funil
# pedido é de um ambiente diferente, o card vai para o funil do ambiente dele,
# na coluna equivalente:
#   cada coluna da jornada → a de mesmo papel (item 344: Consulta Agendada,
#   Confirmada, Não Foi, Consulta Realizada, Indicação, Sem Indicação, Não
#   Fechou, Cirurgia Agendada, Cirurgia Realizada, Pós Operatório) · o resto
#   (Envio de Orçamento…) → Novo Contato
# Se ele já tem card lá, esse card anda (nunca para trás) e o novo não nasce.
# Cada desvio deixa "[cerca ambiente] card CEVICO redirecionado" no log.
#
# Passe livre (Crm::CardRouter.bypass): a migração (rake) e o administrador
# que pediu explicitamente para pôr o paciente no funil escolhido.
module Crm::CardRouter
  module_function

  def bypass(reason = 'admin')
    previous = Current.cevico_env_bypass
    Current.cevico_env_bypass = reason.to_s
    yield
  ensure
    Current.cevico_env_bypass = previous
  end

  def bypassed?
    Current.cevico_env_bypass.present?
  end

  # migração em lote: sem reflexo na Agenda nem automação
  def quiet?
    Current.cevico_env_bypass == 'carga'
  end

  # chamado pelo before_validation do card novo; true = segue
  def route!(card) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return true if bypassed? || card.contact.nil? || card.pipeline.nil?

    account = card.pipeline.account
    env = Crm::Environments.anchored_partner_id(account, card.contact)
    return true if env.nil? || env == Crm::Environments.environment_id_for_pipeline(account, card.pipeline_id)

    stage = target_stage(account, env, card.stage)
    if stage.nil? # ambiente sem funil configurado: segue como antes (e avisa no log)
      Rails.logger.warn "[cerca ambiente] contato #{card.contact_id}: o ambiente #{env} não tem funil — card segue no funil #{card.pipeline_id}"
      return true
    end

    existing = Crm::Contact.find_by(contact_id: card.contact_id, pipeline_id: stage.pipeline_id)
    if existing
      advance!(existing, stage)
      # o card recusado desfaz a transação do save! (e o avanço junto) — refaz depois, fora dela
      wanted = card.stage
      ActiveRecord::Base.current_transaction.after_rollback { readvance!(account, env, wanted, existing.id) }
      return refuse!(card, "já tem card no funil do ambiente dele (card #{existing.id})")
    end

    log(card, stage)
    card.pipeline = stage.pipeline
    card.stage = stage
    card.cevico_source_id = nil # o carimbo segue o funil novo
    true
  rescue StandardError => e
    Rails.logger.error "[cerca ambiente] card do contato #{card.contact_id}: #{e.class}: #{e.message}"
    true
  end

  # papel da coluna pelo nome: o mesmo de Crm::PartnerFunnel (item 344 — 11
  # colunas, cada uma com a sua equivalente; antes consulta realizada,
  # indicação e não fechou caíam todas em "Consulta Confirmada")
  def role_for(stage)
    return :new if stage.nil?
    return :confirmed if Crm::ConfirmationReflector.confirmed_stage?(stage)

    Crm::PartnerFunnel.role_of(stage.name) || :new
  end

  # coluna equivalente no funil do ambiente
  def target_stage(account, env, stage, create: true)
    role = role_for(stage)
    source = Crm::Environments.source(account, env)
    return Crm::PartnerFunnel.stage!(account, role, create: create) if source&.legacy_partner?

    pipeline = Crm::Environments.entry_pipeline(account, env)
    return nil if pipeline.nil?

    Crm::PartnerFunnel.find_stage(pipeline, role) || pipeline.stages.order(:position).first
  end

  def advance!(existing, stage)
    return if existing.stage_id == stage.id || existing.stage&.position.to_i >= stage.position.to_i

    bypass('admin') { existing.update!(stage_id: stage.id) }
  end

  def readvance!(account, env, wanted, card_id)
    existing = Crm::Contact.find_by(id: card_id)
    stage = existing && target_stage(account, env, wanted)
    advance!(existing, stage) if stage
  rescue StandardError => e
    Rails.logger.error "[cerca ambiente] avançar card #{card_id}: #{e.class}: #{e.message}"
  end

  def refuse!(card, why)
    Rails.logger.info "[cerca ambiente] card CEVICO NÃO criado: contato #{card.contact_id} · funil #{card.pipeline_id} · #{why}"
    card.errors.add(:base, "Paciente de outro ambiente do CRM: #{why}")
    throw :abort
  end

  def log(card, stage)
    Rails.logger.info "[cerca ambiente] card CEVICO redirecionado: contato #{card.contact_id} · " \
                      "funil #{card.pipeline_id}/coluna #{card.stage_id} → funil #{stage.pipeline_id}/coluna #{stage.id} (#{stage.name})"
  end
end
