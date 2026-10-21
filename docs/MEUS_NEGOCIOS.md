# Meus negócios — o lançador do dono (21/10/2026)

Uma tela só do dono com os ícones das empresas dele (CEVICO, LIFE, Sua Ótica…).
Clicar = entrar no sistema daquela empresa já logado, numa aba nova.
Cada sistema segue na sua VPS, com seu banco: esta instalação só guarda o
endereço e um token que **gera o login**. Nenhum dado de negócio passa por aqui.

## Como funciona

1. A tela pede ao servidor o link de entrada do negócio escolhido.
2. O servidor chama a **API de plataforma** do sistema de destino
   (`GET /platform/api/v1/users/:id/login`) com o token daquele sistema.
3. O destino devolve um link de uso único (`/app/login?email=…&sso_auth_token=…`),
   válido por 5 minutos. Acrescentamos `sso_account_id` para cair na conta certa.
4. O navegador abre o link: logado, direto no Meu Painel da empresa.

Quem vê a tela: **administrador** da conta **e** e-mail listado em
`MEUS_NEGOCIOS_DONOS`. Para todo o resto o item nem aparece no menu.

## Configurar (duas pontas)

### 1. No sistema de DESTINO (ex.: CEVICO) — autorizar a entrada

No console do serviço web (EasyPanel → `>_`):

```bash
bundle exec rake "cevico:negocios:autorizar[atendimento@guilhermecorder.com.br]"
```

Imprime o `user_id`, as contas (id=nome) e o **token** do app de plataforma
"Meus negócios (lançador)". Guarde o token: ele entra no ambiente do sistema
que terá o botão. Revogar = apagar o app em `/super_admin/platform_apps`.

CEVICO e Sua Ótica são a **mesma instalação** com contas diferentes: um token
só, e cada cartão aponta para a sua `account_id`.

### 2. No sistema que TEM o botão (o Sistema Unificado da Life) — variáveis de ambiente

```
MEUS_NEGOCIOS_DONOS=atendimento@guilhermecorder.com.br
MEUS_NEGOCIOS=[{"chave":"life","nome":"LIFE Energia Solar","descricao":"energia solar · Piracicaba","logo":"/brand-assets/life/logo_thumbnail.png","cor":"#D2990B","local":true,"account_id":1},{"chave":"cevico","nome":"CEVICO","descricao":"clínica · São Paulo","logo":"https://SISTEMA-DA-CEVICO/brand-assets/logo_thumbnail.png","cor":"#152C61","url":"https://SISTEMA-DA-CEVICO","user_id":USER_ID,"account_id":1,"token":"TOKEN"},{"chave":"sua-otica","nome":"Sua Ótica","descricao":"óticas · São Paulo","cor":"#0A84FF","url":"https://SISTEMA-DA-CEVICO","user_id":USER_ID,"account_id":CONTA_DA_OTICA,"token":"TOKEN"}]
```

- JSON em **uma linha só**. `local: true` = este mesmo sistema (abre sem SSO).
- `logo` pode ser caminho local (`/brand-assets/…`) ou URL completa; sem logo
  o cartão mostra a inicial do nome.
- Depois de salvar, **Implantar** o serviço web (o sidekiq não precisa).
- Conferir sem expor tokens: `bundle exec rake cevico:negocios:conferir`.

## Segurança

- O token de plataforma permite gerar login do usuário autorizado naquele
  sistema. Ele vive **só no ambiente** da VPS que tem o botão, nunca no
  navegador nem no código. Só o usuário autorizado pelo rake pode ser logado.
- A tela e o login exigem admin + e-mail de dono; a lista enviada ao navegador
  nunca inclui token nem `user_id`.
- Link de entrada expira em 5 minutos e morre no primeiro uso.
- Sempre HTTPS entre os sistemas (`FORCE_SSL=true` nos dois).

## Arquivos

- `app/services/cevico/negocios.rb` — lê o ambiente, gera o link
- `app/controllers/api/v1/accounts/crm/negocios_controller.rb` — `GET crm/negocios`, `POST crm/negocios/:chave/login`
- `lib/tasks/cevico_negocios.rake` — `cevico:negocios:autorizar`, `cevico:negocios:conferir`
- `app/javascript/dashboard/routes/dashboard/negocios/` — tela `/app/accounts/:id/negocios`
- Menu lateral: item "Meus negócios" (só dono), logo abaixo do Painel do empresário
- `spec/controllers/api/v1/accounts/crm/negocios_spec.rb`
