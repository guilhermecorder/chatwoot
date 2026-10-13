# 🧯 CEVICO Rodada 6 (#215): o sistema confere se o backup da noite saiu.
#
# O script da VPS (script/backup_cevico.sh) grava, ao terminar, um bilhete
# .cevico_backup_status dentro da pasta de arquivos enviados (na VPS
# /root/cevico-storage = /app/storage aqui dentro). Este verificador lê o
# bilhete e aponta o que estiver errado:
# - não existe bilhete (o backup nunca rodou ou a pasta é outra);
# - o último backup tem mais de 26 h (o cron parou);
# - o arquivo do banco ficou com menos de 1 MB (dump vazio/quebrado);
# - a cópia para fora da VPS (rclone) não foi feita.
module Cevico::BackupCheck
  MAX_AGE = 26.hours
  MIN_DB_BYTES = 1.megabyte
  FILE_NAME = '.cevico_backup_status'.freeze

  module_function

  def status_path
    ENV.fetch('CEVICO_BACKUP_STATUS_FILE', Rails.root.join('storage', FILE_NAME).to_s)
  end

  # devolve { ok:, problems: [..], status: {..} }
  def check(path: status_path, now: Time.current)
    return result(["nenhum backup registrado (bilhete não encontrado em #{path})"], {}) unless File.exist?(path)

    status = JSON.parse(File.read(path))
    result(problems_for(status, now), status)
  rescue JSON::ParserError
    result(["bilhete do backup ilegível (#{path})"], {})
  end

  def problems_for(status, now)
    problems = [age_problem(status, now)]
    problems << "arquivo do banco com só #{status['banco_bytes'].to_i} bytes (menos de 1 MB)" if status['banco_bytes'].to_i < MIN_DB_BYTES
    problems << "cópia para fora da VPS: #{status['envio'].presence || 'sem registro'}" unless status['envio'] == 'ok'
    problems << "o próprio script avisou: #{status['erro']}" if status['erro'].present?
    problems.compact
  end

  def age_problem(status, now)
    finished = Time.zone.parse(status['data'].to_s)
    return 'data do último backup ausente' if finished.nil?

    "último backup tem #{((now - finished) / 1.hour).round} h (mais de 26 h: o cron parou?)" if now - finished > MAX_AGE
  rescue ArgumentError
    'data do último backup ilegível'
  end

  def result(problems, status)
    { ok: problems.empty?, problems: problems, status: status }
  end
end
