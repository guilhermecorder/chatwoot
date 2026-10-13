require 'rails_helper'

# 🔒 Rodada 4 da auditoria (achado #318): só o Cevico::SettingMerge grava
# agenda_config / ai_config do crm_settings. Este "lint" varre app/ e lib/ e
# falha listando quem ainda grava direto (update!/update/update_column(s)/
# update_all/atribuição + save). A ALLOW-LIST abaixo é o que os grupos G1–G3
# ainda vão converter nesta rodada; quando um arquivo é convertido, tire-o
# daqui (entrada sem uso também falha, para a lista só encolher). No fim da
# rodada ela fica vazia.
RSpec.describe 'Cevico::SettingMerge — gravador único do crm_settings' do # rubocop:disable RSpec/DescribeClass
  let(:helper) { 'app/services/cevico/setting_merge.rb' }
  # Pega: `.update!(agenda_config:`, `.update!('agenda_config' =>`, a coluna em
  # qualquer posição dentro do parêntese (`.update!(n8n_api_key: x, ai_config: cfg)`),
  # `.assign_attributes(ai_config:`, `.update_column(:agenda_config, x)`,
  # `.update_attribute(:ai_config, x)`, `s.agenda_config = …`, `s[:agenda_config] = …`
  # e `s['ai_config'] = …`.
  # NÃO dá para pegar por grep "mutação em memória + save!" (`s.agenda_config['x'] = 1; s.save!`):
  # isso é regra de REVISÃO — quem revisa o grupo confere à mão.
  let(:pattern) do
    /\.(?:update!?|update_columns?|update_all|assign_attributes|update_attribute)\([^)]*?['":]?(?:agenda_config|ai_config)['"]?\s*(?::|=>|,)|
     \.(?:agenda_config|ai_config)\s*=[^=~>]|
     \[['":]?(?:agenda_config|ai_config)['"]?\]\s*=[^=]/mx
  end
  let(:allow_list) do
    %w[
      app/controllers/api/v1/accounts/crm/radar_controller.rb
      app/jobs/crm/appointment_reminder_send_job.rb
      app/jobs/crm/external_surgery_job.rb
      app/jobs/crm/external_surgery_undo_job.rb
      app/jobs/crm/responder_agent_job.rb
      app/jobs/crm/responder_rescue_job.rb
      app/services/crm/auto_manager_service.rb
      app/services/crm/birthdays.rb
      app/services/crm/conversation_auditor_service.rb
      app/services/crm/creative_service.rb
      app/services/crm/harvest_service.rb
      app/services/crm/voice_agent/settings.rb
    ]
  end

  def offenders_in(pattern, helper)
    files = Dir[Rails.root.join('app/**/*.rb')] + Dir[Rails.root.join('lib/**/*.{rb,rake}')]
    files.each_with_object({}) do |path, found|
      rel = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if rel == helper

      content = File.read(path)
      lines = content.to_enum(:scan, pattern).map { Regexp.last_match.pre_match.count("\n") + 1 }
      found[rel] = lines if lines.any?
    end
  end

  it 'ninguém grava agenda_config/ai_config fora do Cevico::SettingMerge (fora da allow-list da rodada)', :aggregate_failures do
    found = offenders_in(pattern, helper)
    new_offenders = found.keys - allow_list
    stale_entries = allow_list - found.keys

    listing = new_offenders.map { |rel| "#{rel}:#{found[rel].join(',')}" }
    expect(new_offenders).to be_empty,
                             "grava agenda_config/ai_config direto — use Cevico::SettingMerge.merge!/merge_key!:\n  #{listing.join("\n  ")}"
    expect(stale_entries).to be_empty,
                             "já convertidos, tire da allow-list em setting_merge_lint_spec.rb:\n  #{stale_entries.join("\n  ")}"
  end
end
