require 'rails_helper'

# 🚨 achado #217 (auditoria 07/10): "Como alguém descobre que o lembrete D-1
# não saiu? Hoje, pelo paciente que faltou." O vigia confere o sinal de vida
# dos robôs a cada 10 min e avisa o administrador (Radar + tarefa 🔴 + e-mail).
RSpec.describe Crm::CronWatchdogJob do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:now) { Time.utc(2026, 10, 13, 14, 30) }
  let(:health) { Crm::CronHealth }

  def clear_redis
    (health::JOBS.keys + ['sidekiq']).each do |job|
      Redis::Alfred.delete(format(health::KEY, job: job))
      Redis::Alfred.delete(format(health::ROUND_ERRORS_KEY, job: job))
    end
    Redis::Alfred.delete(health::SIDEKIQ_KEY)
  end

  # todos os robôs em dia (e a fila andando) às `at`, menos o que o teste quebrar
  def all_healthy!(at, except: nil)
    health::JOBS.each_key { |job| health.ran!(job, now: at) unless job == except }
    health.sidekiq_beat!(now: at)
  end

  def radar_alerts
    Array(CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'alerts'))
  end

  before do
    clear_redis
    CrmSetting.create!(account: account)
  end

  after { clear_redis }

  # relógio parado em `now` (o "ainda vale?" do Radar usa a hora de agora)
  around { |example| travel_to(now) { example.run } }

  it 'tudo em dia: não avisa ninguém, mas grava o resumo em ai_config.cron_health', :aggregate_failures do
    all_healthy!(now - 1.minute)

    expect { described_class.perform_now(now) }.not_to have_enqueued_mail(AdministratorNotifications::CevicoAlertMailer)

    summary = CrmSetting.find_by(account: account).ai_config['cron_health']
    expect(summary['jobs']['lembretes']['status']).to eq('ok')
    expect(summary['incidents']).to eq({})
    expect(account.tasks.count).to eq(0)
    expect(radar_alerts).to be_empty
  end

  it 'lembrete parado há 2 horários: aviso no Radar só para o admin, tarefa 🔴 e e-mail', :aggregate_failures do
    all_healthy!(now - 1.minute)
    health.ran!('lembretes', now: now - 50.minutes) # perdeu 13:45/14:00 e 14:15

    expect { described_class.perform_now(now) }
      .to have_enqueued_mail(AdministratorNotifications::CevicoAlertMailer, :robo_parado)

    alert = radar_alerts.find { |a| a['kind'] == 'robo_parado' }
    expect(alert).to include('job' => 'lembretes', 'user_id' => admin.id, 'lock' => true, 'stage_name' => 'Robô parado')
    expect(Crm::RadarExtraAlerts.still_open?(account, alert)).to be(true)

    task = account.tasks.last
    expect(task.title).to eq('🔴 Robô parado: Lembretes de consulta')
    expect(task.priority).to eq('urgent')
    expect(task.assignee).to eq(admin)
    expect(CrmSetting.find_by(account: account).ai_config.dig('cron_health', 'incidents', 'lembretes', 'kind')).to eq('parado')
  end

  it 'o mesmo problema não vira rajada: a rodada seguinte do vigia não repete o aviso (só depois de 12 h)', :aggregate_failures do
    all_healthy!(now - 1.minute)
    health.ran!('lembretes', now: now - 50.minutes)
    described_class.perform_now(now)

    all_healthy!(now + 9.minutes, except: 'lembretes')
    expect { described_class.perform_now(now + 10.minutes) }.not_to have_enqueued_mail(AdministratorNotifications::CevicoAlertMailer)
    expect(account.tasks.count).to eq(1)

    all_healthy!(now + 12.hours - 1.minute, except: 'lembretes')
    expect { described_class.perform_now(now + 12.hours) }.to have_enqueued_mail(AdministratorNotifications::CevicoAlertMailer, :robo_parado)
    expect(account.tasks.count).to eq(1) # tarefa ainda aberta: só ganha a linha nova
    expect(account.tasks.last.description.scan('Lembretes de consulta').size).to be >= 2
  end

  it 'erro 2× seguidas também avisa; quando o robô volta, o aviso do Radar deixa de valer', :aggregate_failures do
    all_healthy!(now - 1.minute)
    2.times do
      health.failed!('jornada', StandardError.new('Meta recusou'), account: account, now: now - 2.minutes)
      health.ran!('jornada', now: now - 2.minutes)
    end

    described_class.perform_now(now)

    alert = radar_alerts.find { |a| a['job'] == 'jornada' }
    expect(alert['stage_name']).to eq('Robô com erro')
    expect(account.tasks.last.title).to eq('🔴 Robô com erro: Mensagens da jornada')

    health.ran!('jornada', now: now - 1.minute)
    expect(Crm::RadarExtraAlerts.still_open?(account, alert)).to be(false)
    all_healthy!(now + 9.minutes)
    described_class.perform_now(now + 10.minutes)
    expect(CrmSetting.find_by(account: account).ai_config.dig('cron_health', 'incidents')).not_to have_key('jornada')
    # o próprio vigia tira o aviso do Radar (não espera o Radar de Oportunidades rodar)
    expect(radar_alerts.select { |a| a['kind'] == 'robo_parado' }).to be_empty
  end

  it 'fila dos robôs parada (sinal de 1 min velho) também avisa' do
    all_healthy!(now - 1.minute)
    health.sidekiq_beat!(now: now - 20.minutes)

    described_class.perform_now(now)

    expect(account.tasks.last.title).to eq('🔴 Robô parado: Fila dos robôs (Sidekiq)')
    # o aviso da fila continua valendo enquanto ela não anda (antes nunca valia)
    alert = radar_alerts.find { |a| a['job'] == 'sidekiq' }
    expect(Crm::RadarExtraAlerts.still_open?(account, alert)).to be(true)
    health.sidekiq_beat!(now: now)
    expect(Crm::RadarExtraAlerts.still_open?(account, alert)).to be(false)
  end

  it 'conta sem administrador: não abre aviso (ficaria visível para todos os atendentes)', :aggregate_failures do
    admin.account_users.update_all(role: :agent) # rubocop:disable Rails/SkipsModelValidations
    all_healthy!(now - 1.minute)
    health.ran!('lembretes', now: now - 50.minutes)

    expect { described_class.perform_now(now) }.not_to have_enqueued_mail(AdministratorNotifications::CevicoAlertMailer)
    expect(account.tasks.count).to eq(0)
    expect(radar_alerts).to be_empty
  end

  describe 'Meu Painel e Radar pelo WEB (Sidekiq parado inteiro: o vigia não roda)', type: :request do
    it 'o admin vê os robôs com problema no payload do Meu Painel; o atendente não', :aggregate_failures do
      agent = create(:user, account: account, role: :agent)
      all_healthy!(now - 1.minute)
      health.ran!('lembretes', now: now - 50.minutes)

      get "/api/v1/accounts/#{account.id}/crm/home", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['robot_problems'].pluck('job')).to eq(['lembretes'])

      get "/api/v1/accounts/#{account.id}/crm/home", headers: agent.create_new_auth_token, as: :json
      expect(response.parsed_body['robot_problems']).to eq([])
    end

    it '"Atender" sem conversa não apaga os avisos de robô nem conta na eficácia do Radar', :aggregate_failures do
      all_healthy!(now - 1.minute)
      health.ran!('lembretes', now: now - 50.minutes)
      described_class.perform_now(now)

      post "/api/v1/accounts/#{account.id}/crm/radar/attend", params: { conversation_id: nil },
                                                              headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(radar_alerts.count { |a| a['kind'] == 'robo_parado' }).to eq(1)
      expect(CrmSetting.find_by(account: account).ai_config.dig('opportunity_state', 'attended_log')).to be_blank
    end
  end

  it 'o aviso de robô parado não aparece para quem não é administrador' do
    agent = create(:user, account: account, role: :agent)
    all_healthy!(now - 1.minute)
    health.ran!('lembretes', now: now - 50.minutes)
    described_class.perform_now(now)

    visible = radar_alerts.select { |a| a['user_id'].blank? || a['user_id'].to_i == agent.id }
    expect(visible).to be_empty
  end

  describe 'GET /health?sidekiq=1', type: :request do
    it 'responde 503 com a fila parada e 200 com ela andando; o /health simples não muda', :aggregate_failures do
      get '/health', params: { sidekiq: 1 }
      expect(response).to have_http_status(:service_unavailable)

      health.sidekiq_beat!
      get '/health', params: { sidekiq: 1 }
      expect(response).to have_http_status(:ok)

      Redis::Alfred.delete(health::SIDEKIQ_KEY)
      get '/health'
      expect(response).to have_http_status(:ok)
    end
  end
end
