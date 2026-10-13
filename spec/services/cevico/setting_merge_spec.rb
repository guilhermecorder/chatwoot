require 'rails_helper'

# 🔒 Rodada 4 da auditoria (achado #318): gravador travado único do crm_settings.
# Antes, "lê → altera → update!" sem trava fazia o último a gravar apagar a chave
# que o outro acabou de escrever (update! grava a coluna jsonb inteira).
RSpec.describe Cevico::SettingMerge do
  let(:account) { create(:account) }

  describe '.merge!' do
    it 'recebendo a conta, cria a linha do crm_settings, grava e devolve o hash gravado', :aggregate_failures do
      expect(CrmSetting.find_by(account: account)).to be_nil

      saved = described_class.merge!(account, :agenda_config) { |cfg| cfg.merge('oftalmofacil' => { 'cursor' => 5 }) }

      expect(saved).to eq('oftalmofacil' => { 'cursor' => 5 })
      expect(CrmSetting.find_by!(account: account).agenda_config).to eq('oftalmofacil' => { 'cursor' => 5 })
    end

    it 'a foto velha de um escritor NÃO apaga a chave que o outro acabou de gravar (o buraco do #318)', :aggregate_failures do
      row = CrmSetting.create!(account: account, agenda_config: { 'base' => 1 })
      sync = CrmSetting.find(row.id)  # o job do sync carregou a linha minutos atrás
      admin = CrmSetting.find(row.id) # o admin salvou a tela nesse meio-tempo

      described_class.merge!(admin, :agenda_config) { |cfg| cfg.merge('windows' => ['seg']) }
      described_class.merge!(sync, :agenda_config) { |cfg| cfg.merge('oftalmofacil' => { 'cursor' => 9 }) }

      expect(row.reload.agenda_config).to eq('base' => 1, 'windows' => ['seg'], 'oftalmofacil' => { 'cursor' => 9 })
      expect(sync.agenda_config).to eq(row.agenda_config) # quem chamou enxerga o que foi gravado
    end

    it 'o padrão antigo (update! com a foto velha) perde a chave — é o que este helper substitui' do
      row = CrmSetting.create!(account: account, agenda_config: { 'base' => 1 })
      sync = CrmSetting.find(row.id)
      admin = CrmSetting.find(row.id)

      admin.update!(agenda_config: admin.agenda_config.merge('windows' => ['seg']))
      sync.update!(agenda_config: sync.agenda_config.merge('oftalmofacil' => { 'cursor' => 9 }))

      expect(row.reload.agenda_config.keys).not_to include('windows')
    end

    it 'registro sujo (hash mutado em memória) não quebra a trava, não grava a foto velha e fica limpo na coluna', :aggregate_failures do
      row = CrmSetting.create!(account: account, ai_config: { 'agents' => { 'x' => 1 } })
      CrmSetting.find(row.id).update!(ai_config: { 'agents' => { 'x' => 1 }, 'harvest_state' => { 'sent' => [1] } })
      dirty = CrmSetting.find(row.id)
      dirty.ai_config['agents'] = { 'x' => 2 } # muta em memória, como fazem os callers antigos
      dirty.ai_config.delete('harvest_state')
      expect(dirty).to have_changes_to_save

      expect { described_class.merge!(dirty, :ai_config) { |cfg| cfg.merge('radar' => { 'on' => true }) } }.not_to raise_error

      fresh = row.reload.ai_config
      expect(fresh['harvest_state']).to eq('sent' => [1]) # o estado dos jobs não sumiu
      expect(fresh['radar']).to eq('on' => true)
      expect(fresh['agents']).to eq('x' => 1) # a mutação solta em memória não vale como gravação
      expect(dirty.ai_config).to eq(fresh)
      expect(dirty.changed).not_to include('ai_config')
    end

    it 'bloco que só muta a cópia (sem devolver hash) também grava' do
      described_class.merge!(account, :agenda_config) { |cfg| cfg['scheduler_log'] = ['ok'] }
      expect(CrmSetting.find_by!(account: account).agenda_config).to eq('scheduler_log' => ['ok'])
    end

    # REGRA DO BLOCO: `cfg['chave'] = { … }` como última linha devolve o sub-hash;
    # isso NUNCA pode virar a coluna inteira (apagaria todas as irmãs).
    describe 'última linha do bloco devolve um pedaço, não o hash completo' do
      let!(:row) { CrmSetting.create!(account: account, agenda_config: { 'windows' => ['seg'], 'panel_records' => { 'a' => 1 } }) }

      it "`cfg['x'] = { … }` no fim do bloco preserva as chaves irmãs", :aggregate_failures do
        saved = described_class.merge!(account, :agenda_config) { |cfg| cfg['oftalmofacil'] = { 'cursor' => 5 } }

        expect(saved).to eq('windows' => ['seg'], 'panel_records' => { 'a' => 1 }, 'oftalmofacil' => { 'cursor' => 5 })
        expect(row.reload.agenda_config).to eq(saved)
      end

      it 'atribuição em nível mais fundo (`cfg[a][b] = { … }`) também preserva tudo' do
        described_class.merge!(account, :agenda_config) { |cfg| cfg['panel_records']['b'] = { 'x' => 2 } }

        expect(row.reload.agenda_config).to eq('windows' => ['seg'], 'panel_records' => { 'a' => 1, 'b' => { 'x' => 2 } })
      end

      it '`cfg.delete(chave)` no fim do bloco (devolve o sub-hash apagado) só tira a chave', :aggregate_failures do
        saved = described_class.merge!(account, :agenda_config) { |cfg| cfg.delete('panel_records') }

        expect(saved).to eq('windows' => ['seg'])
        expect(row.reload.agenda_config).to eq('windows' => ['seg'])
      end

      it 'gravar na chave o MESMO valor que já estava (cópia fica igual à foto) não encolhe a coluna' do
        described_class.merge!(account, :agenda_config) { |cfg| cfg['panel_records'] = { 'a' => 1 } }

        expect(row.reload.agenda_config).to eq('windows' => ['seg'], 'panel_records' => { 'a' => 1 })
      end

      it 'bloco que devolve nil ou um número grava a cópia como está' do
        described_class.merge!(account, :agenda_config) { |cfg| cfg['n'] = 1; 42 } # rubocop:disable Style/Semicolon

        expect(row.reload.agenda_config).to eq('windows' => ['seg'], 'panel_records' => { 'a' => 1 }, 'n' => 1)
      end
    end

    it 'hash devolvido com chaves símbolo é gravado E devolvido com chaves em texto (memória = banco)', :aggregate_failures do
      settings = CrmSetting.create!(account: account, agenda_config: { 'base' => 1 })

      saved = described_class.merge!(settings, :agenda_config) { |cfg| cfg.merge(nova: { fundo: 1 }) }

      expect(saved).to eq('base' => 1, 'nova' => { 'fundo' => 1 })
      expect(settings.agenda_config['nova']).to eq('fundo' => 1)
      expect(settings.reload.agenda_config).to eq(saved)
    end

    it 'column_presets é LISTA: começa como [] e aceita lista nova devolvida pelo bloco', :aggregate_failures do
      saved = described_class.merge!(account, :column_presets) { |list| list + [{ 'id' => 1 }] }
      expect(saved).to eq([{ 'id' => 1 }])

      saved = described_class.merge!(account, :column_presets) { |list| list << { 'id' => 2 } }
      expect(saved).to eq([{ 'id' => 1 }, { 'id' => 2 }])
      expect(CrmSetting.find_by!(account: account).column_presets).to eq(saved)
    end

    it 'só merge! e merge_key! são públicos; os ajudantes internos não' do
      expect(described_class).to respond_to(:merge!, :merge_key!)
      %i[choose inside? stringify fresh_row find_or_create_row sync_caller].each do |helper|
        expect(described_class).not_to respond_to(helper)
      end
    end

    it 'usa a trava da linha (SELECT ... FOR UPDATE) ao gravar' do
      row = CrmSetting.create!(account: account)
      allow(row).to receive(:with_lock).and_call_original

      described_class.merge!(row, :agenda_config) { |cfg| cfg.merge('a' => 1) }

      expect(row).to have_received(:with_lock)
    end

    it 'recusa coluna que não é config e objeto que não é conta nem crm_settings', :aggregate_failures do
      expect { described_class.merge!(account, :n8n_api_key) { |c| c } }.to raise_error(ArgumentError, /coluna/)
      expect { described_class.merge!(account.id, :agenda_config) { |c| c } }.to raise_error(ArgumentError, /Account ou CrmSetting/)
    end
  end

  describe '.merge_key!' do
    it 'mexe numa chave só, preserva as irmãs e devolve o valor gravado', :aggregate_failures do
      CrmSetting.create!(account: account, agenda_config: { 'windows' => ['seg'], 'oftalmofacil' => { 'cursor' => 1, 'ok' => true } })

      value = described_class.merge_key!(account, :agenda_config, 'oftalmofacil') { |h| h.merge('cursor' => 2) }

      expect(value).to eq('cursor' => 2, 'ok' => true)
      expect(CrmSetting.find_by!(account: account).agenda_config).to eq('windows' => ['seg'], 'oftalmofacil' => { 'cursor' => 2, 'ok' => true })
    end

    it 'chave inexistente começa como hash vazio; bloco que muta sem devolver também vale', :aggregate_failures do
      described_class.merge_key!(account, :ai_config, :radar) { |h| h['last_run'] = 't1' }

      expect(CrmSetting.find_by!(account: account).ai_config).to eq('radar' => { 'last_run' => 't1' })
      expect(described_class.merge_key!(account, :ai_config, :radar) { |h| h }).to eq('last_run' => 't1')
    end

    it 'aceita lista na chave (events, history) sem transformar em hash' do
      CrmSetting.create!(account: account, ai_config: { 'events' => [1] })
      value = described_class.merge_key!(account, :ai_config, 'events') { |list| list + [2] }
      expect(value).to eq([1, 2])
    end

    it "`h['x'] = { … }` no fim do bloco preserva as irmãs DENTRO da chave (não vira o valor inteiro)", :aggregate_failures do
      CrmSetting.create!(account: account, agenda_config: { 'windows' => ['seg'], 'panel_records' => { 'a' => 1 } })

      value = described_class.merge_key!(account, :agenda_config, 'panel_records') { |h| h['b'] = { 'x' => 2 } }

      expect(value).to eq('a' => 1, 'b' => { 'x' => 2 })
      expect(CrmSetting.find_by!(account: account).agenda_config).to eq('windows' => ['seg'], 'panel_records' => { 'a' => 1, 'b' => { 'x' => 2 } })
    end

    it 'valor simples na chave: vale o que o bloco devolveu (inclusive trocar por nil)', :aggregate_failures do
      CrmSetting.create!(account: account, ai_config: { 'cursor' => 3 })

      expect(described_class.merge_key!(account, :ai_config, 'cursor') { |v| v + 1 }).to eq(4)
      expect(CrmSetting.find_by!(account: account).ai_config).to eq('cursor' => 4)
    end

    it 'recusa coluna de lista (column_presets não tem chave)' do
      expect { described_class.merge_key!(account, :column_presets, 'x') { |h| h } }.to raise_error(ArgumentError, /lista/)
    end
  end
end
