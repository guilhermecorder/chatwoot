require 'rails_helper'

# 🤖 Item 315 (03/10): robô de follow-up escolhe caixas e colunas em que atua
# + etapa "lembrete com a IA, contextualizado com a conversa"
RSpec.describe Crm::FollowupBotJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:google) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:instagram) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:pipeline) { Crm::Pipeline.create!(account: account, name: 'Funil', position: 1) }
  let(:orcamento) { Crm::Stage.create!(pipeline: pipeline, name: 'Envio de Orçamento', position: 1, color: '#059669') }
  let(:agendado) { Crm::Stage.create!(pipeline: pipeline, name: 'Consulta Agendada', position: 2, color: '#0F5FA6') }
  let(:job) { described_class.new }

  # o robô só envia dentro do horário da conta (08–20h): os testes rodam a qualquer hora
  def round_the_clock(instance)
    allow(instance).to receive(:send_hours).and_return(0...24)
    instance
  end

  # conversa em silêncio: a clínica falou por último há `hours` horas
  def silent_conversation(inbox, name, hours: 30)
    contact = create(:contact, account: account, name: name)
    conv = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :incoming,
                     content: 'Oi, quero saber da cirurgia', created_at: (hours + 1).hours.ago)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing,
                     content: 'Claro! O orçamento da refrativa é R$ 5.000', created_at: hours.hours.ago, sender: admin)
    conv.update!(last_activity_at: hours.hours.ago)
    conv
  end

  def bot_with(attrs = {})
    Crm::FollowupBot.create!({ account: account, name: 'Robô 24h', sender: admin,
                               steps: [{ 'delay_value' => 1, 'delay_unit' => 'hours', 'message' => '[nome], ficou alguma dúvida?' }] }.merge(attrs))
  end

  describe 'caixas e colunas em que o robô atua' do
    it 'sem nada marcado atua em todas as caixas; com caixas marcadas, só nelas', :aggregate_failures do
      g = silent_conversation(google, 'Do Google')
      i = silent_conversation(instagram, 'Do Instagram')

      expect(job.send(:conversations, bot_with).pluck(:id)).to contain_exactly(g.id, i.id)
      expect(job.send(:conversations, bot_with(inbox_ids: [instagram.id])).pluck(:id)).to eq([i.id])
      # inbox_id antigo continua valendo, somado à lista
      expect(job.send(:conversations, bot_with(inbox_id: google.id, inbox_ids: [instagram.id])).pluck(:id)).to contain_exactly(g.id, i.id)
    end

    it 'com colunas marcadas, só quem tem o card numa delas', :aggregate_failures do
      no_orcamento = silent_conversation(google, 'Em Orçamento')
      no_agendado = silent_conversation(google, 'Agendado')
      sem_card = silent_conversation(google, 'Sem Card')
      Crm::Contact.create!(contact: no_orcamento.contact, pipeline: pipeline, stage: orcamento)
      Crm::Contact.create!(contact: no_agendado.contact, pipeline: pipeline, stage: agendado)

      expect(job.send(:conversations, bot_with(stage_ids: [orcamento.id])).pluck(:id)).to eq([no_orcamento.id])
      expect(job.send(:conversations, bot_with).pluck(:id)).to contain_exactly(no_orcamento.id, no_agendado.id, sem_card.id)
    end
  end

  describe 'etapa de IA' do
    let(:ai_step) { { 'delay_value' => 1, 'delay_unit' => 'hours', 'kind' => 'ai', 'ai_instructions' => 'lembrar do orçamento' } }

    it 'é aceita sem texto fixo e tem rótulo próprio', :aggregate_failures do
      bot = bot_with(steps: [ai_step])
      expect(bot).to be_persisted
      expect(job.send(:step_label, ai_step)).to eq('cutucada de 1h (IA)')
      expect(Crm::FollowupBot.new(account: account, name: 'x', steps: [{ 'delay_value' => 1 }])).not_to be_valid
    end

    it 'a IA escreve o texto a partir da conversa e a cutucada sai marcada como IA' do
      conv = silent_conversation(google, 'Maria Clara')
      bot = bot_with(steps: [ai_step])
      ia = instance_double(Crm::FollowupAiNudgeService, call: { text: 'Oi Maria, ficou alguma dúvida sobre o orçamento?' })
      allow(Crm::FollowupAiNudgeService).to receive(:new).and_return(ia)

      content = job.send(:nudge_content, bot, conv, { step: ai_step, index: 0 })[:text]
      expect(content).to eq('Oi Maria, ficou alguma dúvida sobre o orçamento?')
      expect(Crm::FollowupAiNudgeService).to have_received(:new).with(conversation: conv, bot: bot, step: ai_step)

      job.send(:send_nudge, bot, conv, { step: ai_step, index: 0 }, content)
      sent = conv.messages.outgoing.last
      expect(sent.content).to eq(content)
      expect(sent.additional_attributes).to include('cevico_followup_bot_id' => bot.id, 'cevico_followup_ai' => true)
    end

    it 'sem resposta da IA cai no texto de reserva; sem reserva, nada (e diz se foi erro de configuração)', :aggregate_failures do
      conv = silent_conversation(google, 'Joao Pedro')
      ia = instance_double(Crm::FollowupAiNudgeService, call: { error: 'sem chave', config_error: true })
      allow(Crm::FollowupAiNudgeService).to receive(:new).and_return(ia)

      com_reserva = ai_step.merge('message' => '[nome], ficou alguma dúvida?')
      expect(job.send(:nudge_content, bot_with(steps: [com_reserva]), conv,
                      { step: com_reserva, index: 0 })[:text]).to eq('Joao, ficou alguma dúvida?')
      expect(job.send(:nudge_content, bot_with(steps: [ai_step]), conv, { step: ai_step, index: 0 })).to eq(text: nil, config_error: true)
    end

    # varredura 03/10: a etapa é MARCADA antes da IA (duas rodadas sobrepostas não
    # cutucam duas vezes); erro passageiro tenta de novo, erro de chave não
    it 'erro passageiro da IA desmarca a etapa para a próxima rodada (até 3 vezes); erro de chave trata sem envio', :aggregate_failures do
      conv = silent_conversation(google, 'Ana Lima', hours: 2)
      bot = bot_with(steps: [ai_step])
      ia = instance_double(Crm::FollowupAiNudgeService, call: { error: 'timeout' })
      allow(Crm::FollowupAiNudgeService).to receive(:new).and_return(ia)

      round_the_clock(job)
      3.times { job.send(:process_bot, bot) }
      state = conv.reload.additional_attributes.dig('cevico_followup', 'bots', bot.id.to_s)
      expect(state['ai_tries']).to eq('0' => 3)
      expect(state['sent']).to eq([0]) # 3ª tentativa: fica marcada sem envio
      expect(conv.messages.outgoing.where("additional_attributes ->> 'cevico_followup_bot_id' = ?", bot.id.to_s)).to be_empty
      expect(Crm::FollowupAiNudgeService).to have_received(:new).exactly(3).times

      sem_chave = silent_conversation(google, 'Bia Souza', hours: 2)
      allow(ia).to receive(:call).and_return({ error: 'sem chave', config_error: true })
      job.send(:process_bot, bot)
      expect(sem_chave.reload.additional_attributes.dig('cevico_followup', 'bots', bot.id.to_s, 'sent')).to eq([0])
      expect(Crm::FollowupAiNudgeService).to have_received(:new).exactly(4).times # 1 só para a Bia
    end

    it 'respeita o teto de chamadas à IA por rodada (o resto sai na rodada seguinte, sem marcar)' do
      stub_const('Crm::FollowupBotJob::AI_PER_ROUND', 2)
      3.times { |i| silent_conversation(google, "Paciente #{i}", hours: 2) }
      bot = bot_with(steps: [ai_step])
      ia = instance_double(Crm::FollowupAiNudgeService, call: { text: 'Oi! Ficou alguma dúvida?' })
      allow(Crm::FollowupAiNudgeService).to receive(:new).and_return(ia)

      round_the_clock(job).send(:process_bot, bot)
      expect(Crm::FollowupAiNudgeService).to have_received(:new).exactly(2).times
      expect(bot.reload.activity_log.dig('last_run', 'reasons', 'ia_fila')).to eq(1)

      round_the_clock(described_class.new).send(:process_bot, bot)
      expect(Crm::FollowupAiNudgeService).to have_received(:new).exactly(3).times
    end
  end

  # varredura 03/10
  describe 'âncora do silêncio e cadência completa' do
    it 'nota interna não conta como resposta do atendimento (a vez continua sendo da equipe)' do
      conv = silent_conversation(google, 'Carlos', hours: 5)
      create(:message, account: account, inbox: google, conversation: conv, message_type: :incoming, content: 'E o valor?', created_at: 3.hours.ago)
      create(:message, account: account, inbox: google, conversation: conv, message_type: :outgoing, content: 'ligar depois', private: true,
                       created_at: 2.hours.ago, sender: admin)

      expect(job.send(:silence_anchor, conv)).to be_nil
    end

    it 'cadência completa conta só as cutucadas DESTE robô' do
      conv = silent_conversation(google, 'Dani', hours: 2)
      outro = bot_with(name: 'Outro robô')
      bot = bot_with(steps: [{ 'delay_value' => 1, 'delay_unit' => 'hours', 'message' => 'oi?' },
                             { 'delay_value' => 2, 'delay_unit' => 'hours', 'message' => 'oi de novo?' }])
      create(:message, account: account, inbox: google, conversation: conv, message_type: :outgoing, content: 'cutucada de outro',
                       sender: admin, created_at: 50.minutes.ago, additional_attributes: { 'cevico_followup_bot_id' => outro.id })
      create(:message, account: account, inbox: google, conversation: conv, message_type: :outgoing, content: 'cutucada de outro 2',
                       sender: admin, created_at: 40.minutes.ago, additional_attributes: { 'cevico_followup_bot_id' => outro.id })

      plan = job.send(:plan_for, bot, conv, bot.ordered_steps)
      expect(plan[:reason]).not_to eq('trava_cadencia_completa')
    end
  end
end
