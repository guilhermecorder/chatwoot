# Gerador de PDF da LIFE (serviço)

Cópia do gerador aprovado que fica em `~/Desktop/CLAUDE CODE/LIFE/orcamento/proposta` (lá é onde se mexe no modelo).
Depois de mudar o modelo lá, traga para cá com:

```bash
rsync -a --delete --exclude saida --exclude .DS_Store --exclude __pycache__ --exclude montar.py --exclude exemplo.json --exclude README.md --exclude modelo/preparar_imagens.py --exclude Dockerfile --exclude LEIA.md "$HOME/Desktop/CLAUDE CODE/LIFE/orcamento/proposta/" docker/life-proposta/
```

A imagem é construída pelo fluxo "Gerador de PDF da LIFE" do GitHub (`.github/workflows/life-proposta-pdf.yml`) e roda
como um serviço ao lado do sistema (porta 3041, sem domínio público). O sistema acha o serviço pelo endereço gravado em
`crm_settings.ai_config['kit_quote']['config']['gerador_pdf']` (`url` e `token`).
