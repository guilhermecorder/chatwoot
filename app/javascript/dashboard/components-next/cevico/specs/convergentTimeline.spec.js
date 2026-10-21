import { mount } from '@vue/test-utils';
import ConvergentTimeline from '../ConvergentTimeline.vue';

const timeline = {
  granularity: 'week',
  buckets: [
    { label: '01/09', start: '2026-09-01', end: '2026-09-06' },
    { label: '07/09', start: '2026-09-07', end: '2026-09-13' },
    { label: '14/09', start: '2026-09-14', end: '2026-09-20' },
  ],
  tracks: [
    {
      key: 'spend',
      label: 'Investimento',
      source: 'Meta',
      unit: 'money',
      values: [100, 250, 50],
      total: 400,
    },
    {
      key: 'leads',
      label: 'Leads',
      source: 'WhatsApp + CRM',
      unit: 'count',
      values: [3, 8, 1],
      total: 12,
    },
    {
      key: 'surgeries',
      label: 'Cirurgias realizadas',
      source: 'CRM',
      unit: 'count',
      values: [0, 0, 0],
      total: 0,
    },
    {
      key: 'revenue',
      label: 'Receita',
      source: 'Oftalmofácil + CRM',
      unit: 'money',
      values: [0, 0, 9000],
      total: 9000,
    },
  ],
  lags: [
    {
      from: 'leads',
      to: 'booked',
      days: 2,
      people: 5,
      text: '2 dias entre chegar e marcar a consulta',
    },
  ],
  marks: [{ date: '2026-09-02', bucket: 0, label: 'entrou no ar' }],
  notes: ['Cada passo entra na data em que aconteceu.'],
};

describe('ConvergentTimeline', () => {
  it('desenha uma faixa por fonte, no mesmo eixo, com totais, atrasos e avisos', () => {
    const wrapper = mount(ConvergentTimeline, { props: { timeline } });
    expect(wrapper.findAll('.cv-ct-track')).toHaveLength(4);
    expect(wrapper.text()).toContain('Investimento');
    expect(wrapper.text()).toContain('R$ 400');
    expect(wrapper.text()).toContain('12');
    expect(wrapper.text()).toContain('nada registrado neste período');
    expect(wrapper.text()).toContain('entre chegar e marcar a consulta');
    expect(wrapper.text()).toContain('entrou no ar');
    expect(wrapper.text()).toContain('data em que aconteceu');
  });

  it('na versão sem dados financeiros some investimento e receita', () => {
    const wrapper = mount(ConvergentTimeline, {
      props: { timeline, hideMoney: true },
    });
    expect(wrapper.findAll('.cv-ct-track')).toHaveLength(2);
    expect(wrapper.text()).not.toContain('R$');
  });

  it('sem dados mostra o aviso', () => {
    const wrapper = mount(ConvergentTimeline, { props: { timeline: {} } });
    expect(wrapper.text()).toContain('sem dados neste período');
  });
});
