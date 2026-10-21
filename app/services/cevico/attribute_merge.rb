# Merge ATÔMICO em additional_attributes (Conversation, Contact, Message —
# qualquer registro que tenha a coluna).
#
# Vários caminhos gravam additional_attributes do mesmo registro com o padrão
# lê→altera→grava (update_column), sem trava. Duas gravações concorrentes de
# CHAVES DIFERENTES no mesmo JSON se atropelavam — a pior consequência era
# PERDER A PAUSA (o robô voltava a responder depois que o humano assumiu).
#
# merge! serializa os escritores com um lock de linha (SELECT ... FOR UPDATE):
# relê os attrs FRESCOS dentro da trava, aplica o bloco e grava. Assim uma
# gravação nunca apaga a chave que a outra acabou de escrever.
#
# Regra da casa (auditoria, Rodada 4): esta é a ÚNICA forma permitida de gravar
# additional_attributes — `update!(additional_attributes: …)` e
# `x.additional_attributes = (…).merge(…)` são proibidos fora daqui (o spec-lint
# attribute_merge_lint_spec.rb vigia os ofensores).
module Cevico::AttributeMerge
  module_function

  # Ex.: Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge('x' => 1) }
  # O bloco recebe os attrs atuais (já frescos) e devolve o hash completo a gravar.
  #
  # Se o registro recebido estiver "sujo" (ex.: `message.status = 'read'` ainda
  # sem save), a trava roda numa cópia limpa (lock! recusa registro com mudanças)
  # e a coluna do registro recebido é atualizada com o que foi gravado, sem
  # mexer nas outras mudanças pendentes dele. Mudança pendente na PRÓPRIA coluna
  # (ex.: `conv.additional_attributes['x'] = 1` antes do merge!) seria perdida
  # sem aviso — por isso é recusada: grave pelo bloco.
  def merge!(record)
    raise ArgumentError, "Cevico::AttributeMerge: #{record.class} não tem additional_attributes" unless record.has_attribute?(:additional_attributes)
    if record.will_save_change_to_additional_attributes?
      raise ArgumentError, 'Cevico::AttributeMerge: additional_attributes alterado em memória — grave pelo bloco do merge!'
    end

    row = record.has_changes_to_save? ? record.class.find(record.id) : record
    updated = nil
    row.with_lock do
      current = row.additional_attributes || {}
      updated = yield(current.deep_dup)
      row.update_column(:additional_attributes, updated) # rubocop:disable Rails/SkipsModelValidations
    end
    unless row.equal?(record)
      record[:additional_attributes] = updated
      record.clear_attribute_changes([:additional_attributes])
    end
    record
  end
end
