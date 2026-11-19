import { mount } from '@vue/test-utils';
import TimelineChart from '../TimelineChart.vue';

const labels = ['01/10', '02/10', '03/10', '04/10', '05/10'];
const line = {
  key: 'meta',
  label: 'Meta Ads',
  color: '#db2777',
  values: [null, 40, null, 60, 50],
};
const linePaths = wrapper =>
  wrapper.findAll('svg path[stroke="#db2777"]').map(p => ({
    d: p.attributes('d'),
    dash: p.attributes('stroke-dasharray'),
  }));

describe('TimelineChart', () => {
  it('padrão antigo: curva suave e ponto solto onde a linha quebra', () => {
    const wrapper = mount(TimelineChart, { props: { labels, lines: [line] } });
    const paths = linePaths(wrapper);
    expect(paths).toHaveLength(1);
    expect(paths[0].d).toContain('C');
    expect(wrapper.findAll('svg circle[r="4"]')).toHaveLength(1);
  });

  it('linhas certinhas: reta de ponto a ponto e pontilhado sobre o buraco do meio', () => {
    const wrapper = mount(TimelineChart, {
      props: {
        labels,
        lines: [{ ...line, dots: [false, true, false, true, true] }],
        straight: true,
        bridgeGaps: true,
      },
    });
    const paths = linePaths(wrapper);
    const solid = paths.filter(p => !p.dash);
    const dotted = paths.filter(p => p.dash);
    expect(solid).toHaveLength(1);
    expect(dotted).toHaveLength(1);
    paths.forEach(p => expect(p.d).not.toContain('C'));
    // bolinha só nos baldes marcados (3), nenhuma bola grande solta
    expect(wrapper.findAll('svg circle[fill="#db2777"]')).toHaveLength(3);
    expect(wrapper.findAll('svg circle[r="4"]')).toHaveLength(0);
  });

  it('a legenda mostra o número que a tela mandar', () => {
    const wrapper = mount(TimelineChart, {
      props: {
        labels,
        lines: [{ ...line, legendValue: 'R$ 50 no período' }],
        straight: true,
      },
    });
    expect(wrapper.text()).toContain('Meta Ads');
    expect(wrapper.text()).toContain('R$ 50 no período');
  });
});
