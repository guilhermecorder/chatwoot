// 📅 RÉGUA DE PERÍODO PADRÃO do sistema (item 321, 03/10/2026 — pedido dele:
// "todas as visualizações de todos os ambientes eu gostaria que fossem assim").
// UMA lista só, na mesma ordem, em toda tela que escolhe período:
//   Hoje | Ontem | Últimos 7 dias | Semana passada | Este mês | Mês passado |
//   90 dias | Este ano | Personalizado
// Quem usa: PeriodRuler (a régua), o Kanban do CRM e os popups de indicador.
// O servidor entende as mesmas chaves no concern Crm::ResolvesPeriod.
export const PERIOD_PRESETS = [
  { key: 'today', label: 'Hoje' },
  { key: 'yesterday', label: 'Ontem' },
  { key: 'last7', label: 'Últimos 7 dias' },
  { key: 'last_week', label: 'Semana passada' },
  { key: 'month', label: 'Este mês' },
  { key: 'last_month', label: 'Mês passado' },
  { key: 'last90', label: '90 dias' },
  { key: 'year', label: 'Este ano' },
];

// 📈 item 418 (25/11): pílulas EXTRAS, que só aparecem na tela que pede
// (PeriodRuler :extra-presets="['last2']"). "Hoje + ontem" soma os dois dias,
// para o dia que está começando não ficar com número pequeno demais.
export const PERIOD_EXTRAS = [
  { key: 'last2', label: 'Hoje + ontem', after: 'yesterday' },
];

// a lista da régua com as extras pedidas, cada uma no seu lugar
export const periodPresetsWith = (extraKeys = []) => {
  const list = [...PERIOD_PRESETS];
  PERIOD_EXTRAS.filter(p => extraKeys.includes(p.key)).forEach(extra => {
    const at = list.findIndex(p => p.key === extra.after);
    list.splice(at < 0 ? list.length : at + 1, 0, {
      key: extra.key,
      label: extra.label,
    });
  });
  return list;
};

const pad = n => String(n).padStart(2, '0');
export const periodDateStr = d =>
  `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

// { from, to } (YYYY-MM-DD, fuso do navegador) de cada preset; chave
// desconhecida = hoje
export const periodRangeFor = (key, now = new Date()) => {
  const today = periodDateStr(now);
  const daysAgo = n => {
    const d = new Date(now);
    d.setDate(d.getDate() - n);
    return periodDateStr(d);
  };
  if (key === 'yesterday') return { from: daysAgo(1), to: daysAgo(1) };
  if (key === 'last2') return { from: daysAgo(1), to: today };
  if (key === 'last7') return { from: daysAgo(6), to: today };
  if (key === 'last_week') {
    // semana passada = segunda a domingo ANTERIORES
    const dow = (now.getDay() + 6) % 7; // seg=0 … dom=6
    return { from: daysAgo(dow + 7), to: daysAgo(dow + 1) };
  }
  if (key === 'month') {
    return {
      from: periodDateStr(new Date(now.getFullYear(), now.getMonth(), 1)),
      to: today,
    };
  }
  if (key === 'last_month') {
    return {
      from: periodDateStr(new Date(now.getFullYear(), now.getMonth() - 1, 1)),
      to: periodDateStr(new Date(now.getFullYear(), now.getMonth(), 0)),
    };
  }
  if (key === 'last90') return { from: daysAgo(89), to: today };
  if (key === 'year') {
    return {
      from: periodDateStr(new Date(now.getFullYear(), 0, 1)),
      to: today,
    };
  }
  return { from: today, to: today };
};

// parâmetros para o servidor: sempre o preset; De/Até só no Personalizado
export const periodParams = period => ({
  preset: period.preset,
  ...(period.preset === 'custom' ? { from: period.from, to: period.to } : {}),
});
