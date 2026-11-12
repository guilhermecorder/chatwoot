require 'rails_helper'

# 📝 11/11/2026 (LIFE): resumo escrito do cliente — ficha por conta, etiqueta do campo e a
# ferramenta `anotar_cliente` do atendente de IA.
RSpec.describe Crm::ClientSummary do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ivan Coral') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:campos) do
    [{ 'chave' => 'conta', 'rotulo' => 'Conta de luz', 'quando' => 'quanto paga por mês' },
     { 'chave' => 'Consumo Futuro', 'rotulo' => 'Vai aumentar o consumo', 'quando' => 'ar-condicionado, piscina',
       'etiqueta' => 'Consumo vai aumentar' },
     { 'chave' => '', 'rotulo' => 'sem chave' }]
  end

  def configure!(list = campos)
    CrmSetting.find_or_create_by!(account: account).update!(ai_config: { 'ficha_cliente' => { 'campos' => list } })
  end

  it 'conta sem campos = recurso desligado (a clínica não muda)', :aggregate_failures do
    expect(described_class.enabled?(account)).to be(false)
    expect(described_class.for(contact)).to eq(enabled: false, fields: [], filled: 0)
    expect(described_class.lines(contact, fields: [])).to eq([])
    expect(described_class.write!(contact, { 'conta' => 'R$ 300' }, by: 'Fernando')).to eq([])
  end

  it 'limpa os campos da conta: chave e etiqueta normalizadas, linha sem chave fica de fora' do
    configure!
    expect(described_class.fields(account)).to eq([
                                                    { 'chave' => 'conta', 'rotulo' => 'Conta de luz', 'quando' => 'quanto paga por mês' },
                                                    { 'chave' => 'consumo_futuro', 'rotulo' => 'Vai aumentar o consumo',
                                                      'quando' => 'ar-condicionado, piscina', 'etiqueta' => 'consumo-vai-aumentar' }
                                                  ])
  end

  it 'grava o que o cliente contou, mostra em linhas e põe a etiqueta do campo', :aggregate_failures do
    configure!
    dados = { 'conta' => ' R$ 300 ', 'consumo_futuro' => '2 ar-condicionados', 'outro' => 'x' }
    changed = described_class.write!(contact, dados, by: 'Fernando (IA)')

    expect(changed).to eq(%w[conta consumo_futuro])
    expect(described_class.lines(contact.reload, fields: described_class.fields(account)))
      .to eq([{ label: 'Conta de luz', value: 'R$ 300' }, { label: 'Vai aumentar o consumo', value: '2 ar-condicionados' }])
    expect(described_class.for(contact)).to include(enabled: true, filled: 2)
    expect(described_class.for(contact)[:fields].first).to include(key: 'conta', value: 'R$ 300', by: 'Fernando (IA)')
    expect(contact.label_list).to eq(['consumo-vai-aumentar'])
    expect(account.labels.pluck(:title)).to include('consumo-vai-aumentar')
  end

  it 'não mexe no resto dos dados do contato; valor igual não conta como mudança; vazio apaga e tira a etiqueta', :aggregate_failures do
    configure!
    Cevico::AttributeMerge.merge!(contact) { |attrs| attrs.merge('sexo' => 'masculino') }
    described_class.write!(contact, { 'conta' => 'R$ 300', 'consumo_futuro' => 'piscina' }, by: 'Fernando')

    expect(described_class.write!(contact, { 'conta' => 'R$ 300' }, by: 'Outra pessoa')).to eq([])
    expect(described_class.write!(contact, { 'consumo_futuro' => '' }, by: 'Fernando')).to eq(['consumo_futuro'])
    contact.reload
    expect(contact.additional_attributes['sexo']).to eq('masculino')
    expect(described_class.lines(contact, fields: described_class.fields(account))).to eq([{ label: 'Conta de luz', value: 'R$ 300' }])
    expect(contact.label_list).to be_empty
  end

  describe 'ferramenta anotar_cliente do atendente' do
    def tools(live: false, agent_key: 'atendente_agendamento')
      Crm::ResponderTools.new(conversation: conversation, agent_key: agent_key, live: live)
    end

    it 'só aparece com a ficha configurada e conta o que já foi anotado', :aggregate_failures do
      expect(tools.definitions.pluck(:name)).not_to include('anotar_cliente')

      configure!
      described_class.write!(contact, { 'conta' => 'R$ 300' }, by: 'Fernando')
      tool = tools.definitions.find { |d| d[:name] == 'anotar_cliente' }
      expect(tool.dig(:input_schema, :properties, :dados, :items, :properties, :campo, :enum)).to eq(%w[conta consumo_futuro])
      expect(tool[:description]).to include('consumo_futuro = Vai aumentar o consumo (ar-condicionado, piscina)')
      expect(tool[:description]).to include('Já anotado: Conta de luz: R$ 300.')
      expect(tools(agent_key: 'voice').definitions.pluck(:name)).not_to include('anotar_cliente')
    end

    it 'em sombra não grava nada' do
      configure!
      result = tools.call('anotar_cliente', { 'dados' => [{ 'campo' => 'conta', 'valor' => 'R$ 300' }] })
      expect(result).to include(simulado: true, ok: true)
      expect(described_class.for(contact.reload)[:filled]).to eq(0)
    end

    it 'ao vivo grava a ficha, põe a etiqueta e deixa o rastro na conversa', :aggregate_failures do
      configure!
      result = tools(live: true).call('anotar_cliente', { 'dados' => [{ 'campo' => 'conta', 'valor' => 'R$ 300 por mês' },
                                                                      { 'campo' => 'consumo_futuro', 'valor' => 'quer 2 ar-condicionados' },
                                                                      { 'campo' => 'cpf', 'valor' => '123' }] })

      expect(result).to eq(ok: true, anotado: %w[conta consumo_futuro])
      expect(described_class.lines(contact.reload, fields: described_class.fields(account)).pluck(:value))
        .to eq(['R$ 300 por mês', 'quer 2 ar-condicionados'])
      expect(contact.label_list).to include('consumo-vai-aumentar')
      expect(conversation.messages.where(private: true).last.content).to include('Vai aumentar o consumo: quer 2 ar-condicionados')
    end

    it 'recusa quando nenhum dado é da lista' do
      configure!
      result = tools(live: true).call('anotar_cliente', { 'dados' => [{ 'campo' => 'cpf', 'valor' => '123' }] })
      expect(result[:ok]).to be(false)
    end
  end
end
