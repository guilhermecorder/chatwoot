#!/bin/sh

set -x

echo "Waiting for postgres to become ready...."

$(docker/entrypoints/helpers/pg_database_url.rb)
PG_READY="pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USERNAME"

until $PG_READY
do
  sleep 2;
done

echo "Database ready to accept connections."

# instala gems que faltam no dev (imagem base é compilada para produção);
# sem isto o sidekiq cai em loop quando o Gemfile muda (ex.: gem anthropic)
bundle install

BUNDLE="bundle check"

until $BUNDLE
do
  sleep 2;
done

exec "$@"
