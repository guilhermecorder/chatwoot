require 'rails_helper'

# 📞 rodada 195: quem entra (e quem fica de fora) da lista de leads não responsivos
RSpec.describe Crm::VoiceAgent::UnresponsiveLeads do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'CEVICO') }
  let!(:stage_budget) { pipeline.stages.create!(name: 'Envio de Orçamento', position: 1) }
  let!(:stage_other) { pipeline.stages.create!(name: 'Novos Contatos', position: 0) }
  let(:cfg) { { 'stage_ids' => [stage_budget.id], 'silence_hours' => 24, 'lookback_days' => 7, 'max_attempts' => 2, 'daily_cap' => 20 } }
  let(:now) { Crm::VoiceAgent::Settings::TZ.now }

  def lead(name, phone: '+5511999990001', stage: stage_budget)
    contact = create(:contact, account: account, name: name, phone_number: phone)
    Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage)
    contact
  end

  def talk(contact, type, content, at:)
    conversation = Conversation.find_by(account: account, contact: contact) ||
                   create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, content: content, created_at: at)
  end

  def candidates(overrides = {})
    described_class.new(account, cfg.merge(overrides), now: now).candidates
  end

  it 'lista o lead cuja última mensagem é da clínica há mais de N horas, com motivo legível e objetivo falado', :aggregate_failures do
    maria = lead('Maria Silva')
    talk(maria, :incoming, 'quanto fica a refrativa?', at: now - 31.hours)
    talk(maria, :outgoing, 'Segue o orçamento da refrativa: PRK ou Lasik…', at: now - 30.hours)

    list = candidates
    expect(list.size).to eq(1)
    item = list.first
    expect(item).to include('contact_id' => maria.id, 'name' => 'Maria Silva', 'phone_final' => '0001', 'stage' => 'Envio de Orçamento',
                            'stage_id' => stage_budget.id, 'hours_silent' => 30)
    expect(item['motivo']).to include('Envio de Orçamento').and include('sem resposta há 30 h').and include('Segue o orçamento')
    expect(item['objective']).to include('Envio de Orçamento').and include('há trinta horas').and include('não respondeu')
    expect(item['conversation_id']).to eq(Conversation.find_by(contact: maria).display_id)
  end

  it 'fica de fora quem respondeu depois, quem a clínica falou há pouco e quem parou há mais dias que o olhado', :aggregate_failures do
    answered = lead('Respondeu', phone: '+5511999990002')
    talk(answered, :outgoing, 'Segue o orçamento', at: now - 40.hours)
    talk(answered, :incoming, 'vou pensar', at: now - 2.hours)

    fresh = lead('Recente', phone: '+5511999990003')
    talk(fresh, :outgoing, 'Segue o orçamento', at: now - 3.hours)

    old = lead('Antigo', phone: '+5511999990004')
    talk(old, :outgoing, 'Segue o orçamento', at: now - 10.days)

    silent = lead('Sem conversa', phone: '+5511999990005')

    expect(candidates).to be_empty
    expect(candidates('lookback_days' => 15).pluck('name')).to eq(['Antigo'])
    expect(silent).to be_present
  end

  it 'fica de fora quem não tem telefone, está em outra coluna, pediu para não ser incomodado ou já tem consulta futura', :aggregate_failures do
    no_phone = create(:contact, account: account, name: 'Sem Telefone', phone_number: nil)
    Crm::Contact.create!(contact: no_phone, pipeline: pipeline, stage: stage_budget)
    talk(no_phone, :outgoing, 'Segue o orçamento', at: now - 30.hours)

    other = lead('Outra Coluna', phone: '+5511999990006', stage: stage_other)
    talk(other, :outgoing, 'Segue o orçamento', at: now - 30.hours)

    quiet = lead('Opt-out', phone: '+5511999990007')
    quiet.add_labels([Crm::OptOut::LABEL])
    talk(quiet, :outgoing, 'Segue o orçamento', at: now - 30.hours)

    booked = lead('Já Marcou', phone: '+5511999990008')
    talk(booked, :outgoing, 'Segue o orçamento', at: now - 30.hours)
    account.tasks.create!(title: 'Consulta: Já Marcou', task_type: 'consulta', due_at: now + 2.days, unit: 'paulista',
                          phone: '+5511999990008', contact: booked, creator: admin)

    expect(candidates).to be_empty
  end

  it 'respeita as ligações da IA: nada em 48 h, no máximo N tentativas em 14 dias, e ninguém já na fila de campanha', :aggregate_failures do
    recent_call = lead('Ligou Ontem', phone: '+5511999990009')
    talk(recent_call, :outgoing, 'Segue o orçamento', at: now - 30.hours)
    Crm::Call.create!(account: account, inbox: inbox, contact: recent_call, meta_call_id: 'el:1', handled_by: 'ai', provider: 'elevenlabs',
                      direction: :outbound, status: :completed, started_at: now - 20.hours)

    exhausted = lead('Duas Tentativas', phone: '+5511999990010')
    talk(exhausted, :outgoing, 'Segue o orçamento', at: now - 30.hours)
    [5, 9].each do |days|
      Crm::Call.create!(account: account, inbox: inbox, contact: exhausted, meta_call_id: "el:x#{days}", handled_by: 'ai', provider: 'elevenlabs',
                        direction: :outbound, status: :completed, started_at: now - days.days)
    end

    queued = lead('Na Fila', phone: '+5511999990011')
    talk(queued, :outgoing, 'Segue o orçamento', at: now - 30.hours)
    campaign = Crm::CallCampaign.create!(account: account, name: 'Campanha aberta', status: :processing, audience: {}, stats: {})
    campaign.campaign_contacts.create!(contact: queued, status: 'queued')

    ok = lead('Uma Tentativa Antiga', phone: '+5511999990012')
    talk(ok, :outgoing, 'Segue o orçamento', at: now - 30.hours)
    Crm::Call.create!(account: account, inbox: inbox, contact: ok, meta_call_id: 'el:old', handled_by: 'ai', provider: 'elevenlabs',
                      direction: :outbound, status: :completed, started_at: now - 5.days)

    expect(candidates.pluck('name')).to eq(['Uma Tentativa Antiga'])
    expect(candidates('max_attempts' => 3).pluck('name')).to contain_exactly('Uma Tentativa Antiga', 'Duas Tentativas')
  end

  it 'ordena do mais recente para o mais antigo e respeita o teto do dia' do
    %w[A B C].each_with_index do |name, i|
      contact = lead("Lead #{name}", phone: "+551199999002#{i}")
      talk(contact, :outgoing, 'Segue o orçamento', at: now - (30 + (i * 10)).hours)
    end
    expect(candidates.pluck('name')).to eq(['Lead A', 'Lead B', 'Lead C'])
    expect(candidates('daily_cap' => 2).pluck('name')).to eq(['Lead A', 'Lead B'])
  end

  it 'padrões e limites da config' do
    expect(described_class.setting({}, 'silence_hours')).to eq(24)
    expect(described_class.setting({ 'max_attempts' => 99 }, 'max_attempts')).to eq(5)
    expect(described_class.setting({ 'daily_cap' => '0' }, 'daily_cap')).to eq(20)
    expect(described_class.new(account, { 'stage_ids' => [999_999] }).candidates).to eq([])
  end
end
