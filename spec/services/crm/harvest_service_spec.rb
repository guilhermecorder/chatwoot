require 'rails_helper'

# 🌾 achado #44 (auditoria 07/10): a Colheitadeira gravava o "enviado" só no
# fim do lote — duas rodadas com a mesma lista mandavam a mensagem 2x por
# lead. Agora cada lead é reservado ANTES do envio, dentro da trava.
RSpec.describe Crm::HarvestService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:tpl) do
    { 'name' => 'colheita', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'body' => { '1' => '[gancho]' } } }
  end
  let(:harvest_cfg) do
    { 'enabled' => true, 'mode' => 'send', 'inbox_id' => inbox.id, 'template_params' => tpl, 'daily_cap' => 50, 'require_approval' => true }
  end
  let(:ana) { create(:contact, account: account, name: 'Ana', phone_number: '+5511911110001') }
  let(:bia) { create(:contact, account: account, name: 'Bia', phone_number: '+5511911110002') }
  let(:caio) { create(:contact, account: account, name: 'Caio', phone_number: '+5511911110003') }
  let(:leads) { [ana, bia, caio] }
  let(:month_key) { described_class.new(account: account).month_key }
  let(:harvest_state) do
    {
      'month_key' => month_key, 'status' => 'approved', 'approved_at' => Time.current.iso8601,
      'selected' => leads.map do |c|
        { 'contact_id' => c.id, 'name' => c.name, 'phone' => c.phone_number, 'score' => 80, 'hook' => 'seu orçamento ficou guardado',
          'sent_at' => nil, 'conversation_id' => nil, 'skipped' => false }
      end
    }
  end
  let!(:settings) do
    CrmSetting.create!(account: account, ai_config: { 'agents' => { 'harvest' => harvest_cfg }, 'harvest_state' => harvest_state })
  end
  let(:sent_ids) { [] }

  before do
    create(:user, account: account, role: :administrator) # quem assina o envio (sender_user)
    stub_const('Crm::HarvestService::THROTTLE_SECONDS', 0)
  end

  # grava quem recebeu a mensagem; o bloco decide o que o envio devolve
  # (conversa = saiu; nil = recusado) e pode fazer algo "no meio do lote"
  def stub_sending
    allow(Crm::SendTemplateService).to receive(:new).and_wrap_original do |m, **kw|
      svc = m.call(**kw)
      allow(svc).to receive(:perform) do
        sent_ids << kw[:contact].id
        block_given? ? yield(kw[:contact]) : instance_double(Conversation, display_id: 100 + kw[:contact].id)
      end
      svc
    end
  end

  def lead_of(contact)
    settings.reload.ai_config.dig('harvest_state', 'selected').find { |l| l['contact_id'] == contact.id }
  end

  it 'duas rodadas com a mesma lista não mandam a mensagem duas vezes para o mesmo lead', :aggregate_failures do
    stub_sending
    primeira = described_class.new(account: account)
    segunda = described_class.new(account: account)
    segunda.state # a segunda rodada já leu a lista ANTES de a primeira enviar (foto velha)

    expect(primeira.send_batch!).to include(ok: true, sent: 3, done: true)
    expect(segunda.send_batch!).to include(ok: true, sent: 0)

    expect(sent_ids.sort).to eq(leads.map(&:id).sort)
    expect(sent_ids.size).to eq(3)
    leads.each { |c| expect(lead_of(c)['sent_at']).to be_present }
    expect(settings.reload.ai_config.dig('harvest_state', 'status')).to eq('done')
  end

  it 'reserva o lead ANTES de enviar: a marca já está gravada quando a mensagem sai', :aggregate_failures do
    marks = {}
    stub_sending do |contact|
      marks[contact.id] = lead_of(contact)['sent_at']
      instance_double(Conversation, display_id: 1)
    end

    described_class.new(account: account).send_batch!(max_now: 1)

    expect(sent_ids).to eq([ana.id])
    expect(marks[ana.id]).to be_present
    expect(lead_of(ana)['conversation_id']).to eq(1)
  end

  it 'o "pular" feito pelo admin no meio do lote vale: o lead não recebe e continua pulado', :aggregate_failures do
    stub_sending do |contact|
      # durante o envio da Ana, o admin pula a Bia na tela
      described_class.new(account: account).skip_lead!(bia.id) if contact == ana
      instance_double(Conversation, display_id: 1)
    end

    result = described_class.new(account: account).send_batch!

    expect(result).to include(ok: true, sent: 2, done: true)
    expect(sent_ids).to contain_exactly(ana.id, caio.id)
    expect(lead_of(bia)).to include('skipped' => true, 'sent_at' => nil)
  end

  it 'envio recusado devolve a reserva: o lead fica pulado e sem "enviado"', :aggregate_failures do
    stub_sending { |contact| contact == bia ? nil : instance_double(Conversation, display_id: 1) }

    result = described_class.new(account: account).send_batch!

    expect(result).to include(ok: true, sent: 2, done: true)
    expect(lead_of(bia)).to include('skipped' => true, 'sent_at' => nil, 'conversation_id' => nil)
    expect(lead_of(ana)['sent_at']).to be_present
    expect(described_class.new(account: account).results['stats']).to include('sent' => 2, 'skipped' => 1, 'pending' => 0)
  end

  it 'respeita o teto do lote (max_now) e deixa o resto pendente para a próxima hora', :aggregate_failures do
    stub_sending
    result = described_class.new(account: account).send_batch!(max_now: 2)

    expect(result).to include(ok: true, sent: 2, done: false)
    expect(settings.reload.ai_config.dig('harvest_state', 'status')).to eq('approved')
    expect(lead_of(caio)).to include('sent_at' => nil, 'skipped' => false)
  end

  it 'erro DEPOIS de a mensagem sair mantém o lead como enviado, com a conversa', :aggregate_failures do
    stub_sending
    allow(ana).to receive(:add_labels).and_raise(StandardError, 'etiqueta falhou')
    allow(account.contacts).to receive(:find_by).and_call_original
    allow(account.contacts).to receive(:find_by).with(id: ana.id).and_return(ana)

    result = described_class.new(account: account).send_batch!

    expect(sent_ids).to contain_exactly(ana.id, bia.id, caio.id)
    expect(result).to include(ok: true, sent: 2, done: true) # a Ana recebeu, só a contagem do lote não a soma
    expect(lead_of(ana)).to include('skipped' => false, 'conversation_id' => 100 + ana.id)
    expect(lead_of(ana)['sent_at']).to be_present
    expect(described_class.new(account: account).results['stats']).to include('sent' => 3, 'skipped' => 0, 'sem_conversa' => 0)
  end

  it '"Pular" em lead que já recebeu a mensagem é recusado (não conta duas vezes)', :aggregate_failures do
    stub_sending
    described_class.new(account: account).send_batch!(max_now: 1)

    expect(described_class.new(account: account).skip_lead!(ana.id)).to eq(error: 'Esse lead já recebeu a mensagem.')
    expect(lead_of(ana)['skipped']).to be(false)
    expect(described_class.new(account: account).skip_lead!(bia.id)).to eq(ok: true)
    expect(described_class.new(account: account).results['stats']).to include('sent' => 1, 'skipped' => 1, 'pending' => 1)
  end

  it '"Pausar" no meio do lote segura o resto das mensagens', :aggregate_failures do
    stub_sending do |contact|
      described_class.new(account: account).pause! if contact == ana
      instance_double(Conversation, display_id: 1)
    end

    result = described_class.new(account: account).send_batch!

    expect(result).to include(ok: true, sent: 1, done: false)
    expect(sent_ids).to eq([ana.id])
    expect(lead_of(bia)).to include('sent_at' => nil, 'skipped' => false)
    expect(settings.reload.ai_config.dig('harvest_state', 'status')).to eq('paused')
  end

  it 'conta à parte o lead reservado sem conversa (Sidekiq caiu entre a reserva e o envio)' do
    stub_sending
    described_class.new(account: account).send_batch!(max_now: 1)
    described_class.new(account: account).send(:update_lead!, bia.id) { |l| l['sent_at'] = Time.current.iso8601 }

    expect(described_class.new(account: account).results['stats']).to include('sent' => 2, 'sem_conversa' => 1, 'pending' => 1)
  end

  # 🛡️ Rodada 6 (#256): o Sidekiq morto NO MEIO do lote (deploy, falta de
  # memória) — Sidekiq::Shutdown não é StandardError, nenhum rescue segura.
  # Quem já recebeu fica gravado; o lead da vez fica reservado sem conversa
  # (a equipe decide à mão) e a rodada seguinte não reenvia para ninguém.
  it 'retomada após interrupção no meio do lote: ninguém recebe duas vezes', :aggregate_failures do
    stub_sending do |contact|
      raise Sidekiq::Shutdown if contact == caio

      instance_double(Conversation, display_id: 100 + contact.id)
    end

    expect { described_class.new(account: account).send_batch! }.to raise_error(Sidekiq::Shutdown)

    expect(lead_of(ana)).to include('conversation_id' => 100 + ana.id)
    expect(lead_of(bia)).to include('conversation_id' => 100 + bia.id)
    expect([lead_of(ana), lead_of(bia)].pluck('sent_at')).to all(be_present)
    expect(lead_of(caio)['sent_at']).to be_present # reservado antes de o processo cair
    expect(lead_of(caio)['conversation_id']).to be_nil

    # rodada seguinte (cron da próxima hora): nada sai de novo
    stub_sending
    expect(described_class.new(account: account).send_batch!).to include(ok: true, sent: 0, done: true)
    expect(sent_ids).to eq([ana.id, bia.id, caio.id])
    expect(described_class.new(account: account).results['stats']).to include('sent' => 3, 'sem_conversa' => 1, 'pending' => 0)
  end

  context 'with o teto diário (anti-bloqueio do WhatsApp)' do
    let(:harvest_cfg) { super().merge('daily_cap' => 5) }
    let(:leads) do
      Array.new(7) { |i| create(:contact, account: account, name: "Lead #{i}", phone_number: "+55119333300#{i}") }
    end
    let(:harvest_state) do
      super().tap do |state|
        # 4 já saíram HOJE, 1 saiu anteontem (não conta no teto de hoje), 2 pendentes
        state['selected'].first(4).each { |l| l.merge!('sent_at' => Time.current.iso8601, 'conversation_id' => 1) }
        state['selected'][4].merge!('sent_at' => 2.days.ago.iso8601, 'conversation_id' => 2)
      end
    end

    it 'só manda o que falta para o teto do dia; depois disso, a rodada pula', :aggregate_failures do
      stub_sending

      expect(described_class.new(account: account).send_batch!).to include(ok: true, sent: 1, done: false)
      expect(sent_ids).to eq([leads[5].id])

      expect(described_class.new(account: account).send_batch!).to eq(skipped: 'teto diário')
      expect(sent_ids).to eq([leads[5].id])
      expect(lead_of(leads[6])['sent_at']).to be_nil
    end
  end

  describe 'prévia da colheita (generate_preview!)' do
    let(:stage) do
      Crm::Pipeline.create!(account: account, name: 'CEVICO', position: 0)
                   .stages.create!(name: 'Orçamento enviado', color: '#000', position: 0)
    end
    let(:leads) { [] }

    before do
      Rails.cache.clear
      ai = settings.ai_config.merge('api_key' => 'sk-teste').except('harvest_state')
      settings.update!(ai_config: ai)
    end

    def cold_lead(name, phone, **attrs)
      create(:contact, account: account, name: name, phone_number: phone, last_activity_at: 90.days.ago, **attrs).tap do |c|
        Crm::Contact.create!(contact: c, pipeline: stage.pipeline, stage: stage, value: 5000)
      end
    end

    # a IA não é chamada nos testes: a pontuação fica a de reserva (heurística)
    def preview_service
      described_class.new(account: account).tap { |s| allow(s).to receive(:score_pool) { |pool| pool } }
    end

    def selected_ids
      settings.reload.ai_config.dig('harvest_state', 'selected').pluck('contact_id')
    end

    it 'paciente de parceiro, quem pediu para não ser contatado e quem já foi colhido ficam fora', :aggregate_failures do
      frio = cold_lead('Frio', '+5511944440001')
      # veio PRIMEIRO pelo parceiro (card no funil dos parceiros antes do card da CEVICO — regra B)
      partners = Crm::Pipeline.create!(account: account, name: 'OFTALMOFÁCIL', position: 1)
      partner_stage = partners.stages.create!(name: 'Cirurgia Agendada', color: '#000', position: 0)
      settings.update!(agenda_config: { 'oftalmofacil' => { 'partner_pipeline_id' => partners.id } })
      parceiro = create(:contact, account: account, name: 'Parceiro', phone_number: '+5511944440002', last_activity_at: 90.days.ago,
                                  additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' })
      Crm::Contact.create!(contact: parceiro, pipeline: partners, stage: partner_stage, created_at: 10.days.ago)
      # 🧭 item 341: hoje a cerca do ambiente não deixaria esse card nascer — passe livre para montar o cenário
      Crm::CardRouter.bypass('carga') { Crm::Contact.create!(contact: parceiro, pipeline: stage.pipeline, stage: stage, value: 9000) }
      cold_lead('Quieto', '+5511944440003').add_labels(['nao_perturbe'])
      cold_lead('Colhido', '+5511944440004').add_labels(['colheita_2026_09'])

      expect(preview_service.generate_preview!).to include(ok: true, planned: 1)
      expect(selected_ids).to eq([frio.id])
    end

    it 'gerar a prévia duas vezes abre UMA tarefa de aprovação; o cron do mesmo mês não regera', :aggregate_failures do
      cold_lead('Frio', '+5511944440001')

      preview_service.generate_preview!
      preview_service.generate_preview!
      expect(account.tasks.where('title LIKE ?', '🌾 Colheita%').count).to eq(1)

      service = preview_service
      allow(service).to receive(:generate_preview!)
      Crm::HarvestJob.new.send(:maybe_generate, service, { 'day_of_month' => 1 })
      expect(service).not_to have_received(:generate_preview!)
    end

    it 'regerar a prévia depois do envio não traz de volta quem já recebeu nem apaga o "enviado"', :aggregate_failures do
      frio = cold_lead('Frio', '+5511944440001')
      preview_service.generate_preview!
      described_class.new(account: account).approve!(nil)
      stub_sending
      described_class.new(account: account).send_batch!
      expect(sent_ids).to eq([frio.id])

      expect(preview_service.generate_preview!).to eq(error: 'Nenhum lead frio elegível encontrado.')
      state = settings.reload.ai_config['harvest_state']
      expect(state['status']).to eq('done')
      expect(state['selected'].first['sent_at']).to be_present
    end

    # revisão da Rodada 6: o caso que o teste acima não pega — o lead foi
    # reservado (sent_at), mas o Sidekiq caiu antes da conversa e da etiqueta.
    # Sem a etiqueta ele voltaria na busca; a prévia nova não pode trazê-lo
    # de volta como pendente.
    it 'regerar a prévia no mesmo mês mantém quem ficou reservado sem conversa e sem etiqueta', :aggregate_failures do
      frio = cold_lead('Frio', '+5511944440001')
      morno = cold_lead('Morno', '+5511944440002')
      preview_service.generate_preview!
      described_class.new(account: account).approve!(nil)
      # reserva feita, mensagem não saiu: sem conversa, sem etiqueta colheita_AAAA_MM
      described_class.new(account: account).send(:update_lead!, frio.id) { |l| l['sent_at'] = Time.current.iso8601 }
      described_class.new(account: account).send(:update_lead!, morno.id) { |l| l['skipped'] = true }
      novo = cold_lead('Novo', '+5511944440003')

      expect(preview_service.generate_preview!).to include(ok: true, planned: 1)
      state = settings.reload.ai_config['harvest_state']
      expect(state['status']).to eq('preview')
      expect(selected_ids).to contain_exactly(frio.id, morno.id, novo.id)
      expect(state['selected'].find { |l| l['contact_id'] == frio.id }['sent_at']).to be_present
      expect(state['selected'].find { |l| l['contact_id'] == morno.id }['skipped']).to be(true)

      described_class.new(account: account).approve!(nil)
      stub_sending
      described_class.new(account: account).send_batch!
      expect(sent_ids).to eq([novo.id])
    end

    it 'a tarefa de aprovação é uma por mês, mesmo que a prévia nova tenha outro número de leads', :aggregate_failures do
      cold_lead('Frio', '+5511944440001')
      preview_service.generate_preview!
      cold_lead('Morno', '+5511944440002')
      preview_service.generate_preview!

      tasks = account.tasks.where('title LIKE ?', '🌾 Colheita%')
      expect(tasks.count).to eq(1)
      expect(tasks.first.title).to include('2 leads')
    end
  end

  context 'when no modo organizar (só etiqueta, sem mensagem)' do
    let(:harvest_cfg) { super().merge('mode' => 'organize') }

    it 'grava lead a lead: o "pular" feito pelo admin durante a etiquetagem vale', :aggregate_failures do
      allow(account.contacts).to receive(:find_by).and_call_original
      allow(account.contacts).to receive(:find_by).with(id: ana.id) do
        described_class.new(account: account).skip_lead!(bia.id) # admin pula a Bia enquanto a Ana é etiquetada
        ana
      end

      result = described_class.new(account: account).send_batch!

      expect(result).to include(ok: true, organized: 2, done: true)
      expect(lead_of(bia)).to include('skipped' => true, 'sent_at' => nil)
      expect(lead_of(ana)['sent_at']).to be_present
      expect(lead_of(caio)['sent_at']).to be_present
      expect(ana.reload.label_list).to include("oportunidade_#{month_key.tr('-', '_')}")
      expect(bia.reload.label_list).to be_empty
      expect(settings.reload.ai_config.dig('harvest_state', 'status')).to eq('done')
    end
  end
end
