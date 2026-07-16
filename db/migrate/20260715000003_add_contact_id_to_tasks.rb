# CENTRAL DO PACIENTE — Fase 0 (unificação): consulta/tarefa amarrada ao
# contato de verdade. Aditiva: só cria a coluna + índice e preenche o que
# der para casar pelo telefone (últimos 8 dígitos, mesmo critério que o
# sistema já usava nos matches ad hoc). Quem não casar continua com o
# telefone como fallback — nada é apagado.
class AddContactIdToTasks < ActiveRecord::Migration[7.0]
  def up # rubocop:disable Metrics/MethodLength
    add_reference :tasks, :contact, foreign_key: true, index: true

    # Backfill em SQL puro (uma passada, sem N+1): para cada task com
    # telefone, o contato da MESMA conta cujos últimos 8 dígitos batem.
    # Empate (número duplicado) → prefere o match de número inteiro,
    # depois o contato mais antigo (menor id).
    execute <<~SQL.squish
      UPDATE tasks
      SET contact_id = matched.contact_id
      FROM (
        SELECT DISTINCT ON (t.id) t.id AS task_id, c.id AS contact_id
        FROM tasks t
        JOIN contacts c
          ON c.account_id = t.account_id
         AND RIGHT(regexp_replace(COALESCE(c.phone_number, ''), '\\D', '', 'g'), 8) =
             RIGHT(regexp_replace(COALESCE(t.phone, ''), '\\D', '', 'g'), 8)
        WHERE t.contact_id IS NULL
          AND LENGTH(regexp_replace(COALESCE(t.phone, ''), '\\D', '', 'g')) >= 8
          AND LENGTH(regexp_replace(COALESCE(c.phone_number, ''), '\\D', '', 'g')) >= 8
        ORDER BY t.id,
                 (regexp_replace(COALESCE(c.phone_number, ''), '\\D', '', 'g') =
                  regexp_replace(COALESCE(t.phone, ''), '\\D', '', 'g')) DESC,
                 c.id
      ) matched
      WHERE tasks.id = matched.task_id
    SQL
  end

  def down
    remove_reference :tasks, :contact
  end
end
