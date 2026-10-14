require 'rails_helper'
require 'prism'

RSpec.describe CrmAutomationFireJob do
  # action_type permitido no modelo => método privado do job que executa a ação
  let(:handlers) do
    {
      'webhook' => :fire_webhook,
      'n8n_flow' => :fire_n8n,
      'apply_label' => :apply_label,
      'move_card' => :move_card,
      'log_timeline' => :log_timeline,
      'notify_team' => :notify_team,
      'meta_ads_event' => :fire_meta_ads,
      'google_ads_conversion' => :fire_google_ads,
      'send_form' => :send_form,
      'ai_analyze' => :ai_analyze,
      'schedule_appointment' => :schedule_appointment,
      'set_value' => :set_value,
      'send_template' => :send_template,
      'closing_extract' => :closing_extract,
      'nps_score' => :nps_score
    }
  end

  # Lê o `case automation.action_type` do #perform direto do fonte, para que
  # um tipo despachado pelo job sem constar em Crm::Automation::ACTION_TYPES
  # (ou vice-versa) quebre aqui — e não como 422 na tela de automações.
  def dispatched_action_types
    source = Rails.root.join('app/jobs/crm_automation_fire_job.rb').read
    case_node = find_action_type_case(Prism.parse(source).value)
    raise 'case automation.action_type não encontrado em CrmAutomationFireJob#perform' unless case_node

    case_node.conditions.flat_map { |when_node| when_node.conditions.map(&:unescaped) }
  end

  def find_action_type_case(node)
    return node if action_type_case?(node)

    node.compact_child_nodes.each do |child|
      found = find_action_type_case(child)
      return found if found
    end
    nil
  end

  def action_type_case?(node)
    node.is_a?(Prism::CaseNode) &&
      node.predicate.is_a?(Prism::CallNode) &&
      node.predicate.name == :action_type &&
      node.predicate.receiver&.slice == 'automation'
  end

  describe 'dispatch table' do
    it 'dispatches exactly the action types the model allows' do
      expect(dispatched_action_types).to match_array(Crm::Automation::ACTION_TYPES)
    end

    it 'maps a handler in this spec for every allowed action type' do
      expect(handlers.keys).to match_array(Crm::Automation::ACTION_TYPES)
    end
  end

  describe '#perform' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
    let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Coluna') }
    let(:job) { described_class.new }

    def create_automation(action_type, attrs = {})
      stage.automations.create!({ name: "Automação #{action_type}", trigger_type: 'card_entered',
                                  action_type: action_type, delay_minutes: 0, action_config: {} }.merge(attrs))
    end

    Crm::Automation::ACTION_TYPES.each do |action_type|
      it "runs the #{action_type} handler and logs the firing" do
        automation = create_automation(action_type)
        handler = handlers.fetch(action_type)
        allow(job).to receive(handler)

        job.perform(automation.id, contact.id)

        expect(job).to have_received(handler)
        log = Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id)
        expect(log&.status).to eq('fired')
      end
    end

    it 'passes the contact and the pipeline to closing_extract' do
      automation = create_automation('closing_extract')
      allow(job).to receive(:closing_extract)

      job.perform(automation.id, contact.id)

      expect(job).to have_received(:closing_extract).with(contact, pipeline)
    end

    it 'passes the contact to nps_score' do
      automation = create_automation('nps_score')
      allow(job).to receive(:nps_score)

      job.perform(automation.id, contact.id)

      expect(job).to have_received(:nps_score).with(contact)
    end

    # item 313 ---------------------------------------------------------------
    it 'sends the closing event with the card value and the procedure inside it' do
      Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, value: 5700)
      contact.update!(additional_attributes: { 'page_ads' => { 'slug' => 'refrativa' } })
      contact.add_labels(['refrativa'])
      automation = create_automation('google_ads_conversion',
                                     action_config: { 'ga4_event_name' => 'fechou_cirurgia', 'required_label' => 'Refrativa' })
      service = instance_double(GoogleAdsConversionsService, call: { success: true })
      allow(GoogleAdsConversionsService).to receive(:new).and_return(service)

      job.perform(automation.id, contact.id)

      expect(GoogleAdsConversionsService).to have_received(:new).with(
        hash_including(event_name: 'fechou_cirurgia',
                       params: { procedimento: 'refrativa', cevico_page: 'refrativa', value: 5700.0, currency: 'BRL' })
      )
    end

    it 'sends only value and currency to Meta on a closing (o procedimento não sai junto com o telefone)' do
      Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, value: 5700)
      contact.add_labels(['refrativa'])
      automation = create_automation('meta_ads_event', action_config: { 'meta_event_name' => 'Purchase', 'required_label' => 'refrativa' })
      service = instance_double(MetaAdsConversionsService, call: { success: true })
      allow(MetaAdsConversionsService).to receive(:new).and_return(service)

      job.perform(automation.id, contact.id)

      expect(MetaAdsConversionsService).to have_received(:new)
        .with(hash_including(event_name: 'Purchase', custom_data: { value: 5700.0, currency: 'BRL' }))
    end

    it 'does not send the card value on events that are not a closing' do
      Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, value: 5700)
      automation = create_automation('meta_ads_event', action_config: { 'meta_event_name' => 'Lead' })
      service = instance_double(MetaAdsConversionsService, call: { success: true })
      allow(MetaAdsConversionsService).to receive(:new).and_return(service)

      job.perform(automation.id, contact.id)

      expect(MetaAdsConversionsService).to have_received(:new).with(hash_including(event_name: 'Lead', custom_data: {}))
    end

    it 'logs the automation as failed when the platform refuses the event' do
      automation = create_automation('meta_ads_event', action_config: { 'meta_event_name' => 'Lead' })
      service = instance_double(MetaAdsConversionsService, call: { success: false, error: 'token vencido' })
      allow(MetaAdsConversionsService).to receive(:new).and_return(service)

      job.perform(automation.id, contact.id)

      log = Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id)
      expect(log.status).to eq('failed')
      expect(log.error_message).to include('token vencido')
    end

    # item 345 -------------------------------------------------------------
    describe 'conversão uma vez por paciente a cada 7 dias' do
      let(:service) { instance_double(GoogleAdsConversionsService, call: { success: true }) }

      before { allow(GoogleAdsConversionsService).to receive(:new).and_return(service) }

      it 'o card que sai e volta para a coluna não manda a mesma conversão de novo' do
        automation = create_automation('google_ads_conversion', action_config: { 'ga4_event_name' => 'agendou_consulta' })
        job.perform(automation.id, contact.id)
        Redis::LockManager.new.unlock("CRM_CONVERSION_ONCE::#{automation.id}::#{contact.id}")

        described_class.new.perform(automation.id, contact.id)

        expect(GoogleAdsConversionsService).to have_received(:new).once
        skipped = Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id, status: 'cancelled')
        expect(skipped.error_message).to include('não repete em 7 dias')
      end

      it 'depois de 7 dias a conversão sai de novo (ex.: cirurgia do 2º olho)' do
        automation = create_automation('google_ads_conversion', action_config: { 'ga4_event_name' => 'fechou_cirurgia' })
        Crm::AutomationLog.create!(automation: automation, contact_id: contact.id, status: 'fired', payload: {}, created_at: 8.days.ago)

        job.perform(automation.id, contact.id)

        expect(GoogleAdsConversionsService).to have_received(:new).once
      end

      it 'uma tentativa que FALHOU não segura a próxima' do
        automation = create_automation('google_ads_conversion', action_config: { 'ga4_event_name' => 'agendou_consulta' })
        Crm::AutomationLog.create!(automation: automation, contact_id: contact.id, status: 'failed', payload: {})

        job.perform(automation.id, contact.id)

        expect(GoogleAdsConversionsService).to have_received(:new).once
      end

      it 'outras ações (mensagem, mover…) seguem disparando a cada entrada' do
        automation = create_automation('nps_score')
        allow(job).to receive(:nps_score)
        Crm::AutomationLog.create!(automation: automation, contact_id: contact.id, status: 'fired', payload: {})

        job.perform(automation.id, contact.id)

        expect(job).to have_received(:nps_score)
      end
    end

    describe 'valor da conversão na coluna de agendamento' do
      let(:booking) { Crm::Stage.create!(pipeline: pipeline, name: 'Agendamento de Consulta') }
      let(:service) { instance_double(GoogleAdsConversionsService, call: { success: true }) }

      before { allow(GoogleAdsConversionsService).to receive(:new).and_return(service) }

      it 'sem valor digitado, leva o valor da consulta marcada (o mesmo da confirmação)' do
        booking
        account.tasks.create!(title: 'Consulta: Paciente', task_type: 'consulta', contact: contact, creator: create(:user, account: account),
                              due_at: 2.days.from_now, procedure: 'CONSULTA | JÁ PAC | R$350')
        automation = booking.automations.create!(name: 'Conversão Google (Consulta)', trigger_type: 'card_entered',
                                                 action_type: 'google_ads_conversion', delay_minutes: 0,
                                                 action_config: { 'ga4_event_name' => 'agendou_consulta' })

        job.perform(automation.id, contact.id)

        expect(GoogleAdsConversionsService).to have_received(:new).with(hash_including(params: hash_including(value: 350.0)))
      end

      it 'valor digitado na automação continua valendo' do
        automation = booking.automations.create!(name: 'Conversão Google (Consulta)', trigger_type: 'card_entered',
                                                 action_type: 'google_ads_conversion', delay_minutes: 0,
                                                 action_config: { 'ga4_event_name' => 'agendou_consulta', 'conversion_value' => '150' })

        job.perform(automation.id, contact.id)

        expect(GoogleAdsConversionsService).to have_received(:new).with(hash_including(params: hash_including(value: 150.0)))
      end
    end

    it 'does nothing when the automation is inactive' do
      automation = create_automation('nps_score', active: false)
      allow(job).to receive(:nps_score)

      job.perform(automation.id, contact.id)

      expect(job).not_to have_received(:nps_score)
      expect(Crm::AutomationLog.where(automation: automation)).to be_empty
    end

    it 'does nothing for a contact from another account' do
      automation = create_automation('closing_extract')
      other_contact = create(:contact, account: create(:account))
      allow(job).to receive(:closing_extract)

      job.perform(automation.id, other_contact.id)

      expect(job).not_to have_received(:closing_extract)
      expect(Crm::AutomationLog.where(automation: automation)).to be_empty
    end
  end

  # achado #194 da auditoria (07/10): dois jobs da MESMA automação pro MESMO
  # paciente rodando juntos mandavam a mensagem modelo / o formulário 2x,
  # porque a marca "já enviei" só era gravada DEPOIS do envio.
  describe 'achado #194: mensagem modelo e formulário saem só UMA vez' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, phone_number: '+5511999990000') }
    let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil') }
    let(:stage) { Crm::Stage.create!(pipeline: pipeline, name: 'Coluna') }
    let(:job) { described_class.new }
    let(:conversation_double) { instance_double(Conversation) }

    def marca(chave, id)
      contact.reload.additional_attributes&.dig(chave, id.to_s)
    end

    describe 'mensagem modelo (send_template)' do
      let(:automation) do
        stage.automations.create!(name: 'Boas-vindas', trigger_type: 'message_created', action_type: 'send_template', delay_minutes: 0,
                                  action_config: { 'inbox_id' => inbox.id, 'template_params' => { 'name' => 'boas_vindas' } })
      end
      let(:service) { instance_double(Crm::SendTemplateService) }

      before do
        allow(Crm::SendTemplateService).to receive(:new).and_return(service)
      end

      it 'segundo job chegando NO MEIO do envio não manda de novo (reprodução do achado)' do
        allow(service).to receive(:perform) do
          # outro job da mesma automação/paciente rodando enquanto o primeiro ainda envia
          described_class.new.perform(automation.id, contact.id)
          conversation_double
        end

        job.perform(automation.id, contact.id)

        expect(service).to have_received(:perform).once
        expect(marca('cevico_templates_sent', automation.id)).to be_present
      end

      it 'a marca "já enviei" é reservada ANTES de chamar o serviço de envio' do
        marca_na_hora_do_envio = nil
        allow(service).to receive(:perform) do
          marca_na_hora_do_envio = marca('cevico_templates_sent', automation.id)
          conversation_double
        end

        job.perform(automation.id, contact.id)

        expect(marca_na_hora_do_envio).to be_present
      end

      it 'envio que não saiu (serviço devolve nil) devolve a marca — o paciente não fica 7 dias sem receber' do
        marca_na_hora_do_envio = nil
        allow(service).to receive(:perform) do
          marca_na_hora_do_envio = marca('cevico_templates_sent', automation.id)
          nil
        end

        job.perform(automation.id, contact.id)

        expect(marca_na_hora_do_envio).to be_present # reservou antes…
        expect(marca('cevico_templates_sent', automation.id)).to be_nil # …e devolveu
      end

      it 'envio que estourou erro devolve a marca e registra a falha' do
        marca_na_hora_do_envio = nil
        allow(service).to receive(:perform) do
          marca_na_hora_do_envio = marca('cevico_templates_sent', automation.id)
          raise 'Meta fora do ar'
        end

        job.perform(automation.id, contact.id)

        expect(marca_na_hora_do_envio).to be_present
        expect(marca('cevico_templates_sent', automation.id)).to be_nil
        expect(Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id).status).to eq('failed')
      end

      describe 'marca "já enfileirado" do listener (freio do gatilho Mensagem criada)' do
        let(:chave_fila) { described_class.queued_key(automation.id, contact.id) }

        before { Redis::LockManager.new.lock(chave_fila, 600) }

        after { Redis::LockManager.new.unlock(chave_fila) }

        it 'some quando o job termina com envio — o log de disparo assume o freio' do
          allow(service).to receive(:perform).and_return(conversation_double)

          job.perform(automation.id, contact.id)

          expect(Redis::LockManager.new.locked?(chave_fila)).to be(false)
          expect(Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id).fired_at).to be_present
        end

        it 'some também quando o envio falhou — a próxima mensagem do paciente tenta de novo' do
          allow(service).to receive(:perform).and_raise('Meta fora do ar')

          job.perform(automation.id, contact.id)

          expect(Redis::LockManager.new.locked?(chave_fila)).to be(false)
        end
      end

      it 'com marca recente (dentro de 7 dias) não envia' do
        contact.update!(additional_attributes: { 'cevico_templates_sent' => { automation.id.to_s => 2.days.ago.iso8601 } })
        allow(service).to receive(:perform).and_return(conversation_double)

        job.perform(automation.id, contact.id)

        expect(service).not_to have_received(:perform)
      end

      it 'com marca velha (mais de 7 dias) envia de novo' do
        contact.update!(additional_attributes: { 'cevico_templates_sent' => { automation.id.to_s => 8.days.ago.iso8601 } })
        allow(service).to receive(:perform).and_return(conversation_double)

        job.perform(automation.id, contact.id)

        expect(service).to have_received(:perform).once
      end

      it 'trava no Redis já tomada por outro job → pula sem enviar e sem gravar marca' do
        allow(service).to receive(:perform).and_return(conversation_double)
        chave = "CRM_AUTOMATION_SEND_LOCK::#{automation.id}::#{contact.id}"
        trava = Redis::LockManager.new
        trava.lock(chave, 30)
        begin
          job.perform(automation.id, contact.id)
        ensure
          trava.unlock(chave)
        end

        expect(service).not_to have_received(:perform)
        expect(marca('cevico_templates_sent', automation.id)).to be_nil
      end

      it 'solta a trava do Redis ao terminar' do
        allow(service).to receive(:perform).and_return(conversation_double)

        job.perform(automation.id, contact.id)

        expect(Redis::LockManager.new.locked?("CRM_AUTOMATION_SEND_LOCK::#{automation.id}::#{contact.id}")).to be(false)
      end
    end

    # 🔐 Rodada 4 (#119): card que nasceu do formulário público sem o paciente
    # nunca ter escrito → nada que fale com ele (mensagem modelo paga para um
    # número que um estranho digitou); ações internas continuam
    describe 'achado #119: card de formulário sem conversa do paciente' do
      let(:automation) do
        stage.automations.create!(name: 'Card parado', trigger_type: 'card_stalled', action_type: 'send_template', delay_minutes: 60,
                                  action_config: { 'inbox_id' => inbox.id, 'template_params' => { 'name' => 'vamos_agendar' } })
      end
      let(:service) { instance_double(Crm::SendTemplateService, perform: conversation_double) }

      before do
        allow(Crm::SendTemplateService).to receive(:new).and_return(service)
        Crm::Contact.create!(contact: contact, pipeline: pipeline, stage: stage, origin: 'formulario')
      end

      it 'não manda a mensagem modelo, não grava marca nem disparo — e o pulo aparece no log (1 por dia)' do
        2.times { job.perform(automation.id, contact.id, { event_type: 'card_stalled' }) }

        expect(Crm::SendTemplateService).not_to have_received(:new)
        expect(marca('cevico_templates_sent', automation.id)).to be_nil
        expect(Crm::AutomationLog.where(automation: automation, status: 'fired')).to be_empty
        pulos = Crm::AutomationLog.where(automation: automation, contact_id: contact.id, status: 'cancelled')
        expect(pulos.count).to eq(1)
        expect(pulos.first.error_message).to include('formulário público', 'nunca escreveu')
      end

      it 'depois que o paciente escreve para a clínica, o envio volta a valer' do
        conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'oi')

        job.perform(automation.id, contact.id, { event_type: 'card_stalled' })

        expect(service).to have_received(:perform).once
      end

      it 'ação interna (etiqueta) continua rodando para o card anônimo' do
        etiqueta = stage.automations.create!(name: 'Etiqueta', trigger_type: 'card_stalled', action_type: 'apply_label', delay_minutes: 60,
                                             action_config: { 'label' => 'formulario' })

        job.perform(etiqueta.id, contact.id)

        expect(Crm::AutomationLog.find_by(automation: etiqueta, contact_id: contact.id)&.status).to eq('fired')
      end
    end

    describe 'formulário (send_form)' do
      let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
      let(:form) do
        Crm::Form.create!(account: account, name: 'Pré-operatório', questions: [{ 'id' => 'q1', 'label' => 'Dor?', 'type' => 'yesno' }])
      end
      let(:automation) do
        stage.automations.create!(name: 'Formulário', trigger_type: 'message_created', action_type: 'send_form', delay_minutes: 0,
                                  action_config: { 'form_id' => form.id })
      end

      def mensagens_do_formulario
        conversation.messages.where(message_type: :outgoing).where('content LIKE ?', "%#{form.slug}%")
      end

      it 'segundo job chegando NO MEIO do envio não manda o link de novo (reprodução do achado)' do
        allow(Crm::Form).to receive(:find_by).and_return(form)
        allow(form).to receive(:public_link_for).and_wrap_original do |m, *args|
          described_class.new.perform(automation.id, contact.id)
          m.call(*args)
        end

        job.perform(automation.id, contact.id)

        expect(mensagens_do_formulario.count).to eq(1)
        expect(form.reload.sent_count).to eq(1)
        expect(marca('cevico_forms_sent', form.id)).to be_present
      end

      it 'erro ao montar/mandar o link devolve a marca e registra a falha' do
        marca_na_hora_do_envio = nil
        allow(Crm::Form).to receive(:find_by).and_return(form)
        allow(form).to receive(:public_link_for) do
          marca_na_hora_do_envio = marca('cevico_forms_sent', form.id)
          raise 'deu ruim'
        end

        job.perform(automation.id, contact.id)

        expect(marca_na_hora_do_envio).to be_present # reservou antes…
        expect(mensagens_do_formulario.count).to eq(0)
        expect(marca('cevico_forms_sent', form.id)).to be_nil # …e devolveu
        expect(Crm::AutomationLog.find_by(automation: automation, contact_id: contact.id).status).to eq('failed')
      end

      it 'manda o link ASSINADO do paciente (a resposta já nasce confirmada, sem código)' do
        job.perform(automation.id, contact.id)

        msg = mensagens_do_formulario.last
        token = CGI.unescape(msg.content[%r{/forms/#{form.slug}/(\S+)}, 1].to_s)
        expect(Crm::Form.verify_token(token)).to include(form_id: form.id, contact_id: contact.id)
      end

      it 'com marca recente não manda o link de novo' do
        contact.update!(additional_attributes: { 'cevico_forms_sent' => { form.id.to_s => 1.day.ago.iso8601 } })

        job.perform(automation.id, contact.id)

        expect(mensagens_do_formulario.count).to eq(0)
      end

      # 🔐 achado #118: resposta "não confirmada" (link limpo em cadastro existente)
      describe 'resposta não confirmada do link limpo' do
        let(:marca_nao_confirmada) { Crm::FormResponse.unverified_meta(informed_name: 'Alguém') }

        def resposta_nao_confirmada(quando)
          form.responses.create!(account: account, contact_id: contact.id, completed_at: quando,
                                 answers: [{ 'id' => 'q1', 'label' => 'Dor?', 'type' => 'yesno', 'value' => 'sim' }, marca_nao_confirmada])
        end

        it 'resposta anônima SEM link enviado antes não cala a automação: o paciente de verdade recebe o link' do
          resposta_nao_confirmada(1.hour.ago)

          job.perform(automation.id, contact.id)

          expect(mensagens_do_formulario.count).to eq(1)
        end

        it 'resposta que chegou DEPOIS de o link ter sido enviado conta como "já respondeu"' do
          contact.update!(additional_attributes: { 'cevico_forms_sent' => { form.id.to_s => 10.days.ago.iso8601 } })
          resposta_nao_confirmada(9.days.ago)

          job.perform(automation.id, contact.id)

          expect(mensagens_do_formulario.count).to eq(0)
        end

        it 'resposta confirmada (link assinado) continua contando como "já respondeu"' do
          form.responses.create!(account: account, contact_id: contact.id, completed_at: 1.hour.ago,
                                 answers: [{ 'id' => 'q1', 'label' => 'Dor?', 'type' => 'yesno', 'value' => 'não' }])

          job.perform(automation.id, contact.id)

          expect(mensagens_do_formulario.count).to eq(0)
        end
      end
    end
  end
end
