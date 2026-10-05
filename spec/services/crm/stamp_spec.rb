require 'rails_helper'

# 🏷️ item 322 (04/10): fontes de pacientes + carimbo de origem — cada registro
# nasce sabendo DE QUEM É (fonte) e COMO nasceu; o passado é carimbado pelas
# regras de hoje (cerca dos parceiros) sem reescrever o que já tem carimbo.
RSpec.describe Crm::Stamp do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:partner_inbox) { create(:inbox, account: account, name: 'Oftalmofácil') }
  let!(:cevico) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Envio de Orçamento', color: '#000', position: 1)
    end
  end
  let!(:partners) do
    Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1).tap do |p|
      p.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 0)
    end
  end
  let(:own) { Crm::Sources.own(account) }
  let(:partner) { Crm::Sources.partner(account) }

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

  describe 'fontes' do
    it 'a casa fica com o funil que ninguém pegou; o Oftalmofácil com o funil e a caixa dos parceiros' do
      expect(Crm::Sources.list(account).map(&:key)).to eq(%w[cevico oftalmofacil])
      expect(Crm::Sources.id_for_pipeline(account, cevico.id)).to eq(own.id)
      expect(Crm::Sources.id_for_pipeline(account, partners.id)).to eq(partner.id)
      expect(Crm::Sources.id_for_inbox(account, partner_inbox.id)).to eq(partner.id)
    end
  end

  describe 'card e entrada em coluna' do
    it 'nascem com a fonte do funil e o como (sem ninguém logado = robo)' do
      card = Crm::Contact.create!(contact: contact('Ana'), pipeline: cevico, stage: cevico.stages.first)
      expect(card.cevico_source_id).to eq(own.id)
      expect(card.cevico_born_via).to eq('robo')
      expect(card.stage_logs.last).to have_attributes(cevico_source_id: own.id, cevico_born_via: 'robo')
    end

    it 'cada movimentação grava o SEU como: equipe ao arrastar, carga no lote' do
      card = described_class.with(via: 'paciente') { Crm::Contact.create!(contact: contact('Bia'), pipeline: cevico, stage: cevico.stages.first) }
      Current.user = user
      card.update!(stage_id: cevico.stages.last.id)
      expect(card.stage_logs.order(:id).pluck(:cevico_born_via)).to eq(%w[paciente equipe])

      Current.reset
      described_class.with(via: 'carga') { card.update!(stage_id: cevico.stages.first.id) }
      expect(card.stage_logs.order(:id).last.cevico_born_via).to eq('carga')
      expect(Current.cevico_via).to be_nil
    end

    it 'card no funil dos parceiros nasce do Oftalmofácil' do
      card = Crm::Contact.create!(contact: contact('Caio'), pipeline: partners, stage: partners.stages.first)
      expect(card.cevico_source_id).to eq(partner.id)
      expect(card.stage_logs.last.cevico_source_id).to eq(partner.id)
    end
  end

  describe 'paciente: a primeira evidência carimba e não muda mais' do
    it 'paciente novo com 1º card na casa é da casa, mesmo entrando depois no funil dos parceiros' do
      ana = contact('Ana')
      expect(ana.cevico_source_id).to be_nil
      Crm::Contact.create!(contact: ana, pipeline: cevico, stage: cevico.stages.first)
      Crm::Contact.create!(contact: ana, pipeline: partners, stage: partners.stages.first)
      expect(ana.reload.cevico_source_id).to eq(own.id)
    end

    it 'paciente novo com 1º card no funil dos parceiros é do Oftalmofácil' do
      caio = contact('Caio')
      Crm::Contact.create!(contact: caio, pipeline: partners, stage: partners.stages.first)
      Crm::Contact.create!(contact: caio, pipeline: cevico, stage: cevico.stages.first)
      expect(caio.reload.cevico_source_id).to eq(partner.id)
    end

    it 'paciente criado pelo hub com parceiro já nasce do Oftalmofácil, como sync' do
      p = described_class.with(via: 'sync') { contact('Do hub', additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' }) }
      expect(p).to have_attributes(cevico_source_id: partner.id, cevico_born_via: 'sync')
    end

    it 'paciente ANTIGO sem carimbo segue a cerca de hoje, não a evidência nova' do
      antigo = contact('Antigo', created_at: 3.months.ago)
      antigo.add_labels(%w[of_clinica_visao_norte])
      expect(described_class.claim_contact!(antigo, own.id)).to eq(partner.id)
    end

    it 'sem ninguém logado o paciente nasce como "paciente"; com pessoa logada, "equipe"' do
      expect(contact('Escreveu').cevico_born_via).to eq('paciente')
      Current.user = user
      expect(contact('Cadastrado').cevico_born_via).to eq('equipe')
    end
  end

  describe 'agendamento' do
    def task(attrs = {})
      Task.create!({ account: account, creator: user, title: 'Consulta: Paciente', task_type: 'consulta', due_at: 2.days.from_now }.merge(attrs))
    end

    it 'origem Oftalmofácil no formulário → fonte Oftalmofácil; CEVICO → casa' do
      expect(task(origin: 'oftalmofacil').cevico_source_id).to eq(partner.id)
      expect(task(origin: 'cevico').cevico_source_id).to eq(own.id)
    end

    it 'item de parceiro vindo do hub → Oftalmofácil, como sync' do
      t = task(source: 'oftalmofacil', source_detail: 'CLINICA VISAO NORTE', external_ref: 'tok-1')
      expect(t).to have_attributes(cevico_source_id: partner.id, cevico_born_via: 'sync')
    end

    it 'sem origem escolhida segue a fonte do paciente; trocar a origem recarimba' do
      caio = contact('Caio')
      Crm::Contact.create!(contact: caio, pipeline: partners, stage: partners.stages.first)
      t = task(contact: caio)
      expect(t.cevico_source_id).to eq(partner.id)
      t.update!(origin: 'cevico')
      expect(t.reload.cevico_source_id).to eq(own.id)
    end
  end

  describe Crm::SourceBackfill do
    # registros "de antes do carimbo": zera o que o modelo carimbou ao criar
    def unstamp!
      [Contact, Crm::Contact, Crm::StageLog, Task, Crm::OftalmofacilSurgery].each do |model|
        model.update_all(cevico_source_id: nil, cevico_born_via: nil) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    let(:ours) { contact('Nosso') }
    let(:theirs) { contact('Parceiro') }
    let(:both) { contact('Dos dois — chegou primeiro na CEVICO') }

    before do
      Crm::Contact.create!(contact: ours, pipeline: cevico, stage: cevico.stages.first)
      Crm::Contact.create!(contact: theirs, pipeline: partners, stage: partners.stages.first)
      Crm::Contact.create!(contact: both, pipeline: cevico, stage: cevico.stages.first, created_at: 2.months.ago)
      Crm::Contact.create!(contact: both, pipeline: partners, stage: partners.stages.first)
      Task.create!(account: account, creator: user, title: 'Consulta: Parceiro', task_type: 'consulta', origin: 'oftalmofacil')
      Task.create!(account: account, creator: user, title: 'Consulta: Nosso', task_type: 'consulta')
      Crm::StageLog.order(:id).first.update!(event_type: 'bulk')
      unstamp!
    end

    it 'a prévia conta sem gravar' do
      preview = described_class.preview(account)
      expect(preview[:cards]).to eq('oftalmofacil' => 2, 'cevico' => 2)
      expect(preview[:contacts]).to eq('oftalmofacil' => 1, 'cevico' => 2)
      expect(preview[:tasks]).to eq('oftalmofacil' => 1, 'cevico' => 1)
      expect(described_class.pending(account)[:cards]).to eq(4)
    end

    it 'carimba pelas regras de hoje (funil, origem do agendamento, cerca com a regra B)' do
      described_class.run!(account)
      expect(described_class.pending(account).values.sum).to eq(0)
      expect(ours.reload.cevico_source_id).to eq(own.id)
      expect(theirs.reload.cevico_source_id).to eq(partner.id)
      expect(both.reload.cevico_source_id).to eq(own.id) # regra B: quem chegou primeiro
      expect(Crm::StageLog.where(cevico_source_id: partner.id).count).to eq(2)
      expect(Crm::StageLog.find_by(event_type: 'bulk').cevico_born_via).to eq('carga')
      expect(Crm::StageLog.where(event_type: 'entered').pluck(:cevico_born_via).uniq).to eq([nil]) # passado sem "como": não inventa
    end

    it 'rodar de novo não muda nada e não reescreve quem já tem carimbo' do
      described_class.run!(account)
      ours.update_columns(cevico_source_id: partner.id) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.run!(account).values.sum { |h| h.values.sum }).to eq(0)
      expect(ours.reload.cevico_source_id).to eq(partner.id)
    end

    it 'o retrato das fontes fecha com a cerca' do
      described_class.run!(account)
      overview = Crm::SourceOverview.new(account).call
      of = overview[:sources].find { |s| s[:key] == 'oftalmofacil' }
      expect(of[:counts]).to include(patients: 1, cards: 2, appointments: 1)
      expect(of[:pipeline_ids]).to eq([partners.id])
      expect(overview[:fence]).to include(only_stamp: 0, only_fence: 0)
    end
  end
end
