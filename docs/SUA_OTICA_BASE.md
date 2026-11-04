# Sua Ótica — a base de clientes do SavWin no CRM e a reativação em lotes

Montado em 03/11/2026. Objetivo: trazer os clientes que já compraram na loja (cadastro do SavWin) para o funil
"Pós-venda e relacionamento", já separados por segmento, e chamar cada segmento pelo WhatsApp em lotes pequenos,
com aprovação de cada lote e teste de abordagem (A e B), até achar a mensagem que mais converte.

## 1. Exportar no SavWin (quem faz: a loja)

Grade **Clientes** (ou **Vendas por cliente**) → Ver tudo → **Exportar CSV**, com as colunas:

| Coluna no SavWin | O importador entende como |
|---|---|
| Nome / Cliente | nome |
| Celular / Telefone / WhatsApp | celular (só celular entra; fixo fica no relatório) |
| Data de nascimento / Aniversário | nascimento |
| Data da última compra / Data da venda | última compra |
| Valor / Valor total / Líquido | valor da última compra |
| Lente / Produto / Descrição | tipo de lente (é aqui que o importador vê "multifocal") |
| Vendedor(a) | vendedora |

Pode ser uma linha por cliente ou uma linha por venda: do mesmo celular fica a venda mais recente. Cabeçalho sem
distinção de maiúsculas e acentos; separador `;` ou `,`. Período sugerido: 01/11/2023 até hoje (mais de 3 anos não
entra na campanha, mas pode vir no arquivo). XLSX precisa ser salvo como CSV antes.

## 2. Rodar a importação (quem faz: quem tem o console)

Primeiro um ensaio, que só mostra o relatório:

```
DRY=1 bundle exec rake "cevico:otica:base[1,/app/tmp/clientes.csv]"
```

Depois, de verdade:

```
bundle exec rake "cevico:otica:base[1,/app/tmp/clientes.csv]"
```

(`1` é a conta; na bancada local é `6517`.) Rodar de novo com o mesmo arquivo não duplica nada; com um arquivo
mais novo, atualiza quem mudou de segmento. O relatório diz quantos por segmento, sem celular, sem data, repetidos,
contatos criados ou atualizados e cards criados, movidos ou mantidos.

## 3. O que a importação deixa no CRM

**Contato** (Contatos → cada pessoa), com os atributos personalizados: última compra, valor da última compra, tipo de
lente, vendedora, data de nascimento, origem da base (`savwin`) e segmento da base.

**Etiqueta do segmento** (regras em `campanhas/reativacao-base/PLANO.md` da pasta OTICA):

| Etiqueta | Quem | Coluna no funil "Pós-venda e relacionamento" |
|---|---|---|
| `base_s0` | última compra há menos de 6 meses | Base: compra recente (não recebe campanha) |
| `base_s2` | 6 a 12 meses | 6 meses (segundo óculos) |
| `base_s1` | 12 a 36 meses | 1 ano ou parcelas acabaram (nova oferta) |
| `base_s3` | multifocal há 18 a 36 meses (vale sobre o s1) | Multifocal há mais de 18 meses |
| `base_s4` | aniversário nos próximos 7 dias (etiqueta extra) | mantém a coluna do segmento |
| `base_fora` | mais de 36 meses ou sem data | sem card |

Quem já tem card numa coluna "viva" (Nova oferta em conversa, Comprou de novo, Pedido em produção, Pronto para
retirar) não é mexido. O card nasce direto, sem disparar as automações de "entrou na coluna": quem fala com o cliente
é a Reativação (abaixo) ou a Jornada, sempre com aprovação.

As duas colunas novas ("Base: compra recente" e "Multifocal há mais de 18 meses") entram no funil ao rodar
`rake "cevico:otica:preparar[1]"` (idempotente). Rode o preparar ANTES da primeira importação.

## 4. Chamar a base em lotes (tela Marketing → Reativação)

A tela é a mesma da clínica (itens 379 a 382), com as mensagens da ótica: `config/otica/reativacao_base.yml`, três
públicos em ordem de prioridade (Multifocal → Segundo óculos → Renovar), duas mensagens por público (A e B) para
testar. O que for editado na tela fica por cima do arquivo, com "Restaurar original".

Passo a passo:

1. Criar os modelos na Meta (Gerenciador do WhatsApp → Modelos, categoria Marketing, pt_BR, `{{1}}` = primeiro nome,
   com a linha de opt-out) para cada mensagem que vai ao ar; na caixa GOOGLE do sistema, "Buscar novos templates".
2. Reativação → Plano: fatias = as colunas dos segmentos, com a porcentagem de cada; teto por dia (100 a 300);
   janela de horário; dias úteis; **"Eu aprovo cada lote"** ligado; **modo de teste** com o celular do Guilherme
   ligado na primeira rodada. Salvar → Ativar.
3. "Ver o próximo lote": a lista nome a nome, coluna, modelo e caixa. Aprovar. Conferir no celular de teste.
4. Desligar o modo de teste e aprovar o primeiro lote de verdade (sugestão: 100 pessoas do público Multifocal,
   metade com a mensagem A e metade com a B).
5. Em 3 a 5 dias, comparar respostas e visitas marcadas por mensagem (Resultados da campanha) e seguir com a que
   converteu mais. Quem respondeu cai com a Val no WhatsApp; o agente reconhece o segmento pela primeira mensagem
   da loja (roteiro, recepção 1c). "SAIR" vira etiqueta `nao_perturbe` e a pessoa não recebe mais nada.

Aniversariantes (`base_s4`) ficam fora deste plano: a etiqueta é refeita a cada importação e serve para uma campanha
semanal própria.

## 5. Arquivos

- `app/services/otica/base_import.rb` (importador) · `lib/tasks/cevico_otica.rake` (`cevico:otica:base`)
- `config/otica/preparo.yml` (colunas novas do funil 2) · `config/otica/reativacao_base.yml` (públicos e mensagens)
- `app/services/cevico/reactivation_messages.rb` escolhe o arquivo pelo ramo da empresa (`Cevico::Company#segment`)
- `spec/services/otica/base_import_spec.rb` com a amostra sintética `spec/fixtures/otica/savwin_clientes_amostra.csv`
