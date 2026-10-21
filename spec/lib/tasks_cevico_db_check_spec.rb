require 'rails_helper'
require 'rake'

# 🩺 Rodada 6 (RESIL-NOVO2 e #215): índice inválido em silêncio e backup que não sai
RSpec.describe 'cevico:db_check / cevico:db_reindex_invalid / cevico:backup_check' do # rubocop:disable RSpec/DescribeClass
  before do
    Rake.application.rake_require('tasks/cevico_db_check')
    Rake::Task.define_task(:environment)
    %w[cevico:db_check cevico:db_reindex_invalid cevico:backup_check].each { |t| Rake::Task[t].reenable }
  end

  def run(task, env = {})
    stub_const('ENV', ENV.to_h.merge(env))
    Rake::Task[task].invoke
  end

  describe 'índices inválidos' do
    # CREATE INDEX CONCURRENTLY não roda dentro de transação: aqui sem a
    # transação automática do teste, e a tabela de teste é apagada no fim
    self.use_transactional_tests = false

    let(:conn) { ActiveRecord::Base.connection }
    let(:suffix) { SecureRandom.hex(3) }
    let(:table) { "cevico_r6_teste_#{suffix}" }
    let(:parent) { "cevico_r6_pai_#{suffix}" }
    let(:index) { "index_#{table}_on_nome" }

    before do
      conn.execute("CREATE TABLE #{parent} (id bigserial PRIMARY KEY)")
      conn.execute("CREATE TABLE #{table} (id bigserial PRIMARY KEY, nome varchar, pai_id bigint REFERENCES #{parent}(id))")
      conn.execute("INSERT INTO #{table} (nome) SELECT 'paciente ' || g FROM generate_series(1, 50) g")
      conn.execute("CREATE INDEX #{index} ON #{table} (nome)")
      # o que o Postgres deixa quando o CREATE INDEX CONCURRENTLY é cancelado pelo limite de 14 s
      conn.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{index}'::regclass")
    end

    after do
      conn.execute("DROP TABLE IF EXISTS #{table}")
      conn.execute("DROP TABLE IF EXISTS #{parent}")
    end

    def valid?(name)
      conn.select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = '#{name}'")
    end

    it 'cevico:db_check aponta o índice inválido e a chave estrangeira sem regra de apagar', :aggregate_failures do
      expect { run('cevico:db_check') }.to output(/INVÁLIDO.*#{index}.*chaves estrangeiras.*#{table} → #{parent}/m).to_stdout
    end

    it 'cevico:db_check com STRICT=1 sai com erro se houver índice inválido' do
      expect { run('cevico:db_check', 'STRICT' => '1') }.to raise_error(SystemExit).and output(/INVÁLIDO/).to_stdout
    end

    it 'DRY=1 só mostra; DRY=0 recria com o MESMO nome e o índice volta a valer', :aggregate_failures do
      expect { run('cevico:db_reindex_invalid', 'DRY' => '1') }.to output(/#{index}.*recriar · faria/).to_stdout
      expect(valid?(index)).to be(false)

      Rake::Task['cevico:db_reindex_invalid'].reenable
      expect { run('cevico:db_reindex_invalid', 'DRY' => '0') }.to output(/#{index}.*recriar · FEITO/).to_stdout
      expect(valid?(index)).to be(true)
      expect(conn.select_value("SELECT pg_get_indexdef('#{index}'::regclass)")).to include('(nome)')
      expect(conn.select_value("SELECT count(*) FROM pg_class WHERE relname LIKE '%_cevico_novo'")).to eq(0)
      expect(Cevico::DbCheck.invalid_indexes.pluck('index_name')).not_to include(index)
    end

    it 'sobra _ccnew de um REINDEX que falhou é só apagada (o índice original continua)', :aggregate_failures do
      leftover = "#{index}_ccnew"
      conn.execute("CREATE INDEX #{leftover} ON #{table} (nome)")
      conn.execute("UPDATE pg_index SET indisvalid = false WHERE indexrelid = '#{leftover}'::regclass")

      expect { run('cevico:db_reindex_invalid', 'DRY' => '0') }.to output(/#{leftover}.*apagar sobra · FEITO/).to_stdout
      expect(valid?(leftover)).to be_nil
      expect(valid?(index)).to be(true)
    end

    it 'se recriar falhar, a inválida NÃO some (continua aparecendo para a equipe)', :aggregate_failures do
      allow(Cevico::DbCheck).to receive(:concurrent_definition).and_raise(ActiveRecord::StatementInvalid, 'cancelado')

      expect { run('cevico:db_reindex_invalid', 'DRY' => '0') }.to raise_error(SystemExit).and output(/FALHOU/).to_stdout
      expect(valid?(index)).to be(false)
    end
  end

  describe 'cevico:backup_check' do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, '.cevico_backup_status') }

    after { FileUtils.rm_rf(dir) }

    def write_status(data:, bytes: 65.megabytes, envio: 'ok')
      File.write(path, { data: data.iso8601, banco_bytes: bytes, storage_bytes: 600.megabytes, envio: envio }.to_json)
    end

    it 'sem bilhete = alerta (o backup nunca rodou — o caso da memória de 16/09)' do
      expect { run('cevico:backup_check', 'CEVICO_BACKUP_STATUS_FILE' => path) }
        .to raise_error(SystemExit).and output(/nenhum backup registrado/).to_stdout
    end

    it 'backup de hoje, com tamanho e cópia fora = ok' do
      write_status(data: 3.hours.ago)
      expect { run('cevico:backup_check', 'CEVICO_BACKUP_STATUS_FILE' => path) }.to output(/backup ok/).to_stdout
    end

    it 'backup velho, arquivo pequeno e sem cópia fora = alerta com os três problemas' do
      write_status(data: 30.hours.ago, bytes: 20_000, envio: 'falhou')
      expect { run('cevico:backup_check', 'CEVICO_BACKUP_STATUS_FILE' => path) }
        .to raise_error(SystemExit).and output(/mais de 26 h.*menos de 1 MB.*fora da VPS: falhou/m).to_stdout
    end
  end
end
