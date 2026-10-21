require 'rails_helper'

# 🛡️ Rodada 6 da auditoria — "Rede de segurança" (#261): o robô de follow-up
# (o do incidente de julho — rajadas de 2 em 2 min) só tinha o spec do item
# 315. Aqui ficam as proteções de base, rodando a rodada INTEIRA (perform):
#   · trava da rodada (duas rodadas ao mesmo tempo não cutucam 2×);
#   · etapa marcada não repete; a trava física (mensagens reais) segura
#     mesmo quando o marcador some;
#   · mensagem do paciente zera a cadência;
#   · fora da janela de 24h do WhatsApp, texto simples não sai (só modelo);
#   · paciente de parceiro nunca é cutucado;
#   · dois robôs na mesma conversa guardam cada um o seu estado;
#   · horário de envio 08–20h de São Paulo (com travel_to, sem "neutralizar"
#     o horário como o spec do item 315 faz).
# Item 339 (follow-up inteligente): antes da 1ª cutucada o robô LÊ a conversa;
# aqui a leitura é um dublê que diz "aberta" (a conversa continua viva).
RSpec.describe Crm::FollowupBotJob do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:lock_key) { 'CRM_FOLLOWUP_BOT_JOB_LOCK' }
  let(:reader) { instance_double(Crm::FollowupConversationReader, call: { situacao: 'aberta', motivo: 'perguntou e sumiu', fonte: 'ia' }) }

  before do
    travel_to tz.parse('2026-10-13 14:00') # terça-feira, dentro do horário de envio
    allow(Crm::FollowupConversationReader).to receive(:new).and_return(reader)
  end

  def at(text)
    tz.parse(text)
  end

  def bot_with(steps, **attrs)
    Crm::FollowupBot.create!({ account: account, name: 'Robô', sender: admin, steps: steps }.merge(attrs))
  end

  def text_step(hours, message = '[nome], ficou alguma dúvida?')
    { 'delay_value' => hours, 'delay_unit' => 'hours', 'message' => message }
  end

  # paciente perguntou; a clínica respondeu às `answered` e o paciente sumiu
  def silent_conversation(name, answered:, asked: nil, the_inbox: inbox, contact_attrs: {})
    contact = create(:contact, account: account, name: name, **contact_attrs)
    conv = create(:conversation, account: account, inbox: the_inbox, contact: contact, status: :open)
    incoming!(conv, asked || (at(answered) - 5.minutes))
    create(:message, account: account, inbox: the_inbox, conversation: conv, message_type: :outgoing, sender: admin,
                     content: 'O orçamento da refrativa é R$ 5.000 pelos dois olhos', created_at: at(answered))
    conv.update!(last_activity_at: at(answered))
    conv
  end

  def incoming!(conv, time, text = 'Quero saber da cirurgia')
    create(:message, account: account, inbox: conv.inbox, conversation: conv, message_type: :incoming, sender: conv.contact,
                     content: text, created_at: time)
    conv.update!(last_activity_at: time)
  end

  def nudges(conv, bot = nil)
    scope = conv.messages.outgoing.where("additional_attributes ->> 'cevico_followup_bot_id' IS NOT NULL")
    bot ? scope.where("additional_attributes ->> 'cevico_followup_bot_id' = ?", bot.id.to_s) : scope
  end

  def state_of(conv, bot)
    conv.reload.additional_attributes.dig('cevico_followup', 'bots', bot.id.to_s)
  end

  describe 'trava da rodada' do
    it 'com outra rodada em andamento (trava ocupada) esta não cutuca ninguém; livre, cutuca uma vez só', :aggregate_failures do
      conv = silent_conversation('Maria Clara', answered: '2026-10-13 12:50')
      bot = bot_with([text_step(1)])
      lock_manager = Redis::LockManager.new
      lock_manager.lock(lock_key, 1.minute)

      begin
        described_class.perform_now
        expect(nudges(conv)).to be_empty
        expect(lock_manager.locked?(lock_key)).to be(true) # a trava continua da outra rodada
      ensure
        lock_manager.unlock(lock_key)
      end

      described_class.perform_now
      described_class.perform_now # a rodada seguinte (2 min depois no cron) não repete
      expect(nudges(conv, bot).count).to eq(1)
      expect(nudges(conv, bot).first.content).to eq('Maria, ficou alguma dúvida?')
      expect(lock_manager.locked?(lock_key)).to be(false)
    end
  end

  describe 'etapa marcada não repete' do
    it 'a etapa 1 sai uma vez; horas depois sai a etapa 2 (nunca a 1 de novo)', :aggregate_failures do
      conv = silent_conversation('Joana', answered: '2026-10-13 12:50')
      bot = bot_with([text_step(1, 'primeira'), text_step(3, 'segunda')])

      described_class.perform_now
      expect(state_of(conv, bot)['sent']).to eq([0])

      travel_to at('2026-10-13 15:55')
      described_class.perform_now
      travel_to at('2026-10-13 16:30')
      described_class.perform_now

      expect(nudges(conv, bot).order(:created_at).pluck(:content)).to eq(%w[primeira segunda])
      expect(state_of(conv, bot)['sent']).to eq([0, 1])
    end

    it 'marcador apagado por outro processo: a trava física (mensagens reais) segura a repetição imediata', :aggregate_failures do
      conv = silent_conversation('Bruna', answered: '2026-10-13 12:50')
      bot = bot_with([text_step(1)])
      described_class.perform_now
      expect(nudges(conv, bot).count).to eq(1)

      # o "clobber" de julho: alguém regravou additional_attributes sem o marcador
      conv.reload.update_columns(additional_attributes: {}) # rubocop:disable Rails/SkipsModelValidations
      travel_to at('2026-10-13 14:10')
      described_class.perform_now

      expect(nudges(conv, bot).count).to eq(1) # cadência inteira já saiu nas mensagens
      expect(bot.reload.activity_log.dig('last_run', 'reasons')).to include('trava_cadencia_completa' => 1)
    end
  end

  it 'mensagem do paciente zera a cadência: para na hora e recomeça só no próximo silêncio', :aggregate_failures do
    conv = silent_conversation('Paula', answered: '2026-10-13 12:50')
    bot = bot_with([text_step(1)])
    described_class.perform_now
    expect(nudges(conv, bot).count).to eq(1)

    # a paciente responde: a vez é do atendimento, o robô para
    travel_to at('2026-10-13 14:20')
    incoming!(conv, at('2026-10-13 14:19'), 'Ainda estou pensando no valor')
    described_class.perform_now
    expect(nudges(conv, bot).count).to eq(1)
    expect(bot.reload.activity_log.dig('last_run', 'reasons')).to include('paciente_falou_ultimo' => 1)

    # a clínica responde e a paciente some de novo: cadência NOVA (a etapa 1 vale outra vez)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: admin,
                     content: 'Posso parcelar em 10x', created_at: at('2026-10-13 14:25'))
    travel_to at('2026-10-13 15:30')
    described_class.perform_now

    expect(nudges(conv, bot).count).to eq(2)
    expect(Time.zone.parse(state_of(conv, bot)['anchor'])).to eq(at('2026-10-13 14:25'))
    expect(state_of(conv, bot)['sent']).to eq([0])
  end

  describe 'janela de 24h do WhatsApp' do
    let(:wa_inbox) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false).inbox
    end

    it 'texto simples fora da janela é tratado SEM envio; a etapa de mensagem modelo sai', :aggregate_failures do
      # paciente escreveu há 30 h; a clínica só respondeu há 90 min
      conv = silent_conversation('Renata', answered: '2026-10-13 12:30', asked: at('2026-10-12 08:00'), the_inbox: wa_inbox)
      expect(conv.can_reply?).to be(false)
      texto = bot_with([text_step(1)], name: 'Robô de texto')
      modelo = bot_with([text_step(1, 'Oi [nome], seguimos à disposição').merge('template_params' => {
                                                                                  'name' => 'retomar', 'language' => 'pt_BR',
                                                                                  'processed_params' => { 'body' => { '1' => '[nome]' } }
                                                                                })], name: 'Robô de modelo')
      job = described_class.new

      job.send(:process_bot, texto)
      expect(nudges(conv)).to be_empty
      expect(state_of(conv, texto)['sent']).to eq([0]) # tratada: não tenta de novo a cada 2 min
      expect(texto.reload.activity_log.dig('last_run', 'reasons')).to include('janela_whatsapp' => 1)

      job.send(:process_bot, modelo)
      sent = nudges(conv, modelo).sole
      expect(sent.additional_attributes.dig('template_params', 'name')).to eq('retomar')
      expect(sent.additional_attributes.dig('template_params', 'processed_params', 'body', '1')).to eq('Renata')
    end
  end

  it 'paciente de parceiro nunca é cutucado (cerca dentro do plano, além da lista de conversas)', :aggregate_failures do
    Rails.cache.clear
    conv = silent_conversation('Parceiro', answered: '2026-10-13 12:50', contact_attrs: { additional_attributes: { 'parceiro' => 'CLINICA X' } })
    bot = bot_with([text_step(1)])

    described_class.perform_now

    expect(nudges(conv)).to be_empty
    plan = described_class.new.send(:plan_for, bot, conv, bot.ordered_steps)
    expect(plan[:reason]).to eq('paciente_de_parceiro')
    expect(plan[:chosen]).to be_nil
  end

  it 'dois robôs na mesma conversa: cada um guarda o seu estado e um não apaga o do outro', :aggregate_failures do
    conv = silent_conversation('Carla', answered: '2026-10-13 12:50')
    rapido = bot_with([text_step(1, 'cutucada rápida')], name: 'Robô 1h')
    lento = bot_with([text_step(2, 'cutucada lenta')], name: 'Robô 2h')

    described_class.perform_now
    expect(state_of(conv, rapido)['sent']).to eq([0])
    expect(nudges(conv, lento)).to be_empty # o de 2h ainda espera (nada marcado)

    travel_to at('2026-10-13 15:25')
    described_class.perform_now

    expect(nudges(conv, rapido).pluck(:content)).to eq(['cutucada rápida'])
    expect(nudges(conv, lento).pluck(:content)).to eq(['cutucada lenta'])
    expect(state_of(conv, rapido)['sent']).to eq([0])
    expect(state_of(conv, lento)['sent']).to eq([0])
  end

  it 'horário de envio 08–20h (São Paulo): à noite não sai; na abertura do dia seguinte sai (sem descartar)', :aggregate_failures do
    conv = silent_conversation('Lara', answered: '2026-10-13 19:30')
    bot = bot_with([text_step(1)])

    travel_to at('2026-10-13 21:30')
    described_class.perform_now
    expect(nudges(conv)).to be_empty
    expect(bot.reload.activity_log.dig('last_run', 'status')).to eq('fora_do_expediente')

    travel_to at('2026-10-14 08:05')
    described_class.perform_now
    expect(nudges(conv, bot).count).to eq(1)
  end
end
