# 🏷️ Rodada 5 da auditoria (#17): a etiqueta do CONTATO mudou de verdade →
# automações "Etiqueta adicionada/removida" do CRM, venha de onde vier (telas
# do CRM, tela Contatos do Chatwoot, API/N8N, automação, etiqueta da conversa
# que sobe ao contato). Antes só a etiqueta salva pelas telas do CRM disparava,
# porque dependia do navegador mandar o "antes×depois".
#
# O disparo sai DEPOIS de gravar no banco (after_commit) e passa pela marca de
# contato+etiqueta+automação do CrmAutomationTriggerService (um disparo só).
#
# Só enxerga a etiqueta trocada pelo jeito normal (label_list=, add_labels,
# update_labels). Ficam de fora DE PROPÓSITO (são cargas em massa):
# - mexer direto na lista (label_list.add/remove + save!): campanha
#   (campaign_run_job), marcador da automação de mensagem
#   (message_automation_run_job) e etiqueta da campanha de ligação
#   (voice_agent/post_call_service);
# - renomear etiqueta (Labels::UpdateService) e importação de planilha
#   (DataImportJob grava direto no banco);
# - blocos dentro de Contact.without_label_triggers: ação em lote de
#   Contatos/Conversas e Tratamento de dados (trocar, remover, unificar).
module CevicoLabelTriggers
  extend ActiveSupport::Concern

  SKIP_KEY = :cevico_skip_label_triggers

  included do
    after_save :cevico_track_label_change
    after_commit :cevico_fire_label_triggers
    after_rollback :cevico_forget_label_change
  end

  class_methods do
    # Etiqueta posta em LOTE (ação em massa nas telas de Contatos ou Conversas)
    # não dispara as automações de etiqueta — senão uma seleção de centenas de
    # pacientes viraria centenas de mensagens. A importação de planilha e as
    # cargas do CRM gravam a etiqueta direto no banco e já não passam aqui.
    def without_label_triggers
      previous = Thread.current[SKIP_KEY]
      Thread.current[SKIP_KEY] = true
      yield
    ensure
      Thread.current[SKIP_KEY] = previous
    end

    def label_triggers_skipped?
      Thread.current[SKIP_KEY] == true
    end
  end

  private

  # guarda o antes×depois das etiquetas (se o contato for salvo mais de uma
  # vez na mesma transação, vale o primeiro "antes" e o último "depois")
  def cevico_track_label_change
    return unless saved_change_to_label_list?
    return if self.class.label_triggers_skipped?

    before, after = saved_change_to_label_list
    @cevico_label_change ||= [Array(before).map(&:to_s), nil]
    @cevico_label_change[1] = Array(after).map(&:to_s)
  end

  def cevico_forget_label_change
    @cevico_label_change = nil
  end

  # depois de gravado: só o que entrou e o que saiu de fato (sem diferenciar
  # maiúscula de minúscula). Erro aqui nunca derruba o salvamento do contato.
  def cevico_fire_label_triggers
    before, after = @cevico_label_change
    @cevico_label_change = nil
    return if after.nil?

    CrmAutomationTriggerService.label_change!(self, added: labels_missing_from(after, before),
                                                    removed: labels_missing_from(before, after))
  rescue StandardError => e
    Rails.logger.error "[CevicoLabelTriggers] contato #{id}: #{e.message}"
  end

  # etiquetas de `list` que não estão em `other`
  def labels_missing_from(list, other)
    other_down = other.map(&:downcase)
    list.reject { |l| other_down.include?(l.downcase) }.uniq(&:downcase)
  end
end
