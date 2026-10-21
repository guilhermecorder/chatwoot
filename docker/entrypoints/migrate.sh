#!/bin/sh
# 🧱 CEVICO Rodada 6 (RESIL-NOVO2): roda as migrations com TEMPO DE SOBRA.
#
# Por quê: o sistema normal tem um limite de 14 s por comando no banco
# (config/database.yml). Uma migration que cria índice em tabela grande
# (mensagens, contatos) pode passar disso; o banco cancela no meio e o índice
# fica "inválido" em silêncio — a tela fica lenta e ninguém vê erro.
# Aqui o limite sobe para 600 s (10 min), igual ao que o Chatwoot original usa.
#
# Depois de migrar, confere na hora se ficou algum índice inválido
# (rake cevico:db_check STRICT=1). Se aparecer, siga docs/BACKUP.md seção 3:
# no terminal o script sai com ERRO; no modo "migra e sobe" ele imprime um
# aviso grande e segue subindo o servidor.
#
# Como usar (fluxo "Implantar WEB+SIDEKIQ", só quando a rodada TEM migration;
# BACKUP antes, sempre):
#   - no terminal do serviço web do EasyPanel, depois de implantar a imagem nova:
#       sh docker/entrypoints/migrate.sh
#   - ou como comando do web (migra e depois sobe o servidor):
#       sh docker/entrypoints/migrate.sh bundle exec rails s -p 3000 -b 0.0.0.0
#
# Enquanto roda, o teste de saúde (healthcheck.sh) responde "saudável" para o
# contêiner nunca ser reiniciado no meio da migration.

set -e

MARCA=/tmp/cevico-migrando
touch "$MARCA"
trap 'rm -f "$MARCA"' EXIT INT TERM

LIMITE="${CEVICO_MIGRATE_TIMEOUT:-600s}"
echo "[CEVICO] migrations com limite de ${LIMITE} por comando..."

# o limite maior vale SÓ para este comando (não muda o resto do contêiner)
POSTGRES_STATEMENT_TIMEOUT="$LIMITE" bundle exec rails db:migrate

# conferência dos índices (STRICT=1: sai com erro se sobrou índice inválido)
if ! STRICT=1 bundle exec rails cevico:db_check; then
  echo "[CEVICO] ################################################################"
  echo "[CEVICO] ⚠️  SOBROU ÍNDICE INVÁLIDO depois da migration (lista acima)."
  echo "[CEVICO] ⚠️  Consertar: bundle exec rake cevico:db_reindex_invalid DRY=1"
  echo "[CEVICO] ⚠️  e depois DRY=0 (docs/BACKUP.md, seção 3)."
  echo "[CEVICO] ################################################################"
  # no terminal (sem comando depois) sai com erro para ninguém deixar passar;
  # no modo "migra e sobe o servidor" segue subindo (o sistema funciona, só
  # fica lento naquela tela) — o aviso fica no log do web
  [ "$#" -gt 0 ] || exit 1
fi

rm -f "$MARCA"
trap - EXIT INT TERM

# se veio um comando depois (ex.: subir o servidor), segue com ele com o limite
# normal de sempre (os 600 s ficaram só na migration)
if [ "$#" -gt 0 ]; then
  exec "$@"
fi
