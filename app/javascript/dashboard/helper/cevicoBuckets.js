// 📈 item 285 (29/09): fatia um período em BALDES de tempo (hora, dia ou
// semana) para os gráficos de área do kit. Período de até 2 dias → por hora;
// até 45 dias → por dia; acima → por semana.
const HOUR = 3600000;
const DAY = 24 * HOUR;
const pad = n => String(n).padStart(2, '0');

export const granularityOf = (since, until) => {
  const span = new Date(until) - new Date(since);
  if (span <= 2 * DAY) return 'hour';
  if (span <= 45 * DAY) return 'day';
  return 'week';
};

const floorTo = (date, gran) => {
  const d = new Date(date);
  d.setMinutes(0, 0, 0);
  if (gran !== 'hour') d.setHours(0);
  return d;
};
const stepOf = gran => {
  if (gran === 'hour') return HOUR;
  if (gran === 'day') return DAY;
  return 7 * DAY;
};
const labelOf = (d, gran) => {
  if (gran === 'hour') return `${pad(d.getHours())}h`;
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`;
};

// items: lista qualquer · at(item) → data · key(item) → a série do item
// devolve { labels, granularity, series: { [key]: [n por balde] }, total: [n por balde] }
export const bucketize = (items, since, until, at, key = () => 'total') => {
  const gran = granularityOf(since, until);
  const step = stepOf(gran);
  const start = floorTo(since, gran).getTime();
  const end = Math.max(start, Math.min(new Date(until).getTime(), Date.now()));
  const size = Math.min(400, Math.max(1, Math.floor((end - start) / step) + 1));
  const labels = Array.from({ length: size }, (_, i) =>
    labelOf(new Date(start + i * step), gran)
  );
  const series = {};
  const total = new Array(size).fill(0);
  items.forEach(item => {
    const when = at(item);
    if (!when) return;
    const i = Math.floor((new Date(when).getTime() - start) / step);
    if (i < 0 || i >= size) return;
    const k = key(item);
    if (!series[k]) series[k] = new Array(size).fill(0);
    series[k][i] += 1;
    total[i] += 1;
  });
  return { labels, granularity: gran, series, total };
};

// curva suave que passa pelos pontos sem "barriga" abaixo de zero
// (monótona: cada trecho vira uma Bézier cúbica)
export const smoothPath = pts => {
  if (!pts.length) return '';
  if (pts.length === 1) return `M${pts[0][0]},${pts[0][1]}`;
  const n = pts.length;
  const dx = [];
  const slope = [];
  for (let i = 0; i < n - 1; i += 1) {
    dx.push(pts[i + 1][0] - pts[i][0]);
    slope.push((pts[i + 1][1] - pts[i][1]) / (dx[i] || 1));
  }
  const tan = [slope[0]];
  for (let i = 1; i < n - 1; i += 1) {
    tan.push(slope[i - 1] * slope[i] <= 0 ? 0 : (slope[i - 1] + slope[i]) / 2);
  }
  tan.push(slope[n - 2]);
  for (let i = 0; i < n - 1; i += 1) {
    if (slope[i] === 0) {
      tan[i] = 0;
      tan[i + 1] = 0;
    } else {
      const a = tan[i] / slope[i];
      const b = tan[i + 1] / slope[i];
      const h = Math.hypot(a, b);
      if (h > 3) {
        tan[i] = (3 / h) * a * slope[i];
        tan[i + 1] = (3 / h) * b * slope[i];
      }
    }
  }
  const f = v => v.toFixed(1);
  let d = `M${f(pts[0][0])},${f(pts[0][1])}`;
  for (let i = 0; i < n - 1; i += 1) {
    const c1x = pts[i][0] + dx[i] / 3;
    const c1y = pts[i][1] + (tan[i] * dx[i]) / 3;
    const c2x = pts[i + 1][0] - dx[i] / 3;
    const c2y = pts[i + 1][1] - (tan[i + 1] * dx[i]) / 3;
    d += ` C${f(c1x)},${f(c1y)} ${f(c2x)},${f(c2y)} ${f(pts[i + 1][0])},${f(pts[i + 1][1])}`;
  }
  return d;
};
