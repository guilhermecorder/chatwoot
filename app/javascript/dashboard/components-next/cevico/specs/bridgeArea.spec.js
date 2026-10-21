import { mount } from '@vue/test-utils';
import AreaChart from '../AreaChart.vue';
import BridgeFlow from '../BridgeFlow.vue';

describe('AreaChart', () => {
  it('desenha uma área por série com valor e avisa o clique na legenda', async () => {
    const wrapper = mount(AreaChart, {
      props: {
        labels: ['01/09', '02/09', '03/09'],
        series: [
          { key: 'google', label: 'Google', color: '#2563eb', values: [1, 3, 2] },
          { key: 'vazio', label: 'Vazio', color: '#000000', values: [0, 0, 0] },
        ],
      },
    });
    expect(wrapper.findAll('.cv-area-serie')).toHaveLength(1);
    expect(wrapper.text()).toContain('Google');
    expect(wrapper.text()).toContain('100%');
    await wrapper.find('.cv-area-key').trigger('click');
    expect(wrapper.emitted('pick')[0][0].key).toBe('google');
  });

  it('sem dados mostra o aviso em vez do gráfico', () => {
    const wrapper = mount(AreaChart, { props: { labels: [], series: [] } });
    expect(wrapper.find('svg').exists()).toBe(false);
    expect(wrapper.text()).toContain('nada no período');
  });
});

describe('BridgeFlow', () => {
  const sides = [
    {
      key: 'column',
      title: 'Entraram em Agendamento',
      total: 4,
      unit: 'pacientes',
      color: '#6d28d9',
      branches: [
        { key: 'both', label: 'com consulta marcada', hint: 'a', count: 2 },
        { key: 'no_consult', label: 'sem consulta', hint: 'b', count: 2 },
      ],
    },
    {
      key: 'agenda',
      title: 'Marcadas na Agenda',
      total: 13,
      unit: 'consultas',
      color: '#2563eb',
      branches: [
        { key: 'both', label: 'entraram na coluna', hint: 'c', count: 2 },
        {
          key: 'other_stage',
          label: 'card em outra coluna',
          hint: 'd',
          count: 11,
          stages: [{ name: 'Cirurgia Realizada', color: '#10b981', count: 11 }],
        },
        { key: 'no_card', label: 'sem card', hint: 'e', count: 0 },
      ],
    },
  ];

  it('mostra cada número com os seus ramos e destaca o que é comum', async () => {
    const wrapper = mount(BridgeFlow, { props: { sides } });
    expect(wrapper.findAll('.cv-bridge-side')).toHaveLength(2);
    expect(wrapper.findAll('.cv-bridge-branch')).toHaveLength(4);
    expect(wrapper.findAll('.cv-bridge-shared')).toHaveLength(2);
    expect(wrapper.text()).toContain('Cirurgia Realizada');
    await wrapper.findAll('.cv-bridge-branch')[3].trigger('click');
    expect(wrapper.emitted('pick')[0][0].branch.key).toBe('other_stage');
  });
});
