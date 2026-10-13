# 🩺 CEVICO Rodada 6 (RESIL-NOVO2): saúde do banco depois de migration.
#
# - invalid_indexes: índices que o Postgres marcou como INVÁLIDOS. Acontece
#   quando um CREATE INDEX CONCURRENTLY é cancelado no meio (ex.: o limite de
#   14 s do config/database.yml). O índice fica lá, mas o banco não usa — e a
#   migration com if_not_exists acha que já existe e pula. Resultado: tela
#   lenta sem erro nenhum.
# - foreign_keys_without_on_delete: chaves estrangeiras sem regra de apagar
#   (NO ACTION). Só lista, para a equipe saber o que trava uma exclusão.
# - reindex_invalid!: recria os inválidos SEM travar a tabela (CONCURRENTLY).
#   Sobras "_ccnew"/"_ccold" de um REINDEX CONCURRENTLY que falhou são só
#   apagadas (o índice original continua existindo).
#
# Usado por lib/tasks/cevico_db_check.rake e docker/entrypoints/migrate.sh.
module Cevico::DbCheck
  # tempo de sobra para recriar índice em tabela grande (o normal é 14 s)
  REINDEX_TIMEOUT = '600s'.freeze
  # sobras: de REINDEX CONCURRENTLY do Postgres (_ccnew/_ccold) ou cópia nossa que parou no meio
  LEFTOVER = /(_cc(new|old)\d*|_cevico_novo)\z/

  module_function

  def connection
    ActiveRecord::Base.connection
  end

  def invalid_indexes
    connection.select_all(<<~SQL.squish).to_a
      SELECT c.relname AS index_name, t.relname AS table_name, n.nspname AS schema_name,
             pg_get_indexdef(i.indexrelid) AS definition
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE NOT i.indisvalid AND n.nspname = current_schema()
      ORDER BY t.relname, c.relname
    SQL
  end

  def foreign_keys_without_on_delete
    connection.select_all(<<~SQL.squish).to_a
      SELECT con.conname AS name, t.relname AS table_name, r.relname AS references_table
      FROM pg_constraint con
      JOIN pg_class t ON t.oid = con.conrelid
      JOIN pg_class r ON r.oid = con.confrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE con.contype = 'f' AND con.confdeltype = 'a' AND n.nspname = current_schema()
      ORDER BY t.relname, con.conname
    SQL
  end

  # dry: true só devolve o plano. Devolve [{ index_name:, action:, ok:, error: }]
  def reindex_invalid!(dry: true)
    invalid_indexes.map do |idx|
      leftover = idx['index_name'].match?(LEFTOVER)
      row = { index_name: idx['index_name'], table_name: idx['table_name'], action: leftover ? 'apagar sobra' : 'recriar', ok: nil }
      dry ? row : row.merge(rebuild_result(idx, leftover))
    end
  end

  def rebuild_result(idx, leftover)
    rebuild(idx, leftover)
    { ok: true }
  rescue ActiveRecord::ActiveRecordError => e
    { ok: false, error: e.message }
  end

  # Ordem segura: cria a cópia nova (válida) ANTES de apagar a inválida e só
  # então dá o nome antigo a ela. Se criar falhar, nada some — a inválida
  # continua lá (e continua aparecendo no cevico:db_check).
  def rebuild(idx, leftover)
    # CONCURRENTLY não roda dentro de transação: aborta antes de mexer em algo
    raise ActiveRecord::ActiveRecordError, 'não roda dentro de transação' if connection.transaction_open?

    with_long_timeout do
      if leftover
        drop_index(idx['schema_name'], idx['index_name'])
      else
        temp = "#{idx['index_name'][0, 48]}_cevico_novo"
        create_copy(idx, temp)
        drop_index(idx['schema_name'], idx['index_name'])
        connection.execute("ALTER INDEX #{qualified(idx['schema_name'], temp)} RENAME TO #{connection.quote_table_name(idx['index_name'])}")
      end
    end
  end

  def create_copy(idx, temp)
    drop_index(idx['schema_name'], temp)
    connection.execute(concurrent_definition(idx['definition'], temp))
  rescue ActiveRecord::ActiveRecordError
    # cópia que falhou também fica inválida: limpa para não deixar lixo
    drop_index(idx['schema_name'], temp)
    raise
  end

  def drop_index(schema, name)
    connection.execute("DROP INDEX CONCURRENTLY IF EXISTS #{qualified(schema, name)}")
  end

  def qualified(schema, name)
    "#{connection.quote_table_name(schema)}.#{connection.quote_table_name(name)}"
  end

  # "CREATE [UNIQUE] INDEX nome ON ..." → "CREATE [UNIQUE] INDEX CONCURRENTLY novo_nome ON ..."
  def concurrent_definition(definition, new_name)
    match = definition.match(/\ACREATE (UNIQUE )?INDEX \S+ ON /)
    raise ActiveRecord::ActiveRecordError, "definição inesperada: #{definition}" unless match

    "CREATE #{match[1]}INDEX CONCURRENTLY #{connection.quote_table_name(new_name)} ON #{match.post_match}"
  end

  def with_long_timeout
    old = connection.select_value('SHOW statement_timeout')
    connection.execute("SET statement_timeout = #{connection.quote(REINDEX_TIMEOUT)}")
    yield
  ensure
    connection.execute("SET statement_timeout = #{connection.quote(old)}") if old
  end
end
