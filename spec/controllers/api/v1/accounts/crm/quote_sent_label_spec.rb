require 'rails_helper'

# 🏷️ 11/11/2026 (LIFE): quando o cartão entra em "Orçamento Enviado" o contato ganha sozinho a
# etiqueta `orcamento-enviado` (automação da coluna criada pelo LIFE/agente/followup_life_v3.rb)
# e nasce o compromisso do Fernando com a fila de lembretes.
RSpec.describe 'CRM: orçamento enviado → etiqueta automática + compromisso', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Fernando') }
  let(:contact) { create(:contact, account: account, name: 'Ivan Coral') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Life') }
  let(:pronto) { Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento pronto', position: 0) }
  let(:enviado) do
    Crm::Stage.create!(pipeline: pipeline, name: 'Orçamento Enviado', position: 1,
                       settings: { 'task_owner_id' => admin.id,
                                   'prazo' => { 'modo' => 'dia_util', 'hora' => '09:00', 'tarefa' => 'Confirmar se o cliente recebeu o orçamento',
                                                'lembretes' => [{ 'dias' => 2, 'tarefa' => 'Ligar: o que achou do orçamento?' }] } })
  end

  before do
    Crm::Automation.create!(stage: enviado, name: 'Etiqueta: orçamento enviado', trigger_type: 'card_entered', action_type: 'apply_label',
                            delay_minutes: 0, action_config: { 'label' => 'orcamento-enviado' }, active: true)
  end

  it 'arrastar o cartão para a coluna põe a etiqueta no contato e abre o compromisso', :aggregate_failures do
    card = Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: pronto)

    perform_enqueued_jobs do
      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/contacts/#{card.id}",
            params: { stage_id: enviado.id }, headers: admin.create_new_auth_token, as: :json
    end

    expect(response).to have_http_status(:success)
    expect(contact.reload.label_list).to include('orcamento-enviado')
    task = Crm::StageDeadline.open_tasks(account, enviado.id, card.id).sole
    expect(task.title).to eq('⏰ Ivan Coral — Confirmar se o cliente recebeu o orçamento')
    expect(task.assignee).to eq(admin)
  end
end
