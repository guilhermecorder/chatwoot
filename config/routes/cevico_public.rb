# 🔧 ROTAS PÚBLICAS CEVICO (rodada 171 — facilitar as atualizações do Chatwoot)
# Chamado por `draw(:cevico_public)` no config/routes.rb (logo depois das
# rotas do painel): formulários e páginas públicas (sem login) e os webhooks
# do CEVICO (CSP e assistente de voz). A raiz do domínio oficial e o
# catch-all /:slug ficam no routes.rb porque a ORDEM deles importa.
# Formulário público CEVICO (paciente responde pelo link do WhatsApp, sem login)
# LINK LIMPO (sem token): o paciente se identifica com nome + WhatsApp no
# próprio formulário e o sistema atrela a resposta ao card pelo telefone.
# O 'track' literal precisa vir ANTES da rota com :token (senão o Rails
# entenderia "track" como um token).
post 'forms/:slug/track', to: 'cevico_forms#track'
get 'forms/:slug', to: 'cevico_forms#show', as: :cevico_form_short
post 'forms/:slug', to: 'cevico_forms#submit'
# link assinado antigo (compatibilidade: mensagens já enviadas continuam valendo)
get 'forms/:slug/:token', to: 'cevico_forms#show', as: :cevico_form
post 'forms/:slug/:token', to: 'cevico_forms#submit'
post 'forms/:slug/:token/track', to: 'cevico_forms#track'
# Páginas públicas CEVICO (nutrição/procedimentos — preparadas p/ SEO)
# /cta e /next = redirecionadores que CONTAM o clique (funil + conversão)
get 'p/:slug/cta', to: 'cevico_pages#cta_click', as: :cevico_page_cta
get 'p/:slug/next', to: 'cevico_pages#next_step', as: :cevico_page_next
post 'p/:slug/track', to: 'cevico_pages#track', as: :cevico_page_track
post 'p/:slug/ref', to: 'cevico_pages#mint_ref', as: :cevico_page_ref
# Protocolo do HUB (porta de entrada na raiz do domínio dedicado)
post 'hub/ref', to: 'cevico_pages#hub_ref', as: :cevico_hub_ref
# prévia do RASCUNHO (link secreto do admin — token assinado) +
# ambiente de montagem: status da construção e retoque inline
get 'p/rascunho/:token/status', to: 'cevico_pages#build_status'
post 'p/rascunho/:token/retocar', to: 'cevico_pages#inline_update'
post 'p/rascunho/:token/construtor', to: 'cevico_pages#builder_chat'
post 'p/rascunho/:token/foto', to: 'cevico_pages#builder_upload'
get 'p/rascunho/:token', to: 'cevico_pages#preview', as: :cevico_page_preview
get 'p/:slug', to: 'cevico_pages#show', as: :cevico_page

# 🔐 CEVICO rodada 171: relatórios de CSP das páginas públicas (só log)
post 'webhooks/cevico/csp_report', to: 'webhooks/cevico_csp_reports#create'

# 🤖📞 CEVICO item 169: agente de ligação (ElevenLabs) — ferramentas chamadas
# durante a ligação (token da conta), início da conversa e pós-chamada (HMAC)
post 'webhooks/cevico/voice/:account_id/tools/:tool', to: 'webhooks/cevico_voice#tool'
post 'webhooks/cevico/voice/:account_id/initiation', to: 'webhooks/cevico_voice#initiation'
post 'webhooks/cevico/voice/:account_id/post_call', to: 'webhooks/cevico_voice#post_call'
