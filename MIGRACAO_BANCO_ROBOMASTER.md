# Migração do banco: Robomaster (Chatwoot) → Sistema CEVICO

> **Status: PLANEJADO — não executar sem acompanhamento.**
> Roteiro para levar os ~10.000 leads do Chatwoot do projeto `robomaster`
> para o `sistema_cevico`, na mesma VPS (EasyPanel).

## Estratégia escolhida: DUPLICAR (não apontar)

- **Duplicar** = dump do banco do Robomaster → restaurar no postgres do
  CEVICO → rodar nossas migrations na cópia. O banco original fica
  **intocado** (é o backup natural). ✅
- **Apontar** o CEVICO para o banco vivo do Robomaster ❌ — as migrations
  do fork alterariam o banco que o Robomaster usa (quebraria ele), e dois
  sistemas escrevendo no mesmo banco causa corrupção de dados.

## Pré-checagens (fazer ANTES da janela)

1. **Versão do Chatwoot do Robomaster** — precisa ser <= v4.14.1 (a nossa).
   No terminal do container `robomaster/chatwoot`:
   ```bash
   cat /app/config/app.yml | grep version   # ou: bundle exec rails runner "puts Chatwoot.config[:version]"
   ```
   - Se for MAIS NOVA que 4.14.1: parar e atualizar o fork primeiro.
2. **Tamanho do banco** (para estimar tempo):
   ```bash
   # no terminal do postgres do robomaster (chatwoot-db)
   psql -U $POSTGRES_USER -c "SELECT pg_size_pretty(pg_database_size(current_database()));"
   ```
3. **Espaço em disco na VPS** — precisa de ~2x o tamanho do banco livre.
4. **Anexos**: verificar se o Robomaster usa storage local (volume
   `/app/storage`). Se sim, os arquivos também precisam ser copiados.

## ⚡ Caminho rápido — UM COLAR SÓ (recomendado)

No painel da Hostinger → VPS → **Terminal do navegador** (abre já logado como
root, sem senha). Cole o bloco inteiro abaixo e aperte Enter:

```bash
set -e
echo "== Duplicando banco Robomaster -> Sistema CEVICO =="
SRC=$(docker ps --format '{{.Names}}' | grep -i 'robomaster_chatwoot-db' | head -1)
DST=$(docker ps --format '{{.Names}}' | grep -i 'sistema_cevico_postgres' | head -1)
[ -z "$SRC" ] && { echo "ERRO: banco do robomaster nao encontrado"; exit 1; }
[ -z "$DST" ] && { echo "ERRO: postgres do cevico nao encontrado"; exit 1; }
echo "Origem:  $SRC"
echo "Destino: $DST"
echo "== 1/4 Exportando (nao altera nada no original)..."
docker exec "$SRC" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c -f /tmp/robomaster.dump'
echo "== 2/4 Transferindo..."
docker cp "$SRC":/tmp/robomaster.dump /root/robomaster.dump
docker cp /root/robomaster.dump "$DST":/tmp/robomaster.dump
echo "== 3/4 Criando banco novo chatwoot_migrado..."
docker exec "$DST" sh -c 'createdb -U "$POSTGRES_USER" chatwoot_migrado'
echo "== 4/4 Importando (pode demorar alguns minutos)..."
docker exec "$DST" sh -c 'pg_restore -U "$POSTGRES_USER" -d chatwoot_migrado --no-owner --no-acl /tmp/robomaster.dump'
echo ""
echo "✅ PRONTO! Banco duplicado como 'chatwoot_migrado' no postgres do CEVICO."
echo "Proximo passo: no EasyPanel, mude POSTGRES_DATABASE=chatwoot_migrado"
echo "nos servicos web e sidekiq e clique Implantar."
```

Depois do ✅: EasyPanel → `web` e `sidekiq` → **Ambiente** →
`POSTGRES_DATABASE=chatwoot_migrado` → **Implantar** nos dois.
Rollback: voltar a variável para o valor antigo e implantar.

> Pré-requisito: o fork precisa estar na v4.15.1 (mesma versão do
> Robomaster) — feito em 09/07/2026.

## Janela de migração (passo a passo)

> Combinar horário de baixo movimento. O Robomaster continua no ar durante
> o dump; só o corte final (troca do número) exige pausa.

### 1. Dump do banco do Robomaster
No terminal do serviço `chatwoot-db` (postgres do robomaster):
```bash
pg_dump -U $POSTGRES_USER -d $POSTGRES_DB -F c -f /var/lib/postgresql/data/robomaster.dump
```

### 2. Transferir o dump para o postgres do CEVICO
Na VPS (host), os volumes dos dois postgres ficam em
`/etc/easypanel/projects/<projeto>/<serviço>/volumes/...`. Copiar:
```bash
cp /etc/easypanel/projects/robomaster/chatwoot-db/volumes/.../robomaster.dump \
   /etc/easypanel/projects/sistema_cevico/postgres/volumes/.../
```
(Os caminhos exatos conferimos na hora com `docker volume ls` / inspect.)

### 3. Backup do banco atual do CEVICO (segurança)
No terminal do postgres do CEVICO:
```bash
pg_dump -U postgres -d $POSTGRES_DB -F c -f /var/lib/postgresql/data/cevico_antes_migracao.dump
```

### 4. Restaurar a cópia em um banco novo
```bash
createdb -U postgres chatwoot_migrado
pg_restore -U postgres -d chatwoot_migrado --no-owner --no-acl /var/lib/postgresql/data/robomaster.dump
```

### 5. Apontar o CEVICO para o banco migrado
No EasyPanel → serviço `web` e `sidekiq` → Ambiente:
```
POSTGRES_DATABASE=chatwoot_migrado
```
Implantar. O comando de boot (`db:chatwoot_prepare`) roda as migrations do
fork em cima da cópia — cria as tabelas do CRM, campanhas etc.

### 6. Pós-migração (no terminal do web)
```bash
# título e plano
bundle exec rails runner "InstallationConfig.find_by(name: 'INSTALLATION_NAME')&.update!(value: 'CEVICO S.I')"
bundle exec rails runner "c=InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN'); c&.update!(value: 'enterprise')"
# feature flags do Captain na conta principal (id conferir na hora)
```
- Recriar/conferir usuários admin (Guilherme + Henrique) — vêm do banco
  antigo; senhas antigas valem.
- Conferir caixas de entrada: a caixa da Evolution API vem junto mas não
  funciona no CEVICO — desativar; a caixa WhatsApp Cloud oficial do CEVICO
  precisa ser recriada/reconectada (config fica no banco novo).
- Anexos: copiar volume `storage` se necessário.

### 7. Corte final
- Robomaster deixa de atender (pausar campanhas/entradas por lá).
- Público passa a usar o Sistema CEVICO.
- O banco original do Robomaster permanece como backup permanente.

## Rollback
Se algo der errado no passo 5: voltar `POSTGRES_DATABASE` para o valor
anterior e implantar — o CEVICO volta ao banco pré-migração intocado.

## Depois de estabilizado
- Usar o "Tratamento de dados" (Campanha WhatsApp → Automações) para
  etiquetar as conversas históricas por conteúdo (ex: "3900" →
  orcamento-refrativa) e segmentar campanhas sobre os 10k leads.
