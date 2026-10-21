require 'rails_helper'

# 🔒 Rodada 4 da auditoria (#66/#174/#229): só o Cevico::AttributeMerge grava
# additional_attributes. Este "lint" varre app/, lib/ e enterprise/ e falha
# listando quem ainda grava direto: `update!(additional_attributes:`,
# `update(…)`, `update_column(s)`, `assign_attributes`, `update_attribute` com a
# coluna, `x.additional_attributes = (…).(deep_)merge(…)` (foto velha + save!)
# e `changes[:additional_attributes] = …` (hash montado e gravado depois com
# update_columns — foi assim que o sync do Oftalmofácil escapou da 1ª versão).
# A ALLOW-LIST é o que ainda não foi convertido; quando um arquivo é convertido,
# tire-o daqui (entrada sem uso também falha, para a lista só encolher).
RSpec.describe 'Cevico::AttributeMerge — gravador único de additional_attributes' do # rubocop:disable RSpec/DescribeClass
  let(:helper) { 'app/services/cevico/attribute_merge.rb' }
  # NÃO dá para pegar por grep "mutação em memória + save!"
  # (`m.additional_attributes['x'] = 1; m.save!`): isso é regra de REVISÃO.
  let(:pattern) do
    # (?:[^()]|\([^()]*\))*? deixa passar um nível de parênteses antes da coluna
    # (ex.: `update!(name: f(1), additional_attributes: …)`)
    /\.(?:update!?|update_columns?|update_all|assign_attributes|update_attribute)\(
       \s*(?:[^()]|\([^()]*\))*?['":]?additional_attributes['"]?\s*(?::|=>|,)|
     \badditional_attributes\s*=(?!=)[^\n]*\.(?:deep_)?merge\b|
     \[:?['"]?additional_attributes['"]?\]\s*=(?!=)/mx
  end
  let(:allow_list) do
    %w[
      app/jobs/avatar/avatar_from_url_job.rb
      app/models/concerns/liquidable.rb
      app/services/data_imports/importer.rb
      enterprise/app/services/contacts/company_association_service.rb
      enterprise/app/services/whatsapp/call_permission_reply_service.rb
      enterprise/app/services/whatsapp/call_permission_request_service.rb
      enterprise/app/services/whatsapp/call_service.rb
      enterprise/app/services/whatsapp/incoming_call_service.rb
      lib/integrations/google_translate/detect_language_service.rb
    ]
    # Todos são código do Chatwoot de origem — não mexemos para o merge de versão
    # continuar limpo; se sumirem numa atualização, tire daqui. Código da CEVICO
    # NUNCA entra nesta lista: converta para o merge!.
  end

  def offenders_in(pattern, helper)
    files = %w[app/**/*.rb lib/**/*.{rb,rake} enterprise/**/*.rb].flat_map { |glob| Dir[Rails.root.join(glob)] }
    files.each_with_object({}) do |path, found|
      rel = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if rel == helper

      content = File.read(path)
      lines = content.to_enum(:scan, pattern).map { Regexp.last_match.pre_match.count("\n") + 1 }
      found[rel] = lines if lines.any?
    end
  end

  it 'ninguém grava additional_attributes fora do Cevico::AttributeMerge (fora da allow-list)', :aggregate_failures do
    found = offenders_in(pattern, helper)
    new_offenders = found.keys - allow_list
    stale_entries = allow_list - found.keys

    listing = new_offenders.map { |rel| "#{rel}:#{found[rel].join(',')}" }
    expect(new_offenders).to be_empty,
                             "grava additional_attributes direto — use Cevico::AttributeMerge.merge!(record) { … }:\n  #{listing.join("\n  ")}"
    expect(stale_entries).to be_empty,
                             "já convertidos, tire da allow-list em attribute_merge_lint_spec.rb:\n  #{stale_entries.join("\n  ")}"
  end

  it 'o padrão pega as formas de gravar que a auditoria encontrou' do
    exemplos = [
      "record.update!(\n  additional_attributes: record.additional_attributes.merge('meta_ads' => meta)\n)",
      "conversation.update!(additional_attributes: attrs.merge('k' => 1))",
      'conversation.update!(additional_attributes: attrs)',
      "message.additional_attributes = (message.additional_attributes || {}).merge('cevico_wa_billing' => billing)",
      'self.additional_attributes = additional_attributes.merge(x: 1)',
      'avatarable.update_columns(additional_attributes: additional_attributes)',
      "changes[:additional_attributes] = current.merge('parceiro' => 'X')",
      'updates[\'additional_attributes\'] = attrs',
      "conversation.additional_attributes = attrs.deep_merge('k' => 1)",
      'contact.update!(name: nome.strip.first(80), additional_attributes: attrs)'
    ]
    expect(exemplos).to all(match(pattern))

    inocentes = [
      "Cevico::AttributeMerge.merge!(record) { |attrs| attrs.merge('x' => 1) }",
      "attrs = (conversation.additional_attributes || {}).merge('k' => 1)",
      "record.additional_attributes&.[]('meta_ads')",
      "conversation.additional_attributes == {}.merge('x' => 1)",
      'changes[:additional_attributes] == {}',
      "message.additional_attributes['cevico_wa_billing']"
    ]
    expect(inocentes.grep(pattern)).to be_empty
  end
end
