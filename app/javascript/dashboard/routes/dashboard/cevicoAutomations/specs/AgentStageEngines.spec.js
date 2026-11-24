import { mount, flushPromises } from '@vue/test-utils';
import AgentStageEngines from '../AgentStageEngines.vue';
import CrmAPI from 'dashboard/api/crm';

// 🧭 23/11: motor por coluna do CRM — a peça do cartão do atendente
vi.mock('dashboard/api/crm', () => ({
  default: { getAiStageModels: vi.fn(), saveAiStageModels: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const payload = (stageModels = {}) => ({
  agent: 'atendente_agendamento',
  default_model: 'claude-sonnet-5',
  stages: [
    { slot: 'sem_card', name: 'Sem card ainda (contato novo)' },
    { slot: '1', name: 'Novos Contatos' },
    { slot: '2', name: 'Envio de Orçamento' },
  ],
  stage_models: stageModels,
  usage_7d: [{ model: 'claude-sonnet-5', calls: 200, cost_usd: 10 }],
  usd_brl: 5,
});

const PickerStub = {
  props: ['modelValue', 'emptyLabel'],
  emits: ['update:modelValue'],
  template:
    '<select class="picker" :value="modelValue" @change="$emit(\'update:modelValue\', $event.target.value)"><option value="">{{ emptyLabel }}</option><option value="gpt-6-luna">GPT Luna</option><option value="claude-opus-5-5">Opus</option></select>',
};

const build = () =>
  mount(AgentStageEngines, {
    props: {
      agentKey: 'atendente_agendamento',
      claudeModels: [{ value: 'claude-sonnet-5', label: 'Claude Sonnet 5' }],
    },
    global: { stubs: { LlmModelPicker: PickerStub } },
  });

describe('AgentStageEngines', () => {
  beforeEach(() => {
    CrmAPI.getAiStageModels.mockReset();
    CrmAPI.saveAiStageModels.mockReset();
  });

  it('mostra uma linha por coluna, com o modelo do cartão como opção padrão', async () => {
    CrmAPI.getAiStageModels.mockResolvedValue({
      data: payload({ 2: 'claude-opus-5-5' }),
    });
    const wrapper = build();
    await flushPromises();

    const text = wrapper.text();
    expect(text).toContain('Sem card ainda (contato novo)');
    expect(text).toContain('Novos Contatos');
    expect(text).toContain('Envio de Orçamento');
    expect(text).toContain('O do cartão (Claude Sonnet 5)');
    expect(text).toContain('1 coluna com motor');
    const pickers = wrapper.findAll('select.picker');
    expect(pickers).toHaveLength(3);
    expect(pickers[2].element.value).toBe('claude-opus-5-5');
    // gasto por modelo em reais (10 dólares × 5)
    expect(text).toContain('200 chamadas');
    expect(text).toMatch(/R\$\s?50,00/);
  });

  it('só libera o Salvar quando há mudança e manda a escolha de cada coluna', async () => {
    CrmAPI.getAiStageModels.mockResolvedValue({ data: payload() });
    CrmAPI.saveAiStageModels.mockResolvedValue({
      data: payload({ 1: 'gpt-6-luna' }),
    });
    const wrapper = build();
    await flushPromises();

    const button = wrapper.find('button.cv-btn');
    expect(button.attributes('disabled')).toBeDefined();

    await wrapper.findAll('select.picker')[1].setValue('gpt-6-luna');
    expect(button.attributes('disabled')).toBeUndefined();
    await button.trigger('click');
    await flushPromises();

    expect(CrmAPI.saveAiStageModels).toHaveBeenCalledWith({
      agent: 'atendente_agendamento',
      stage_models: { 1: 'gpt-6-luna' },
    });
    expect(wrapper.find('button.cv-btn').attributes('disabled')).toBeDefined();
  });

  it('voltar para "o do cartão" tira a coluna da lista', async () => {
    CrmAPI.getAiStageModels.mockResolvedValue({
      data: payload({ 1: 'gpt-6-luna' }),
    });
    CrmAPI.saveAiStageModels.mockResolvedValue({ data: payload() });
    const wrapper = build();
    await flushPromises();

    await wrapper.findAll('select.picker')[1].setValue('');
    await wrapper.find('button.cv-btn').trigger('click');
    await flushPromises();

    expect(CrmAPI.saveAiStageModels).toHaveBeenCalledWith({
      agent: 'atendente_agendamento',
      stage_models: {},
    });
  });
});
