import { scanAgenda } from '../cevicoAgenda';

// ⚖️ item 422: com a régua de carga ligada, o encaixe conta na ocupação
describe('scanAgenda countStacked', () => {
  const day = new Date(2030, 0, 2); // quarta-feira
  const win = {
    dow: 3,
    unit: 'tatuape',
    doctor: 'Dr. Gustavo Bittar',
    start: '08:00',
    end: '09:00',
    block: 15,
  };
  const task = hm => ({
    due_at: new Date(`2030-01-02T${hm}:00`).toISOString(),
    unit: 'tatuape',
    modality: 'avaliacao',
  });
  const tasks = [task('08:00'), task('08:00'), task('08:30')];
  const scan = countStacked =>
    scanAgenda({
      windows: [win],
      tasks,
      blockedSet: new Set(),
      from: day,
      days: 1,
      freeLimit: 0,
      countStacked,
    });

  it('desligada: horário com 2 conta 1 (como antes)', () => {
    expect(scan(false).pct).toBe(50);
  });

  it('ligada: encaixe conta 2', () => {
    expect(scan(true).pct).toBe(75);
  });
});
