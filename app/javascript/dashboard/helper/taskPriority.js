// 🌡️ 11/11/2026 (LIFE, pedido do Guilherme): as TAREFAS do Meu Painel com
// cliente, etapa do funil, valor e TEMPERATURA, em ordem de prioridade.
// Os pontos vêm do servidor (Crm::TaskPriority); aqui fica só a FALA DE GENTE:
// "falou há 3 horas e espera resposta", "R$ 24.800", o porquê da temperatura.
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

// a regra, do jeito que aparece na tela ("Como a temperatura funciona")
export const HEAT_RULE = [
  {
    key: 'fala',
    title: 'O cliente falou há pouco?',
    detail: 'até 24 horas +3 · até 3 dias +2 · até 7 dias +1',
  },
  {
    key: 'espera',
    title: 'Ele está esperando resposta?',
    detail: 'a última mensagem da conversa é dele +1',
  },
  {
    key: 'etapa',
    title: 'Onde está no funil?',
    detail: '+1 por etapa que já avançou, até +3',
  },
  {
    key: 'prazo',
    title: 'E o prazo da tarefa?',
    detail: 'atrasou +3 · vence nas próximas 24 horas +2',
  },
];

export const HEAT_LEVELS = {
  quente: {
    label: 'Quente',
    range: '7 a 10 pontos',
    icon: 'i-lucide-flame',
    hint: 'pegue primeiro',
  },
  morna: {
    label: 'Morna',
    range: '4 a 6 pontos',
    icon: 'i-lucide-thermometer',
    hint: 'ainda hoje',
  },
  fria: {
    label: 'Fria',
    range: '0 a 3 pontos',
    icon: 'i-lucide-snowflake',
    hint: 'pode esperar',
  },
};

export const heatMeta = task =>
  HEAT_LEVELS[task?.heat?.level] || HEAT_LEVELS.fria;

// "há 20 min", "há 3 horas", "ontem", "há 5 dias"
export const agoText = (iso, now = new Date()) => {
  if (!iso) return null;
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return null;
  const diff = Math.max(0, now.getTime() - at.getTime());
  if (diff < 5 * 60 * 1000) return 'agora há pouco';
  if (diff < HOUR) return `há ${Math.round(diff / 60000)} min`;
  if (diff < DAY) {
    const hours = Math.floor(diff / HOUR);
    return `há ${hours} ${hours === 1 ? 'hora' : 'horas'}`;
  }
  const days = Math.floor(diff / DAY);
  return days === 1 ? 'ontem' : `há ${days} dias`;
};

// o que o sistema sabe da conversa com o cliente, numa frase
//   tone: 'wait' (ele espera resposta) · 'talk' (falou e já foi respondido) ·
//         'quiet' (faz mais de 7 dias) · 'none' (nunca mandou mensagem)
export const clientLine = (task, now = new Date()) => {
  if (!task?.contact) return null;
  const ago = agoText(task.last_client_at, now);
  if (!ago) return { text: 'Ainda sem mensagem do cliente', tone: 'none' };
  if (task.client_waiting)
    return { text: `Falou ${ago} e espera resposta`, tone: 'wait' };
  const quiet =
    now.getTime() - new Date(task.last_client_at).getTime() > 7 * DAY;
  return quiet
    ? { text: `Em silêncio: última mensagem ${ago}`, tone: 'quiet' }
    : { text: `Falou ${ago}, já respondido`, tone: 'talk' };
};

// título da tarefa → { who, what }: "⏰ Retorno · Marcos Silva — Retorno:
// chamar o cliente" vira quem = Marcos Silva, o quê = "Retorno: chamar o cliente"
const LEADING_MARK = /^[^\p{L}\p{N}]+/u;
export const splitTaskTitle = (title, contactName = null) => {
  const clean = String(title || '')
    .replace(LEADING_MARK, '')
    .trim();
  const cut = clean.indexOf(' — ');
  if (cut === -1) return { who: contactName || null, what: clean };
  const left = clean.slice(0, cut).trim();
  const what = clean.slice(cut + 3).trim();
  const who = contactName || left.split(' · ').pop().trim();
  return { who: who || null, what: what || clean };
};

// R$ 24.800 (centavos só quando existem)
export const moneyBR = value => {
  const n = Number(value);
  if (value === null || value === undefined || value === '') return null;
  if (!Number.isFinite(n) || n <= 0) return null;
  return n.toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: Number.isInteger(n) ? 0 : 2,
    maximumFractionDigits: 2,
  });
};

// o porquê da temperatura desta tarefa: [{ key, title, points }]
export const heatBreakdown = task =>
  (task?.heat?.parts || []).map(part => ({
    key: part.key,
    points: part.points,
    title: HEAT_RULE.find(r => r.key === part.key)?.title || part.key,
  }));

// contagem para os botões de filtro
export const heatCounts = (tasks, now = new Date()) => {
  const list = tasks || [];
  return {
    todas: list.length,
    quentes: list.filter(t => t.heat?.level === 'quente').length,
    atrasadas: list.filter(
      t => t.due_at && new Date(t.due_at).getTime() < now.getTime()
    ).length,
  };
};

export const filterTasks = (tasks, filter, now = new Date()) => {
  const list = tasks || [];
  if (filter === 'quentes') return list.filter(t => t.heat?.level === 'quente');
  if (filter === 'atrasadas')
    return list.filter(
      t => t.due_at && new Date(t.due_at).getTime() < now.getTime()
    );
  return list;
};
