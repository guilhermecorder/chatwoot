require 'rails_helper'

# 🔔 11/11/2026 (LIFE): a tela "Editar coluna" grava o prazo da etapa com a fila de lembretes.
RSpec.describe 'CRM: prazo da coluna com lembretes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 0) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages/#{stage.id}" }

  it 'guarda o primeiro compromisso e a fila; devolve tudo para a tela', :aggregate_failures do
    prazo = { modo: 'dia_util', hora: '09:00', tarefa: 'Confirmar se recebeu o orçamento',
              lembretes: [{ dias: 2, tarefa: 'Ligar: o que achou do orçamento?' }, { dias: 0, tarefa: 'linha incompleta' }] }
    patch url, params: { stage: { name: stage.name, settings: { prazo: prazo } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    salvo = stage.reload.settings['prazo']
    expect(salvo['tarefa']).to eq('Confirmar se recebeu o orçamento')
    expect(salvo['lembretes']).to eq([{ 'dias' => 2, 'tarefa' => 'Ligar: o que achou do orçamento?' }])
    expect(response.parsed_body.dig('prazo', 'lembretes')).to eq([{ 'dias' => 2, 'tarefa' => 'Ligar: o que achou do orçamento?' }])
  end
end
