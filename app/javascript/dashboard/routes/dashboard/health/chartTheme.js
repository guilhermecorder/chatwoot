// TEMA dos gráficos Chart.js do HUB (rodada 31b) — pedido dele 19/09:
// "todas as palavras encaixem perfeitamente, fonte sem moldura, cores de
// alto contraste nos modos claro e escuro". Texto dos eixos/legendas em
// preto (claro) ou branco (escuro), 11px semibold, rótulos do eixo X sem
// rotação (pulam quando não cabem) e legenda com bolinha.
import { Chart as ChartJS } from 'chart.js';

export const isDarkMode = () =>
  document.documentElement.classList.contains('dark') || document.body.classList.contains('dark');

export const applyChartTheme = () => {
  const dark = isDarkMode();
  ChartJS.defaults.color = dark ? 'rgba(255, 255, 255, 0.88)' : '#1e293b';
  ChartJS.defaults.borderColor = dark ? 'rgba(255, 255, 255, 0.14)' : 'rgba(15, 23, 42, 0.1)';
  ChartJS.defaults.font.size = 11;
  ChartJS.defaults.font.weight = '600';
  ChartJS.defaults.scale.ticks.maxRotation = 0;
  ChartJS.defaults.scale.ticks.autoSkip = true;
  ChartJS.defaults.scale.ticks.autoSkipPadding = 10;
  ChartJS.defaults.plugins.legend.labels.boxWidth = 8;
  ChartJS.defaults.plugins.legend.labels.boxHeight = 8;
  ChartJS.defaults.plugins.legend.labels.usePointStyle = true;
  ChartJS.defaults.plugins.legend.labels.padding = 12;
  ChartJS.defaults.plugins.tooltip.titleFont = { size: 11, weight: '700' };
  ChartJS.defaults.plugins.tooltip.bodyFont = { size: 11 };
};

// troca de tema ao vivo (o app alterna a classe .dark sem recarregar):
// reaplica os padrões e redesenha os gráficos abertos
let watching = false;
export const watchChartTheme = () => {
  if (watching || typeof MutationObserver === 'undefined') return;
  watching = true;
  const obs = new MutationObserver(() => {
    applyChartTheme();
    Object.values(ChartJS.instances || {}).forEach(c => c.update('none'));
  });
  obs.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
  obs.observe(document.body, { attributes: true, attributeFilter: ['class'] });
};
