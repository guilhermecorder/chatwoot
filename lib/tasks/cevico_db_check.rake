# 🩺 CEVICO Rodada 6 — rede de segurança do banco e do backup
#
#   bundle exec rake cevico:db_check
#     lista índices INVÁLIDOS (criação cancelada no meio) e chaves estrangeiras
#     sem regra de apagar. Só lê. STRICT=1 faz sair com erro se houver inválido.
#
#   bundle exec rake cevico:db_reindex_invalid DRY=1   (padrão: só mostra)
#   bundle exec rake cevico:db_reindex_invalid DRY=0   (recria sem travar a tabela)
#     recria os índices inválidos com CONCURRENTLY (até 10 min por índice).
#     BACKUP antes, janela calma.
#
#   bundle exec rake cevico:backup_check
#     confere o bilhete que o script/backup_cevico.sh deixa na pasta storage
#     (último backup < 26 h, banco >= 1 MB, cópia fora da VPS ok). Sai com erro
#     se algo estiver errado (dá para usar em cron/monitor).
#
# Passo a passo completo: docs/BACKUP.md
namespace :cevico do # rubocop:disable Metrics/BlockLength
  desc 'Banco: lista índices inválidos e chaves estrangeiras sem regra de apagar (só leitura)'
  task db_check: :environment do
    invalid = Cevico::DbCheck.invalid_indexes
    if invalid.empty?
      puts '[CEVICO] índices: nenhum inválido ✅'
    else
      puts "[CEVICO] ⚠️ #{invalid.size} índice(s) INVÁLIDO(S) — o banco não usa, a tela fica lenta:"
      invalid.each { |i| puts "  - #{i['index_name']} (tabela #{i['table_name']})" }
      puts '  → para recriar: bundle exec rake cevico:db_reindex_invalid DRY=1 (depois DRY=0)'
    end

    fks = Cevico::DbCheck.foreign_keys_without_on_delete
    puts "[CEVICO] chaves estrangeiras sem regra de apagar (NO ACTION): #{fks.size}"
    fks.each { |fk| puts "  - #{fk['table_name']} → #{fk['references_table']} (#{fk['name']})" }

    abort('[CEVICO] STRICT=1: há índice inválido') if ENV['STRICT'] == '1' && invalid.any?
  end

  desc 'Banco: recria os índices inválidos sem travar a tabela (DRY=1 padrão só mostra; DRY=0 aplica)'
  task db_reindex_invalid: :environment do
    dry = ENV.fetch('DRY', '1') != '0'
    rows = Cevico::DbCheck.reindex_invalid!(dry: dry)
    if rows.empty?
      puts '[CEVICO] nenhum índice inválido — nada a fazer ✅'
      next
    end

    labels = { nil => 'faria', true => 'FEITO' }
    rows.each do |r|
      status = labels.fetch(r[:ok]) { "FALHOU: #{r[:error]}" }
      puts "  - #{r[:index_name]} (tabela #{r[:table_name]}): #{r[:action]} · #{status}"
    end
    if dry
      puts "TOTAL: #{rows.size} índice(s) (DRY: nada mudou). Para aplicar: DRY=0 — backup antes, janela calma"
    else
      failed = rows.count { |r| r[:ok] == false }
      puts "APLICADO: #{rows.size - failed} ok, #{failed} com falha"
      abort('[CEVICO] algum índice não foi recriado — veja acima') if failed.positive?
    end
  end

  desc 'Backup: confere se o backup da noite saiu (bilhete do script/backup_cevico.sh)'
  task backup_check: :environment do
    res = Cevico::BackupCheck.check
    st = res[:status]
    puts "[CEVICO] último backup: #{st['data'] || '—'} · banco #{st['banco_bytes'] || '—'} bytes · " \
         "arquivos #{st['storage_bytes'] || '—'} bytes · cópia fora: #{st['envio'] || '—'}"
    if res[:ok]
      puts '[CEVICO] backup ok ✅'
    else
      res[:problems].each { |p| puts "  ⚠️ #{p}" }
      abort('[CEVICO] backup com problema — veja docs/BACKUP.md')
    end
  end
end
