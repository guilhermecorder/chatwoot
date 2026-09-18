require 'rails_helper'

# 🔧 Facilitar as atualizações do Chatwoot (rodada 171): migration CEVICO com
# horário "redondo" (20260728000001) já colidiu com uma do upstream na
# atualização 4.17.1. Daqui em diante toda migration nova usa o timestamp
# REAL (`rails g migration` faz isso sozinho). As antigas ficam na lista de
# exceções — nunca renomear migration que já rodou em produção.
RSpec.describe 'Migrations CEVICO' do # rubocop:disable RSpec/DescribeClass
  let(:legacy_round_versions) { %w[20260728000001 20260910000001 20260917000001] }
  let(:cutoff) { '20260918' }

  it 'usam timestamp real (nada de 000000/000001) a partir de 18/09/2026' do
    offenders = Dir[Rails.root.join('db/migrate/*.rb')].filter_map do |path|
      version = File.basename(path)[0, 14]
      next if version < cutoff
      next if legacy_round_versions.include?(version)

      path if version.end_with?('000000', '000001', '000002', '000003')
    end
    expect(offenders).to be_empty, "migrations com horário redondo: #{offenders.map { |p| File.basename(p) }.join(', ')}"
  end
end
