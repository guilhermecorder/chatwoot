require 'rails_helper'

# 🔎 item 328 (05/10, Fase 2 das Fontes): a porta única de leitura — a lente
# filtra pela fonte carimbada (e, onde ainda não há carimbo, pelas regras que
# carimbam o passado) — e "tudo o que foi marcado" aberto em três cortes.
RSpec.describe Crm::SourceLens do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:capture_inbox) { create(:inbox, account: account, name: 'Caixa Google') }
  let(:partner_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 1)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Consulta Agendada', color: '#000', position: 0)
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 1)
    end
  end
  let(:own) { Crm::Sources.own(account) }
  let(:partner) { Crm::Sources.partner(account) }
  let(:house_lens) { described_class.for(account, 'cevico') }
  let(:partner_lens) { described_class.for(account, 'oftalmofacil') }
  let(:all_lens) { described_class.for(account, 'all') }
  let(:since) { 1.day.ago }
  let(:until_at) { 1.day.from_now }

  before do
    Rails.cache.clear
    Current.reset
    CrmSetting.create!(account: account, agenda_config: {
                         'oftalmofacil' => { 'provider_name' => 'CATARATA_SP', 'partner_pipeline_id' => partners.id,
                                             'partner_inbox_ids' => [partner_inbox.id] }
                       })
  end

  after { Current.reset }

  def contact(name, attrs = {})
    create(:contact, { account: account, name: name }.merge(attrs))
  end

  def task(attrs = {})
    Task.create!({ account: account, creator: user, title: 'Consulta: Paciente', task_type: 'consulta', due_at: 2.days.from_now }.merge(attrs))
  end

  def conversation(person, inbox)
    create(:conversation, account: account, inbox: inbox, contact: person)
  end

  describe 'qual lente' do
    it 'sem escolha (ou chave desconhecida) é a casa; "all" e "tudo" não filtram' do
      expect(described_class.for(account, nil)).to be_own
      expect(described_class.for(account, 'nao_existe').key).to eq('cevico')
      expect(described_class.for(account, 'tudo')).to be_all
      expect(partner_lens.key).to eq('oftalmofacil')
    end

    it 'cada lente enxerga os seus funis, com o da casa na frente' do
      expect(house_lens.pipelines).to eq([cevico])
      expect(partner_lens.pipelines).to eq([partners])
      expect(all_lens.pipelines).to eq([cevico, partners])
    end
  end

  describe 'agendamentos' do
    it 'separa pelo carimbo: da casa × do Oftalmofácil × tudo' do
      ours = task
      theirs = task(origin: 'oftalmofacil')
      expect(house_lens.tasks(account.tasks)).to contain_exactly(ours)
      expect(partner_lens.tasks(account.tasks)).to contain_exactly(theirs)
      expect(all_lens.tasks(account.tasks)).to contain_exactly(ours, theirs)
    end

    it 'sem carimbo, vale a regra que carimba o passado (parceiro escolhido ou vindo do hub)' do
      ours = task
      chosen = task(origin: 'oftalmofacil')
      hub = task(source: 'oftalmofacil', source_detail: 'CLINICA_PARCEIRA')
      Task.where(id: [ours.id, chosen.id, hub.id]).update_all(cevico_source_id: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(house_lens.tasks(account.tasks)).to contain_exactly(ours)
      expect(partner_lens.tasks(account.tasks)).to contain_exactly(chosen, hub)
    end
  end

  describe 'cards e entradas em coluna' do
    it 'seguem a fonte dona do funil, com ou sem carimbo' do
      ours = Crm::Contact.create!(contact: contact('Ana'), pipeline: cevico, stage: cevico.stages.first)
      theirs = Crm::Contact.create!(contact: contact('Bia'), pipeline: partners, stage: partners.stages.first)
      expect(house_lens.cards(Crm::Contact.all)).to contain_exactly(ours)
      expect(partner_lens.stage_logs(Crm::StageLog.all).pluck(:crm_contact_id)).to eq([theirs.id])

      Crm::Contact.update_all(cevico_source_id: nil) # rubocop:disable Rails/SkipsModelValidations
      Crm::StageLog.update_all(cevico_source_id: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(partner_lens.cards(Crm::Contact.all)).to contain_exactly(theirs)
      expect(house_lens.stage_logs(Crm::StageLog.all).pluck(:crm_contact_id)).to eq([ours.id])
    end
  end

  describe 'pacientes' do
    it 'carimbado segue o carimbo; sem carimbo segue a cerca dos parceiros' do
      ana = contact('Ana')
      bia = contact('Bia')
      caio = contact('Caio', additional_attributes: { 'parceiro' => 'CLINICA_PARCEIRA' })
      Contact.where(id: ana.id).update_all(cevico_source_id: own.id) # rubocop:disable Rails/SkipsModelValidations
      Contact.where(id: [bia.id, caio.id]).update_all(cevico_source_id: nil) # rubocop:disable Rails/SkipsModelValidations
      Crm::PartnerGuard.forget!(account)
      expect(house_lens.contacts(account.contacts)).to contain_exactly(ana, bia)
      expect(partner_lens.contacts(account.contacts)).to contain_exactly(caio)
      expect(all_lens.contacts(account.contacts).count).to eq(3)
    end
  end

  describe 'conversas (pela caixa de entrada)' do
    it 'caixa que nenhuma fonte pegou é da casa; a do parceiro é dele' do
      ours = conversation(contact('Ana'), capture_inbox)
      theirs = conversation(contact('Bia'), partner_inbox)
      expect(house_lens.inboxes(account.conversations)).to contain_exactly(ours)
      expect(partner_lens.inboxes(account.conversations)).to contain_exactly(theirs)
    end
  end

  describe 'universo de leads e coluna de agendamento pela lente' do
    it 'casa = quem chegou pelas caixas de captação; Oftalmofácil = pacientes novos dele; tudo = a soma' do
      ana = contact('Ana')
      conversation(ana, capture_inbox)
      bia = contact('Bia')
      Crm::Contact.create!(contact: bia, pipeline: partners, stage: partners.stages.first)
      Crm::PartnerGuard.forget!(account)

      expect(Crm::LeadsUniverse.scope(account, since, until_at, lens: house_lens)).to contain_exactly(ana)
      expect(Crm::LeadsUniverse.scope(account, since, until_at, lens: partner_lens)).to contain_exactly(bia)
      expect(Crm::LeadsUniverse.scope(account, since, until_at, lens: all_lens)).to contain_exactly(ana, bia)
      # sem lente continua a régua de sempre (a da casa)
      expect(Crm::LeadsUniverse.scope(account, since, until_at)).to contain_exactly(ana)
    end

    it 'cada fonte tem a SUA coluna de agendamento (nunca a de cirurgia)' do
      house_stage = cevico.stages.find_by(name: 'Agendamento de Consulta')
      partner_stage = partners.stages.find_by(name: 'Consulta Agendada')
      Crm::Contact.create!(contact: contact('Ana'), pipeline: cevico, stage: house_stage)
      Crm::Contact.create!(contact: contact('Bia'), pipeline: partners, stage: partner_stage)
      Crm::Contact.create!(contact: contact('Caio'), pipeline: partners, stage: partners.stages.find_by(name: 'Cirurgia Agendada'))

      expect(Crm::BookingRate.stage_ids(account, all_lens)).to eq([house_stage.id, partner_stage.id])
      expect(Crm::BookingRate.count(account, since, until_at, lens: house_lens)).to eq(1)
      expect(Crm::BookingRate.count(account, since, until_at, lens: partner_lens)).to eq(1)
      expect(Crm::BookingRate.count(account, since, until_at, lens: all_lens)).to eq(2)
      expect(Crm::BookingRate.count(account, since, until_at)).to eq(1)
    end
  end

  describe 'cesto de indicadores' do
    it 'com a lente, as consultas do período separam por fonte; sem lente, nada muda' do
      task(due_at: 1.hour.from_now)
      task(due_at: 1.hour.from_now, origin: 'oftalmofacil')
      bag = ->(lens) { Crm::KpiBagService.new(account: account, since: since, until_at: until_at, lens: lens).call[:metrics] }

      expect(bag.call(house_lens)['appointments_due'][:value]).to eq(1)
      expect(bag.call(partner_lens)['appointments_due'][:value]).to eq(1)
      expect(bag.call(all_lens)['appointments_due'][:value]).to eq(2)
      expect(bag.call(nil)['appointments_due'][:value]).to eq(2)
      expect(bag.call(house_lens)['appointments_booked'][:value]).to eq(1)
      expect(bag.call(all_lens)['appointments_booked'][:value]).to eq(2)
      expect(bag.call(nil)['appointments_booked'][:value]).to eq(1)
    end
  end

  describe 'tudo o que foi marcado, em três cortes (Crm::BookingCuts)' do
    let(:house_stage) { cevico.stages.find_by(name: 'Agendamento de Consulta') }

    def cuts(lens)
      Crm::BookingCuts.new(account, lens: lens).call(since, until_at)
    end

    def counts(list)
      list.to_h { |slice| [slice[:key], slice[:count]] }
    end

    it 'o que foi: tipos da Agenda + só mudança de coluna; lançada e histórico ficam fora, contados ao lado' do
      ana = contact('Ana')
      task(contact: ana, modality: 'avaliacao')
      task(modality: 'retorno')
      task(modality: 'pos_op')
      task(task_type: 'cirurgia', title: 'Cirurgia: Paciente')
      task(booking_kind: 'registro')
      task(due_at: 3.days.ago)
      task(canceled_at: Time.current)
      # Ana tem consulta na Agenda: a entrada dela na coluna não conta de novo
      Crm::Contact.create!(contact: ana, pipeline: cevico, stage: house_stage)
      # Bia só mudou de coluna
      Crm::Contact.create!(contact: contact('Bia'), pipeline: cevico, stage: house_stage)

      out = cuts(house_lens)
      expect(out).to include(total: 5, agenda: 4, column_only: 1, outside: { registered: 1, history: 1 })
      expect(counts(out[:what])).to eq('avaliacao' => 1, 'retorno' => 1, 'pos_op' => 1, 'cirurgia' => 1, 'coluna' => 1)
      expect(out[:rows].find { |r| r[:what] == 'coluna' }).to include(name: 'Bia', via: 'robo')
    end

    it 'de onde veio: fonte, caixa por onde o paciente chegou e particular' do
      ana = contact('Ana')
      conversation(ana, capture_inbox)
      task(contact: ana, particular: true)
      task(origin: 'oftalmofacil')

      out = cuts(all_lens)
      expect(counts(out[:sources])).to eq('cevico' => 1, 'oftalmofacil' => 1)
      expect(counts(out[:inboxes])).to eq(capture_inbox.id => 1, 'sem_cadastro' => 1)
      expect(out[:particular]).to eq(yes: 1, no: 1)
      expect(cuts(house_lens)[:total]).to eq(1)
      expect(cuts(partner_lens)[:total]).to eq(1)
    end

    it 'quem fez: o carimbo; antes do carimbo, a marca do Atendente de IA (e avisa quantos foram deduzidos)' do
      Current.user = user
      task
      Current.reset
      Crm::Stamp.with(via: 'paciente') { task }
      old_team = task
      old_robot = task(description: 'Agendada pela IA')
      hub = task(source: 'oftalmofacil')
      Task.where(id: [old_team.id, old_robot.id, hub.id]).update_all(cevico_born_via: nil) # rubocop:disable Rails/SkipsModelValidations

      out = cuts(house_lens)
      expect(counts(out[:who])).to eq('equipe' => 2, 'paciente' => 1, 'robo' => 1, 'sync' => 1)
      expect(out[:deduced]).to eq(2)
    end
  end
end
