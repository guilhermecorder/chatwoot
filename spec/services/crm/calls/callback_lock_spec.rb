require 'rails_helper'

# 📵🔒 item 325 (05/10): ligação travada — responsável por coluna do CRM, trava
# ao tocar e ligação perdida travada até o retorno (atendeu, ou 2 tentativas).
RSpec.describe Crm::Calls::CallbackLock do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bia) { create(:user, account: account, role: :agent, name: 'Bia') }
  let(:inbox) { create(:inbox, account: account) }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Pós-operatório', color: '#000', position: 1)
    end
  end
  let(:novos) { pipeline.stages.first }
  let(:pos_op) { pipeline.stages.last }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:calls_cfg) do
    { 'lock' => { 'enabled' => true, 'after_seconds' => 5, 'attempts' => 2 },
      'stage_owners' => { novos.id.to_s => ana.id, pos_op.id.to_s => bia.id } }
  end
  let!(:settings) { CrmSetting.create!(account: account, agenda_config: { 'calls' => calls_cfg }) }

  def call!(attrs = {})
    Crm::Call.create!({ account: account, inbox: inbox, contact: contact, meta_call_id: "wacid.#{SecureRandom.hex(4)}", direction: :inbound,
                        status: :missed, end_reason: 'not_answered', wa_id: '5511999990000', started_at: 5.minutes.ago,
                        ended_at: 4.minutes.ago, simulated: true }.merge(attrs))
  end

  def call_back!(status, at: 1.minute.ago)
    call!(direction: :outbound, status: status, started_at: at, created_at: at,
          answered_at: (status == :completed ? at : nil), ended_at: at + 30.seconds)
  end

  describe 'responsável' do
    it 'é quem responde pela coluna do card; sem card vale a coluna de entrada; sem dono, o padrão', :aggregate_failures do
      expect(described_class.owner_id(account, contact.id)).to eq(ana.id) # sem card → Novos Contatos
      Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: pos_op)
      expect(described_class.owner_id(account, contact.id)).to eq(bia.id)

      settings.update!(agenda_config: { 'calls' => calls_cfg.merge('stage_owners' => {}) })
      expect(described_class.owner_id(account, contact.id)).to be_nil
      settings.update!(agenda_config: { 'calls' => calls_cfg.merge('stage_owners' => {}, 'default_owner' => ana.id) })
      expect(described_class.owner_id(account, contact.id)).to eq(ana.id)
    end
  end

  describe 'tocando' do
    it 'o responsável toca primeiro e é quem trava; os outros continuam na lista (rede de segurança)' do
      targets = described_class.ringing(account, call!(status: :ringing), [bia.id], [bia.id])
      expect(targets).to eq(ring_user_ids: [bia.id, ana.id], ring_first_user_ids: [ana.id], lock_user_ids: [ana.id], lock_after_seconds: 5)
    end

    it 'com "só o responsável", toca só para ele; com a trava desligada, nada muda', :aggregate_failures do
      settings.update!(agenda_config: { 'calls' => calls_cfg.deep_merge('lock' => { 'exclusive' => true }) })
      expect(described_class.ringing(account, call!(status: :ringing), [bia.id], [])[:ring_user_ids]).to eq([ana.id])

      settings.update!(agenda_config: { 'calls' => calls_cfg.deep_merge('lock' => { 'enabled' => false }) })
      expect(described_class.ringing(account, call!(status: :ringing), [bia.id], [bia.id]))
        .to eq(ring_user_ids: [bia.id], ring_first_user_ids: [bia.id])
    end
  end

  describe 'perdida' do
    let(:missed) { call! }

    before { described_class.arm!(missed) }

    it 'trava a tela do responsável (e só a dele), com o aviso do Radar no nome dele', :aggregate_failures do
      expect(described_class.pending_for(account, ana)).to eq(missed)
      expect(described_class.pending_for(account, bia)).to be_nil
      alert = Crm::Calls::RadarAlert.push(missed)
      expect(alert).to include('user_id' => ana.id, 'lock' => true)
      expect(Crm::Calls::RadarAlert.still_open?(account, alert)).to be(true)
    end

    it 'mensagem de texto NÃO solta; 1 ligação de volta sem resposta também não; a 2ª solta', :aggregate_failures do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      missed.update!(conversation: conversation)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: ana)
      expect(described_class.done?(missed)).to be(false)

      call_back!(:missed, at: 3.minutes.ago)
      expect(described_class.payload(missed)).to include(attempts_done: 1, attempts_needed: 2)
      expect(described_class.pending_for(account, ana)).to eq(missed)

      call_back!(:missed, at: 2.minutes.ago)
      expect(described_class.pending_for(account, ana)).to be_nil
    end

    it 'solta na hora se o paciente atendeu a ligação de volta, ou se alguém marcou como retornada', :aggregate_failures do
      call_back!(:completed)
      expect(described_class.done?(missed)).to be(true)

      outra = call!(started_at: 20.seconds.ago, ended_at: 10.seconds.ago) # perdida DEPOIS daquela ligação atendida
      described_class.arm!(outra)
      expect(described_class.pending_for(account, ana)).to eq(outra)
      outra.mark_returned!(bia, note: 'liguei do fixo')
      expect(described_class.pending_for(account, ana)).to be_nil
    end

    it 'com a trava desligada não arma nada e o aviso segue geral, como era' do
      settings.update!(agenda_config: { 'calls' => calls_cfg.deep_merge('lock' => { 'enabled' => false }) })
      livre = call!
      expect(described_class.arm!(livre)).to be_nil
      expect(Crm::Calls::RadarAlert.push(livre)).not_to include('lock')
    end
  end

  it 'salva só gente e colunas da conta, com os limites de segundos e tentativas' do
    other = create(:user, account: create(:account))
    params = ActionController::Parameters.new(lock: { enabled: true, after_seconds: 99, attempts: 0, exclusive: 'true' },
                                              stage_owners: { novos.id.to_s => ana.id, '999999' => ana.id, pos_op.id.to_s => other.id },
                                              default_owner: other.id)
    expect(described_class.sanitize(account, params)).to eq(
      'lock' => { 'enabled' => true, 'after_seconds' => 5, 'attempts' => 2, 'exclusive' => true },
      'stage_owners' => { novos.id.to_s => ana.id }, 'default_owner' => nil
    )
  end
end
