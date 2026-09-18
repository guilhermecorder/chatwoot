#!/usr/bin/env bash
# 🔧 Lista viva dos arquivos do UPSTREAM que o CEVICO alterou (rodada 171).
# Antes de cada atualização do Chatwoot, gere este relatório: são os
# arquivos onde o merge pode dar conflito. Arquivos 100% nossos (novos)
# não entram — eles nunca conflitam.
#   uso: script/cevico_touchpoints.sh [tag-do-upstream]   (padrão: último v4.x)
set -euo pipefail
cd "$(dirname "$0")/.."
TAG="${1:-$(git tag --list 'v4.*' | sort -V | tail -1)}"
OUT="docs/PONTOS_DE_CONTATO_UPSTREAM.md"
{
  echo "# Pontos de contato com o upstream (base: $TAG)"
  echo
  echo "Gerado por \`script/cevico_touchpoints.sh $TAG\` em $(date +%d/%m/%Y). Arquivos do Chatwoot"
  echo "original que o CEVICO modificou — na próxima atualização, são estes que podem conflitar."
  echo "Arquivos novos nossos (app/services/crm, components-next/cevico, …) não aparecem: nunca conflitam."
  echo
  echo "| arquivo | linhas +/- |"
  echo "|---|---|"
  git diff --numstat "$TAG" HEAD -- . ':(exclude)pnpm-lock.yaml' ':(exclude)db/schema.rb' | while read -r add del file; do
    if git cat-file -e "$TAG:$file" 2>/dev/null; then
      echo "| \`$file\` | +$add/−$del |"
    fi
  done
} > "$OUT"
echo "→ $OUT ($(grep -c '^| `' "$OUT") arquivos)"
