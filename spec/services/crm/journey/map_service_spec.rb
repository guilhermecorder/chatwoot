require 'rails_helper'

# Mapa da jornada (item 173): tudo o que age em cada etapa + personalização.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Mapa da jornada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/journey_messages" }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
  let!(:stage_lead) { Crm::Stage.create!(pipeline: pipeline, name: 'Novos Contatos') }
  let!(:stage_surgery) { Crm::Stage.create!(pipeline: pipeline, name: 'Cirurgia Agendada') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:bot_steps) { [{ 'delay_value' => 2, 'delay_unit' => 'hours', 'message' => 'oi' }] }

  before do
    CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd1' => { 'enabled' => true, 'hour' => 9 } } })
  end

  it 'adivinha a etapa pelo nome da coluna (cirurgia antes de consulta)' do
    svc = Crm::Journey::MapService.new(account: account)
    expect(svc.guess_step('Cirurgia Agendada')).to eq('cirurgia')
    expect(svc.guess_step('Agendamento de Consulta')).to eq('consulta')
    expect(svc.guess_step('Pós Operatório')).to eq('pos_op')
    expect(svc.guess_step('Não Fechou Ainda')).to eq('orcamento')
    expect(svc.guess_step('Coluna X')).to eq('lead')
  end

  it 'pendura lembretes, follow-up, réguas, automações e agentes nas etapas' do
    bot = Crm::FollowupBot.create!(account: account, name: 'Cutucada', active: true, stage: stage_surgery, steps: bot_steps)
    rule = Crm::MessageAutomation.create!(account: account, inbox: channel.inbox, name: 'Régua 7d', active: false, delay_days: 7,
                                          trigger_stage: stage_lead, template_params: { 'name' => 'regua' })
    auto = Crm::Automation.create!(stage: stage_lead, name: 'Conversão', trigger_type: 'card_entered', action_type: 'meta_ads_event', active: true)

    result = Crm::Journey::MapService.new(account: account).call
    by_id = result[:items].index_by { |i| i[:id] }
    expect(by_id['reminder:d1']).to include(step: 'consulta', enabled: true, when_label: 'às 09:00')
    expect(by_id["followup:#{bot.id}"]).to include(step: 'cirurgia', when_label: '1 cutucada(s) · 1ª após 2h')
    expect(by_id["message_automation:#{rule.id}"]).to include(step: 'lead', enabled: false)
    expect(by_id["column_automation:#{auto.id}"]).to include(step: 'lead', detail: 'Novos Contatos: envia conversão à Meta')
    expect(by_id['agent:nps'][:step]).to eq('pos_op')
    expect(by_id['agent:opportunity'][:step]).to be_nil
    expect(result[:stage_steps][stage_surgery.id]).to eq('cirurgia')
  end

  it 'respeita a personalização: coluna → etapa, item movido, escondido, categoria oculta, ordem e nomes' do
    bot = Crm::FollowupBot.create!(account: account, name: 'Cutucada', active: true, stage: stage_surgery, steps: bot_steps)
    post "#{base}/update_settings",
         params: { map: { stage_steps: { stage_surgery.id.to_s => 'pos_op' }, overrides: { 'agent:nps' => 'geral', 'agent:harvest' => 'retorno' },
                          hidden: ['reminder:d0'], show: { campaign: false }, step_order: %w[retorno lead],
                          step_labels: { lead: 'Novo contato' }, density: 'compact', queue: 'top' } },
         headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('settings', 'map', 'density')).to eq('compact')

    get "#{base}/map", headers: admin.create_new_auth_token, as: :json
    body = response.parsed_body
    expect(body['steps'].map { |s| s['key'] }.first(2)).to eq(%w[retorno lead])
    expect(body['steps'][1]['label']).to eq('Novo contato')
    items = body['items'].index_by { |i| i['id'] }
    expect(items["followup:#{bot.id}"]['step']).to eq('pos_op')
    expect(items['agent:nps']['step']).to be_nil
    expect(items['agent:harvest']['step']).to eq('retorno')
    expect(items).not_to have_key('reminder:d0')
    expect(body['hidden_items'].map { |h| h['id'] }).to eq(['reminder:d0'])
    expect(body['map']['queue']).to eq('top')
  end
end
# rubocop:enable RSpec/MultipleExpectations
