require 'rails_helper'

# 🏥 Rodada 4 da auditoria — "Dados que não se perdem":
#   #172 o sync do OftalmoFácil roda SEM trava (cron + "Sincronizar agora" +
#        "Trazer para a Agenda" ao mesmo tempo duplicam paciente/card/consulta);
#   #382 a falha do sync fica só no log e a tela segue mostrando a última rodada boa;
#   #383 cursor/resumo gravados com update! da coluna inteira (apaga o que o admin
#        salvou nas chaves irmãs de agenda_config enquanto o job rodava).
RSpec.describe Crm::OftalmofacilSyncJob do
  let(:account) { create(:account) }
  let(:lock_key) { described_class.lock_key(account.id) }
  let(:of_config) do
    { 'db_host' => 'h', 'db_name' => 'd', 'db_user' => 'u', 'db_password' => 'p', 'provider_name' => 'CATARATA_SP',
      'enabled' => true, 'last_run_at' => 2.hours.ago.iso8601, 'last_sync_at' => '2026-10-01 08:00:00' }
  end
  let!(:settings) do
    CrmSetting.create!(account: account, agenda_config: { 'oftalmofacil' => of_config, 'calls' => { 'enabled' => true } })
  end
  let(:result) do
    Crm::OftalmofacilSyncService::Result.new(
      pulled: 3, created_contacts: 1, moved: 0, ahead: 0, labeled: 0, errors: [], cursor: '2026-10-13 10:00:00', cursor_id: 77,
      tasks_created: 1, tasks_updated: 0, partners: 0, skipped_partners: 0, healed: 0, unread_found: 0, tasks_adopted: 0
    )
  end
  let(:service) do
    instance_double(Crm::OftalmofacilSyncService, call: result, heal_agenda!: nil, dedupe_tasks!: nil, refresh_upcoming!: nil)
  end

  before { allow(Crm::OftalmofacilSyncService).to receive(:new).and_return(service) }

  after { Redis::Alfred.delete(lock_key) }

  def of_saved
    CrmSetting.find(settings.id).agenda_config['oftalmofacil']
  end

  describe 'trava por conta (#172)' do
    it 'com a trava ocupada, o cron e o botão pulam a conta e não mexem na trava dos outros', :aggregate_failures do
      Redis::LockManager.new.lock(lock_key, 1.minute)

      described_class.perform_now(account.id)
      described_class.perform_now

      expect(service).not_to have_received(:call)
      expect(Redis::LockManager.new.locked?(lock_key)).to be(true)
      expect(of_saved['last_run_at']).to eq(of_config['last_run_at'])
    end

    it 'com a trava livre roda uma vez, grava cursor e resumo e solta a trava no fim', :aggregate_failures do
      described_class.perform_now(account.id)

      expect(service).to have_received(:call).once
      expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
      expect(of_saved['last_sync_at']).to eq('2026-10-13 10:00:00')
      expect(of_saved['last_sync_id']).to eq(77)
      expect(of_saved['last_result']).to include('pulled' => 3, 'tasks_created' => 1, 'error_count' => 0)
      expect(Time.zone.parse(of_saved['last_run_at'])).to be_within(5.seconds).of(Time.current)
    end

    it '"Trazer para a Agenda" (reconcile!) com a trava ocupada devolve o aviso e não reprocessa nada', :aggregate_failures do
      Redis::LockManager.new.lock(lock_key, 1.minute)
      check = Crm::OftalmofacilDayCheck.new(account: account, date: Date.current, config: of_config.merge('agenda_enabled' => true))

      out = check.reconcile!

      expect(out[:fixed]).to eq(0)
      expect(out[:errors]).to eq([described_class::BUSY_MESSAGE])
      expect(Crm::OftalmofacilSyncService).not_to have_received(:new)
      expect(Redis::LockManager.new.locked?(lock_key)).to be(true)
    end

    it 'a rodada que passou do tempo não apaga a trava de quem entrou depois (senha própria)', :aggregate_failures do
      allow(service).to receive(:call) do
        # a trava da rodada 1 expirou e a rodada 2 pegou a sua
        Redis::Alfred.set(lock_key, 'senha-da-rodada-2', ex: 60)
        result
      end

      described_class.perform_now(account.id)

      expect(Redis::Alfred.get(lock_key)).to eq('senha-da-rodada-2')
      expect(described_class.busy?(account.id)).to be(true)
    end
  end

  describe 'cursor gravado sob trava (#383)' do
    it 'grava cursor, resumo e erro pelo Cevico::SettingMerge (só a chave oftalmofacil, sob a trava da linha)', :aggregate_failures do
      allow(Cevico::SettingMerge).to receive(:merge_key!).and_call_original

      described_class.perform_now(account.id)
      allow(service).to receive(:call).and_raise(StandardError, 'timeout')
      described_class.perform_now(account.id)

      expect(Cevico::SettingMerge).to have_received(:merge_key!).with(settings, :agenda_config, 'oftalmofacil').twice
      expect(CrmSetting.find(settings.id).agenda_config['calls']).to eq('enabled' => true)
    end

    it 'não apaga o que o admin salvou nas chaves irmãs enquanto o job rodava' do
      allow(service).to receive(:call) do
        # o admin salva Ligações no meio da rodada (outra request, outra cópia da linha)
        CrmSetting.find(settings.id).then { |s| s.update!(agenda_config: s.agenda_config.merge('calls' => { 'enabled' => false, 'inbox_id' => 9 })) }
        result
      end

      described_class.perform_now(account.id)

      saved = CrmSetting.find(settings.id).agenda_config
      expect(saved['calls']).to eq('enabled' => false, 'inbox_id' => 9)
      expect(saved.dig('oftalmofacil', 'last_sync_id')).to eq(77)
    end
  end

  describe 'falha visível (#382)' do
    it 'quando o hub falha: grava o erro, mantém a última rodada boa, solta a trava e não levanta', :aggregate_failures do
      allow(service).to receive(:call).and_raise(StandardError, 'Access denied for user')

      expect { described_class.perform_now(account.id) }.not_to raise_error

      expect(of_saved['last_error']).to include('Access denied for user')
      expect(Time.zone.parse(of_saved['last_error_at'])).to be_within(5.seconds).of(Time.current)
      expect(of_saved['last_run_at']).to eq(of_config['last_run_at'])
      expect(of_saved['last_sync_at']).to eq('2026-10-01 08:00:00')
      expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
      expect(described_class.alert_for(of_saved)).to include('kind' => 'erro')
    end

    it 'uma rodada boa depois do erro apaga a faixa (last_run_at mais novo que last_error_at)' do
      allow(service).to receive(:call).and_raise(StandardError, 'timeout')
      described_class.perform_now(account.id)
      expect(described_class.alert_for(of_saved)).to include('kind' => 'erro')

      allow(service).to receive(:call).and_return(result)
      described_class.perform_now(account.id)

      expect(described_class.alert_for(of_saved)).to be_nil
    end

    # revisão: o service REAL não levanta quando o hub cai — engole a falha e
    # devolve o result. Estes testes usam o service de verdade, sem dublê.
    context 'with o service de verdade e o hub fora do ar' do
      before { allow(Crm::OftalmofacilSyncService).to receive(:new).and_call_original }

      it 'conexão recusada: grava a falha, NÃO avança last_run_at nem o cursor e a tela mostra "erro"', :aggregate_failures do
        allow(Mysql).to receive(:connect).and_raise(Errno::ECONNREFUSED)

        expect { described_class.perform_now(account.id) }.not_to raise_error

        expect(of_saved['last_error']).to include('Não alcancei o servidor do OftalmoFácil')
        expect(Time.zone.parse(of_saved['last_error_at'])).to be_within(5.seconds).of(Time.current)
        expect(of_saved['last_run_at']).to eq(of_config['last_run_at'])
        expect(of_saved['last_sync_at']).to eq('2026-10-01 08:00:00')
        expect(of_saved['last_result']).to be_nil
        expect(Redis::LockManager.new.locked?(lock_key)).to be(false)
        expect(described_class.alert_for(of_saved)).to include('kind' => 'erro')
      end

      it 'senha errada: a mensagem gravada é a da casa (sem o tipo técnico do erro)' do
        allow(Mysql).to receive(:connect).and_raise(StandardError, "Access denied for user 'u'@'1.2.3.4' (1045)")

        described_class.perform_now(account.id)

        expect(of_saved['last_error']).to start_with('Acesso recusado: confira usuário e senha')
      end
    end
  end

  describe 'trava renovada durante a rodada (revisão do #172)' do
    it 'a cada lote lido do hub a trava ganha mais LOCK_TTL — só se a senha ainda for a nossa', :aggregate_failures do
      token = described_class.acquire_lock(account.id)
      Redis::Alfred.expire(lock_key, 30)

      described_class.renew_lock(account.id, token)
      expect(Redis::Alfred.ttl(lock_key)).to be > 30.minutes.to_i

      Redis::Alfred.set(lock_key, 'senha-de-outra-rodada', ex: 30)
      described_class.renew_lock(account.id, token)
      expect(Redis::Alfred.ttl(lock_key)).to be <= 30
    end

    it 'o job passa ao service um heartbeat que renova a trava da conta' do
      allow(described_class).to receive(:renew_lock)
      allow(Crm::OftalmofacilSyncService).to receive(:new) do |**kwargs|
        kwargs[:heartbeat].call
        service
      end

      described_class.perform_now(account.id)

      expect(described_class).to have_received(:renew_lock).with(account.id, kind_of(String))
    end

    it 'com uma rodada em andamento (recarga longa), a tela não acusa "parada"', :aggregate_failures do
      expect(described_class.alert_for(of_config, account_id: account.id)).to include('kind' => 'parada')

      Redis::LockManager.new.lock(lock_key, 1.minute)
      expect(described_class.alert_for(of_config, account_id: account.id)).to be_nil
      # erro continua aparecendo mesmo com rodada em andamento
      expect(described_class.alert_for(of_config.merge('last_error_at' => Time.current.iso8601), account_id: account.id))
        .to include('kind' => 'erro')
    end
  end

  describe '.alert_for (o que a tela mostra em faixa vermelha)' do
    it 'nada quando a integração está desligada ou sem conexão configurada', :aggregate_failures do
      expect(described_class.alert_for(of_config.merge('enabled' => false, 'last_error_at' => Time.current.iso8601))).to be_nil
      expect(described_class.alert_for(of_config.merge('db_password' => nil))).to be_nil
      expect(described_class.alert_for(nil)).to be_nil
    end

    it '"parada" quando ligada e sem rodada boa há mais de 45 minutos; nada quando a rodada é recente', :aggregate_failures do
      expect(described_class.alert_for(of_config)).to include('kind' => 'parada')
      expect(described_class.alert_for(of_config.merge('last_run_at' => 10.minutes.ago.iso8601))).to be_nil
      # nunca rodou: conta a partir de quando a conexão foi salva
      expect(described_class.alert_for(of_config.except('last_run_at').merge('updated_at' => 3.hours.ago.iso8601))).to include('kind' => 'parada')
      expect(described_class.alert_for(of_config.except('last_run_at').merge('updated_at' => 5.minutes.ago.iso8601))).to be_nil
    end

    it 'integração religada agora (card salvo há pouco) não ganha faixa só porque a rodada boa é antiga', :aggregate_failures do
      religada = of_config.merge('updated_at' => 2.minutes.ago.iso8601) # last_run_at = 2 h atrás
      expect(described_class.alert_for(religada)).to be_nil
      # e passado o tempo sem rodar, a faixa volta contando do que for mais novo (o card salvo)
      saved_at = 50.minutes.ago.iso8601
      alert = described_class.alert_for(of_config.merge('updated_at' => saved_at))
      expect(alert).to include('kind' => 'parada', 'at' => Time.zone.parse(saved_at).iso8601)
      expect(alert['message']).to include('não rodou desde que a conexão foi salva')
    end

    it '"erro" vence a "parada" e traz a hora da falha, sem o erro cru', :aggregate_failures do
      failed_at = 1.hour.ago.iso8601
      alert = described_class.alert_for(of_config.merge('last_error' => 'Access denied', 'last_error_at' => failed_at))
      expect(alert).to include('kind' => 'erro', 'at' => Time.zone.parse(failed_at).iso8601)
      expect(alert['message']).not_to include('Access denied')
    end
  end
end
