require 'rails_helper'

# 🛡️ Rodada 6 da auditoria — "Rede de segurança" (#260): a Gestão Financeira
# (livro caixa) não tinha teste nenhum. Aqui:
#   · só quem tem a área Financeiro entra (padrão: ninguém além do admin);
#   · o valor digitado segue a regra única do Cevico::Money — "5.000" é
#     R$ 5.000,00, nunca R$ 5,00 (o bug de julho, por outro caminho);
#   · as contas do resumo (receita − custos − tributos) e o isolamento entre
#     clínicas (o lançamento da conta B não entra no resumo da conta A).
RSpec.describe 'CEVICO Gestão Financeira (livro caixa)', type: :request do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:other_admin) { create(:user, account: other_account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/finance" }

  before do
    Current.reset
    travel_to tz.parse('2026-10-13 12:00')
    CrmSetting.create!(account: account)
  end

  def entry!(acc, kind, amount, date = '2026-10-10', category: nil)
    acc.cevico_finance_entries.create!(entry_date: Date.parse(date), kind: kind, amount: amount, description: "#{kind} #{amount}",
                                       category: category)
  end

  def create_entry(amount, user: admin, kind: 'receita')
    post "#{base}/create_entry", params: { entry_date: '2026-10-10', kind: kind, description: 'Cirurgia', amount: amount },
                                 headers: user.create_new_auth_token, as: :json
  end

  it 'atendente sem a área Financeiro: 403 para ver e para lançar', :aggregate_failures do
    get base, params: { preset: 'month' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    expect { create_entry(5000, user: agent) }.not_to change(CevicoFinanceEntry, :count)
    expect(response).to have_http_status(:forbidden)
  end

  describe 'valor digitado (regra única do Cevico::Money)' do
    {
      5000 => 5000.0,
      '5000' => 5000.0,
      '5.000' => 5000.0, # antes: "5.000".to_f = 5.0 (R$ 5,00)
      '5.000,00' => 5000.0, # antes: 5.0
      'R$ 12.500' => 12_500.0,
      '3900,5' => 3900.5,
      1234.56 => 1234.56
    }.each do |digitado, gravado|
      it "lança #{digitado.inspect} como R$ #{gravado}" do
        create_entry(digitado)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['amount']).to eq(gravado)
        expect(account.cevico_finance_entries.last.amount.to_f).to eq(gravado)
      end
    end

    it 'valor vazio, zero ou que não é dinheiro é recusado (nunca grava valor inventado)', :aggregate_failures do
      ['', '0', 'à combinar', '5,000'].each do |digitado|
        expect { create_entry(digitado) }.not_to change(CevicoFinanceEntry, :count)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  it 'o resumo do mês faz as contas certas e ignora o que é de outra clínica', :aggregate_failures do
    entry!(account, 'receita', 10_000, category: 'cirurgias')
    entry!(account, 'custo', 3_000, category: 'sala_cirurgica')
    entry!(account, 'tributo', 1_000)
    entry!(account, 'investimento_equipamento', 500)
    entry!(account, 'receita', 7_777, '2026-09-30') # mês passado: fora do período
    entry!(other_account, 'receita', 99_999)

    get base, params: { preset: 'month' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    summary = response.parsed_body['summary']
    expect(summary).to include('receita' => 10_000.0, 'custo' => 3000.0, 'tributo' => 1000.0, 'lucro' => 6000.0,
                               'margem' => 60.0, 'investimentos' => 500.0, 'caixa' => 5500.0, 'lancamentos' => 4)
    expect(response.parsed_body['by_category']['receita']).to eq([{ 'category' => 'cirurgias', 'label' => 'Cirurgias', 'total' => 10_000.0 }])
    outubro = response.parsed_body['monthly'].find { |m| m['month'] == '2026-10-01' }
    expect(outubro).to include('receita' => 10_000.0, 'lucro' => 6000.0)
    expect(response.body).not_to include('99999')
  end

  it 'comparar dois meses lado a lado', :aggregate_failures do
    entry!(account, 'receita', 10_000)
    entry!(account, 'receita', 7_000, '2026-09-15')

    get "#{base}/compare", params: { month_a: '2026-09-01', month_b: '2026-10-20' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body.dig('a', 'summary', 'receita')).to eq(7000.0)
    expect(response.parsed_body.dig('b', 'summary', 'receita')).to eq(10_000.0)

    get "#{base}/compare", params: { month_a: 'xx' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'a conta B não altera nem apaga o lançamento da conta A', :aggregate_failures do
    entry = entry!(account, 'receita', 10_000)
    other_base = "/api/v1/accounts/#{other_account.id}/crm/finance"

    post "#{other_base}/update_entry", params: { entry_id: entry.id, kind: 'receita', amount: 1 },
                                       headers: other_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{other_base}/delete_entry", params: { entry_id: entry.id }, headers: other_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(entry.reload.amount.to_f).to eq(10_000.0)

    get base, params: { preset: 'month' }, headers: other_admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
