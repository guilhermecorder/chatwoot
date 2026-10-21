# WhatsApp oficial da LIFE — ligar o número ao sistema (21/10/2026)

## O que já existe na Meta (lido no Gerenciador de Negócios em 21/10)

- Portfólio **BM - SC LIFE** (id 518112780139697), razão social SC Consultoria e
  Representação, CNPJ 20.217.098/0001-40 — **empresa VERIFICADA** em 5/jun/2026.
- Conta do WhatsApp (WABA) **Life Energia Solar**, id **1281480050636687** —
  status **Aprovada**.
- Número **+55 19 99129-2906** — **já conectado à API de Nuvem**, qualidade Alta.
- Pendência: o nome de exibição "Life Atendimento ao Cliente" foi **rejeitado**
  (diretrizes de nome). Enviar outro: "Life Energia Solar".
- **Falta um app**: o portfólio não tem nenhum aplicativo. Sem app não há token
  nem webhook — é só isso que separa o número do sistema.
- Não há forma de pagamento. Para responder quem chama (conversa iniciada pelo
  cliente) não é preciso; só para mensagens que a empresa inicia (modelos).

## Passo a passo (no Chrome do Guilherme, logado)

### 1. Nome de exibição
WhatsApp Manager → Telefones → ⚙ do número → Nome de exibição → "Life Energia Solar" → enviar.

### 2. Criar o app
developers.facebook.com → Meus apps → Criar app → tipo **Empresa** → nome
"Sistema LIFE" → portfólio **BM - SC LIFE** → criar.
Dentro do app: Adicionar produto → **WhatsApp** → Configurar → escolher a WABA
"Life Energia Solar" (não a de teste).

### 3. Token permanente (usuário do sistema)
Gerenciador de Negócios → Configurações → Usuários → **Usuários do sistema** →
Adicionar → nome "sistema-life", função Administrador.
→ Adicionar ativos: o app "Sistema LIFE" (controle total) e a conta do WhatsApp
"Life Energia Solar" (controle total).
→ Gerar token: app "Sistema LIFE", validade **nunca expira**, permissões
`whatsapp_business_messaging` e `whatsapp_business_management`. Copiar o token
(só aparece uma vez).

### 4. Anotar os ids
App → WhatsApp → Configuração da API: **Phone number ID** e **WhatsApp Business
Account ID** (= 1281480050636687).

### 5. No sistema LIFE
Configurações → Caixas de entrada → Nova → **WhatsApp** → provedor
**WhatsApp Cloud**: nome "LIFE WhatsApp", número +5519991292906, Phone number
ID, Business Account ID, API key = o token. Criar e anotar o endereço do
webhook que a tela mostra (`https://<sistema-life>/webhooks/whatsapp/+5519991292906`).

### 6. Webhook no app
App → WhatsApp → Configuração → Webhook → Editar: URL de callback = o endereço
acima; Verificar token = o mesmo token do webhook mostrado na caixa de entrada.
Verificar e salvar → Gerenciar → assinar **messages**.

### 7. Testar
Mandar "oi" para o número de outro celular: a conversa tem de nascer na caixa
"LIFE WhatsApp". Responder pelo sistema e ver chegar no celular.

## Depois
- O número sai do aplicativo WhatsApp Business do celular: avisar o Fernando.
- Para a empresa iniciar conversa (lembretes, campanhas) cadastrar forma de
  pagamento no portfólio e criar modelos de mensagem.
- Sua Ótica: o portfólio **suaoticabrasil** (id 1986634811820771) está com a
  verificação da empresa **rejeitada**, sem telefone e endereço — reenviar os
  documentos antes de qualquer API oficial lá.
