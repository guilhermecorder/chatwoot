# Sistema Unificado — a instalação da Life (HUB) com tudo dentro (21/10/2026)

**O que é:** a instalação que roda na VPS `sistema_life` (EasyPanel `jpx4ik`,
endereço sistema-life-web.jpx4ik.easypanel.host) é o **Sistema Unificado,
personalizado para a Life**: marca `hub` (`MARCA=hub`), dois mundos —
**Saúde** (treino, cardio, boxe, corpo, dieta, análises, rotina, educação) e
**Negócios** (o sistema completo: CRM, conversas, agenda, páginas, Meta,
agentes, financeiro…) — e, dentro de Negócios, o lançador **Meus negócios**
(CEVICO · LIFE · Sua Ótica por SSO, ver docs/MEUS_NEGOCIOS.md).

Não chamar de CEVICO: a CEVICO é uma das empresas que ele acessa a partir daqui.

## As linhas de código (e a regra de ouro)

- `develop` / `feat/rodada-172` — a linha de produção do sistema (a CEVICO
  roda daí). Toda rodada do sistema nasce aqui.
- `feat/hub-saude` — a linha do Sistema Unificado: **tudo da linha de
  produção + o mundo Saúde + a marca hub**. Em 21/10 recebeu a linha de
  produção inteira por merge (57b83e2, itens até 357).

**Regra:** a imagem da VPS da Life nasce SEMPRE da `feat/hub-saude`.
Uma imagem da `develop` colocada lá apaga o mundo Saúde da tela (o banco
fica intacto, mas o HUB some) — aconteceu em 21/10 e foi revertido com a
imagem `74b4d8b`. Para trazer novidades da produção: `git merge develop`
na `feat/hub-saude`, resolver, testar local, buildar.

## Como atualizar a VPS da Life

1. **Backup** do banco (console `>_` do postgres: `pg_dump -U postgres chatwoot | gzip > /var/lib/postgresql/data/antes.sql.gz`, ou `~/backup_life.sh`).
2. Serviço **web** → Imagem: a etiqueta nova (formato `ghcr.io/guilhermecorder/chatwoot:<7 chars>`, buildada da `feat/hub-saude`).
3. Se a entrega disser que **tem migration**: comando do web, só nesta subida,
   `sh docker/entrypoints/migrate.sh bundle exec rails s -p 3000 -b 0.0.0.0`
   (limite de 600 s por comando + conferência de índices). Implantar, esperar
   o log mostrar as migrations e o servidor de pé.
4. Serviço **sidekiq** → mesma imagem → Implantar.
5. Devolver o comando do web para `bundle exec rails s -p 3000 -b 0.0.0.0` e Implantar.
6. Conferir: tela abre com a marca hub, `/hub` mostra os dois mundos, Saúde
   abre o treino, Negócios abre o Meu Painel; console: `bundle exec rails cevico:db_check STRICT=1`.

Reversão = colar a imagem anterior nos dois serviços (as migrations não
precisam ser desfeitas).

## O que mudou no merge de 21/10 (para quem for mexer)

- Acessos: a árvore (`config/cevico/access_catalog.yml`) ganhou o nó
  **`saude`**; a capability antiga `health` aponta para ele. Os módulos da
  Saúde por pessoa (`agent_permissions.health_modules`) continuam.
- A tela "Personalização" (camada de segmento, fase B) saiu do menu: a
  **Identidade da empresa** (Configurações → Empresa) faz o papel. A camada de
  segmento continua existindo para o mundo Saúde (`window.SEGMENTO`,
  `config/segmentos/saude.yml`).
- Sidebar: mundo Saúde, `hub_mode`, convidado só-Saúde e os quadradinhos
  coloridos preservados; o convidado só-Saúde agora é "não-admin com o nó
  `saude` liberado".
- Rotas da Saúde vivem em `config/routes/cevico_crm.rb` (junto com as do CRM).
