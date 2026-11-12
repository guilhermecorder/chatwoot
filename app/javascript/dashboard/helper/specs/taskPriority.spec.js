import {
  agoText,
  clientLine,
  splitTaskTitle,
  moneyBR,
  heatMeta,
  heatBreakdown,
  heatCounts,
  filterTasks,
} from '../taskPriority';

describe('taskPriority (🌡️ tarefas do Meu Painel em fala de gente)', () => {
  const now = new Date(2026, 10, 11, 15, 0); // qua 11/11 15:00 (hora local)
  const ago = ms => new Date(now.getTime() - ms).toISOString();
  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const DAY = 24 * HOUR;

  it('diz há quanto tempo o cliente falou', () => {
    expect(agoText(ago(2 * MIN), now)).toBe('agora há pouco');
    expect(agoText(ago(20 * MIN), now)).toBe('há 20 min');
    expect(agoText(ago(HOUR), now)).toBe('há 1 hora');
    expect(agoText(ago(3 * HOUR), now)).toBe('há 3 horas');
    expect(agoText(ago(30 * HOUR), now)).toBe('ontem');
    expect(agoText(ago(5 * DAY), now)).toBe('há 5 dias');
    expect(agoText(null, now)).toBeNull();
    expect(agoText('isso não é data', now)).toBeNull();
  });

  it('resume a conversa numa frase, sem inventar o que não sabe', () => {
    const contact = { id: 1, name: 'Ivan Coral' };
    expect(clientLine({ title: 'Ligar para o fornecedor' }, now)).toBeNull();
    expect(clientLine({ contact }, now)).toEqual({
      text: 'Ainda sem mensagem do cliente',
      tone: 'none',
    });
    expect(
      clientLine(
        { contact, last_client_at: ago(3 * HOUR), client_waiting: true },
        now
      )
    ).toEqual({ text: 'Falou há 3 horas e espera resposta', tone: 'wait' });
    expect(
      clientLine(
        { contact, last_client_at: ago(2 * DAY), client_waiting: false },
        now
      )
    ).toEqual({ text: 'Falou há 2 dias, já respondido', tone: 'talk' });
    expect(
      clientLine(
        { contact, last_client_at: ago(12 * DAY), client_waiting: false },
        now
      )
    ).toEqual({
      text: 'Em silêncio: última mensagem há 12 dias',
      tone: 'quiet',
    });
  });

  it('separa quem é o cliente do que precisa ser feito', () => {
    expect(
      splitTaskTitle(
        '⏰ Retorno · Marcos Silva — Retorno: chamar o cliente (ficou de pensar)'
      )
    ).toEqual({
      who: 'Marcos Silva',
      what: 'Retorno: chamar o cliente (ficou de pensar)',
    });
    expect(
      splitTaskTitle(
        '⏰ Ivan Coral (exemplo) — Montar e enviar o orçamento',
        'Ivan Coral'
      )
    ).toEqual({ who: 'Ivan Coral', what: 'Montar e enviar o orçamento' });
    expect(
      splitTaskTitle('🙋 Atendimento · Ana Paula — Orçamento: conta recebida')
    ).toEqual({ who: 'Ana Paula', what: 'Orçamento: conta recebida' });
    expect(splitTaskTitle('Ligar para o fornecedor')).toEqual({
      who: null,
      what: 'Ligar para o fornecedor',
    });
    expect(splitTaskTitle(null)).toEqual({ who: null, what: '' });
  });

  it('mostra o valor do orçamento só quando existe', () => {
    expect(moneyBR(24800).replace(/\s/g, ' ')).toBe('R$ 24.800');
    expect(moneyBR(1234.5).replace(/\s/g, ' ')).toBe('R$ 1.234,50');
    expect(moneyBR(null)).toBeNull();
    expect(moneyBR(0)).toBeNull();
    expect(moneyBR('')).toBeNull();
  });

  it('explica a temperatura de cada tarefa', () => {
    const task = {
      heat: {
        level: 'quente',
        points: 9,
        parts: [
          { key: 'fala', points: 3 },
          { key: 'espera', points: 1 },
          { key: 'etapa', points: 2 },
          { key: 'prazo', points: 3 },
        ],
      },
    };
    expect(heatMeta(task).label).toBe('Quente');
    expect(heatMeta({}).label).toBe('Fria');
    expect(heatBreakdown(task)).toEqual([
      { key: 'fala', points: 3, title: 'O cliente falou há pouco?' },
      { key: 'espera', points: 1, title: 'Ele está esperando resposta?' },
      { key: 'etapa', points: 2, title: 'Onde está no funil?' },
      { key: 'prazo', points: 3, title: 'E o prazo da tarefa?' },
    ]);
    expect(heatBreakdown({})).toEqual([]);
  });

  it('conta e filtra quentes e atrasadas', () => {
    const tasks = [
      { id: 1, heat: { level: 'quente' }, due_at: ago(HOUR) },
      { id: 2, heat: { level: 'morna' }, due_at: ago(-DAY) },
      { id: 3, heat: { level: 'fria' }, due_at: null },
      { id: 4, heat: { level: 'quente' }, due_at: ago(-2 * HOUR) },
    ];
    expect(heatCounts(tasks, now)).toEqual({
      todas: 4,
      quentes: 2,
      atrasadas: 1,
    });
    expect(filterTasks(tasks, 'quentes', now).map(t => t.id)).toEqual([1, 4]);
    expect(filterTasks(tasks, 'atrasadas', now).map(t => t.id)).toEqual([1]);
    expect(filterTasks(tasks, 'todas', now)).toHaveLength(4);
    expect(heatCounts(null, now)).toEqual({
      todas: 0,
      quentes: 0,
      atrasadas: 0,
    });
  });
});
