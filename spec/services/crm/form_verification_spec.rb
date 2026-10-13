require 'rails_helper'

# 🔐 Rodada 4 da auditoria (achado #119): o formulário do link limpo só grava
# "confirmado" no cadastro certo. Código de 6 dígitos pela conversa em que o
# paciente já fala com a clínica (Redis: 10 min, 5 tentativas), paciente novo
# sem card, teto diário por formulário e robô de coluna que ignora card de
# formulário sem conversa do paciente.
RSpec.describe Crm::FormVerification do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:paciente) { create(:contact, account: account, name: 'Paciente Original', phone_number: '+5511912345678') }
  let!(:pipeline) do
    Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
      p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
      p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 1)
    end
  end
  let(:agendamento) { pipeline.stages.find_by(name: 'Agendamento de Consulta') }
  let(:form) do
    Crm::Form.create!(account: account, name: 'Pré-avaliação', slug: 'pre-avaliacao-codigo', funnel_stats: {}, ai_insight: {},
                      questions: [{ 'id' => 'q1', 'label' => 'Alergias', 'type' => 'text' }])
  end
  let(:resposta) do
    form.responses.create!(account: account, contact_id: paciente.id, completed_at: Time.current,
                           answers: [{ 'id' => 'q1', 'label' => 'Alergias', 'type' => 'text', 'value' => 'nenhuma' },
                                     Crm::FormResponse.unverified_meta(informed_name: 'Fulano')])
  end

  def conversa(contact = paciente, caixa: inbox, escreveu_ha: 1.hour, fone: '5511912345678')
    ci = create(:contact_inbox, contact: contact, inbox: caixa, source_id: fone)
    create(:conversation, account: account, inbox: caixa, contact: contact, contact_inbox: ci).tap do |c|
      create(:message, account: account, inbox: caixa, conversation: c, message_type: :incoming, content: 'oi', created_at: escreveu_ha.ago)
    end
  end

  def saidas(conversation)
    conversation.messages.where(message_type: :outgoing)
  end

  after do
    Redis::Alfred.delete(described_class.code_key(resposta))
    Redis::Alfred.delete(described_class.tries_key(resposta))
    Redis::Alfred.delete(described_class.contact_codes_key(paciente))
  end

  def nova_resposta
    form.responses.create!(account: account, contact_id: paciente.id, completed_at: Time.current,
                           answers: [Crm::FormResponse.unverified_meta(informed_name: 'Fulano')])
  end

  describe '.start!' do
    it 'manda o código de 6 dígitos pela conversa recente e guarda só no Redis (10 min), sem devolver o final do número' do
      c = conversa
      resultado = described_class.start!(resposta)

      expect(resultado).to eq(status: 'sent')
      msg = saidas(c).last
      codigo = msg.content[/\b\d{6}\b/]
      expect(codigo).to be_present
      expect(msg.content).to include('vale 10 minutos', 'ignore', 'não precisa responder aqui')
      expect(msg.additional_attributes['cevico_auto']).to eq('formulario_codigo')
      expect(Redis::Alfred.get(described_class.code_key(resposta))).to eq(codigo)
      expect(Redis::Alfred.ttl(described_class.code_key(resposta))).to be_between(500, 600)
    end

    it 'não manda duas vezes enquanto o código ainda vale (SET NX)' do
      c = conversa
      described_class.start!(resposta)
      expect(described_class.start!(resposta)).to eq(status: 'none', reason: 'ja_enviado')
      expect(saidas(c).count).to eq(1)
    end

    it 'sem conversa em que o paciente escreveu nas últimas 24 h não manda nada (sem modelo pago)' do
      c = conversa(escreveu_ha: 25.hours)
      expect(described_class.start!(resposta)).to eq(status: 'none', reason: 'sem_janela')
      expect(saidas(c)).to be_empty
      expect(Redis::Alfred.get(described_class.code_key(resposta))).to be_nil
    end

    it 'paciente de parceiro (cerca) nunca recebe o código' do
      paciente.update!(additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' })
      c = conversa
      expect(described_class.start!(resposta)).to eq(status: 'none', reason: 'parceiro')
      expect(saidas(c)).to be_empty
    end

    it 'conversa na caixa dos PARCEIROS não serve para o código' do
      CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => { 'partner_inbox_ids' => [inbox.id] } })
      c = conversa
      expect(described_class.start!(resposta)).to eq(status: 'none', reason: 'sem_janela')
      expect(saidas(c)).to be_empty
    end

    it 'resposta do link assinado (confirmada) ou de paciente novo não recebe código' do
      conversa
      confirmada = form.responses.create!(account: account, contact_id: paciente.id, completed_at: Time.current,
                                          answers: [{ 'id' => 'q1', 'label' => 'Alergias', 'type' => 'text', 'value' => 'x' }])
      expect(described_class.start!(confirmada)).to eq(status: 'none', reason: 'sem_marca')

      nova = form.responses.create!(account: account, contact_id: paciente.id, completed_at: Time.current,
                                    answers: [Crm::FormResponse.unverified_meta(via: Crm::FormResponse::VIA_NEW_CONTACT)])
      expect(described_class.start!(nova)).to eq(status: 'none', reason: 'sem_marca')
    end

    # revisão da Rodada 4: cada envio do link limpo cria uma resposta nova —
    # sem limite por paciente, repetir o formulário enchia o WhatsApp dele e
    # somava 5 chutes por código
    it 'no máximo 3 códigos por paciente por hora: 4 envios seguidos geram só 3 mensagens', :aggregate_failures do
      c = conversa
      respostas = Array.new(4) { nova_resposta }

      resultados = respostas.map { |r| described_class.start!(r) }

      expect(resultados.first(3)).to all(eq(status: 'sent'))
      expect(resultados.last).to eq(status: 'none', reason: 'limite_codigos')
      expect(saidas(c).count).to eq(3)
      expect(Redis::Alfred.get(described_class.code_key(respostas.last))).to be_nil
      expect(Redis::Alfred.ttl(described_class.contact_codes_key(paciente))).to be_between(1, 3600)
    ensure
      respostas&.each { |r| Redis::Alfred.delete(described_class.code_key(r)) }
    end

    it 'se a mensagem não sair, libera o Redis para tentar de novo' do
      conversa
      allow(described_class).to receive(:deliver!).and_raise('WhatsApp fora do ar')
      expect(described_class.start!(resposta)).to eq(status: 'none', reason: 'erro')
      expect(Redis::Alfred.get(described_class.code_key(resposta))).to be_nil
    end
  end

  describe '.verify!' do
    let!(:c) { conversa }
    let(:codigo) do
      described_class.start!(resposta)
      saidas(c).last.content[/\b\d{6}\b/]
    end

    it 'código certo confirma a resposta (via codigo), cria o card em Agendamento de Consulta e queima o código', :aggregate_failures do
      expect(described_class.verify!(resposta, codigo)).to eq(ok: true)

      expect(resposta.reload.verified?).to be(true)
      expect(resposta.meta).to include('via' => 'codigo', 'informed_name' => 'Fulano')
      expect(resposta.meta['confirmed_at']).to be_present
      expect(resposta.answer_items.map { |a| a['value'] }).to eq(['nenhuma'])
      card = Crm::Contact.find_by(contact_id: paciente.id, pipeline_id: pipeline.id)
      expect(card.stage_id).to eq(agendamento.id)
      expect(card.origin).to eq('formulario')
      expect(Redis::Alfred.get(described_class.code_key(resposta))).to be_nil
      expect(described_class.verify!(resposta, codigo)).to include(ok: false, error: 'wrong')
    end

    it 'card que já existe no funil não anda de coluna' do
      novos = pipeline.stages.find_by(name: 'Novos Contatos')
      Crm::Contact.create!(contact: paciente, pipeline: pipeline, stage: novos, origin: 'GOOGLE')

      described_class.verify!(resposta, codigo)

      card = Crm::Contact.find_by(contact_id: paciente.id, pipeline_id: pipeline.id)
      expect(card.stage_id).to eq(novos.id)
      expect(card.origin).to eq('GOOGLE')
    end

    it 'código errado conta tentativa; a 5ª errada tranca e o certo não vale mais' do
      codigo
      4.times do |n|
        expect(described_class.verify!(resposta, '000000')).to eq(ok: false, error: 'wrong', remaining: 4 - n)
      end
      expect(described_class.verify!(resposta, '000000')).to eq(ok: false, error: 'locked', remaining: 0)
      expect(described_class.verify!(resposta, codigo)).to eq(ok: false, error: 'locked', remaining: 0)
      expect(resposta.reload.verified?).to be(false)
      expect(Crm::Contact.where(contact_id: paciente.id)).to be_empty
    end

    it 'código vencido (sumiu do Redis) não confirma e responde igual a código errado' do
      codigo
      Redis::Alfred.delete(described_class.code_key(resposta))
      expect(described_class.verify!(resposta, codigo)).to eq(ok: false, error: 'wrong', remaining: 4)
      expect(resposta.reload.verified?).to be(false)
    end

    # LGPD: a página não pode contar quem é paciente com conversa recente
    it 'resposta que nunca recebeu código (telefone novo) responde IGUAL a código errado e também tranca em 5' do
      nova = form.responses.create!(account: account, contact_id: paciente.id, completed_at: Time.current,
                                    answers: [Crm::FormResponse.unverified_meta(via: Crm::FormResponse::VIA_NEW_CONTACT)])
      4.times { |n| expect(described_class.verify!(nova, '123456')).to eq(ok: false, error: 'wrong', remaining: 4 - n) }
      expect(described_class.verify!(nova, '123456')).to eq(ok: false, error: 'locked', remaining: 0)
      expect(nova.reload.verified?).to be(false)
    ensure
      Redis::Alfred.delete(described_class.tries_key(nova)) if nova
    end

    it 'aceita o código digitado com espaços e não aceita tamanho diferente' do
      codigo
      expect(described_class.verify!(resposta, codigo[0, 3])).to include(ok: false, error: 'wrong')
      expect(described_class.verify!(resposta, "#{codigo[0, 3]} #{codigo[3, 3]}")).to eq(ok: true)
    end
  end

  describe '.new_contact_allowed? (teto diário por formulário)' do
    before do
      stub_const('Crm::Form::DAILY_NEW_CONTACTS', 2)
      Redis::Alfred.delete(described_class.cap_key(form))
    end

    after { Redis::Alfred.delete(described_class.cap_key(form)) }

    it 'deixa passar até o teto, recusa depois e abre UMA tarefa 🔴 para o administrador', :aggregate_failures do
      admin = create(:user, account: account, role: :administrator)

      expect(described_class.new_contact_allowed?(form)).to be(true)
      expect(described_class.new_contact_allowed?(form)).to be(true)
      expect(account.tasks.count).to eq(0)

      expect(described_class.new_contact_allowed?(form)).to be(false)
      expect(described_class.new_contact_allowed?(form)).to be(false)

      tarefas = account.tasks.where("title LIKE '%teto diário%'")
      expect(tarefas.count).to eq(1)
      expect(tarefas.first.assignee_id).to eq(admin.id)
      expect(tarefas.first.description).to include(form.public_short_link, 'CEVICO_FORM_DAILY_NEW_CONTACTS')
    end

    it 'o contador é por formulário e some em 1 dia' do
      outro = Crm::Form.create!(account: account, name: 'Outro', funnel_stats: {}, ai_insight: {}, questions: [])
      Redis::Alfred.delete(described_class.cap_key(outro))
      2.times { described_class.new_contact_allowed?(form) }
      expect(described_class.new_contact_allowed?(form)).to be(false)
      expect(described_class.new_contact_allowed?(outro)).to be(true)
      expect(Redis::Alfred.ttl(described_class.cap_key(form))).to be_between(1, 86_400)
    ensure
      Redis::Alfred.delete(described_class.cap_key(outro))
    end

    it 'Redis fora do ar não trava a página (deixa passar e registra no log)' do
      allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError)
      allow(Rails.logger).to receive(:error)
      expect(described_class.new_contact_allowed?(form)).to be(true)
      expect(Rails.logger).to have_received(:error).with(/teto diário/)
    end
  end

  describe '.open_pending_task! (lead do formulário sem conversa)' do
    before { Redis::Alfred.delete(described_class.pending_tasks_key(form)) }
    after { Redis::Alfred.delete(described_class.pending_tasks_key(form)) }

    it 'abre uma tarefa "ligar e confirmar" com o paciente e o telefone, no máximo N por formulário por dia', :aggregate_failures do
      stub_const('Crm::FormVerification::PENDING_TASKS_PER_DAY', 1)
      create(:user, account: account, role: :administrator)
      outro = create(:contact, account: account, name: 'Outro Lead', phone_number: '+5511900001111')

      described_class.open_pending_task!(paciente, form: form)
      described_class.open_pending_task!(outro, form: form)

      tarefas = account.tasks.where(contact_id: [paciente.id, outro.id])
      expect(tarefas.count).to eq(1)
      tarefa = tarefas.first
      expect(tarefa.contact_id).to eq(paciente.id)
      expect(tarefa.phone).to eq(paciente.phone_number)
      expect(tarefa.title).to include('Lead do formulário sem conversa')
      expect(tarefa.description).to include(form.name, 'NÃO foi confirmado')
      expect(tarefa.assignee_id).to be_present
    end
  end

  describe '.release_new_contact_slot!' do
    after { Redis::Alfred.delete(described_class.cap_key(form)) }

    it 'devolve a vaga do teto do dia quando ninguém novo foi criado' do
      Redis::Alfred.delete(described_class.cap_key(form))
      2.times { described_class.new_contact_allowed?(form) }
      described_class.release_new_contact_slot!(form)
      expect(Redis::Alfred.get(described_class.cap_key(form)).to_i).to eq(1)
    end
  end

  describe '.mark_pending!' do
    it 'grava a marca do formulário pendente no paciente novo pelo merge atômico' do
      described_class.mark_pending!(paciente, form: form, response: resposta, informed_name: '  Fulano  ')
      marca = paciente.reload.additional_attributes['cevico_form_pending']
      expect(marca).to include('form_id' => form.id, 'response_id' => resposta.id, 'informed_name' => 'Fulano')
      expect(marca['at']).to be_present
    end
  end

  describe '.anonymous_card?' do
    it 'card de origem formulario cujo paciente nunca escreveu = anônimo; depois que ele escreve, deixa de ser' do
      Crm::Contact.create!(contact: paciente, pipeline: pipeline, stage: agendamento, origin: 'formulario')
      expect(described_class.anonymous_card?(paciente, pipeline)).to be(true)

      conversa(escreveu_ha: 10.days)
      expect(described_class.anonymous_card?(paciente, pipeline)).to be(false)
    end

    it 'card de outra origem nunca é anônimo (mesmo sem conversa)' do
      Crm::Contact.create!(contact: paciente, pipeline: pipeline, stage: agendamento, origin: 'GOOGLE')
      expect(described_class.anonymous_card?(paciente, pipeline)).to be(false)
      expect(described_class.anonymous_card?(nil, pipeline)).to be(false)
    end
  end
end
