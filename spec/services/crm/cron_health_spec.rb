require 'rails_helper'

# 🚨 achado #217 (auditoria 07/10): os robôs engoliam o erro com
# Rails.logger.error e ninguém ficava sabendo quando um parava. Agora cada
# rodada deixa sinal de vida (ran!) e cada erro é registrado (failed!) — e vai
# para o rastreador de erros.
RSpec.describe Crm::CronHealth do
  let(:account) { create(:account) }
  # 13/10 (terça) 14:30 UTC — os lembretes (*/15) rodaram às 14:15 e 14:00
  let(:now) { Time.utc(2026, 10, 13, 14, 30) }

  def clear_redis
    (described_class::JOBS.keys + ['sidekiq']).each do |job|
      Redis::Alfred.delete(format(described_class::KEY, job: job))
      Redis::Alfred.delete(format(described_class::ROUND_ERRORS_KEY, job: job))
    end
    Redis::Alfred.delete(described_class::SIDEKIQ_KEY)
    Redis::Alfred.with { |conn| conn.keys('cevico:cron_health:*:tracked:*').each { |k| conn.del(k) } }
  end

  before { clear_redis }
  after { clear_redis }

  describe 'robô parado (sem rodada nos 2 últimos horários do cron)' do
    it 'rodou no último horário: em dia' do
      described_class.ran!('lembretes', now: Time.utc(2026, 10, 13, 14, 15, 30))

      expect(described_class.problem_for('lembretes', now: now)).to be_nil
    end

    it 'perdeu só 1 horário: ainda não avisa (pode ser atraso da fila)' do
      described_class.ran!('lembretes', now: Time.utc(2026, 10, 13, 14, 0, 40))

      expect(described_class.problem_for('lembretes', now: now)).to be_nil
    end

    it 'perdeu 2 horários seguidos: parado, com a hora da última rodada em São Paulo', :aggregate_failures do
      described_class.ran!('lembretes', now: Time.utc(2026, 10, 13, 13, 45, 40))

      problem = described_class.problem_for('lembretes', now: now)
      expect(problem[:kind]).to eq('parado')
      expect(problem[:label]).to eq('Lembretes de consulta')
      expect(problem[:message]).to include('13/10 às 10:45')
    end

    it 'respeita o calendário do cron: a Colheitadeira parada no domingo não é "robô parado"' do
      # roda 12h–20h UTC de segunda a sábado; última rodada sábado 20:10
      described_class.ran!('colheita', now: Time.utc(2026, 10, 10, 20, 10, 30))

      expect(described_class.problem_for('colheita', now: Time.utc(2026, 10, 12, 12, 25))).to be_nil
      expect(described_class.problem_for('colheita', now: Time.utc(2026, 10, 12, 13, 25))[:kind]).to eq('parado')
    end

    it 'robô que nunca deixou sinal conta a partir da 1ª vez que o vigia olhou (logo depois do deploy não avisa)', :aggregate_failures do
      expect(described_class.problem_for('jornada', now: now)).to be_nil

      expect(described_class.problem_for('jornada', now: now + 45.minutes)[:kind]).to eq('parado')
    end
  end

  describe 'robô com erro' do
    it 'erro manda para o rastreador de erros e fica registrado com a conta', :aggregate_failures do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      described_class.failed!('lembretes', StandardError.new('Meta fora do ar'), account: account, now: now)

      expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(StandardError), account: account)
      expect(tracker).to have_received(:capture_exception)
      expect(described_class.state('lembretes')['last_error']).to eq("conta #{account.id} · StandardError: Meta fora do ar")
    end

    it '1 rodada com erro não avisa; 2 seguidas avisam; 1 rodada boa zera', :aggregate_failures do
      described_class.failed!('nps', StandardError.new('boom'), now: now)
      described_class.ran!('nps', now: now)
      expect(described_class.problem_for('nps', now: now)).to be_nil

      described_class.failed!('nps', StandardError.new('boom de novo'), now: now + 15.minutes)
      described_class.ran!('nps', now: now + 15.minutes)
      problem = described_class.problem_for('nps', now: now + 16.minutes)
      expect(problem[:kind]).to eq('erro')
      expect(problem[:message]).to include('boom de novo')

      described_class.ran!('nps', now: now + 30.minutes)
      expect(described_class.problem_for('nps', now: now + 31.minutes)).to be_nil
      expect(described_class.state('nps')['last_ok_at']).to eq((now + 30.minutes).iso8601)
    end

    it 'Redis fora do ar não derruba o robô que chama', :aggregate_failures do
      allow(Redis::Alfred).to receive(:incr).and_raise(Redis::CannotConnectError)
      allow(Redis::Alfred).to receive(:get).and_raise(Redis::CannotConnectError)

      expect { described_class.failed!('jornada', StandardError.new('x')) }.not_to raise_error
      expect { described_class.ran!('jornada') }.not_to raise_error
    end
  end

  describe 'robôs chamam o sinal de vida' do
    it 'o lembrete que quebra numa conta registra o erro e a rodada termina com sinal de vida', :aggregate_failures do
      CrmSetting.create!(account: account, agenda_config: { 'appointment_reminders' => { 'd1' => { 'enabled' => true } } })
      job = Crm::AppointmentReminderSendJob.new
      allow(job).to receive(:reconcile_refused)
      allow(job).to receive(:run_followups)
      allow(job).to receive(:run_regua).and_raise(StandardError, 'modelo sumiu')

      job.perform(now)

      state = described_class.state('lembretes')
      expect(state['last_error']).to include('modelo sumiu')
      expect(state['last_run_at']).to be_present
      expect(state['error_streak']).to eq(1)
    end

    it 'a jornada que quebra numa conta registra o erro (antes ia só para o log)', :aggregate_failures do
      allow(Crm::Journey::Planner).to receive(:new).and_raise(StandardError, 'planner caiu')
      # rodada MANUAL (tela, com conta) não entra na saúde do cron
      Crm::JourneyRunJob.new.perform(account.id)
      expect(described_class.state('jornada')['last_error']).to be_nil

      job = Crm::JourneyRunJob.new
      allow(job).to receive(:accounts_with_messages).and_return(Account.where(id: account.id))
      job.perform

      expect(described_class.state('jornada')['last_error']).to include('planner caiu')
      expect(described_class.state('jornada')['error_streak']).to eq(1)
    end

    it 'o Radar fora do horário também deixa sinal de vida (o cron está vivo)' do
      job = Crm::OpportunityRadarJob.new
      allow(job).to receive(:should_run_now?).and_return(false)

      job.perform

      expect(described_class.state('radar')['last_run_at']).to be_present
    end

    it 'follow-up: 1 conversa com erro entre várias não marca o robô "com erro"; metade ou mais marca', :aggregate_failures do
      convs = create_list(:conversation, 4, account: account)
      bot = instance_double(Crm::FollowupBot, account: account, within_window?: true, ordered_steps: [:etapa])
      run_with_failures = lambda do |bad|
        job = Crm::FollowupBotJob.new
        allow(job).to receive_messages(send_hours: 0..23, conversations: Conversation.where(id: convs.map(&:id)),
                                       record_run: nil, event_for: {})
        allow(job).to receive(:process_conversation) { |_b, c| raise StandardError, 'contato apagado' if bad.include?(c.id) }
        job.send(:process_bot, bot)
        described_class.ran!('followup', now: now)
      end

      run_with_failures.call([convs.first.id])
      expect(described_class.state('followup')['error_streak']).to eq(0)

      run_with_failures.call(convs.first(2).map(&:id))
      expect(described_class.state('followup')['error_streak']).to eq(1)
    end
  end

  describe 'erro repetido não lota o rastreador' do
    it 'o mesmo erro do mesmo item vai ao rastreador 1× por hora; count: false não marca a rodada', :aggregate_failures do
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      3.times { described_class.failed!('followup', StandardError.new('contato apagado'), item: 'conversa 7', count: false, now: now) }
      described_class.failed!('followup', StandardError.new('contato apagado'), item: 'conversa 8', count: false, now: now)
      described_class.ran!('followup', now: now)

      expect(tracker).to have_received(:capture_exception).twice
      expect(described_class.state('followup')['error_streak']).to eq(0)
      expect(described_class.state('followup')['last_error']).to include('contato apagado')
    end
  end

  describe 'fila dos robôs (Sidekiq)' do
    it 'sinal de 1 min fresco = viva; velho = parada', :aggregate_failures do
      described_class.sidekiq_beat!(now: now - 1.minute)
      expect(described_class.sidekiq_alive?(now: now)).to be(true)

      # folga de 15 min: a fila dos robôs espera a 'low' esvaziar
      described_class.sidekiq_beat!(now: now - 10.minutes)
      expect(described_class.sidekiq_alive?(now: now)).to be(true)

      described_class.sidekiq_beat!(now: now - 20.minutes)
      expect(described_class.sidekiq_alive?(now: now)).to be(false)
      expect(described_class.problems(now: now)).to include('sidekiq')
    end
  end
end
