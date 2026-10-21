# Atualizar o sistema LIFE para a imagem atual (outubro/2026)

A VPS da LIFE (EasyPanel `jpx4ik`, projeto `sistema_life`) roda a imagem de
julho (`3a917b6`). Entre ela e a ponta de hoje há **51 migrations** e tudo que
nasceu depois: Identidade da empresa (Company), Acessos em árvore, Meta por
conta, Páginas com ficha e A/B, Agente de Campanhas, Meus negócios.
A marca continua vindo do ambiente (`MARCA=life`) — nada muda nisso.

## Antes (obrigatório)

1. **Backup.** No Terminal do painel Hostinger da VPS da LIFE:
   `bash ~/backup_life.sh` (se ainda não instalou, use o console `>_` do serviço
   `postgres` no EasyPanel: `pg_dump -U postgres chatwoot | gzip > /var/lib/postgresql/data/antes-atualizacao.sql.gz`).
2. Anote a imagem que está no ar hoje (campo Imagem do serviço web) — é a reversão.

## Passos no EasyPanel (web e sidekiq)

1. Serviço **web** → aba Fonte → Imagem: cole a imagem nova (está na mensagem
   da entrega, no formato `ghcr.io/guilhermecorder/chatwoot:<etiqueta>`).
2. Serviço **web** → Ambiente: acrescente, se quiser o lançador já nesta subida:
   ```
   MEUS_NEGOCIOS_DONOS=atendimento@guilhermecorder.com.br
   MEUS_NEGOCIOS=[...]   ← ver docs/MEUS_NEGOCIOS.md
   ```
3. Serviço **web** → Comando (só para ESTA subida, porque tem migrations):
   ```
   sh docker/entrypoints/migrate.sh bundle exec rails s -p 3000 -b 0.0.0.0
   ```
   Implantar. Nos logs vai aparecer `[CEVICO] migrations com limite de 600s`
   e, no fim, o servidor subindo. Pode levar alguns minutos.
4. Serviço **sidekiq** → mesma imagem nova → Implantar.
5. Quando o web estiver verde e a tela abrir, volte o comando do web para
   `bundle exec rails s -p 3000 -b 0.0.0.0` e Implantar de novo (para a próxima
   reinicialização não rodar migrations à toa).

## Conferir

- Login, Meu Painel abre, marca LIFE na tela.
- Console `>_` do web: `bundle exec rails cevico:db_check STRICT=1` (sem índice inválido).
- Configurações → Identidade da empresa: ramo = "outro" (empresa), vocabulário de energia solar.
- Se configurou o lançador: item "Meus negócios" aparece no menu só para o dono.

## Reverter

Colar a imagem anterior no web e no sidekiq e Implantar. As migrations não
precisam ser desfeitas para a imagem antiga subir.
