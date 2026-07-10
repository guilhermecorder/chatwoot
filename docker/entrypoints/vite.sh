#!/bin/sh
set -x

rm -rf /app/tmp/pids/server.pid
rm -rf /app/tmp/cache/*

pnpm store prune
pnpm install --force

# instala gems que faltem (bin/vite depende de vite_ruby e cia.)
bundle install

echo "Ready to run Vite development server."

exec "$@"
