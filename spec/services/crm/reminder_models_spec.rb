require 'rails_helper'

# 🎯 item 327 (05/10): qual modelo vai para a consulta — personalizado por
# médico e por tipo de atendimento antes do padrão; unidade antes do geral.
RSpec.describe Crm::ReminderModels do
  let(:tpl) { ->(name) { { 'template_params' => { 'name' => name }, 'message_preview' => name } } }
  let(:block) do
    { 'units' => { 'paulista' => tpl.call('padrao_paulista') }, 'followup' => tpl.call('reforco_padrao') }.merge(tpl.call('padrao_geral')).merge(
      'variants' => [
        { 'modality' => 'retorno', 'followup' => tpl.call('reforco_retorno') }.merge(tpl.call('retorno_geral')),
        { 'doctor' => 'Dra. Roberta Negri', 'units' => { 'tatuape' => tpl.call('roberta_tatuape') } },
        { 'units' => { 'paulista' => tpl.call('sem_tipo_nem_medico') } } # ignorado: não diz para quem é
      ]
    )
  end

  def consulta(attrs = {})
    Task.new({ task_type: 'consulta', modality: 'avaliacao', unit: 'paulista' }.merge(attrs))
  end

  def name_of(picked)
    picked&.dig('template_params', 'name')
  end

  it 'escolhe do mais específico para o padrão, e avisa quando saiu o geral', :aggregate_failures do
    expect(described_class.pick(block, consulta)).to include('rank' => [0, 1]).and(satisfy { |p| name_of(p) == 'padrao_paulista' })
    retorno = described_class.pick(block, consulta(modality: 'retorno'))
    expect(retorno).to include('rank' => [1, 0], 'general' => true, 'model' => 'Retorno')
    expect(name_of(retorno)).to eq('retorno_geral')
    roberta = described_class.pick(block, consulta(unit: 'tatuape', doctor: 'DRA. ROBERTA NEGRI', modality: 'retorno'))
    expect(name_of(roberta)).to eq('roberta_tatuape') # médico vence tipo
    expect(roberta['model']).to eq('Dra. Roberta Negri')
  end

  it 'conjunto sem modelo para a consulta passa a vez; sem unidade vale Av. Paulista; tipo desconhecido = avaliação', :aggregate_failures do
    expect(name_of(described_class.pick(block, consulta(doctor: 'Dra. Roberta Negri')))).to eq('padrao_paulista')
    expect(name_of(described_class.pick(block, consulta(unit: nil)))).to eq('padrao_paulista')
    expect(name_of(described_class.pick(block, consulta(unit: 'tatuape', modality: nil)))).to eq('padrao_geral')
    expect(described_class.pick({}, consulta)).to be_nil
  end

  it 'compara dois modelos: tipo/médico antes de unidade × geral' do
    padrao_unidade = described_class.pick(block, consulta)
    retorno_geral = described_class.pick(block, consulta(modality: 'retorno'))
    expect(described_class.better?(retorno_geral, padrao_unidade)).to be(true)
    expect(described_class.better?(padrao_unidade, padrao_unidade)).to be(false)
    expect(described_class.better?(nil, padrao_unidade)).to be(false)
  end

  it 'reforço: o personalizado quando existe, senão o padrão do bloco', :aggregate_failures do
    expect(described_class.followup(block, consulta(modality: 'retorno'))).to include('model' => 'Retorno')
    expect(name_of(described_class.followup(block, consulta))).to eq('reforco_padrao')
    expect(described_class.followup({ 'variants' => [] }, consulta)).to be_nil
  end
end
