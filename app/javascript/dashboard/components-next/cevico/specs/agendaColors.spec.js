import fs from 'fs';
import path from 'path';
import {
  TASK_COLORS,
  taskColorOf,
  attendanceMarkOf,
} from 'dashboard/helper/cevicoAgenda';

describe('Agenda: cor e presença do agendamento (item 290)', () => {
  it('são 12 cores diferentes, com nome, no formato #RRGGBB', () => {
    expect(TASK_COLORS).toHaveLength(12);
    expect(new Set(TASK_COLORS.map(c => c.value)).size).toBe(12);
    expect(new Set(TASK_COLORS.map(c => c.label)).size).toBe(12);
    TASK_COLORS.forEach(c => expect(c.value).toMatch(/^#[0-9A-F]{6}$/));
  });

  it('a lista da tela é a MESMA do servidor (Task::COLORS)', () => {
    const model = fs.readFileSync(
      path.resolve(process.cwd(), 'app/models/task.rb'),
      'utf8'
    );
    const block = model.match(/COLORS = %w\[([\s\S]*?)\]/)[1];
    const server = block.trim().split(/\s+/);
    expect(TASK_COLORS.map(c => c.value)).toEqual(server);
  });

  it('taskColorOf: só devolve cor da lista', () => {
    expect(taskColorOf({ color: '#16A34A' })).toBe('#16A34A');
    expect(taskColorOf({ color: '#16a34a' })).toBe('#16A34A');
    expect(taskColorOf({ color: '#123456' })).toBeNull();
    expect(taskColorOf({ color: '' })).toBeNull();
    expect(taskColorOf({ color: null })).toBeNull();
    expect(taskColorOf({})).toBeNull();
    expect(taskColorOf(null)).toBeNull();
  });

  it('attendanceMarkOf: ✓ foi, ✕ faltou, ! veio e não fez, nada sem presença', () => {
    expect(attendanceMarkOf({ attendance: 'attended' })).toMatchObject({
      sign: '✓',
      cls: 'cv-ag-ev-mark-ok',
      title: 'Compareceu',
    });
    expect(attendanceMarkOf({ attendance: 'missed' })).toMatchObject({
      sign: '✕',
      cls: 'cv-ag-ev-mark-no',
      title: 'Faltou',
    });
    expect(
      attendanceMarkOf({ attendance: 'attended', task_type: 'cirurgia' }).title
    ).toBe('Realizada');
    expect(
      attendanceMarkOf({ attendance: 'missed', task_type: 'cirurgia' }).title
    ).toBe('Não veio');
    expect(attendanceMarkOf({ attendance: 'attended_not_done' }).sign).toBe(
      '!'
    );
    expect(attendanceMarkOf({ attendance: null })).toBeNull();
    expect(attendanceMarkOf({})).toBeNull();
  });

  it('cor não muda o sinal de presença (são independentes)', () => {
    const a = attendanceMarkOf({ attendance: 'missed', color: '#16A34A' });
    const b = attendanceMarkOf({ attendance: 'missed' });
    expect(a).toEqual(b);
  });
});
