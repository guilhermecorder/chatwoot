require 'rails_helper'

# 🧠 Follow-up inteligente (13/10): o robô só cutuca quem ficou com a conversa
# ABERTA. Caso real que motivou: Adriano (Instagram) — "Ainda não", a IA se
# despediu e 25 min depois o robô mandou "Oi, pode falar?".
RSpec.describe Crm::FollowupBotJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:job) { described_class.new }
  let(:bot) do
    Crm::FollowupBot.create!(account: account, name: 'Robô', sender: admin,
                             steps: [{ 'delay_value' => 20, 'delay_unit' => 'minutes', 'message' => 'Oi, pode falar?' },
                                     { 'delay_value' => 3, 'delay_unit' => 'hours', 'message' => '[nome], no seu tempo ok?' }])
  end

  before do
    allow(job).to receive(:send_hours).and_return(0...24)
    travel_to Time.zone.parse('2026-10-13 14:00:00 -03:00') # terça-feira
  end

  # conversa: falas em ordem [[:incoming|:outgoing, texto, minutos atrás, attrs]]
  def conversation_with(lines, name: 'Adriano')
    contact = create(:contact, account: account, name: name)
    conv = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)
    lines.each do |type, text, ago, attrs|
      create(:message, account: account, inbox: inbox, conversation: conv, message_type: type, content: text,
                       created_at: ago.minutes.ago, sender: type == :outgoing ? admin : contact,
                       additional_attributes: attrs || {})
    end
    conv.update!(last_activity_at: 1.minute.ago)
    conv
  end

  def adriano(farewell_attrs = {})
    conversation_with([
                        [:incoming, 'Oi', 60],
                        [:outgoing, 'Conseguiu pensar sobre a avaliação?', 59],
                        [:incoming, 'Ainda nao', 40],
                        [:outgoing, 'Sem problemas, Adriano, fico tranquilo em esperar.', 39],
                        [:outgoing, 'Qualquer dia que quiser conversar ou agendar, é só me chamar aqui.', 39, farewell_attrs]
                      ])
  end

  def run_round(conversation)
    run = { status: 'ok', candidates: 1, sent: 0, reasons: Hash.new(0) }
    job.instance_variable_set(:@reads, 0)
    job.send(:process_conversation, bot, conversation, bot.ordered_steps, run, [])
    run
  end

  def nudges(conversation)
    conversation.messages.where("additional_attributes ->> 'cevico_followup_bot_id' IS NOT NULL")
  end

  describe 'regra de frases (reserva sem IA)' do
    it 'lê as situações típicas', :aggregate_failures do
      rule = Crm::FollowupConversationReader
      expect(rule.rule_verdict('Ainda nao', 'Fico tranquilo, é só me chamar aqui')).to eq('adiada')
      expect(rule.rule_verdict('vou pensar e depois te falo', '')).to eq('adiada')
      expect(rule.rule_verdict('não tenho interesse', 'Posso te ajudar?')).to eq('recusou')
      expect(rule.rule_verdict('já fiz em outra clínica', '')).to eq('recusou')
      expect(rule.rule_verdict('Oi, já fiz a cirurgia em outra clínica, obrigado', '')).to eq('recusou')
      expect(rule.rule_verdict('Obrigado!', 'Por nada, boa consulta!')).to eq('encerrada')
      expect(rule.rule_verdict('quero saber o preço', 'O valor é R$ 5.000. Quer agendar a avaliação?')).to eq('aberta')
    end
  end

  describe 'rede de segurança sobre a IA' do
    it 'IA disse "encerrada" mas o paciente adiou: vale "adiada" (garante a reativação)' do
      conv = adriano
      reader = Crm::FollowupConversationReader.new(conversation: conv)
      expect(reader.send(:refine, 'encerrada')).to eq('adiada')
      expect(reader.send(:refine, 'aberta')).to eq('aberta')
    end
  end

  describe 'o caso do Adriano' do
    it 'paciente adiou e a IA se despediu: NÃO cutuca, guarda a leitura e agenda a reativação', :aggregate_failures do
      conv = adriano
      reader = instance_double(Crm::FollowupConversationReader,
                               call: { situacao: 'adiada', motivo: 'paciente disse que ainda não', fonte: 'ia' })
      allow(Crm::FollowupConversationReader).to receive(:new).and_return(reader)

      run = run_round(conv)

      expect(nudges(conv)).to be_empty
      expect(run[:reasons]['conversa_adiada']).to eq(1)
      leitura = conv.reload.additional_attributes['cevico_conversa_leitura']
      expect(leitura['situacao']).to eq('adiada')
      expect(Time.zone.parse(leitura['reativar_em'])).to be_within(1.minute).of(7.days.from_now)

      # rodada seguinte: não lê de novo (uma leitura por silêncio) e segue sem cutucar
      run_round(conv)
      expect(Crm::FollowupConversationReader).to have_received(:new).once
      expect(nudges(conv)).to be_empty
    end

    it 'carimbo de despedida do Atendente vence uma leitura "aberta"' do
      conv = adriano('cevico_encerrou' => true)
      reader = instance_double(Crm::FollowupConversationReader, call: { situacao: 'aberta', motivo: 'x', fonte: 'ia' })
      allow(Crm::FollowupConversationReader).to receive(:new).and_return(reader)

      run_round(conv)

      expect(nudges(conv)).to be_empty
      expect(conv.reload.additional_attributes.dig('cevico_conversa_leitura', 'situacao')).to eq('encerrada')
    end

    it 'sem chave da API, a regra de frases segura a cutucada' do
      conv = adriano
      run_round(conv)
      expect(nudges(conv)).to be_empty
      expect(conv.reload.additional_attributes.dig('cevico_conversa_leitura', 'fonte')).to eq('regra')
    end
  end

  describe 'conversa aberta continua recebendo cutucada' do
    it 'a clínica perguntou e o paciente sumiu: cutuca', :aggregate_failures do
      conv = conversation_with([[:incoming, 'Quanto custa a refrativa?', 50],
                                [:outgoing, 'O valor é R$ 5.000 por olho. Quer agendar a avaliação?', 45]])
      run = run_round(conv)
      expect(run[:sent]).to eq(1)
      expect(nudges(conv).first.content).to eq('Oi, pode falar?')
    end

    it 'a equipe falou de novo depois da leitura: lê outra vez' do
      conv = adriano
      allow(Crm::FollowupConversationReader).to receive(:new).and_call_original
      run_round(conv) # regra: adiada
      create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: admin,
                       content: 'Adriano, abriu uma vaga amanhã às 10h. Quer que eu reserve?', created_at: 30.minutes.ago)
      conv.messages.where(content: 'Ainda nao').update_all(created_at: 31.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      run_round(conv)
      expect(Crm::FollowupConversationReader).to have_received(:new).twice
    end
  end

  describe 'recusa' do
    it 'para e aplica perda_sem_interesse no contato', :aggregate_failures do
      conv = conversation_with([[:incoming, 'não tenho interesse, obrigado', 50],
                                [:outgoing, 'Tudo bem! Se mudar de ideia estamos aqui.', 45]])
      run_round(conv)
      expect(nudges(conv)).to be_empty
      expect(conv.contact.reload.label_list).to include('perda_sem_interesse')
      expect(account.labels.where(title: 'perda_sem_interesse')).to exist
    end
  end

  describe 'lead frio (nunca escreveu)' do
    it 'só 1 cutucada; a 2ª etapa não sai', :aggregate_failures do
      conv = conversation_with([[:outgoing, 'Oi! Vi seu cadastro no site. Quer saber da cirurgia?', 30]], name: 'Frio')
      allow(Crm::FollowupConversationReader).to receive(:new)
        .and_return(instance_double(Crm::FollowupConversationReader, call: { situacao: 'aberta', motivo: 'x', fonte: 'ia' }))

      expect(run_round(conv)[:sent]).to eq(1)
      travel 4.hours
      run = run_round(conv)
      expect(run[:sent]).to eq(0)
      expect(nudges(conv).count).to eq(1)
    end
  end

  describe 'possível bloqueio' do
    it 'cutucada anterior não entregue: o robô para' do
      conv = conversation_with([[:incoming, 'quero saber', 400],
                                [:outgoing, 'Claro! Qual cirurgia te interessa?', 380]])
      conv.update!(additional_attributes: { 'cevico_conversa_leitura' => {
                     'key' => conv.messages.outgoing.last.id, 'situacao' => 'aberta', 'at' => 1.hour.ago.iso8601
                   } })
      create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, content: 'Oi, pode falar?',
                       status: :failed, created_at: 350.minutes.ago,
                       additional_attributes: { 'cevico_followup_bot_id' => bot.id, 'cevico_followup_step' => 0 })
      expect(run_round(conv)[:reasons]['entrega_falhou']).to eq(1)
    end
  end

  describe 'fim de semana' do
    it 'sábado sem fala do paciente no dia: espera a segunda', :aggregate_failures do
      travel_to Time.zone.parse('2026-10-17 11:00:00 -03:00') # sábado
      # paciente escreveu na sexta; a equipe respondeu no sábado de manhã
      conv = conversation_with([[:incoming, 'quero saber', 60 * 20],
                                [:outgoing, 'Claro! Quer agendar?', 30]])
      plan = job.send(:plan_for, bot, conv, bot.ordered_steps)
      expect(plan[:chosen]).to be_nil
      expect(plan[:wait][:due_at].in_time_zone('America/Sao_Paulo').strftime('%a %H')).to eq('Mon 08') # abertura do horário padrão
    end

    it 'sábado com fala do paciente no mesmo dia: cutuca normalmente' do
      travel_to Time.zone.parse('2026-10-17 11:00:00 -03:00')
      conv = conversation_with([[:incoming, 'quero saber', 60],
                                [:outgoing, 'Claro! Quer agendar?', 50]])
      expect(job.send(:plan_for, bot, conv, bot.ordered_steps)[:chosen]).to be_present
    end
  end

  describe 'reativação de quem adiou (mensagem modelo)' do
    let(:whatsapp) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
    let(:template) { { 'name' => 'retomar_conversa', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => {} } }

    def adiada(conv, days_ago: 0)
      conv.update!(additional_attributes: { 'cevico_conversa_leitura' => {
                     'key' => Crm::FollowupClosure.last_clinic(conv).first, 'situacao' => 'adiada',
                     'at' => (7 + days_ago).days.ago.iso8601, 'reativar_em' => days_ago.days.ago.iso8601
                   } })
    end

    def configure(models)
      CrmSetting.find_or_create_by!(account_id: account.id).update!(agenda_config: {
                                                                      'followup_smart' => { 'reativacao' => { 'ativa' => true,
                                                                                                              'modelos' => models } }
                                                                    })
    end

    def wa_conversation
      contact = create(:contact, account: account, name: 'Maria Adiou', phone_number: "+551199#{rand(1_000_000..9_999_999)}")
      conv = create(:conversation, account: account, inbox: whatsapp, contact: contact, status: :resolved)
      create(:message, account: account, inbox: whatsapp, conversation: conv, message_type: :incoming, content: 'vou pensar',
                       created_at: 8.days.ago)
      create(:message, account: account, inbox: whatsapp, conversation: conv, message_type: :outgoing, content: 'Fico à disposição!',
                       created_at: 8.days.ago, sender: admin)
      conv
    end

    it 'envia UMA mensagem modelo pela caixa da conversa e não repete', :aggregate_failures do
      conv = wa_conversation
      adiada(conv)
      configure(whatsapp.id.to_s => { 'message' => 'Oi {{1}}, tudo bem?',
                                      'template_params' => template.merge('processed_params' => { 'body' => { '1' => '[nome]' } }) })

      job.send(:process_reactivations)
      job.send(:process_reactivations)

      sent = conv.messages.where("additional_attributes ->> 'cevico_followup_reativacao' IS NOT NULL")
      expect(sent.count).to eq(1)
      expect(sent.first.content).to eq('Oi Maria, tudo bem?')
      expect(sent.first.additional_attributes['template_params']['name']).to eq('retomar_conversa')
      expect(conv.reload.additional_attributes.dig('cevico_conversa_leitura', 'reativacao')).to eq('enviada')
    end

    it 'paciente voltou a escrever, sem modelo ou passou do prazo: não envia', :aggregate_failures do
      configure({})
      sem_modelo = wa_conversation
      adiada(sem_modelo)
      job.send(:process_reactivations)
      expect(sem_modelo.reload.additional_attributes.dig('cevico_conversa_leitura', 'reativacao')).to eq('sem_modelo')

      configure(whatsapp.id.to_s => { 'message' => 'Oi', 'template_params' => template })
      velha = wa_conversation
      adiada(velha, days_ago: 5)
      job.send(:process_reactivations)
      expect(velha.reload.additional_attributes.dig('cevico_conversa_leitura', 'reativacao')).to eq('perdida')
    end
  end

  describe 'Atendente de IA carimba a despedida' do
    it 'etapa encerramento ou pausar (sem chamar humano) = despedida', :aggregate_failures do
      expect(Crm::ResponderAgentJob.farewell?(etapa: 'encerramento', pausar: false)).to be(true)
      expect(Crm::ResponderAgentJob.farewell?(etapa: 'orcamento', pausar: true)).to be(true)
      expect(Crm::ResponderAgentJob.farewell?(etapa: 'orcamento', pausar: false)).to be(false)
      expect(Crm::ResponderAgentJob.farewell?(etapa: 'encerramento', pausar: true, chamar_humano: true)).to be(false)
    end
  end

  describe 'Resultado do follow-up' do
    it 'conta cutucadas, respostas e conversas seguradas por coluna', :aggregate_failures do
      conv = conversation_with([[:incoming, 'oi', 300], [:outgoing, 'Quer agendar?', 290]])
      create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, content: 'Oi, pode falar?',
                       created_at: 200.minutes.ago, additional_attributes: { 'cevico_followup_bot_id' => bot.id })
      create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming, content: 'oi, posso sim',
                       created_at: 100.minutes.ago)
      adiou = adriano
      Crm::FollowupClosure.save!(adiou, 'key' => 1, 'situacao' => 'adiada', 'at' => Time.current.iso8601)

      total = Crm::FollowupResults.new(account, from: 1.day.ago, to: Time.current).call[:total]
      expect(total[:cutucadas]).to eq(1)
      expect(total[:responderam]).to eq(1)
      expect(total[:seguradas]['adiada']).to eq(1)
    end
  end
end
