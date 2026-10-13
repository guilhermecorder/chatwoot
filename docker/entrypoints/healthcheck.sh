#!/bin/sh
# 🩺 CEVICO Rodada 6: teste de saúde da imagem (HEALTHCHECK do docker/Dockerfile
# e healthcheck do docker-compose.easypanel.yaml). A MESMA imagem roda o web e o
# Sidekiq, então o teste olha qual processo está de pé neste contêiner:
# - migration rodando (docker/entrypoints/migrate.sh) → sempre saudável:
#   derrubar o contêiner no meio de uma migration deixa índice pela metade;
# - web (puma de pé) → /health tem que responder;
# - Sidekiq → o "batimento" DESTE processo no Redis tem que ser recente
#   (o Sidekiq grava a cada ~10 s; travado = para de bater);
# - qualquer outra coisa (subindo, vite, console) → saudável, não atrapalha.

[ -f /tmp/cevico-migrando ] && exit 0

if pgrep -f 'puma [0-9]' >/dev/null 2>&1; then
  # porta 3000 fixa, igual ao comando do web (rails s -p 3000).
  # X-Forwarded-Proto: https → com FORCE_SSL=true o Rails responderia 301 para
  # https://127.0.0.1/health, o wget cairia na porta 443 e o EasyPanel ficaria
  # reiniciando o web sem parar. Com o cabeçalho o Rails trata como HTTPS.
  wget -q -T 12 -O /dev/null --header 'X-Forwarded-Proto: https' "http://127.0.0.1:3000/health" || exit 1
  exit 0
fi

SIDEKIQ_PID="$(pgrep -f 'sidekiq [0-9]' 2>/dev/null | head -1)"
if [ -n "$SIDEKIQ_PID" ]; then
  # Só dá "doente" quando conseguiu falar com o Redis E o batimento deste
  # processo sumiu ou está velho (> 90 s). Redis fora do ar, gem que não carrega
  # ou Sentinel → "saudável" (reiniciar o Sidekiq não conserta isso e ainda
  # poderia perder o trabalho em andamento; o Redis tem o próprio teste).
  cd /app 2>/dev/null || true
  ruby - "$SIDEKIQ_PID" <<'RUBY'
begin
  require 'bundler/setup'
  require 'redis'
  require 'socket'
rescue LoadError, StandardError => e
  warn "[saude] sem teste do Sidekiq (não carregou o redis: #{e.message})"
  exit 0
end
exit 0 if ENV['REDIS_SENTINELS'].to_s != ''

pid = ARGV[0]
host = ENV['DYNO'] || Socket.gethostname # o mesmo nome que o Sidekiq usa
opts = { url: ENV.fetch('REDIS_URL', 'redis://127.0.0.1:6379'), timeout: 5, reconnect_attempts: 1 }
opts[:password] = ENV['REDIS_PASSWORD'] if ENV['REDIS_PASSWORD'].to_s != ''
begin
  redis = Redis.new(**opts)
  key = redis.smembers('processes').find { |k| k.start_with?("#{host}:#{pid}:") }
  beat = key && redis.hget(key, 'beat').to_f
rescue StandardError => e
  warn "[saude] Redis não respondeu (#{e.class}): sem teste do Sidekiq"
  exit 0
end
idade = beat.to_f.positive? ? Time.now.to_f - beat : nil
if idade.nil? || idade > 90
  warn "[saude] Sidekiq (pid #{pid}) sem batimento recente no Redis#{idade ? " (#{idade.round} s)" : ''}"
  exit 1
end
exit 0
RUBY
  exit $?
fi

# ninguém conhecido de pé: se o contêiner é do Sidekiq e o processo caiu, o
# próprio contêiner sai; aqui não há o que testar
exit 0
