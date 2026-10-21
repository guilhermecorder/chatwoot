require 'rails_helper'

# 🔐 Auditoria 10/2026 — achado #118 (paliativo sem migration): o formulário
# público pelo LINK LIMPO (/forms/:slug, sem token) identifica o paciente só
# com nome + WhatsApp digitados. Quando isso cai num cadastro que já existe,
# a resposta nasce "não confirmada" (marca dentro do próprio answers), o
# cadastro não muda, e id/label/type das respostas vêm do banco — do cliente
# só o valor, com limite de tamanho. O link assinado continua confirmado.
RSpec.describe 'Formulário público CEVICO (achado #118)', type: :request do
  let(:account) { create(:account) }
  let(:form) do
    Crm::Form.create!(account: account, name: 'Pré-avaliação', slug: 'pre-avaliacao-teste', funnel_stats: {}, ai_insight: {},
                      questions: [
                        { 'id' => 'q1', 'label' => 'Alergias', 'type' => 'text', 'required' => true },
                        { 'id' => 'q2', 'label' => 'Usa óculos?', 'type' => 'yesno' },
                        { 'id' => 'q3', 'label' => 'Bem-vindo', 'type' => 'message' }
                      ])
  end
  let!(:paciente) { create(:contact, account: account, name: 'Paciente Original', phone_number: '+5511912345678') }
  let(:respostas_do_cliente) do
    [
      { id: 'q1', label: 'Alergias', type: 'text', value: 'nenhuma' },
      { id: 'q2', label: 'Rótulo inventado', type: 'text', value: 'sim' },
      { id: 'zz', label: 'Pergunta que não existe', type: 'text', value: 'dado clínico falso' }
    ]
  end
  let(:ultima_resposta) { Crm::FormResponse.order(:id).last }

  describe 'link limpo (sem token)' do
    it 'resposta que cai em cadastro existente nasce NÃO confirmada e não muda o cadastro' do
      post "/forms/#{form.slug}", params: { identity: { name: 'Fulano Qualquer', phone: '11912345678' }, answers: respostas_do_cliente },
                                  as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ok']).to be(true)
      expect(ultima_resposta.contact_id).to eq(paciente.id)
      expect(ultima_resposta.verified?).to be(false)
      expect(ultima_resposta.meta).to include('via' => 'link_limpo', 'informed_name' => 'Fulano Qualquer')
      expect(paciente.reload.name).to eq('Paciente Original')
    end

    it 'não muda nem o nome em branco de cadastro existente (quem digitou pode não ser o dono do telefone)' do
      paciente.update!(name: '')
      post "/forms/#{form.slug}", params: { identity: { name: 'Fulano Qualquer', phone: '11912345678' }, answers: respostas_do_cliente },
                                  as: :json

      expect(response).to have_http_status(:ok)
      expect(paciente.reload.name).to eq('')
      expect(ultima_resposta.meta['informed_name']).to eq('Fulano Qualquer')
    end

    it 'id/label/type vêm das perguntas do banco; pergunta inventada é descartada' do
      post "/forms/#{form.slug}", params: { identity: { name: 'Fulano', phone: '11912345678' }, answers: respostas_do_cliente }, as: :json

      items = ultima_resposta.answer_items
      expect(items.map { |a| a['id'] }).to eq(%w[q1 q2])
      expect(items.find { |a| a['id'] == 'q2' }).to include('label' => 'Usa óculos?', 'type' => 'yesno', 'value' => 'sim')
      expect(ultima_resposta.answers.to_json).not_to include('dado clínico falso', 'Rótulo inventado')
    end

    # 🔐 Rodada 4 (#119): telefone desconhecido NÃO vira card na coluna de
    # agendamento (nem indicador de etapa) — só o paciente, com marca pendente
    it 'telefone desconhecido cria o paciente com o nome digitado, SEM card, e a resposta fica não confirmada', :aggregate_failures do
      create(:user, account: account, role: :administrator)
      expect do
        post "/forms/#{form.slug}", params: { identity: { name: 'Novo Paciente', phone: '11988887777' }, answers: respostas_do_cliente },
                                    as: :json
      end.to change(Contact, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['verify']).to eq('status' => 'check') # igual a qualquer telefone (LGPD)
      novo = Contact.order(:id).last
      expect(novo.name).to eq('Novo Paciente')
      expect(ultima_resposta.contact_id).to eq(novo.id)
      expect(ultima_resposta.verified?).to be(false)
      expect(ultima_resposta.meta['via']).to eq('cadastro_novo')
      expect(ultima_resposta.answer_items.size).to eq(2)
      expect(Crm::Contact.where(contact_id: novo.id)).to be_empty
      expect(Crm::StageLog.count).to eq(0)
      marca = novo.reload.additional_attributes['cevico_form_pending']
      expect(marca).to include('form_id' => form.id, 'response_id' => ultima_resposta.id, 'informed_name' => 'Novo Paciente')
      # a equipe enxerga o lead sem card: tarefa "ligar e confirmar"
      tarefa = account.tasks.find_by(contact_id: novo.id)
      expect(tarefa.title).to include('Lead do formulário sem conversa')
      expect(tarefa.phone).to eq(novo.phone_number)
    ensure
      Redis::Alfred.delete(Crm::FormVerification.pending_tasks_key(form))
    end

    it 'recusa respostas acima de 32 KB (sem criar cadastro) e corta cada valor em 2000 caracteres' do
      perguntas = (1..20).map { |n| { 'id' => "t#{n}", 'label' => "Texto #{n}", 'type' => 'text' } }
      form.update!(questions: perguntas)
      enormes = perguntas.map { |q| { id: q['id'], value: 'x' * 5000 } }

      # telefone desconhecido + resposta grande demais: nada é gravado, nem o paciente
      expect do
        post "/forms/#{form.slug}", params: { identity: { name: 'Fulano', phone: '11955554444' }, answers: enormes }, as: :json
      end.not_to change(Contact, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('too_large')

      post "/forms/#{form.slug}", params: { identity: { name: 'Fulano', phone: '11912345678' }, answers: enormes.first(3) }, as: :json
      expect(response).to have_http_status(:ok)
      expect(ultima_resposta.answer_items.map { |a| a['value'].length }).to all(eq(2000))
    end
  end

  # 🔐 Rodada 4 da auditoria — achado #119: o link limpo só grava "confirmado"
  # no cadastro certo. Cadastro existente recebe um código pela conversa em
  # que já fala com a clínica; telefone desconhecido não vira card em massa.
  describe 'achado #119: código pelo WhatsApp e formulário em massa' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    end
    let(:inbox) { channel.inbox }
    let!(:pipeline) do
      Crm::Pipeline.create!(account: account, name: 'CEVICO | Jornada do Paciente', position: 0).tap do |p|
        p.stages.create!(name: 'Novos Contatos', color: '#000', position: 0)
        p.stages.create!(name: 'Agendamento de Consulta', color: '#000', position: 1)
      end
    end
    let(:agendamento) { pipeline.stages.find_by(name: 'Agendamento de Consulta') }
    let(:identidade) { { name: 'Fulano Qualquer', phone: '11912345678' } }

    def conversa_recente(contact, escreveu_ha: 1.hour)
      ci = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511912345678')
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci).tap do |c|
        create(:message, account: account, inbox: inbox, conversation: c, message_type: :incoming, content: 'oi',
                         created_at: escreveu_ha.ago)
      end
    end

    def codigo_enviado(conversation)
      msg = conversation.messages.where(message_type: :outgoing).order(:id).last
      msg.content[/\b\d{6}\b/]
    end

    after do
      Redis::Alfred.delete(Crm::FormVerification.code_key(ultima_resposta)) if ultima_resposta
      Redis::Alfred.delete(Crm::FormVerification.contact_codes_key(paciente))
    end

    it 'a página do link limpo traz o card do código e a rota de conferir — nunca um código' do
      get "/forms/#{form.slug}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="step-code"', "/forms/#{form.slug}/verify", 'Pular por agora')
      expect(response.body).not_to include('cevico:form_code')
    end

    it 'cadastro existente com conversa nas últimas 24 h: código pela conversa (nunca na página); acertar confirma e cria o card',
       :aggregate_failures do
      conversa = conversa_recente(paciente)

      post "/forms/#{form.slug}", params: { identity: identidade, answers: respostas_do_cliente }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['verify']).to eq('status' => 'check')
      codigo = codigo_enviado(conversa)
      expect(codigo).to match(/\A\d{6}\z/)
      expect(response.body).not_to include(codigo)
      mensagem = conversa.messages.where(message_type: :outgoing).last
      expect(mensagem.additional_attributes['cevico_auto']).to eq('formulario_codigo')
      expect(ultima_resposta.verified?).to be(false)
      expect(Crm::Contact.where(contact_id: paciente.id)).to be_empty

      post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: '000000' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'wrong', 'remaining' => 4)
      expect(ultima_resposta.reload.verified?).to be(false)

      post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: codigo }, as: :json
      expect(response).to have_http_status(:ok)
      expect(ultima_resposta.reload.verified?).to be(true)
      expect(ultima_resposta.meta).to include('via' => 'codigo', 'informed_name' => 'Fulano Qualquer')
      expect(ultima_resposta.answer_items.map { |a| a['id'] }).to eq(%w[q1 q2])
      card = Crm::Contact.find_by(contact_id: paciente.id, pipeline_id: pipeline.id)
      expect(card.stage_id).to eq(agendamento.id)
      expect(card.origin).to eq('formulario')
      expect(paciente.reload.name).to eq('Paciente Original')

      # código já usado não serve de novo
      post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: codigo }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('wrong')
    end

    it 'cadastro existente SEM conversa nas últimas 24 h: nenhum código, nenhuma mensagem e a resposta fica não confirmada' do
      conversa = conversa_recente(paciente, escreveu_ha: 2.days)

      post "/forms/#{form.slug}", params: { identity: identidade, answers: respostas_do_cliente }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['verify']).to eq('status' => 'check')
      expect(conversa.messages.where(message_type: :outgoing)).to be_empty
      expect(ultima_resposta.verified?).to be(false)
      expect(Crm::Contact.where(contact_id: paciente.id)).to be_empty
    end

    it 'paciente de parceiro (cerca) nunca recebe o código, mesmo com conversa aberta' do
      paciente.update!(additional_attributes: { 'parceiro' => 'CLINICA VISAO NORTE' })
      conversa = conversa_recente(paciente)

      post "/forms/#{form.slug}", params: { identity: identidade, answers: respostas_do_cliente }, as: :json

      expect(response.parsed_body['verify']).to eq('status' => 'check')
      expect(conversa.messages.where(message_type: :outgoing)).to be_empty
      expect(ultima_resposta.verified?).to be(false)
    end

    it 'o código de 5 tentativas: a 5ª errada tranca e nem o código certo passa depois' do
      conversa = conversa_recente(paciente)
      post "/forms/#{form.slug}", params: { identity: identidade, answers: respostas_do_cliente }, as: :json
      codigo = codigo_enviado(conversa)

      4.times do
        post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: '111111' }, as: :json
        expect(response.parsed_body['error']).to eq('wrong')
      end
      post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: '111111' }, as: :json
      expect(response.parsed_body).to include('error' => 'locked', 'remaining' => 0)

      post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: codigo }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(ultima_resposta.reload.verified?).to be(false)
    end

    it 'resposta do link ASSINADO não aceita código (já é confirmada) e resposta de outro formulário também não' do
      token = CGI.unescape(form.public_link_for(paciente).split('/').last)
      post "/forms/#{form.slug}/#{token}", params: { answers: respostas_do_cliente }, as: :json
      expect(response.parsed_body).not_to have_key('verify')

      post "/forms/#{form.slug}/verify", params: { response_id: ultima_resposta.id, code: '123456' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('wrong')
      expect(ultima_resposta.reload.verified?).to be(true)

      post "/forms/#{form.slug}/verify", params: { response_id: 999_999, code: '123456' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'teto diário de cadastros novos: passou do teto não cria paciente, guarda a resposta solta (com o telefone) e abre tarefa 🔴',
       :aggregate_failures do
      stub_const('Crm::Form::DAILY_NEW_CONTACTS', 2)
      Redis::Alfred.delete(Crm::FormVerification.cap_key(form))
      admin = create(:user, account: account, role: :administrator)

      %w[11955550001 11955550002].each do |fone|
        post "/forms/#{form.slug}", params: { identity: { name: 'Pessoa', phone: fone }, answers: respostas_do_cliente }, as: :json
        expect(response).to have_http_status(:ok)
      end

      expect do
        post "/forms/#{form.slug}", params: { identity: { name: 'Pessoa', phone: '11955550003' }, answers: respostas_do_cliente }, as: :json
      end.not_to change(Contact, :count)
      # LGPD: responde igual aos outros casos (um erro só para telefone
      # desconhecido contaria quem é paciente)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['verify']).to eq('status' => 'check')
      expect(Crm::FormResponse.count).to eq(3)
      expect(ultima_resposta.contact_id).to be_nil
      expect(ultima_resposta.verified?).to be(false)
      expect(ultima_resposta.meta).to include('via' => 'cadastro_novo', 'informed_phone' => '11955550003', 'informed_name' => 'Pessoa')

      tarefa = account.tasks.order(:id).last
      expect(tarefa.title).to include('teto diário', form.name)
      expect(tarefa.assignee_id).to eq(admin.id)
      expect(tarefa.priority).to eq('urgent')

      # a 4ª não abre outra tarefa; paciente já cadastrado continua passando
      post "/forms/#{form.slug}", params: { identity: { name: 'Pessoa', phone: '11955550004' }, answers: respostas_do_cliente }, as: :json
      expect(account.tasks.where("title LIKE '%teto diário%'").count).to eq(1)
      post "/forms/#{form.slug}", params: { identity: identidade, answers: respostas_do_cliente }, as: :json
      expect(response).to have_http_status(:ok)
    ensure
      Redis::Alfred.delete(Crm::FormVerification.cap_key(form))
      Redis::Alfred.delete(Crm::FormVerification.pending_tasks_key(form))
    end

    # revisão da Rodada 4 (LGPD): o JSON da página não pode contar se o
    # telefone é de paciente com conversa recente
    it 'a resposta da página é IGUAL para paciente com conversa, paciente sem conversa e telefone desconhecido', :aggregate_failures do
      conversa_recente(paciente)
      sem_conversa = create(:contact, account: account, name: 'Sem Conversa', phone_number: '+5511933334444')

      corpos = [identidade, { name: 'X', phone: sem_conversa.phone_number }, { name: 'Y', phone: '11977776666' }].map do |ident|
        post "/forms/#{form.slug}", params: { identity: ident, answers: respostas_do_cliente }, as: :json
        expect(response).to have_http_status(:ok)
        response.parsed_body.except('id')
      end

      expect(corpos.uniq).to eq([{ 'ok' => true, 'verify' => { 'status' => 'check' } }])
    ensure
      Redis::Alfred.delete(Crm::FormVerification.contact_codes_key(paciente))
      Redis::Alfred.delete(Crm::FormVerification.pending_tasks_key(form))
    end

    it 'no máximo 3 códigos por paciente por hora: 4 envios seguidos do mesmo telefone geram só 3 mensagens' do
      conversa = conversa_recente(paciente)

      4.times do
        post "/forms/#{form.slug}", params: { identity: identidade, answers: respostas_do_cliente }, as: :json
        expect(response.parsed_body['verify']).to eq('status' => 'check')
      end

      expect(conversa.messages.where(message_type: :outgoing).count).to eq(3)
      expect(Crm::FormResponse.where(contact_id: paciente.id).map(&:verified?)).to all(be(false))
    ensure
      Crm::FormResponse.find_each { |r| Redis::Alfred.delete(Crm::FormVerification.code_key(r)) }
      Redis::Alfred.delete(Crm::FormVerification.contact_codes_key(paciente))
    end
  end

  describe 'id reservado da marca' do
    it 'o formulário não aceita pergunta com o id da marca' do
      form.questions << { 'id' => Crm::FormResponse::META_ID, 'label' => 'Truque', 'type' => 'text' }
      expect(form).not_to be_valid
      expect(form.errors[:questions].first).to include('reservado')
    end
  end

  describe 'link assinado (token com o paciente)' do
    it 'continua confirmado e sem marca' do
      token = CGI.unescape(form.public_link_for(paciente).split('/').last)
      post "/forms/#{form.slug}/#{token}", params: { answers: respostas_do_cliente }, as: :json

      expect(response).to have_http_status(:ok)
      expect(ultima_resposta.contact_id).to eq(paciente.id)
      expect(ultima_resposta.verified?).to be(true)
      expect(ultima_resposta.meta).to eq({})
      expect(ultima_resposta.answer_items.map { |a| a['id'] }).to eq(%w[q1 q2])
    end
  end

  describe 'onde a equipe lê as respostas' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let!(:consulta) do
      Task.create!(account: account, creator: admin, assignee: admin, title: 'Consulta: Paciente Original', task_type: 'consulta',
                   contact_id: paciente.id, due_at: 1.day.from_now)
    end

    before do
      post "/forms/#{form.slug}", params: { identity: { name: 'Fulano Qualquer', phone: '11912345678' }, answers: respostas_do_cliente },
                                  as: :json
    end

    it 'a Agenda recebe o selo "não confirmada" e nunca a marca como se fosse resposta' do
      get "/api/v1/accounts/#{account.id}/tasks/agenda_details", params: { ids: consulta.id.to_s },
                                                                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      detail = response.parsed_body.first['form_response']
      expect(detail['verified']).to be(false)
      expect(detail['unverified_count']).to eq(1)
      expect(detail['form']).to include('Pré-avaliação', 'NÃO confirmada')
      expect(detail['answers'].map { |a| a['id'] }).to eq(%w[q1 q2])
    end

    it 'na Agenda a resposta CONFIRMADA (link assinado) ganha da não confirmada mais nova' do
      # o paciente respondeu pelo link assinado ANTES; depois veio a do link limpo (no before)
      form.responses.create!(account: account, contact_id: paciente.id, completed_at: 2.days.ago,
                             answers: [{ 'id' => 'q1', 'label' => 'Alergias', 'type' => 'text', 'value' => 'resposta do paciente' }])

      get "/api/v1/accounts/#{account.id}/tasks/agenda_details", params: { ids: consulta.id.to_s },
                                                                 headers: admin.create_new_auth_token, as: :json

      detail = response.parsed_body.first['form_response']
      expect(detail['verified']).to be(true)
      expect(detail['unverified_count']).to eq(1)
      expect(detail['answers'].first['value']).to eq('resposta do paciente')
      expect(detail['form']).to include('Pré-avaliação', 'não confirmada')
    end

    it 'o Espaço do Paciente recebe verified=false e o nome digitado' do
      get "/api/v1/accounts/#{account.id}/crm/patients/#{paciente.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      evento = response.parsed_body['timeline'].find { |e| e['type'] == 'formulario' }
      expect(evento).to include('verified' => false, 'informed_name' => 'Fulano Qualquer')
      expect(evento['answers'].map { |a| a['id'] }).to eq(%w[q1 q2])
    end

    it 'o Analista de Formulários avisa a IA que a resposta não é confirmada' do
      service = Crm::FormInsightService.new(form: form, responses: form.responses.to_a)
      corpus = service.send(:build_corpus)
      expect(corpus).to include('Resposta 1 (não confirmada')
      expect(corpus).to include('Alergias: nenhuma')
      expect(corpus).not_to include('_cevico')
    end
  end
end
