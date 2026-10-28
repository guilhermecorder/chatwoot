# Personalização por conta (28/10/2026)

O que a conta pode trocar POR DENTRO do sistema, sem código e sem IA, em
**Configurações → Personalização** (só administradores). Nasceu em cima da
"Identidade da empresa" (rodada 334) e da Personalização do coringa (05/08).

## As três camadas (de baixo para cima)

| Camada | Onde mora | Quem muda | O que cobre |
|---|---|---|---|
| Marca | `MARCA=` na VPS + `config/brands/*.yml` + `public/brand-assets/` | deploy | nome do sistema, logos/favicon da instalação, cores da tela de login |
| Segmento | `config/segmentos/{clinica,empresa,saude}.yml` | build | termos, ~44 frases, profissionais/unidades/janelas padrão, listas, metas, prompts |
| **Conta** | `crm_settings.agenda_config['company']` + `['segment']` + anexos no `crm_settings` | **admin, na tela** | tudo abaixo |

Ordem de resolução em todo lugar: **conta > segmento > clínica**. Conta sem
nada salvo = CEVICO de hoje, byte a byte.

## Blocos da tela

1. **Quem somos** — nome, ramo (clínica / ótica / outro), cidade, slogan,
   sobre, o que oferece, tom de voz (vai para os robôs de IA).
2. **Identidade visual** — upload de ícone (barra lateral + aba), imagem do
   cabeçalho (no lugar do olho CEVICO), logo claro e escuro; nome do sistema;
   paleta padrão (antes da cor do dia); marca d'água liga/desliga.
   Imagens = `has_one_attached :brand_{icon,hero,logo,logo_dark}` no
   `CrmSetting` (entram no backup como todo o storage).
3. **Palavras** — as 11 palavras (paciente, consulta, médico, cirurgia,
   empresa, unidade + plurais) + **Dicionário global**: troca as palavras da
   clínica em TODAS as telas (inclusive as que ainda escrevem o texto à mão).
   Automático = ligado fora da clínica. Nunca toca em conversas, mensagens,
   campos de texto, `[data-sem-dicionario]`. Motor: `helper/dicionarioGlobal.js`
   (nós de texto + title/placeholder/aria-label, MutationObserver, idempotente).
4. **Frases das telas** — frases inteiras (gênero/concordância), com busca:
   as ~44 do segmento + as que cada tela adaptada registra em
   `helper/frases/<tela>.js` (`frase('inicio.x', 'Texto de hoje')`).
5. **Nomes dos ambientes** — item do menu e título da tela, por ambiente
   (`helper/ambientesCatalogo.js`; Sidebar usa `nomeAmbiente(chave, padrão)`,
   CevicoHero renomeia pelo nome da rota).
6. **Unidades** — lojas/filiais (chave gravada no banco: renomear rótulo é
   livre, renomear chave quebra histórico).
7. **Equipe, listas e meta** — profissionais, agendas paralelas, motivos,
   opções de indicação/venda, meta do mês, contexto do negócio (tela do
   coringa embutida; salva com o próprio botão).
8. **Assistente virtual**, 9. **Módulos** (Cirurgias, Médicos, Oftalmofácil,
   Notas clínicas, Pós-operatório), 10. **Site público** — como antes.

## Resolvedores (frontend) — `helper/segmento.js`

- `termo('cliente')` / `termoCap('profissional')` — palavra (conta > segmento > clínica)
- `frase('chave', 'Texto de hoje')` — frase inteira
- `nomeAmbiente('Agenda', 'Agenda')` — nome do ambiente
- `imagemEmpresa('hero', '/brand-assets/cevico-eye.svg')`, `visualEmpresa()`, `marcaDaguaLigada()`
- `EMPRESA.atual` — a empresa da conta (reativo; o store do CRM chama `definirEmpresa` quando as settings chegam)
- `nomeSistemaHero()` — nome do sistema na saudação

Servidor — `Cevico::Company`: `phrase`, `label`, `dictionary_enabled?`,
`dictionary_pairs`, `visual`, `images`, `save!` e `save_image!`;
endpoint `POST crm/settings/update_company_image` (multipart kind + file | remove).

## Como vestir a Life (por dentro, em 5 minutos)

1. Quem somos: nome "LIFE Energia Solar", ramo **Outro ramo**.
2. Palavras: paciente → cliente(s), consulta → vistoria(s), médico →
   consultor(es), cirurgia → instalação(ões), empresa → empresa, unidade →
   unidade. Dicionário global: Automático (fica ligado).
3. Identidade visual: ícone e imagem do cabeçalho da Life; paleta; nome do
   sistema "Sistema LIFE".
4. Nomes dos ambientes: Agenda → "Vistorias", Espaço do Paciente → "Espaço do
   Cliente", Dashboard dos Médicos → "Dashboard dos Consultores".
5. Equipe: os consultores da Life; unidades: a loja; meta do mês.
6. Módulos: todos de clínica desligados (já vem assim fora da clínica).

## O que ainda é estrutura de clínica (fase seguinte)

- Ficha rápida do Espaço do Cliente (OD/OE, refração, acuidade, PIO).
- Etapas fixas do funil (Consulta → Indicação → Cirurgia) dentro dos KPIs e dos robôs.
- Páginas públicas da CEVICO (`cevico_pages`, formulários públicos).
- Copywriter / Construtor de Páginas / Editor com prompt CEVICO.
