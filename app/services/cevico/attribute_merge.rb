# Merge ATÔMICO em additional_attributes (Conversation/Contact).
#
# Vários caminhos gravam additional_attributes do mesmo registro com o padrão
# lê→altera→grava (update_column), sem trava. Duas gravações concorrentes de
# CHAVES DIFERENTES no mesmo JSON se atropelavam — a pior consequência era
# PERDER A PAUSA (o robô voltava a responder depois que o humano assumiu).
#
# merge! serializa os escritores com um lock de linha (SELECT ... FOR UPDATE):
# relê os attrs FRESCOS dentro da trava, aplica o bloco e grava. Assim uma
# gravação nunca apaga a chave que a outra acabou de escrever.
module Cevico::AttributeMerge
  module_function

  # Ex.: Cevico::AttributeMerge.merge!(conversation) { |attrs| attrs.merge('x' => 1) }
  # O bloco recebe os attrs atuais (já frescos) e devolve o hash completo a gravar.
  def merge!(record)
    record.with_lock do
      current = record.additional_attributes || {}
      updated = yield(current.deep_dup)
      record.update_column(:additional_attributes, updated) # rubocop:disable Rails/SkipsModelValidations
    end
    record
  end
end
