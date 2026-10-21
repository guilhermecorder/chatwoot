require 'rails_helper'

# 🛡️ Rodada 6 da auditoria — "Rede de segurança" (#260): a colagem
# "telefone;valor" das cirurgias feitas fora do sistema (Tratamento de dados)
# lia o valor com regra própria e não tinha teste. Agora passa pela regra
# única do Cevico::Money: "5.000" = R$ 5.000,00 (nunca R$ 5,00) e o que não é
# dinheiro fica SEM valor (o card não recebe valor inventado).
RSpec.describe 'CEVICO cirurgias de fora — leitura do valor colado', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0) }
  let(:stage) { pipeline.stages.create!(name: 'Cirurgia Realizada', color: '#000', position: 0) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/external_surgeries" }

  # [telefone colado, valor colado, valor que o card deve receber]
  let(:table) do
    [
      ['11999990001', 'R$ 5.000', 5000.0],
      ['11999990002', '12.500', 12_500.0],
      ['(11) 99999-0003', '5.000,00', 5000.0],
      ['11999990004', '3900,5', 3900.5],
      ['11999990005', '1.234.567', 1_234_567.0],
      ['11999990006', '24187.8', 24_187.8], # número cru do Excel
      ['11999990007', 'à combinar', nil],
      ['11999990008', '5,000', nil], # milhar no jeito americano: ambíguo → sem valor
      ['11999990009', '0', nil],
      ['11999990010', '', nil]
    ]
  end
  let!(:patients) do
    table.each_with_index.map do |(_phone, _value, _expected), i|
      create(:contact, account: account, name: "Paciente #{i + 1}", phone_number: format('+55119999900%02d', i + 1))
    end
  end

  before { Current.reset }

  def pasted_list
    table.map.with_index { |(phone, value, _), i| "#{phone}#{i == 2 ? "\t" : ';'}#{value}" }.join("\n")
  end

  it 'cada valor colado vira o valor certo no job (tabela de casos)', :aggregate_failures do
    expect do
      post "#{base}/apply", params: { list: pasted_list, target_stage_id: stage.id }, headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(Crm::ExternalSurgeryJob)
    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('matched' => table.size)

    pairs = ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args][1].to_h
    table.each_with_index do |(_phone, value, expected), i|
      expect(pairs[patients[i].id]).to eq(expected), "#{value.inspect} deveria virar #{expected.inspect}, virou #{pairs[patients[i].id].inspect}"
    end
  end

  it 'a prévia casa todos os telefones (com máscara, tab ou ponto e vírgula)', :aggregate_failures do
    post "#{base}/preview", params: { list: pasted_list, target_stage_id: stage.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('total_lines' => table.size, 'matched' => table.size, 'unmatched_count' => 0)
  end

  it 'quem não tem "Tratamento de dados" não importa', :aggregate_failures do
    expect do
      post "#{base}/apply", params: { list: pasted_list, target_stage_id: stage.id }, headers: agent.create_new_auth_token, as: :json
    end.not_to have_enqueued_job(Crm::ExternalSurgeryJob)
    expect(response).to have_http_status(:forbidden)
  end
end
