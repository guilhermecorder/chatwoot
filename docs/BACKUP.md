# Rede de segurança da CEVICO — backup, Redis, migrations e filas

Rodada 6 da auditoria (13/10/2026). Achados: #215 (backup), RESIL-NOVO1 (Redis),
RESIL-NOVO2 (migrations e índice inválido), RESIL-1 (fila da IA).

Tudo aqui é feito NA VPS ou no EasyPanel (projeto `sistema_cevico`), numa janela
calma. Nada disso muda tela nem atendimento.

---

## 1. Backup diário (banco + arquivos) com cópia fora da VPS

### O que mudou
- O script agora mora no repositório: `script/backup_cevico.sh` (o antigo
  `/root/backup_cevico.sh` ficou sem gerar arquivo desde 16/09 — não confiar nele).
- Ele salva **o banco** (`chatwoot_migrado`) **e os arquivos enviados**
  (`/root/cevico-storage`: fotos de exame, áudios, anexos — o pg_dump não pega isso).
- Manda os dois para **fora da VPS** (Google Drive ou S3, via rclone) — **o banco
  primeiro**. Se o pacote dos arquivos falhar, o banco vai para fora mesmo assim.
- O pacote dos arquivos roda com o sistema no ar: foto chegando no meio da leitura
  faz o `tar` dar "código 1" — é normal e o pacote vale (só código 2+ é falha).
- Guarda na VPS: **banco 14 dias**, **arquivos só 3 dias** (cada pacote tem centenas
  de MB e fica no MESMO disco do banco de produção — 14 dias deles poderiam encher
  o disco e parar o Postgres). Lá fora: tudo 30 dias.
- Disco da VPS acima de **80%** → avisa; acima de **90%** → nem cria o pacote dos
  arquivos (o banco continua sendo salvo e enviado).
- **Avisa** (webhook) se: o contêiner do banco não for achado, o dump falhar,
  o arquivo do dia não existir ou tiver menos de 1 MB, o pacote dos arquivos falhar,
  ou a cópia fora falhar. Termina com erro (código 1) se qualquer coisa deu errado.
- Deixa um bilhete `.cevico_backup_status` na pasta storage; o sistema confere com
  `bundle exec rake cevico:backup_check` (sai com erro se o último backup tiver mais
  de 26 h, menos de 1 MB ou não tiver ido para fora).

### Instalar na VPS (uma vez)
1. Copiar o script: `mkdir -p /root/cevico && nano /root/cevico/backup_cevico.sh`
   (colar o conteúdo de `script/backup_cevico.sh`) e `chmod +x /root/cevico/backup_cevico.sh`.
2. Instalar o rclone: `curl https://rclone.org/install.sh | bash`.
3. Criar o destino: `rclone config` → novo remoto (ex.: nome `cevico-drive`, tipo
   Google Drive; ou S3). Testar: `rclone lsd cevico-drive:`.
4. Criar `/root/.cevico_backup.env`:
   ```
   RCLONE_DESTINO=cevico-drive:backups-cevico
   ALERTA_WEBHOOK_URL=https://…   # opcional: recebe {"text": "..."} (ex.: fluxo do n8n que manda WhatsApp)
   ```
5. Ver o espaço do disco ANTES (`df -h /`): precisa sobrar pelo menos ~3× o tamanho
   da pasta de arquivos (`du -sh /root/cevico-storage`). Se o disco já passa de 80%,
   liberar espaço primeiro (backups antigos em `/root`, imagens velhas:
   `docker image prune`). Depois rodar uma vez na mão e olhar a saída:
   `bash /root/cevico/backup_cevico.sh`
   Esperado: banco ~60–70 MB, arquivos ~600 MB+, "enviado para cevico-drive:…".
6. Trocar o cron (`crontab -e`), apagando a linha antiga do `/root/backup_cevico.sh`:
   ```
   0 6 * * *  bash /root/cevico/backup_cevico.sh >> /root/backups/cevico/backup.log 2>&1
   0 9 * * *  bash /root/cevico/backup_cevico.sh verificar >> /root/backups/cevico/backup.log 2>&1
   ```
   (06:00 do servidor em UTC = 03:00 de Brasília; a linha das 9h só confere e avisa.)

### Conferir
- Na VPS: `ls -lh /root/backups/cevico/ | tail` e `tail -20 /root/backups/cevico/backup.log`.
- No sistema (terminal do serviço web no EasyPanel): `bundle exec rake cevico:backup_check`.
- Lá fora: `rclone ls cevico-drive:backups-cevico | tail`.

### Restaurar (testar 1× por mês num banco de TESTE, nunca no de produção)
```
C=$(docker ps --format '{{.Names}}' | grep '^sistema_cevico_postgres' | head -1)
docker exec "$C" createdb -U postgres teste_restore
gunzip -c /root/backups/cevico/cevico_banco_AAAAMMDD_HHMM.sql.gz | docker exec -i "$C" psql -U postgres -d teste_restore
docker exec "$C" psql -U postgres -d teste_restore -c 'select count(*) from contacts'
docker exec "$C" dropdb -U postgres teste_restore
```
Arquivos: `tar -xzf cevico_arquivos_AAAAMMDD_HHMM.tar.gz -C /tmp/teste_restore`
(conferir que as pastas de 2 letras com fotos aparecem). Se o arquivo estiver só
lá fora: `rclone copy cevico-drive:backups-cevico/NOME /root/`.

---

## 2. Redis com AOF (fila não some se o Redis cair)

### Por quê
O Redis guardava a fila só numa "foto" tirada de tempos em tempos. Se caísse,
voltava da última foto: mensagens enfileiradas nos últimos minutos sumiam — ficavam
"enviadas" na tela e nunca chegavam ao paciente.

### O que mudou (docker-compose.easypanel.yaml)
`--appendonly yes --appendfsync everysec` (grava cada mudança no disco a cada 1 s),
`--maxmemory 512mb --maxmemory-policy noeviction` (memória cheia = recusa com erro
visível em vez de apagar fila) e teste de saúde (`redis-cli ping`).

⚠️ Em produção o Redis é um serviço próprio do EasyPanel (`sistema_cevico_redis`),
que provavelmente NÃO lê este arquivo: o AOF só passa a valer quando o comando
for trocado lá (passo 4 abaixo). **Não conferido ainda** se o serviço de Redis do
EasyPanel deixa editar o comando:
- procurar no serviço Redis do projeto `sistema_cevico` um campo "Comando"/"Command"
  (aba Geral ou Avançado) e colar:
  `redis-server --requirepass "SENHA" --appendonly yes --appendfsync everysec --maxmemory 512mb --maxmemory-policy noeviction`
- **plano B** (se não existir o campo): criar um serviço do tipo App com a imagem
  `redis:7-alpine`, o mesmo volume `/data` e esse comando — mudança maior, pedir
  ajuda antes. Até lá, o `config set appendonly yes` do passo 2 já protege, mas
  **se perde quando o Redis reinicia** (repetir o passo 2 depois de cada reinício).

### ⚠️ Aplicar SEM perder a fila (testado em 13/10)
Trocar o comando direto faz o Redis subir VAZIO (ele passa a ler só o arquivo novo,
que ainda não existe). A ordem certa:
1. Ver quanto o Redis usa hoje (para o maxmemory ficar folgado, 3× o uso):
   `docker exec -it $(docker ps --format '{{.Names}}' | grep '^sistema_cevico_redis' | head -1) redis-cli -a 'SENHA' info memory | grep used_memory_human`
   Se passar de ~150 MB, usar `REDIS_MAXMEMORY` maior no ambiente do Redis.
2. Ligar o AOF com o Redis NO AR (ele cria o arquivo novo com tudo o que já tem):
   `… redis-cli -a 'SENHA' config set appendonly yes`
3. Esperar `aof_rewrite_in_progress:0`: `… redis-cli -a 'SENHA' info persistence | grep aof_`
4. Só então trocar o comando do Redis no EasyPanel (o mesmo do compose) e implantar.
5. Conferir: `… redis-cli -a 'SENHA' config get appendonly` → `yes`.
Reversão: voltar o comando antigo (com o AOF já criado, nada se perde).

---

## 3. Migrations com tempo de sobra + índice inválido

### Por quê
O sistema tem limite de 14 s por comando no banco. Migration que cria índice em
tabela grande pode passar disso; o banco cancela e o índice fica **inválido** em
silêncio (o banco não usa, a tela fica lenta, nenhum erro aparece).

### Como rodar migration agora (fluxo "Implantar WEB+SIDEKIQ" com migration)
1. BACKUP antes (seção 1, ou o comando de backup manual de sempre).
2. Implantar a imagem nova no WEB.
3. No terminal do serviço web do EasyPanel: `sh docker/entrypoints/migrate.sh`
   (limite de 600 s só para a migration; no fim já roda `cevico:db_check STRICT=1`:
   se sobrar índice inválido, o comando termina com ERRO e mostra o nome — consertar
   com o passo abaixo antes de seguir).
   - Se o comando do web no EasyPanel for `… db:chatwoot_prepare && … rails s …`,
     trocar por `sh docker/entrypoints/migrate.sh bundle exec rails s -p 3000 -b 0.0.0.0`
     (migra com 600 s e sobe o servidor com os 14 s normais). Nesse modo, índice
     inválido NÃO impede o servidor de subir: aparece um aviso grande com `####`
     no log do web — olhar o log depois de cada implantação com migration.
4. Implantar o SIDEKIQ.

Enquanto a migration roda, o teste de saúde do contêiner responde "saudável" (nunca
reinicia no meio dela).

### Conferir/consertar índice inválido
- Ver: `bundle exec rake cevico:db_check` (ou direto no banco:
  `SELECT c.relname FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid WHERE NOT i.indisvalid;`).
- Consertar (janela calma, backup antes):
  `bundle exec rake cevico:db_reindex_invalid DRY=1` (só mostra) →
  `bundle exec rake cevico:db_reindex_invalid DRY=0` (recria sem travar a tabela:
  cria a cópia boa primeiro, apaga a inválida, dá o nome antigo à nova).

---

## 4. Filas do Sidekiq (a IA não trava mais o resto)

### Por quê
A IA (Atendente do WhatsApp, do Instagram, leitura de áudio/imagem) pode levar
minutos quando a Anthropic fica lenta. Ela ocupava as 10 linhas da fila `default` e
travava tudo abaixo: mensagens do WhatsApp entrando, lembretes, NPS, jornada.

### O que mudou
- Fila `ai` com os **3 atendentes de IA** (ResponderAgentJob, InstagramAgentJob,
  MediaReadingJob), numa **cápsula** própria DENTRO do mesmo Sidekiq
  (config/sidekiq.yml): `SIDEKIQ_AI_CONCURRENCY`, padrão **5**.
- Fila `ai_fundo` com a IA de bastidor das automações do CRM (analisar conversa,
  fechamento, NPS, agendar pela conversa — `CrmAutomationFireJob` só nessas ações):
  outra cápsula, `SIDEKIQ_AI_BG_CONCURRENCY`, padrão **2**. Assim um "mover 200
  cards" com análise de IA não faz o paciente esperar na fila `ai`.
- **Não precisa criar 2º serviço no EasyPanel**: o Sidekiq único de hoje já atende
  as filas `ai` e `ai_fundo` (as cápsulas sobem junto com ele).
- Mensagem do WhatsApp entrando (`Webhooks::WhatsappEventsJob`) saiu da fila `low`
  (fundo) para `medium`.
- Conexões do banco do Sidekiq = 10 + 5 + 2 (config/database.yml soma sozinho).
- O que AINDA chama IA nas 10 linhas normais (fica registrado): o robô de follow-up
  (fila `high`, uma rodada por vez, até 30 s por chamada) e montar/editar página
  (fila `default`, clique raro do admin; se fosse para `ai_fundo` poderia ficar
  mais de 15 min na fila atrás de um lote de cards e a tela perderia o andamento).

### ⚠️ Decisão do Guilherme: quantas conversas a IA responde ao mesmo tempo
Antes da Rodada 6 a IA podia usar as 10 linhas (até 10 conversas juntas, mas
travando o resto). Agora o teto é `SIDEKIQ_AI_CONCURRENCY` (padrão 5). Cada resposta
segura a linha durante a chamada da IA e as pausas de 3 s entre balões.
- Medir no pico (manhã / resposta de campanha): Sidekiq Web → aba "Ocupados",
  quantos `Crm::ResponderAgentJob` rodam juntos; ou a "latência" da fila `ai`.
- Fila `ai` com espera acima de ~1 min no pico → subir para 6–8
  (`SIDEKIQ_AI_CONCURRENCY` no ambiente do SIDEKIQ e implantar de novo).

### Reversão (voltar a imagem anterior, ex.: `:85ece38`)
A imagem antiga NÃO escuta as filas `ai`/`ai_fundo`: o que estiver nelas ficaria
parado para sempre (paciente sem resposta). Depois de implantar a imagem antiga no
WEB e no SIDEKIQ, rodar no terminal do serviço web (e de novo 5 min depois):
```
bundle exec rails runner 'de = %w[ai ai_fundo]; para = "default"; mv = ->(i) { i.merge("queue" => para, "args" => i["args"].map { |a| a.is_a?(Hash) && a["queue_name"] ? a.merge("queue_name" => para) : a }) }; de.each { |f| Sidekiq::Queue.new(f).each { |j| Sidekiq::Client.push(mv.(j.item)); j.delete } }; [Sidekiq::ScheduledSet.new, Sidekiq::RetrySet.new].each { |s| s.each { |j| next unless de.include?(j.queue); Sidekiq::Client.push(mv.(j.item).merge("at" => j.at.to_f)); j.delete } }'
```
(move o que está esperando, agendado e em nova tentativa para a fila `default`;
testado localmente em 13/10.)

### Opcional (só se um dia precisar)
- 2º serviço Sidekiq só para a IA (mais memória na VPS): **não é necessário** — as
  cápsulas já separam a IA dentro do mesmo processo. Se um dia quiser processo
  separado, pedir o ajuste antes (precisa de um arquivo de filas próprio por
  processo, ex.: um com `critical,high,medium,default,low,scheduled_jobs…` e outro
  só com `ai,ai_fundo`; só copiar o serviço com `-q ai` faria a IA rodar nos dois).

---

## 5. Teste de saúde dos contêineres

A imagem (docker/Dockerfile) e o compose têm `docker/entrypoints/healthcheck.sh`:
- **web** → `/health` na porta 3000 tem que responder. O teste manda o cabeçalho
  `X-Forwarded-Proto: https`: sem ele, com `FORCE_SSL=true` o Rails responderia
  "vá para https" e o teste falharia sempre — o EasyPanel ficaria reiniciando o web
  a cada ~5 min. (Testado: com o cabeçalho, 200; sem, 301.)
- **Sidekiq** → o "batimento" deste processo no Redis tem que ter menos de 90 s
  (o Sidekiq grava a cada ~10 s; travado = para de bater). Se o Redis estiver fora
  do ar o teste NÃO derruba o Sidekiq (reiniciar não conserta e poderia perder
  trabalho em andamento; o Redis tem o próprio teste).
- **migration rodando** → sempre saudável (nunca reinicia no meio dela).

Folgado de propósito: só marca "doente" depois de ~2,5 min seguidos falhando
(5 tentativas de 30 s), com 3 min de tolerância ao subir.
