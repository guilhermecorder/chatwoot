#!/usr/bin/env bash
# 🧯 CEVICO — backup diário (Rodada 6, achado #215). Roda NA VPS, fora dos contêineres.
#
# O que faz, nesta ordem:
#   1. acha o contêiner do Postgres pelo começo do nome (sistema_cevico_postgres…
#      — o final muda a cada recriação no EasyPanel);
#   2. pg_dump do banco chatwoot_migrado → .sql.gz (confere se o gzip está inteiro);
#   3. tar.gz da pasta de arquivos enviados (/root/cevico-storage: fotos de exame,
#      áudios, anexos — o pg_dump NÃO cobre isso);
#   4. manda para FORA da VPS com rclone (Google Drive ou S3) — o banco primeiro;
#      se o tar dos arquivos falhar, o banco vai mesmo assim;
#   5. apaga o que for velho: banco 14 dias aqui, arquivos 3 dias aqui (são
#      grandes e moram no mesmo disco do banco), tudo 30 dias lá fora;
#      avisa se o disco passar de 80% (acima de 90% nem cria o tar dos arquivos);
#   6. deixa um bilhete (.cevico_backup_status) na pasta storage — o sistema lê
#      com `rake cevico:backup_check`;
#   7. AVISA (webhook) se algo deu errado ou se o arquivo do dia não existe / tem
#      menos de 1 MB.
#
# Uso:
#   bash script/backup_cevico.sh            → faz o backup completo
#   bash script/backup_cevico.sh verificar  → só confere o arquivo de hoje e avisa
#
# Configuração (variáveis de ambiente ou /root/.cevico_backup.env):
#   BANCO=chatwoot_migrado                 (NUNCA o $POSTGRES_DB do contêiner: aponta pro banco vazio "postgres")
#   PREFIXO_CONTAINER=sistema_cevico_postgres
#   PASTA=/root/backups/cevico
#   STORAGE_DIR=/root/cevico-storage
#   RCLONE_DESTINO=cevico-drive:backups-cevico   (vazio = não manda para fora, e avisa)
#   ALERTA_WEBHOOK_URL=https://…           (recebe POST JSON {"text": "..."}; ex.: fluxo do n8n que manda WhatsApp)
#   RETENCAO_LOCAL_DIAS=14  (banco aqui)  RETENCAO_LOCAL_ARQUIVOS_DIAS=3  (arquivos aqui)
#   RETENCAO_FORA_DIAS=30   (tudo lá fora)
#
# Cron sugerido (horário do servidor em UTC; 06:00 UTC = 03:00 de Brasília):
#   0 6 * * *  bash /root/cevico/backup_cevico.sh >> /root/backups/cevico/backup.log 2>&1
#   0 9 * * *  bash /root/cevico/backup_cevico.sh verificar >> /root/backups/cevico/backup.log 2>&1
#
# Restaurar: ver docs/BACKUP.md.

set -euo pipefail

[ -f /root/.cevico_backup.env ] && . /root/.cevico_backup.env

BANCO="${BANCO:-chatwoot_migrado}"
PREFIXO_CONTAINER="${PREFIXO_CONTAINER:-sistema_cevico_postgres}"
PASTA="${PASTA:-/root/backups/cevico}"
STORAGE_DIR="${STORAGE_DIR:-/root/cevico-storage}"
RCLONE_DESTINO="${RCLONE_DESTINO:-}"
ALERTA_WEBHOOK_URL="${ALERTA_WEBHOOK_URL:-}"
RETENCAO_LOCAL_DIAS="${RETENCAO_LOCAL_DIAS:-14}"
RETENCAO_LOCAL_ARQUIVOS_DIAS="${RETENCAO_LOCAL_ARQUIVOS_DIAS:-3}"
RETENCAO_FORA_DIAS="${RETENCAO_FORA_DIAS:-30}"
MIN_BYTES="${MIN_BYTES:-1048576}" # 1 MB: abaixo disso o dump está vazio ou quebrado
ERRO=""

HOJE="$(date +%Y%m%d)"
AGORA="$(date +%Y%m%d_%H%M)"
ARQ_BANCO="$PASTA/cevico_banco_${AGORA}.sql.gz"
ARQ_STORAGE="$PASTA/cevico_arquivos_${AGORA}.tar.gz"
BILHETE="$STORAGE_DIR/.cevico_backup_status"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

tamanho() { if [ -f "$1" ]; then wc -c <"$1" | tr -d ' '; else echo 0; fi; }

alertar() {
  log "⚠️ ALERTA: $1"
  if [ -n "$ALERTA_WEBHOOK_URL" ]; then
    local texto="🧯 Backup CEVICO ($(hostname)): $1"
    texto="${texto//\\/\\\\}"; texto="${texto//\"/\\\"}"
    curl -fsS -m 20 -X POST -H 'Content-Type: application/json' \
      -d "{\"text\": \"$texto\"}" "$ALERTA_WEBHOOK_URL" >/dev/null || log "não consegui mandar o alerta pelo webhook"
  else
    log "(sem ALERTA_WEBHOOK_URL: o alerta ficou só neste log)"
  fi
}

gravar_bilhete() { # $1 envio (ok|falhou|desligado) · $2 erro (texto ou vazio)
  [ -d "$STORAGE_DIR" ] || return 0
  local erro
  erro="$(printf '%s' "$2" | tr '"' "'")"
  printf '{"data": "%s", "banco_arquivo": "%s", "banco_bytes": %s, "storage_bytes": %s, "envio": "%s", "erro": "%s"}\n' \
    "$(date -Iseconds)" "$(basename "$ARQ_BANCO")" "$(tamanho "$ARQ_BANCO")" "$(tamanho "$ARQ_STORAGE")" "$1" "$erro" \
    >"$BILHETE.tmp" && mv "$BILHETE.tmp" "$BILHETE"
}

# confere se existe backup do banco de HOJE com pelo menos 1 MB
verificar() {
  local ultimo
  ultimo="$(ls -1t "$PASTA"/cevico_banco_"${HOJE}"_*.sql.gz 2>/dev/null | head -1 || true)"
  if [ -z "$ultimo" ]; then
    alertar "não existe backup do banco de hoje ($HOJE) em $PASTA"
    return 1
  fi
  if [ "$(tamanho "$ultimo")" -lt "$MIN_BYTES" ]; then
    alertar "backup de hoje com menos de 1 MB: $ultimo ($(tamanho "$ultimo") bytes)"
    return 1
  fi
  log "ok: $ultimo ($(tamanho "$ultimo") bytes)"
}

if [ "${1:-}" = "verificar" ]; then
  verificar
  exit $?
fi

falhou() {
  local motivo="$1"
  alertar "$motivo"
  gravar_bilhete "${ENVIO:-não chegou lá}" "$motivo"
  exit 1
}

mkdir -p "$PASTA"
log "início do backup (banco $BANCO)"

# 1. contêiner do Postgres pelo começo do nome
CONTAINER="$(docker ps --format '{{.Names}}' | grep "^${PREFIXO_CONTAINER}" | head -1 || true)"
[ -n "$CONTAINER" ] || falhou "contêiner do Postgres não encontrado (nome começando com $PREFIXO_CONTAINER)"
log "contêiner: $CONTAINER"

# 2. banco (arquivo .parcial até o gzip conferir — nunca deixa meio arquivo com nome de bom)
if ! docker exec "$CONTAINER" sh -c 'pg_dump -U "${POSTGRES_USER:-postgres}" -d "$1"' sh "$BANCO" | gzip >"$ARQ_BANCO.parcial"; then
  rm -f "$ARQ_BANCO.parcial"
  falhou "pg_dump do banco $BANCO falhou"
fi
gzip -t "$ARQ_BANCO.parcial" || { rm -f "$ARQ_BANCO.parcial"; falhou "arquivo do banco saiu corrompido (gzip -t)"; }
mv "$ARQ_BANCO.parcial" "$ARQ_BANCO"
log "banco: $ARQ_BANCO ($(tamanho "$ARQ_BANCO") bytes)"
# pequeno demais = suspeito: avisa, mas SEGUE (os arquivos e a cópia fora ainda valem a pena)
if [ "$(tamanho "$ARQ_BANCO")" -lt "$MIN_BYTES" ]; then
  ERRO="arquivo do banco com menos de 1 MB ($(tamanho "$ARQ_BANCO") bytes)"
  alertar "$ERRO"
fi

# anota um problema que NÃO interrompe o backup (o resto ainda vale a pena)
anotar_erro() {
  ERRO="${ERRO:+$ERRO; }$1"
  alertar "$1"
}

# 3. arquivos enviados (fotos de exame, áudios, anexos)
# 3a. disco: o backup mora no MESMO disco do banco de produção. Disco cheio =
#     Postgres para = sistema cai. Acima de 80% avisa; acima de 90% nem cria o
#     tar dos arquivos aqui (o banco, que é pequeno, continua sendo salvo).
USO_DISCO="$(df -P "$PASTA" | awk 'NR==2 {gsub("%", "", $5); print $5}')"
PULAR_ARQUIVOS=""
STORAGE_PRONTO="" # só vira 1 se o pacote de HOJE (desta rodada) saiu bom
if [ "${USO_DISCO:-0}" -ge 90 ]; then
  PULAR_ARQUIVOS=1
  anotar_erro "disco da VPS em ${USO_DISCO}%: pulei o backup dos ARQUIVOS para não encher o disco do banco (liberar espaço!)"
elif [ "${USO_DISCO:-0}" -ge 80 ]; then
  alertar "disco da VPS em ${USO_DISCO}% (acima de 80%): liberar espaço antes que o banco pare"
fi

# 3b. o tar roda com o sistema no ar: arquivo que muda ou some no meio da leitura
#     (foto nova chegando, limpeza do sistema) faz o tar sair com código 1. Isso é
#     normal e o pacote continua bom — só código 2 ou mais é falha de verdade.
#     Mesmo com falha aqui o script SEGUE: o banco ainda vai para fora da VPS.
if [ ! -d "$STORAGE_DIR" ]; then
  anotar_erro "pasta de arquivos $STORAGE_DIR não existe (fotos de exame ficariam sem backup)"
elif [ -z "$PULAR_ARQUIVOS" ]; then
  set +e
  tar --warning=no-file-changed --warning=no-file-removed \
    -czf "$ARQ_STORAGE.parcial" -C "$(dirname "$STORAGE_DIR")" --exclude='.cevico_backup_status*' "$(basename "$STORAGE_DIR")"
  RC_TAR=$?
  set -e
  # código 0/1 + gzip inteiro = pacote bom (o gzip -t pega tar que nem chegou a escrever)
  if [ "$RC_TAR" -le 1 ] && [ -s "$ARQ_STORAGE.parcial" ] && gzip -t "$ARQ_STORAGE.parcial"; then
    mv "$ARQ_STORAGE.parcial" "$ARQ_STORAGE"
    STORAGE_PRONTO=1
    [ "$RC_TAR" -eq 1 ] && log "aviso: algum arquivo mudou durante a leitura (normal com o sistema no ar)"
    log "arquivos: $ARQ_STORAGE ($(tamanho "$ARQ_STORAGE") bytes)"
  else
    rm -f "$ARQ_STORAGE.parcial"
    anotar_erro "tar da pasta $STORAGE_DIR falhou (código $RC_TAR) — o banco segue para fora mesmo assim"
  fi
fi

# 4. fora da VPS — o BANCO primeiro (é o mais importante e o menor)
if [ -z "$RCLONE_DESTINO" ]; then
  ENVIO="desligado"
  alertar "RCLONE_DESTINO vazio: o backup ficou SÓ nesta VPS (se o disco morrer, perde tudo)"
elif ! command -v rclone >/dev/null 2>&1; then
  ENVIO="falhou"
  alertar "rclone não instalado: o backup ficou SÓ nesta VPS"
elif rclone copy "$ARQ_BANCO" "$RCLONE_DESTINO/"; then
  log "banco enviado para $RCLONE_DESTINO"
  if [ -z "$STORAGE_PRONTO" ]; then
    ENVIO="só o banco (arquivos sem pacote hoje)"
  elif rclone copy "$ARQ_STORAGE" "$RCLONE_DESTINO/"; then
    ENVIO="ok"
    log "arquivos enviados para $RCLONE_DESTINO"
  else
    ENVIO="só o banco (envio dos arquivos falhou)"
    alertar "envio dos ARQUIVOS para $RCLONE_DESTINO falhou (o banco foi)"
  fi
  rclone delete --min-age "${RETENCAO_FORA_DIAS}d" --include 'cevico_*' "$RCLONE_DESTINO/" || log "não consegui limpar os antigos lá fora"
else
  ENVIO="falhou"
  alertar "envio para $RCLONE_DESTINO falhou: o backup ficou SÓ nesta VPS"
fi

# 5. retenção local (só os arquivos deste script). Banco: 14 dias (pequeno).
#    Arquivos: só 3 dias (cada pacote tem centenas de MB e a cópia completa fica
#    lá fora por 30 dias) — 14 dias deles encheriam o disco do banco.
find "$PASTA" -maxdepth 1 -type f -name 'cevico_banco_*.sql.gz' -mtime +"$RETENCAO_LOCAL_DIAS" -delete
find "$PASTA" -maxdepth 1 -type f -name 'cevico_arquivos_*.tar.gz' -mtime +"$RETENCAO_LOCAL_ARQUIVOS_DIAS" -delete
find "$PASTA" -maxdepth 1 -type f -name 'cevico_*.parcial' -mtime +1 -delete

# 6. bilhete para o sistema (rake cevico:backup_check)
gravar_bilhete "$ENVIO" "$ERRO"

# 7. conferência final do arquivo do dia (+ sai com erro se algo deu errado no caminho)
verificar || exit 1
[ -z "$ERRO" ] || { log "terminou COM problema: $ERRO"; exit 1; }
log "fim do backup"
