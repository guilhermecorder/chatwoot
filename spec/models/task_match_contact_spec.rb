require 'rails_helper'

# 📞 Auditoria 10/2026 (#239, fecha o A16 de julho): casar telefone com contato
# confere o DDD. Dois números que só compartilham os 8 últimos dígitos
# (11 99999-0000 × 21 99999-0000) são pessoas diferentes — a consulta de um
# nunca pode cair no cadastro do outro.
RSpec.describe Task do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let!(:sao_paulo) { create(:contact, account: account, name: 'Maria SP', phone_number: '+5511999990000') }
  let!(:rio) { create(:contact, account: account, name: 'Maria RJ', phone_number: '+5521999990000') }

  describe '.match_contact' do
    it 'acha o cadastro certo pelo DDD, com ou sem +55 e máscara', :aggregate_failures do
      expect(described_class.match_contact(account, '(21) 99999-0000')).to eq(rio)
      expect(described_class.match_contact(account, '+55 11 99999-0000')).to eq(sao_paulo)
      expect(described_class.match_contact(account, '5511999990000')).to eq(sao_paulo)
    end

    it 'telefone sem DDD que bate com dois cadastros prefere o DDD da clínica (mesma convenção do normalize_phone)' do
      expect(described_class.match_contact(account, '99999-0000')).to eq(sao_paulo)
    end

    it 'telefone sem DDD que bate com dois cadastros e nenhum é do DDD da clínica = ambíguo → nil (não chuta o mais antigo)' do
      sao_paulo.destroy!
      create(:contact, account: account, name: 'Maria MG', phone_number: '+5531999990000')
      expect(described_class.match_contact(account, '99999-0000')).to be_nil
    end

    it 'cadastro duplicado da MESMA linha (sync com +55 e digitado sem +55) não vira ambíguo: devolve o exato mais antigo', :aggregate_failures do
      manual = create(:contact, account: account, name: 'Maria SP (manual)', phone_number: '+11999990000')
      expect(described_class.match_contact(account, '(11) 99999-0000')).to eq(sao_paulo)
      expect(described_class.match_contact(account, '+55 11 99999-0000')).to eq(sao_paulo)
      sao_paulo.destroy!
      expect(described_class.match_contact(account, '5511999990000')).to eq(manual)
    end

    it 'não casa número de outro DDD só pelo final de 8 dígitos' do
      expect(described_class.match_contact(account, '(31) 99999-0000')).to be_nil
    end
  end

  describe 'vínculo automático da task pelo telefone (link_contact_by_phone)' do
    it 'consulta com o telefone do Rio amarra no cadastro do Rio, não no mais antigo' do
      task = described_class.create!(account: account, creator: user, title: 'Consulta: Maria RJ', task_type: 'consulta',
                                     due_at: 1.day.from_now, phone: '(21) 99999-0000')
      expect(task.contact).to eq(rio)
    end

    it 'telefone ambíguo (sem DDD, dois cadastros fora do DDD da clínica) fica sem vínculo' do
      sao_paulo.destroy!
      create(:contact, account: account, name: 'Maria MG', phone_number: '+5531999990000')
      task = described_class.create!(account: account, creator: user, title: 'Consulta: Maria', task_type: 'consulta',
                                     due_at: 1.day.from_now, phone: '99999-0000')
      expect(task.contact).to be_nil
    end

    it 'telefone sem DDD com cadastro do DDD da clínica amarra nele' do
      task = described_class.create!(account: account, creator: user, title: 'Consulta: Maria', task_type: 'consulta',
                                     due_at: 1.day.from_now, phone: '99999-0000')
      expect(task.contact).to eq(sao_paulo)
    end
  end

  describe '.for_patient' do
    let!(:legacy_rio) do
      described_class.create!(account: account, creator: user, title: 'Consulta antiga RJ', task_type: 'consulta',
                              due_at: 10.days.ago, phone: '(21) 99999-0000').tap { |t| t.update_column(:contact_id, nil) } # rubocop:disable Rails/SkipsModelValidations
    end

    it 'registro antigo sem link entra só para o paciente da mesma linha', :aggregate_failures do
      expect(described_class.for_patient(account, rio)).to include(legacy_rio)
      expect(described_class.for_patient(account, sao_paulo)).not_to include(legacy_rio)
    end
  end

  describe 'tipo da consulta (infer_consulta_modality)' do
    it 'consulta anterior de outro DDD não faz a primeira consulta virar retorno' do
      account.contacts.destroy_all # sem cadastro: o hook decide só pelo telefone
      described_class.create!(account: account, creator: user, title: 'Consulta antiga RJ', task_type: 'consulta',
                              due_at: 10.days.ago, phone: '(21) 99999-0000')
      nova = described_class.create!(account: account, creator: user, title: 'Consulta: Maria SP', task_type: 'consulta',
                                     due_at: 1.day.from_now, phone: '(11) 99999-0000')
      expect(nova.modality).to eq('avaliacao')
    end

    it 'consulta anterior da MESMA linha faz a nova nascer como retorno' do
      account.contacts.destroy_all
      described_class.create!(account: account, creator: user, title: 'Consulta antiga SP', task_type: 'consulta',
                              due_at: 10.days.ago, phone: '(11) 99999-0000')
      nova = described_class.create!(account: account, creator: user, title: 'Consulta: Maria SP', task_type: 'consulta',
                                     due_at: 1.day.from_now, phone: '+55 11 99999-0000')
      expect(nova.modality).to eq('retorno')
    end
  end
end
