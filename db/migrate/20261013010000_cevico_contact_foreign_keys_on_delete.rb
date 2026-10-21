# 🔒 Rodada 6 da auditoria (#210/#227/#270/#200) — "o que acontece com os
# dados da CEVICO quando um paciente é APAGADO".
#
# PROBLEMA: as tabelas da CEVICO apontam para `contacts` com chave estrangeira
# SEM regra de exclusão. Resultado: apagar um paciente (botão Excluir contato,
# pedido de exclusão da LGPD) ou mesclar duplicados dava erro 500 para todo
# paciente que tinha card no CRM, consulta, anotação clínica ou formulário.
#
# REGRA NOVA (decidida pelo lado mais seguro para o paciente e para a clínica):
#   - APAGA junto (cascade) — dado do paciente, direito de exclusão da LGPD:
#       crm_contacts (card do funil), crm_clinical_notes (anotações clínicas),
#       crm_form_responses (respostas de formulário),
#       crm_campaign_contacts (participação em campanha), cevico_page_refs
#       (links de página com rastreio do paciente)
#   - DESLIGA o paciente e mantém o registro (nullify) — o horário continua
#       ocupado na Agenda / hub, só fica "sem paciente":
#       tasks (consultas/tarefas), cevico_oftalmofacil_surgeries (cirurgias)
#   (cevico_calls, cevico_journey_sends e cevico_call_campaign_contacts já
#    nasceram com regra — nullify/cascade — e não mudam aqui.)
#
# ⚠️ O QUE CONTINUA GUARDADO DEPOIS DE APAGAR O PACIENTE (decisão do Guilherme):
#   apagar o contato NÃO apaga tudo dele. Ficam, só "sem paciente":
#     - consultas/tarefas (tasks): o título ("Consulta: Maria ...") e o
#       telefone continuam na Agenda;
#     - cirurgias do hub (cevico_oftalmofacil_surgeries): nome e telefone do
#       paciente continuam (vêm do Oftalmofácil);
#     - ligações (cevico_calls): gravação e transcrição continuam;
#     - pedidos da ótica e registros de automação (sem chave estrangeira):
#       ficam apontando para um contato que não existe mais.
#   E a Agenda volta a ligar essas consultas a um cadastro NOVO com o mesmo
#   telefone (Task.for_patient busca pelo telefone e o
#   link_contact_by_phone ao salvar a consulta).
#   Ou seja: o botão "Excluir contato" resolve o erro 500 e apaga card,
#   anotações clínicas e formulários, mas NÃO é sozinho uma "exclusão LGPD
#   completa". Se o Guilherme quiser isso, o caminho é uma ação separada
#   "Apagar dados do paciente (LGPD)" que, além de apagar, apaga o telefone e o
#   nome das consultas/cirurgias e a gravação/transcrição das ligações.
#   (Não mudamos a regra da Agenda sem a decisão dele.)
#
# COMO RODA (seguro em produção, sem travar o sistema):
#   - disable_ddl_transaction!: cada tabela é trocada numa transação pequena
#     e curta, com lock_timeout de 3 s (se a tabela estiver ocupada, desiste
#     rápido em vez de deixar as telas esperando; tenta de novo sozinha até 3
#     vezes por tabela). Se mesmo assim parar com "lock timeout" ou
#     "deadlock detected", NÃO é estrago: as tabelas já trocadas ficam certas
#     e é só rodar de novo.
#   - rodar na janela calma com `sh docker/entrypoints/migrate.sh` (a conferência
#     de tasks e crm_contacts pode passar do limite normal de 14 s por comando).
#   - a chave nova entra como NOT VALID (instantâneo) e a conferência das
#     linhas (VALIDATE) roda depois, sem bloquear leituras/escritas.
#   - idempotente: se a chave já tem a regra certa, pula. Pode rodar de novo.
#
# ANTES DE RODAR EM PRODUÇÃO: BACKUP (/root/backup_cevico.sh na VPS).
# VOLTAR ATRÁS: `rails db:rollback` devolve as chaves SEM regra (como antes).
class CevicoContactForeignKeysOnDelete < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  LOCK_TIMEOUT = '3s'.freeze
  TRIES = 3

  # tabela => regra ao apagar o paciente
  RULES = {
    crm_contacts: :cascade,
    crm_clinical_notes: :cascade,
    crm_form_responses: :cascade,
    crm_campaign_contacts: :cascade,
    cevico_page_refs: :cascade,
    tasks: :nullify,
    cevico_oftalmofacil_surgeries: :nullify
  }.freeze

  def up
    RULES.each { |table, rule| swap_contact_fk(table, rule) }
  end

  def down
    RULES.each_key { |table| swap_contact_fk(table, nil) }
  end

  private

  # troca a chave estrangeira contact_id → contacts.id da tabela para a regra
  # pedida (nil = sem regra, o jeito antigo). Não faz nada se já está certa.
  def swap_contact_fk(table, rule)
    current = contact_fk(table)
    return if current && current.on_delete == rule && current.validated?

    replace_contact_fk(table, current, rule) unless current&.on_delete == rule
    validate_foreign_key(table, column: :contact_id)
  end

  # troca rápida (tabela ocupada = desiste em 3 s e tenta de novo, até 3 vezes)
  def replace_contact_fk(table, current, rule)
    attempt = 0
    begin
      attempt += 1
      transaction do
        execute("SET LOCAL lock_timeout = '#{LOCK_TIMEOUT}'")
        remove_foreign_key(table, column: :contact_id) if current
        add_foreign_key(table, :contacts, column: :contact_id, on_delete: rule, validate: false)
      end
    rescue ActiveRecord::LockWaitTimeout, ActiveRecord::Deadlocked
      raise if attempt >= TRIES

      sleep(attempt)
      retry
    end
  end

  def contact_fk(table)
    foreign_keys(table).find { |fk| fk.to_table == 'contacts' && fk.column == 'contact_id' }
  end
end
