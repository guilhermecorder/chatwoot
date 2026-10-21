# Cevico::SettingMerge — gravador único do crm_settings (Rodada 4, achado #318)

- Toda gravação em `agenda_config` / `ai_config` passa por `Cevico::SettingMerge.merge!(account_ou_settings, :agenda_config) { |cfg| cfg['x'] = 1; cfg }` — trava a linha, relê fresco, aplica o bloco e grava; devolve o hash gravado (aceita Account ou CrmSetting e cria a linha se faltar).
- Para mexer numa chave só: `Cevico::SettingMerge.merge_key!(settings, :ai_config, 'radar') { |h| h.merge('last_run' => t) }` — as chaves irmãs ficam intactas; devolve o valor gravado na chave.
- `spec/services/cevico/setting_merge_lint_spec.rb` falha para quem gravar direto (`update!(agenda_config:`, `update_column(:ai_config`, `x.agenda_config = …`, `x[:ai_config] = …`); a allow-list dele só encolhe (arquivo convertido = tirar da lista) e fica vazia no fim da rodada.

## Ao converter um ponto antigo (G1–G3)

1. Termine o bloco SEMPRE com `cfg` (o hash completo). O helper se protege: se o bloco mexeu na cópia (`cfg['x'] = {…}`, `cfg.delete('y')`), grava a cópia inteira, nunca o pedaço devolvido na última linha; se não mexeu e devolveu um hash novo (`cfg.merge(…)`), grava o devolvido. Não misture os dois estilos no mesmo bloco (`cfg['x'] = 1; cfg.merge(…)` perde o merge).
2. Nos controllers, passe o CrmSetting que você já tem na mão (`crm_settings`), não `Current.account`: o helper atualiza esse objeto com a foto gravada, e a resposta montada logo depois (`settings_json(crm_settings)`) sai certa. Com Account ele não tem como achar o objeto do controller.
3. Enquanto a allow-list do lint não zerar, uma escrita antiga (ainda na lista) continua podendo apagar o que o `merge!` gravou — o buraco do #318 só fecha de verdade no fim da rodada, com a lista vazia.
4. Decisão registrada (G0, 13/10): entre "levantar erro quando o bloco não devolve o hash completo" e "o helper decide sozinho pela cópia", ficou o lado que nunca derruba um job em produção e nunca encolhe a coluna (o de cima). `column_presets` é lista (`[]`): `merge!` aceita, `merge_key!` recusa.
