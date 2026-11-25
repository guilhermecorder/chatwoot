import { mount, flushPromises } from '@vue/test-utils';
import AgentInboxEngines from '../AgentInboxEngines.vue';
import CrmAPI from 'dashboard/api/crm';

// 📥 item 416: motor por caixa — a peça do cartão do atendente
vi.mock('dashboard/api/crm', () => ({
  default: { getAiStageModels: vi.fn(), saveAiStageModels: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const payload = (engines = {}) => ({
  agent: 'atendente_agendamento',
  default_model: 'claude-sonnet-5',
  default_effort: 'medium',
  stages: [],
  stage_models: {},
  inboxes: [
    { id: '5', name: 'CONFIRMAÇÃO DE CONSULTA' },
    { id: '7', name: 'INSTAGRAM 2' },
  ],
  inbox_engines: engines,
  usage_7d: [],
  usd_brl: 5,
});

const PickerStub = {
  props: ['modelValue', 'emptyLabel'],
  emits: ['update:modelValue'],
  template:
    '<select class="picker" :value="modelValue" @change="$emit(\'update:modelValue\', $event.target.value)"><option value="">{{ emptyLabel }}</option><option value="gpt-6-luna">GPT Luna</option></select>',
};

const build = () =>
  mount(AgentInboxEngines, {
    props: { agentKey: 'atendente_agendamento' },
    global: { stubs: { LlmModelPicker: PickerStub } },
  });

describe('AgentInboxEngines', () => {
  beforeEach(() => {
    CrmAPI.getAiStageModels.mockReset();
    CrmAPI.saveAiStageModels.mockReset();
  });

  it('mostra só as caixas com motor próprio, com motor, esforço e Roteiro', async () => {
    CrmAPI.getAiStageModels.mockResolvedValue({
      data: payload({
        5: { model: 'gpt-6-luna', effort: 'high', script: 'v2' },
      }),
    });
    const wrapper = build();
    await flushPromises();

    const text = wrapper.text();
    expect(text).toContain('1 caixa com motor próprio');
    expect(text).toContain('CONFIRMAÇÃO DE CONSULTA');
    expect(wrapper.find('select.picker').element.value).toBe('gpt-6-luna');
    expect(wrapper.find('select.inbox-effort').element.value).toBe('high');
    expect(wrapper.find('select.inbox-script').element.value).toBe('v2');
    // o esforço do cartão aparece como opção padrão
    expect(text).toContain('O do cartão (médio)');
    // a outra caixa fica para adicionar
    const add = wrapper.find('select.inbox-add');
    expect(add.text()).toContain('INSTAGRAM 2');
    expect(add.text()).not.toContain('CONFIRMAÇÃO');
  });

  it('adiciona uma caixa, escolhe tudo e salva só as caixas', async () => {
    CrmAPI.getAiStageModels.mockResolvedValue({ data: payload() });
    CrmAPI.saveAiStageModels.mockResolvedValue({
      data: payload({
        5: { model: 'gpt-6-luna', effort: 'high', script: 'v2' },
      }),
    });
    const wrapper = build();
    await flushPromises();

    const button = wrapper.find('button.inbox-save');
    expect(button.attributes('disabled')).toBeDefined();

    await wrapper.find('select.inbox-add').setValue('5');
    await wrapper.find('select.picker').setValue('gpt-6-luna');
    await wrapper.find('select.inbox-effort').setValue('high');
    await wrapper.find('select.inbox-script').setValue('v2');
    expect(button.attributes('disabled')).toBeUndefined();
    await button.trigger('click');
    await flushPromises();

    expect(CrmAPI.saveAiStageModels).toHaveBeenCalledWith({
      agent: 'atendente_agendamento',
      part: 'inbox',
      inbox_engines: {
        5: { model: 'gpt-6-luna', effort: 'high', script: 'v2' },
      },
    });
  });

  it('tirar a caixa manda a lista sem ela', async () => {
    CrmAPI.getAiStageModels.mockResolvedValue({
      data: payload({ 5: { model: 'gpt-6-luna' } }),
    });
    CrmAPI.saveAiStageModels.mockResolvedValue({ data: payload() });
    const wrapper = build();
    await flushPromises();

    const remove = wrapper.findAll('button').find(b => b.text() === 'Tirar');
    await remove.trigger('click');
    await wrapper.find('button.inbox-save').trigger('click');
    await flushPromises();

    expect(CrmAPI.saveAiStageModels).toHaveBeenCalledWith({
      agent: 'atendente_agendamento',
      part: 'inbox',
      inbox_engines: {},
    });
  });
});
