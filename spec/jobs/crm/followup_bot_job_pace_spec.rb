require 'rails_helper'

# 🚦 Item 345 (14/10) — "follow-up espaçado". Tudo o que vencia de madrugada
# saía às 08:00 de uma vez pelo mesmo número (parece SPAM para a Meta). Agora:
#   · no máximo N cutucadas a cada M min POR CAIXA (padrão 5 a cada 5),
#     somando todos os robôs e a reativação de quem adiou;
#   · a fila da rodada começa por quem tem a janela de 24h do WhatsApp mais
#     perto de fechar; sem janela aberta vai por último;
#   · quem passou do teto NÃO é marcado — espera a vez e sai depois, mesmo
#     que a espera passe das 3h do "momento perdido".
RSpec.describe Crm::FollowupBotJob do
  let(:tz) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, name: 'GOOGLE') }
  let(:other_inbox) { create(:inbox, account: account, name: 'INSTAGRAM') }
  let(:reader) { instance_double(Crm::FollowupConversationReader, call: { situacao: 'aberta', motivo: 'perguntou e sumiu', fonte: 'ia' }) }

  before do
    travel_to tz.parse('2026-10-13 14:00') # terça-feira, dentro do horário de envio
    allow(Crm::FollowupConversationReader).to receive(:new).and_return(reader)
  end

  def bot_with(steps = [text_step(1)], **attrs)
    Crm::FollowupBot.create!({ account: account, name: 'Robô', sender: admin, steps: steps }.merge(attrs))
  end

  def text_step(hours, message = '[nome], ficou alguma dúvida?')
    { 'delay_value' => hours, 'delay_unit' => 'hours', 'message' => message }
  end

  def pace!(per_window, minutes = 5)
    CrmSetting.find_or_create_by!(account_id: account.id)
              .update!(agenda_config: { 'followup_pace' => { 'per_window' => per_window, 'minutes' => minutes } })
  end

  # paciente escreveu `asked` minutos atrás; a clínica respondeu há `answered` min e o paciente sumiu
  def silent_conversation(name, asked: 70, answered: 65, the_inbox: inbox)
    contact = create(:contact, account: account, name: name)
    conv = create(:conversation, account: account, inbox: the_inbox, contact: contact, status: :open)
    create(:message, account: account, inbox: the_inbox, conversation: conv, message_type: :incoming, sender: contact,
                     content: 'Quero saber da cirurgia', created_at: asked.minutes.ago)
    create(:message, account: account, inbox: the_inbox, conversation: conv, message_type: :outgoing, sender: admin,
                     content: 'O orçamento é R$ 5.000 pelos dois olhos', created_at: answered.minutes.ago)
    conv.update!(last_activity_at: answered.minutes.ago)
    conv
  end

  def nudges(conv)
    conv.messages.outgoing.where("additional_attributes ->> 'cevico_followup_bot_id' IS NOT NULL")
  end

  def state_of(conv, bot)
    conv.reload.additional_attributes&.dig('cevico_followup', 'bots', bot.id.to_s)
  end

  describe '.pace_config' do
    it 'usa o padrão quando falta, é inválido ou fora da faixa; 0 = sem limite', :aggregate_failures do
      expect(described_class.pace_config(nil)).to eq('per_window' => 5, 'minutes' => 5)
      expect(described_class.pace_config('lixo')).to eq('per_window' => 5, 'minutes' => 5)
      expect(described_class.pace_config('per_window' => '3', 'minutes' => '10')).to eq('per_window' => 3, 'minutes' => 10)
      expect(described_class.pace_config(per_window: 8, minutes: 2)).to eq('per_window' => 8, 'minutes' => 2)
      expect(described_class.pace_config('per_window' => 'abc', 'minutes' => -1)).to eq('per_window' => 5, 'minutes' => 5)
      expect(described_class.pace_config('per_window' => 1000, 'minutes' => 0)).to eq('per_window' => 5, 'minutes' => 5)
      expect(described_class.pace_config('per_window' => 0, 'minutes' => 7)).to eq('per_window' => 0, 'minutes' => 7)
    end
  end

  describe 'teto por número' do
    it 'no máximo N por caixa na rodada; o resto espera SEM ser marcado e sai depois', :aggregate_failures do
      pace!(5)
      bot = bot_with
      google = Array.new(7) { |i| silent_conversation("Paciente #{i}") }
      insta = silent_conversation('Instagram', the_inbox: other_inbox)

      described_class.perform_now

      sent, held = google.partition { |c| nudges(c).exists? }
      expect(sent.size).to eq(5)
      expect(nudges(insta).count).to eq(1) # outro número: conta separada
      expect(held.map { |c| state_of(c, bot) }).to all(be_nil) # nada marcado
      expect(bot.reload.activity_log.dig('last_run', 'reasons')).to include('ritmo' => 2)

      travel 6.minutes # a janela do ritmo andou
      described_class.perform_now
      expect(held.map { |c| nudges(c).count }).to eq([1, 1])
    end

    it 'conta o que já saiu na janela (de qualquer robô e da reativação)', :aggregate_failures do
      pace!(2)
      outro = bot_with([text_step(9)], name: 'Outro robô', active: false)
      antiga = silent_conversation('Antiga')
      antiga.update!(status: :resolved) # fora da fila: só empresta as mensagens já enviadas
      create(:message, account: account, inbox: inbox, conversation: antiga, message_type: :outgoing, content: 'cutucada do outro',
                       created_at: 2.minutes.ago, additional_attributes: { 'cevico_followup_bot_id' => outro.id })
      create(:message, account: account, inbox: inbox, conversation: antiga, message_type: :outgoing, content: 'Oi, tudo bem?',
                       created_at: 1.minute.ago, additional_attributes: { 'cevico_followup_reativacao' => true })
      bot = bot_with
      conv = silent_conversation('Nova')

      described_class.perform_now

      expect(nudges(conv)).to be_empty
      expect(bot.reload.activity_log.dig('last_run', 'reasons')).to include('ritmo' => 1)
    end

    it 'per_window 0 = sem limite' do
      pace!(0)
      bot_with
      convs = Array.new(7) { |i| silent_conversation("Paciente #{i}") }
      described_class.perform_now
      expect(convs.count { |c| nudges(c).exists? }).to eq(7)
    end
  end

  it 'prioridade: janela de 24h mais perto de fechar primeiro; sem janela aberta por último', :aggregate_failures do
    pace!(2)
    bot = bot_with
    sem_janela = silent_conversation('Sem janela', asked: 30 * 60)  # falou há 30h
    recente = silent_conversation('Recente', asked: 70)             # falou há 70 min
    fechando = silent_conversation('Fechando', asked: 20 * 60)      # falou há 20h

    described_class.perform_now

    expect(nudges(fechando).count).to eq(1)
    expect(nudges(recente).count).to eq(1)
    expect(nudges(sem_janela)).to be_empty
    expect(state_of(sem_janela, bot)).to be_nil
  end

  it 'espera do ritmo não vira "momento perdido": sai mesmo passadas as 3h', :aggregate_failures do
    pace!(1, 5)
    bot = bot_with
    primeira = silent_conversation('Primeira', asked: 20 * 60)
    segunda = silent_conversation('Segunda')

    described_class.perform_now
    expect(nudges(primeira).count).to eq(1)
    expect(nudges(segunda)).to be_empty
    expect(state_of(segunda, bot)).to be_nil

    travel 4.hours # etapa venceu há 4h — sem o lembrete do ritmo seria descartada
    described_class.perform_now

    expect(nudges(segunda).count).to eq(1)
    expect(state_of(segunda, bot)['sent']).to eq([0])
  end

  it 'a previsão do painel avisa que a cutucada está na fila do ritmo' do
    pace!(1)
    bot = bot_with
    create(:message, account: account, inbox: inbox, conversation: silent_conversation('Já foi'), message_type: :outgoing,
                     content: 'cutucada', created_at: 1.minute.ago, additional_attributes: { 'cevico_followup_bot_id' => bot.id })
    conv = silent_conversation('Na fila')

    forecast = described_class.new.forecast(bot, conv)

    expect(forecast[:status]).to eq('proxima')
    expect(forecast[:text]).to include('na fila do ritmo de envio (até 1 mensagem a cada 5 min por número)')
    expect(forecast[:timeline].first[:note]).to eq('na fila do ritmo de envio')
  end

  describe 'reativação de quem adiou' do
    let(:whatsapp) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
    let(:template) { { 'name' => 'retomar_conversa', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => {} } }

    def adiada_conversation(name)
      contact = create(:contact, account: account, name: name, phone_number: "+551199#{rand(1_000_000..9_999_999)}")
      conv = create(:conversation, account: account, inbox: whatsapp, contact: contact, status: :resolved)
      create(:message, account: account, inbox: whatsapp, conversation: conv, message_type: :incoming, content: 'vou pensar',
                       created_at: 8.days.ago)
      create(:message, account: account, inbox: whatsapp, conversation: conv, message_type: :outgoing, content: 'Fico à disposição!',
                       created_at: 8.days.ago, sender: admin)
      adiar!(conv)
    end

    def adiar!(conv)
      leitura = { 'key' => Crm::FollowupClosure.last_clinic(conv).first, 'situacao' => 'adiada',
                  'at' => 7.days.ago.iso8601, 'reativar_em' => 1.minute.ago.iso8601 }
      Cevico::AttributeMerge.merge!(conv) { |attrs| attrs.merge('cevico_conversa_leitura' => leitura) }
    end

    it 'entra no mesmo ritmo: com o número no teto, espera sem gravar nada', :aggregate_failures do
      CrmSetting.find_or_create_by!(account_id: account.id).update!(agenda_config: {
                                                                      'followup_pace' => { 'per_window' => 1, 'minutes' => 5 },
                                                                      'followup_smart' => { 'reativacao' => {
                                                                        'ativa' => true,
                                                                        'modelos' => { whatsapp.id.to_s => { 'message' => 'Oi',
                                                                                                             'template_params' => template } }
                                                                      } }
                                                                    })
      convs = [adiada_conversation('Ana'), adiada_conversation('Bia')]

      described_class.new.send(:process_reactivations)

      leituras = convs.map { |c| c.reload.additional_attributes.dig('cevico_conversa_leitura', 'reativacao') }
      expect(leituras.compact).to eq(['enviada'])
      expect(leituras.count(nil)).to eq(1) # a outra continua na fila, sem trava gravada
    end
  end
end
