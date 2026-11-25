import { mount, flushPromises } from '@vue/test-utils';
import AgentConsultant from '../AgentConsultant.vue';
import CrmAPI from 'dashboard/api/crm';

// 🧑‍🏫 item 414: consultor superior — a peça do cartão do atendente
vi.mock('dashboard/api/crm', () => ({
  default: { getAiConsultant: vi.fn(), saveAiConsultant: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const config = (overrides = {}) => ({
  enabled: false,
  model: '',
  mode: 'sombra',
  triggers: { chamar_humano: true, vaga_invalida: true, sem_pergunta: true },
  question_stages: ['recepcao', 'sondagem'],
  inbox_ids: [],
  tool: false,
  daily_cap: 50,
  timeout: 40,
  effort: 'medium',
  ...overrides,
});

const emptyDay = {
  consultas: 0,
  barradas: 0,
  testes: 0,
  mudou: 0,
  aplicadas: 0,
  falhas: 0,
  puladas: 0,
  custo_usd: 0,
  gatilhos: {},
  efeitos: {},
};

const payload = (overrides = {}, extra = {}) => ({
  agent: 'atendente_agendamento',
  config: config(overrides),
  ready: !!overrides.enabled,
  default_model: 'gpt-6-luna',
  staged: false,
  triggers: {
    chamar_humano: 'chamou a equipe sem urgência clínica',
    vaga_invalida: 'ia agendar em um horário que não validou',
    sem_pergunta: 'resposta vazia ou sem pergunta',
  },
  stages: ['recepcao', 'sondagem', 'autoridade'],
  efforts: ['low', 'medium', 'high'],
  effect_labels: { evitou_equipe: 'não precisava chamar a equipe' },
  trigger_labels: { chamar_humano: 'chamou a equipe sem urgência clínica' },
  limits: { cap_max: 5000, timeout_min: 10, timeout_max: 90 },
  stats: { today: emptyDay, total: emptyDay, cap: 50, span: 7, daily: [] },
  recent: [],
  usd_brl: 5,
  ...extra,
});

const PickerStub = {
  props: ['modelValue', 'emptyLabel'],
  emits: ['update:modelValue'],
  template:
    '<select class="picker" :value="modelValue" @change="$emit(\'update:modelValue\', $event.target.value)"><option value="">{{ emptyLabel }}</option><option value="claude-sonnet-5">Sonnet 5</option></select>',
};

const build = () =>
  mount(AgentConsultant, {
    props: {
      agentKey: 'atendente_agendamento',
      openaiModels: [{ value: 'gpt-6-luna', label: 'GPT-6 Luna' }],
      claudeModels: [{ value: 'claude-sonnet-5', label: 'Claude Sonnet 5' }],
      inboxes: [
        { id: 7, name: 'INSTAGRAM 2' },
        { id: 8, name: 'GOOGLE' },
      ],
    },
    global: { stubs: { LlmModelPicker: PickerStub } },
  });

describe('AgentConsultant', () => {
  beforeEach(() => {
    CrmAPI.getAiConsultant.mockReset();
    CrmAPI.saveAiConsultant.mockReset();
  });

  it('nasce desligado, em sombra, com os três gatilhos e sem contador', async () => {
    CrmAPI.getAiConsultant.mockResolvedValue({ data: payload() });
    const wrapper = build();
    await flushPromises();

    const text = wrapper.text();
    expect(text).toContain('Consultor superior');
    expect(text).toContain('desligado');
    expect(text).toContain('Chamou a equipe sem urgência');
    expect(text).toContain('Horário que não validou');
    expect(text).toContain('Resposta vazia ou sem pergunta');
    expect(text).toContain('O atendente responde com GPT-6 Luna');
    expect(text).not.toContain('O que o consultor fez');
    // gatilhos (3) + ferramenta (1), além do interruptor geral
    expect(wrapper.findAll('button.cv-switch')).toHaveLength(5);
    expect(wrapper.findAll('button.cv-switch.cv-switch-on').length).toBe(3);
  });

  it('salva o modelo, o modo e os gatilhos escolhidos', async () => {
    CrmAPI.getAiConsultant.mockResolvedValue({ data: payload() });
    CrmAPI.saveAiConsultant.mockResolvedValue({
      data: payload({ model: 'claude-sonnet-5', mode: 'ativo' }),
    });
    const wrapper = build();
    await flushPromises();

    const saveButton = () =>
      wrapper.findAll('button.cv-btn').find(b => b.text().includes('Salvar'));
    expect(saveButton().attributes('disabled')).toBeDefined();

    await wrapper.find('select.picker').setValue('claude-sonnet-5');
    // só na caixa INSTAGRAM 2
    await wrapper
      .findAll('button.cv-chip')
      .find(b => b.text() === 'INSTAGRAM 2')
      .trigger('click');
    await wrapper
      .findAll('button.cv-seg-item')
      .find(b => b.text() === 'Ativo')
      .trigger('click');
    // desliga o gatilho "resposta vazia ou sem pergunta" (o 3º interruptor pequeno)
    await wrapper
      .findAll('button.cv-switch:not(.cv-switch-lg)')[2]
      .trigger('click');
    expect(saveButton().attributes('disabled')).toBeUndefined();
    await saveButton().trigger('click');
    await flushPromises();

    expect(CrmAPI.saveAiConsultant).toHaveBeenCalledWith({
      agent: 'atendente_agendamento',
      consultor: config({
        model: 'claude-sonnet-5',
        mode: 'ativo',
        inbox_ids: [7],
        triggers: {
          chamar_humano: true,
          vaga_invalida: true,
          sem_pergunta: false,
        },
      }),
    });
  });

  it('o interruptor liga na hora com o que está na tela', async () => {
    CrmAPI.getAiConsultant.mockResolvedValue({
      data: payload({ model: 'claude-sonnet-5' }),
    });
    CrmAPI.saveAiConsultant.mockResolvedValue({
      data: payload({ model: 'claude-sonnet-5', enabled: true }),
    });
    const wrapper = build();
    await flushPromises();

    await wrapper.find('button.cv-switch-lg').trigger('click');
    await flushPromises();

    expect(CrmAPI.saveAiConsultant).toHaveBeenCalledWith({
      agent: 'atendente_agendamento',
      consultor: config({ model: 'claude-sonnet-5', enabled: true }),
    });
    expect(wrapper.text()).toContain('em sombra');
  });

  it('mostra o contador e as últimas consultas (o que o principal ia fazer × o que saiu)', async () => {
    const total = {
      ...emptyDay,
      consultas: 12,
      testes: 3,
      mudou: 5,
      falhas: 1,
      custo_usd: 0.42,
      gatilhos: { chamar_humano: 9 },
      efeitos: { evitou_equipe: 5 },
    };
    CrmAPI.getAiConsultant.mockResolvedValue({
      data: payload(
        { enabled: true, model: 'claude-sonnet-5' },
        {
          stats: {
            today: { ...emptyDay, consultas: 4 },
            total,
            cap: 50,
            span: 7,
            daily: [],
          },
          recent: [
            {
              id: 9,
              at: '2026-11-24T15:00:00Z',
              conversation_id: 123,
              contact: 'Ana',
              headline: '🧑‍🏫 Consultor superior → não precisava chamar a equipe',
              record: {
                gatilho: 'chamar_humano',
                modelo: 'claude-sonnet-5',
                principal: 'gpt-6-luna',
                aplicado: false,
                antes: {
                  mensagens: ['Vou passar para a equipe.'],
                  chamar_humano: true,
                },
                depois: { mensagens: ['É R$ 300. Quer um horário?'] },
              },
            },
          ],
        }
      ),
    });
    const wrapper = build();
    await flushPromises();

    const text = wrapper.text();
    expect(text).toContain('4 de 50');
    expect(text).toContain('5 de 14'); // 12 + 3 testes - 1 falha
    expect(text).toMatch(/R\$\s?2,10/); // US$ 0,42 × 5
    expect(text).toContain('9× chamou a equipe sem urgência clínica');
    expect(text).toContain('5× não precisava chamar a equipe');

    await wrapper
      .findAll('button')
      .find(b => /última/.test(b.text()))
      .trigger('click');
    await wrapper
      .findAll('button')
      .find(b => b.text().includes('conversa #123'))
      .trigger('click');
    const open = wrapper.text();
    expect(open).toContain('Vou passar para a equipe.');
    expect(open).toContain('chamaria a equipe');
    expect(open).toContain('O consultor (Claude Sonnet 5) responderia');
    expect(open).toContain('É R$ 300. Quer um horário?');
  });
});
