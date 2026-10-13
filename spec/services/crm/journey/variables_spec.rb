require 'rails_helper'

# 🛡️ auditoria R3 (#46): a Meta recusa modelo com variável em branco — e o
# envio ficava "enviada". Token usado NUNCA sai vazio: texto de reserva para
# o que dá (unidade, endereço…) e bloqueio com motivo para o que importa
# (cirurgia sem hora/médico/procedimento, consulta sem hora, paciente sem nome).
RSpec.describe Crm::Journey::Variables do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:settings) { Crm::Journey::Settings.new(account) }
  let(:contact) { create(:contact, account: account, name: 'Maria Teste', phone_number: '+5511999990000') }
  let(:tz) { described_class::TZ }

  before { CrmSetting.create!(account: account, agenda_config: {}) }

  def surgery(hour: '08:30', provider: 'Dra. Fulana', procedure: 'Catarata', clinic: 'IOP')
    Crm::OftalmofacilSurgery.create!(account: account, contact: contact, item_token: SecureRandom.hex(4), patient_name: 'Maria Teste',
                                     surgery_date: Date.new(2026, 9, 19), surgery_hour: hour, status_kind: 'agendada',
                                     procedure_name: procedure, provider_name: provider, clinic_name: clinic, raw: {})
  end

  def message(kind:, text:)
    Crm::JourneyMessage.new(account: account, name: 'm', step: 'cirurgia',
                            trigger: { 'kind' => kind, 'offset_days' => -1, 'at' => '09:00' },
                            content: { 'mode' => 'text', 'text' => text })
  end

  describe '.build' do
    it 'nunca devolve valor em branco: cirurgia sem hora/médico ganha texto de reserva', :aggregate_failures do
      values = described_class.build(surgery(hour: nil, provider: '', clinic: ''), contact, settings)
      expect(values['hora']).to eq('a combinar')
      expect(values['medico']).to eq('nossa equipe médica')
      expect(values['unidade']).to eq('nossa clínica')
      expect(values['endereco']).to eq('endereço a confirmar')
      expect(values.values).to all(be_present)
    end

    it 'mantém os valores de verdade quando a fonte tem o dado', :aggregate_failures do
      values = described_class.build(surgery, contact, settings)
      expect(values).to include('nome' => 'Maria Teste', 'primeiro_nome' => 'Maria', 'data' => '19/09', 'dia_semana' => 'sábado',
                                'hora' => '08:30', 'medico' => 'Dra. Fulana', 'procedimento' => 'Catarata', 'unidade' => 'IOP')
    end

    it 'gatilho de coluna/etiqueta (fonte sem hora/unidade): todo token ganha reserva e nada sai como "{{hora}}"', :aggregate_failures do
      values = described_class.build(nil, contact, settings)
      expect(values.keys).to match_array(described_class::TOKENS)
      expect(values).to include('nome' => 'Maria Teste', 'hora' => 'a combinar', 'unidade' => 'nossa clínica', 'medico' => 'nossa equipe médica')
      text = described_class.substitute('Oi {{primeiro_nome}}, às {{hora}} na {{unidade}} com {{medico}}', values)
      expect(text).to eq('Oi Maria, às a combinar na nossa clínica com nossa equipe médica')
      expect(text).not_to include('{{')
      # hora/unidade não são obrigatórias nesse gatilho: não bloqueia, sai com a reserva
      expect(described_class.missing_reason(message(kind: 'label', text: 'às {{hora}}'), nil, contact, settings)).to be_nil
      expect(described_class.new(nil, contact, settings).blank_tokens).to include('hora', 'unidade', 'medico')
    end

    it 'consulta da Agenda sem médico ganha texto de reserva e a hora vem do horário', :aggregate_failures do
      task = account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                                   title: 'Consulta: Maria', due_at: tz.local(2026, 9, 18, 15, 0), contact: contact)
      values = described_class.build(task, contact, settings)
      expect(values['hora']).to eq('15:00')
      expect(values['medico']).to eq('nossa equipe médica')
      expect(values['unidade']).to be_present
    end
  end

  describe '.used_tokens' do
    it 'acha os tokens no texto livre, nas variáveis do modelo e no reforço', :aggregate_failures do
      expect(described_class.used_tokens(message(kind: 'surgery', text: 'Oi {{primeiro_nome}}, às {{ hora }} com {{medico}} {{xpto}}')))
        .to contain_exactly('primeiro_nome', 'hora', 'medico')

      template = Crm::JourneyMessage.new(
        account: account, name: 'm', step: 'cirurgia', trigger: { 'kind' => 'surgery', 'offset_days' => -1 },
        content: { 'mode' => 'template', 'template_params' => { 'processed_params' => { 'body' => { '1' => '{{nome}}', '2' => '{{data}}' } } },
                   'followup' => { 'enabled' => true, 'template_params' => { 'processed_params' => { 'body' => { '1' => '{{hora}}' } } } } }
      )
      expect(described_class.used_tokens(template)).to contain_exactly('nome', 'data')
      expect(described_class.used_tokens(template, followup: true)).to eq(['hora'])
    end
  end

  describe '.missing_reason' do
    it 'bloqueia cirurgia sem hora quando a mensagem usa {{hora}} (e diz qual variável)', :aggregate_failures do
      why = described_class.missing_reason(message(kind: 'surgery', text: 'Sua cirurgia é às {{hora}}'), surgery(hour: nil), contact, settings)
      expect(why).to start_with('Variável sem valor: hora')
      expect(why).to include('ia em branco')
    end

    it 'bloqueia cirurgia sem médico E sem procedimento listando os dois' do
      why = described_class.missing_reason(message(kind: 'surgery', text: '{{procedimento}} com {{medico}}'),
                                           surgery(provider: nil, procedure: nil), contact, settings)
      expect(why).to eq('Variável sem valor: procedimento, médico — a fonte está sem esse dado e a mensagem ia em branco')
    end

    it 'NÃO bloqueia quando a mensagem não usa o token que falta' do
      why = described_class.missing_reason(message(kind: 'surgery', text: 'Oi {{primeiro_nome}}, é {{data}}'), surgery(hour: nil), contact, settings)
      expect(why).to be_nil
    end

    it 'unidade/endereço sem dado NÃO bloqueiam (saem com o texto de reserva)' do
      why = described_class.missing_reason(message(kind: 'surgery', text: 'Na {{unidade}} ({{endereco}})'), surgery(clinic: ''), contact, settings)
      expect(why).to be_nil
    end

    it 'consulta: hora é obrigatória, médico não', :aggregate_failures do
      task = account.tasks.create!(task_type: 'consulta', modality: 'avaliacao', unit: 'paulista', creator: admin,
                                   title: 'Consulta: Maria', due_at: tz.local(2026, 9, 18, 15, 0), contact: contact)
      expect(described_class.missing_reason(message(kind: 'appointment', text: '{{hora}} {{medico}}'), task, contact, settings)).to be_nil

      task.update_columns(due_at: nil) # rubocop:disable Rails/SkipsModelValidations
      why = described_class.missing_reason(message(kind: 'appointment', text: 'às {{hora}}'), task.reload, contact, settings)
      expect(why).to start_with('Variável sem valor: hora')
    end

    it 'paciente sem nome bloqueia em qualquer gatilho que use o nome' do
      sem_nome = create(:contact, account: account, name: '', phone_number: '+5511999990001')
      why = described_class.missing_reason(message(kind: 'label', text: 'Oi {{primeiro_nome}}'), nil, sem_nome, settings)
      expect(why).to eq('Variável sem valor: nome — a fonte está sem esse dado e a mensagem ia em branco')
    end
  end

  describe '.sample (teste da jornada, #416)' do
    it 'só tem dados fictícios, todos preenchidos, e o lugar vem da configuração', :aggregate_failures do
      values = described_class.sample(settings)
      expect(values.keys).to match_array(described_class::TOKENS)
      expect(values.values).to all(be_present)
      expect(values['nome']).to eq('Ana Exemplo')
      expect(values['medico']).to eq('Dr. Exemplo')
      expect(values['unidade']).to eq('Unidade de exemplo')

      lugar = { 'default' => { 'unidade' => 'Av. Paulista', 'endereco' => 'Av. Paulista, 1000' } }
      CrmSetting.find_by!(account: account).update!(agenda_config: { 'journey' => { 'places' => lugar } })
      values = described_class.sample(Crm::Journey::Settings.new(account))
      expect(values['unidade']).to eq('Av. Paulista')
      expect(values['endereco']).to eq('Av. Paulista, 1000')
    end
  end
end
