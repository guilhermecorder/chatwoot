# 🔒 Rodada 6 da auditoria (#227/#270/#200): MESCLAR paciente leva TUDO da
# CEVICO para o contato que fica.
#
# O ContactMergeAction do Chatwoot só leva conversas, mensagens, notas e
# caixas; depois apaga o duplicado. Com os dados da CEVICO pendurados no
# duplicado (consultas, anotações clínicas, formulários, card do funil...),
# o banco barrava a exclusão (erro 500 na tela "Mesclar" e na unificação) ou,
# pior, o card e o histórico de colunas sumiam junto.
#
# Agora, ANTES de apagar o duplicado (e dentro da mesma transação do merge),
# este módulo:
#   1. card do funil: se o contato que fica NÃO tem card naquele funil, o card
#      do duplicado passa para ele; se os dois têm, fica o que MEXEU POR ÚLTIMO
#      (o estado atual do paciente; empate = coluna mais à direita), o histórico de
#      colunas dos dois vai para ele e campos vazios (valor, responsável...)
#      são completados com os do outro.
#   2. consultas/tarefas, anotações clínicas, respostas de formulário, links de
#      página, cirurgias do hub, ligações, mensagens da Jornada, registros de
#      automação e pedidos da ótica trocam de dono (update_all, sem disparar
#      automação nenhuma).
#   3. campanhas (1 linha por paciente por campanha): se os dois estavam na
#      mesma campanha, fica a linha do contato que fica.
# rubocop:disable Rails/SkipsModelValidations -- de propósito: trocar o dono sem
# disparar automação, log de coluna nem validação do registro inteiro
module Cevico::ContactMergeRecords
  # campos do card que sai usados para completar o card que fica (se vazios)
  CARD_FILL_FIELDS = %w[value assignee_id procedure_of_interest origin notes].freeze

  private

  def merge_and_remove_mergee_contact
    merge_cevico_records
    super
  end

  def merge_cevico_records
    from = @mergee_contact.id
    to = @base_contact.id
    merge_crm_cards(from, to)
    cevico_owned_models.each { |model| model.where(contact_id: from).update_all(contact_id: to) }
    cevico_one_per_campaign.each do |model, campaign_column|
      already_in = model.where(contact_id: to).select(campaign_column)
      model.where(contact_id: from).where(campaign_column => already_in).delete_all
      model.where(contact_id: from).update_all(contact_id: to)
    end
  end

  # tabelas em que basta trocar o dono
  def cevico_owned_models
    [Task, Crm::ClinicalNote, Crm::FormResponse, CevicoPageRef, Crm::OftalmofacilSurgery,
     Crm::Call, Crm::JourneySend, Crm::AutomationLog, CevicoStockOrder]
  end

  # tabelas com "um por campanha" (índice único contato + campanha)
  def cevico_one_per_campaign
    { Crm::CampaignContact => :campaign_id, Crm::CallCampaignContact => :call_campaign_id }
  end

  def merge_crm_cards(from, to)
    Crm::Contact.where(contact_id: from).includes(:stage).find_each do |card|
      base_card = Crm::Contact.includes(:stage).find_by(contact_id: to, pipeline_id: card.pipeline_id)
      # update_columns: troca o dono sem disparar automação nem criar log de coluna
      next card.update_columns(contact_id: to) if base_card.nil?

      keep, drop = [base_card, card].sort_by { |c| card_rank(c) }.reverse
      fuse_cards!(keep, drop, to)
    end
  end

  # Qual card fica: o que MEXEU POR ÚLTIMO (é o retrato de hoje do paciente).
  # Não dá para usar "coluna mais à direita": no funil CEVICO as colunas de
  # desfecho ruim ficam à direita das boas ('Não Foi a Consulta' depois de
  # 'Consulta Confirmada', 'Sem Indicação Cirúrgica' depois de 'Consulta
  # Realizada'...). Um duplicado antigo parado em 'Não Foi a Consulta' tiraria
  # o paciente da coluna de confirmados e dos lembretes. Empate = coluna mais à
  # direita. (Regra escolhida pelo lado mais seguro; o Guilherme pode trocar.)
  def card_rank(card)
    [(card.stage_moved_at || card.updated_at || card.created_at).to_f, card.stage&.position.to_i]
  end

  def fuse_cards!(keep, drop, to)
    now = Time.current
    # o card que sai tem a coluna atual "aberta": fecha para não ficar o
    # paciente em duas colunas ao mesmo tempo no histórico
    drop.stage_logs.where(left_at: nil).find_each { |log| log.close!(now) }
    Crm::StageLog.where(crm_contact_id: drop.id).update_all(crm_contact_id: keep.id)
    fill = CARD_FILL_FIELDS.each_with_object({}) do |field, acc|
      acc[field] = drop[field] if keep[field].blank? && drop[field].present?
    end
    keep.update_columns(fill) if fill.any?
    # sem callbacks: o histórico já foi para o card que fica
    drop.delete
    keep.update_columns(contact_id: to) unless keep.contact_id == to
  end
end
# rubocop:enable Rails/SkipsModelValidations
