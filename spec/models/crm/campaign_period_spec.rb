require 'rails_helper'

# 🕐 Auditoria 12/10 — Rodada 3 (#411): o período do público ("lead chegou
# entre 01/10 e 01/10") é o DIA de São Paulo inteiro. O Rails roda em UTC:
# antes, o lead das 22h de 01/10 (= 01:00 UTC de 02/10) ficava de fora e o
# das 23h de 30/09 (= 02:00 UTC de 01/10) entrava.
RSpec.describe Crm::Campaign, type: :model do
  let(:account) { create(:account) }
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:label) { account.labels.create!(title: 'reativar') }

  def lead!(name, created_at_utc)
    create(:contact, account: account, name: name, phone_number: "+55119#{rand(10_000_000..99_999_999)}",
                     created_at: created_at_utc).tap { |c| c.update!(label_list: ['reativar']) }
  end

  def audience_for(from:, to:)
    described_class.new(account: account, audience: { 'include_label_ids' => [label.id], 'period_field' => 'contact_created',
                                                      'period_from' => from, 'period_to' => to })
  end

  describe '#resolve_audience com período' do
    it 'de 01/10 a 01/10 = das 00:00 às 23:59 de São Paulo (não do dia em UTC)', :aggregate_failures do
      noite_de_30 = lead!('Noite de 30/09', Time.utc(2026, 10, 1, 2, 0))   # 23:00 de 30/09 em SP
      manha_de_01 = lead!('Manhã de 01/10', Time.utc(2026, 10, 1, 12, 0))  # 09:00 de 01/10 em SP
      noite_de_01 = lead!('Noite de 01/10', Time.utc(2026, 10, 2, 1, 0))   # 22:00 de 01/10 em SP
      madrugada_02 = lead!('Madrugada 02/10', Time.utc(2026, 10, 2, 3, 30)) # 00:30 de 02/10 em SP

      ids = audience_for(from: '2026-10-01', to: '2026-10-01').resolve_audience.pluck(:id)

      expect(ids).to contain_exactly(manha_de_01.id, noite_de_01.id)
      expect(ids).not_to include(noite_de_30.id, madrugada_02.id)
    end

    it 'só "de" ou só "até" também contam no fuso da clínica', :aggregate_failures do
      noite_de_30 = lead!('Noite de 30/09', Time.utc(2026, 10, 1, 2, 0))
      noite_de_01 = lead!('Noite de 01/10', Time.utc(2026, 10, 2, 1, 0))

      expect(audience_for(from: '2026-10-01', to: '').resolve_audience.pluck(:id)).to contain_exactly(noite_de_01.id)
      expect(audience_for(from: '', to: '2026-09-30').resolve_audience.pluck(:id)).to contain_exactly(noite_de_30.id)
    end

    it 'data inválida não filtra nada (não derruba a prévia)' do
      lead = lead!('Qualquer', Time.utc(2026, 10, 1, 12, 0))

      expect(audience_for(from: 'sei lá', to: '').resolve_audience.pluck(:id)).to contain_exactly(lead.id)
    end
  end

  describe '.due (#415)' do
    let(:inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false).inbox
    end

    it 'só a AGENDADA que venceu dispara; pausada ou rascunho com data nunca', :aggregate_failures do
      vencida = described_class.create!(account: account, inbox: inbox, name: 'a', template_params: { 'name' => 'x' },
                                        status: :scheduled, scheduled_at: 1.minute.ago)
      futura = described_class.create!(account: account, inbox: inbox, name: 'b', template_params: { 'name' => 'x' },
                                       status: :scheduled, scheduled_at: 1.hour.from_now)
      pausada = described_class.create!(account: account, inbox: inbox, name: 'c', template_params: { 'name' => 'x' },
                                        status: :paused, scheduled_at: 1.minute.ago)

      expect(described_class.due).to include(vencida)
      expect(described_class.due).not_to include(futura, pausada)
    end
  end
end
