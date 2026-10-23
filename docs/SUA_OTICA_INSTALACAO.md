# Sua Ótica — instalação numa VPS própria

O sistema da ótica é a MESMA imagem da CEVICO e da LIFE. O que muda é o ambiente e uma tarefa de preparo.

## Marca
`MARCA=otica` no ambiente do web e do sidekiq veste a instalação com `config/brands/otica.yml`
(nome "Sistema Sua Ótica", logos em `public/brand-assets/otica/`, favicons com os óculos).
Sem `MARCA`, nada muda (CEVICO).

## Preparo da conta
```
bundle exec rake "cevico:otica:preparar[<id da conta>]"
CONTEUDO=/caminho/otica-conteudo.json bundle exec rake "cevico:otica:preparar[<id da conta>]"
DRY=1 bundle exec rake "cevico:otica:preparar[<id da conta>]"
```
Monta, achando tudo POR NOME (rodar de novo não duplica): ramo ótica na Identidade da empresa, funis
"Aquisição" e "Pós-venda e relacionamento" com as colunas, a Agenda ligada às colunas, os 3 atendentes (novos
nascem em modo sombra; existentes mantêm o modo), a etiqueta `parcelas_10x` e a Jornada do pós-venda
(novas nascem com aprovação manual; existentes mantêm o que o dono escolheu). A estrutura está em
`config/otica/preparo.yml`.

## Conteúdo (fora do git)
O roteiro dos atendentes e os textos da Jornada são texto de negócio e **não entram no repositório**
(ele é público). Eles saem de uma conta já pronta e entram na nova pelo arquivo:
```
bundle exec rake "cevico:otica:exportar[<id da conta pronta>]"   # grava tmp/otica-conteudo.json
```
Sem o arquivo, o preparo usa textos neutros na Jornada e mantém o roteiro padrão.

A receita passo a passo do EasyPanel fica com os sócios (fora do repositório).
