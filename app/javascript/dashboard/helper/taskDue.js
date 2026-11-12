// ⏰ 08/11/2026 (LIFE): CONTAGEM REGRESSIVA do prazo de uma tarefa — "em 3 dias",
// "amanhã 09:00", "hoje 09:00", "em 40 min", "atrasada há 2 dias". Usada no Meu
// Painel e no quadro de Tarefas, para o responsável saber o que fazer e quando.
// tone: 'late' (atrasada) · 'soon' (nas próximas 24 h) · 'later'
const pad = n => String(n).padStart(2, '0');
const hhmm = d => `${pad(d.getHours())}:${pad(d.getMinutes())}`;
const ddmm = d => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`;
const startOfDay = d => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const DAY = 24 * 60 * 60 * 1000;

export const dueCountdown = (iso, now = new Date()) => {
  if (!iso) return null;
  const due = new Date(iso);
  if (Number.isNaN(due.getTime())) return null;
  const diff = due.getTime() - now.getTime();
  const days = Math.round((startOfDay(due) - startOfDay(now)) / DAY);

  if (diff < 0) {
    if (days === 0)
      return { text: `atrasada desde ${hhmm(due)}`, tone: 'late' };
    const late = -days;
    return {
      text: `atrasada há ${late} ${late === 1 ? 'dia' : 'dias'}`,
      tone: 'late',
    };
  }
  const tone = diff <= DAY ? 'soon' : 'later';
  if (diff < 60 * 60 * 1000)
    return { text: `em ${Math.max(1, Math.round(diff / 60000))} min`, tone };
  if (days === 0) return { text: `hoje ${hhmm(due)}`, tone };
  if (days === 1) return { text: `amanhã ${hhmm(due)}`, tone };
  return { text: `em ${days} dias · ${ddmm(due)}`, tone };
};

// ⏳ 11/11/2026 (LIFE): PRAZO DA COLUNA no cartão do funil, em fala de gente
// (pedido do Guilherme: vocabulário mais amigável): "pra amanhã, 09:00",
// "é pra hoje, até 09:00", "atrasou 2 dias".
// tone: 'late' (vermelho, atrasou) · 'soon' (amarelo, menos de 24 h) · 'later' (verde)
export const stageDeadline = (iso, now = new Date()) => {
  if (!iso) return null;
  const due = new Date(iso);
  if (Number.isNaN(due.getTime())) return null;
  const diff = due.getTime() - now.getTime();
  const days = Math.round((startOfDay(due) - startOfDay(now)) / DAY);

  if (diff < 0) {
    const hours = Math.floor(-diff / (60 * 60 * 1000));
    if (hours < 1) return { text: 'acabou de vencer', tone: 'late' };
    if (hours < 24)
      return {
        text: `atrasou ${hours} ${hours === 1 ? 'hora' : 'horas'}`,
        tone: 'late',
      };
    const late = Math.floor(hours / 24);
    return {
      text: `atrasou ${late} ${late === 1 ? 'dia' : 'dias'}`,
      tone: 'late',
    };
  }
  const tone = diff <= DAY ? 'soon' : 'later';
  if (diff < 60 * 60 * 1000)
    return { text: `falta ${Math.max(1, Math.round(diff / 60000))} min`, tone };
  if (days === 0) return { text: `é pra hoje, até ${hhmm(due)}`, tone };
  if (days === 1) return { text: `pra amanhã, ${hhmm(due)}`, tone };
  return { text: `pra ${ddmm(due)} · faltam ${days} dias`, tone };
};
