import {
  DEFAULT_WINDOWS,
  isAppointmentTask,
  reservedFor,
  resolveAllWindows,
  resolveWindows,
  windowAccepts,
  windowAt,
} from '../cevicoAgenda';

// item 305: agendamento da Agenda não é cartão do quadro de Tarefas
describe('isAppointmentTask', () => {
  it('consulta, retorno, cirurgia e agendamento antigo (só com unidade) são da Agenda', () => {
    expect(isAppointmentTask({ task_type: 'consulta', modality: 'retorno' })).toBe(true);
    expect(isAppointmentTask({ task_type: 'cirurgia' })).toBe(true);
    expect(isAppointmentTask({ task_type: null, unit: 'tatuape' })).toBe(true);
  });

  it('cartão comum, tarefa do pós-operatório e vazio não são', () => {
    expect(isAppointmentTask({ task_type: 'Administrativo' })).toBe(false);
    expect(isAppointmentTask({ task_type: 'pos_op', unit: '' })).toBe(false);
    expect(isAppointmentTask({ task_type: '' })).toBe(false);
    expect(isAppointmentTask(null)).toBe(false);
  });
});

// item 307: faixa reservada (quarta 13h–14h do Dr. Henrique = só pós-operatório)
describe('faixa reservada', () => {
  const henrique = DEFAULT_WINDOWS.filter(w => w.dow === 3 && w.doctor === 'Dr. Henrique Gemelli');

  it('o padrão divide a quarta do Dr. Henrique em 13h–14h (pós-op) e 14h–17h (geral)', () => {
    expect(henrique.map(w => `${w.start}-${w.end}`)).toEqual(['13:00-14:00', '14:00-17:00']);
    expect(reservedFor(henrique[0])).toEqual(['pos_op']);
    expect(reservedFor(henrique[1])).toEqual([]);
  });

  it('windowAccepts: faixa sem reserva aceita tudo; reservada só o tipo dela; tipo desconhecido é ignorado', () => {
    expect(windowAccepts(henrique[0], 'pos_op')).toBe(true);
    expect(windowAccepts(henrique[0], 'avaliacao')).toBe(false);
    expect(windowAccepts(henrique[1], 'avaliacao')).toBe(true);
    expect(windowAccepts({ only: ['inventado'] }, 'avaliacao')).toBe(true);
  });

  it('windowAt acha a faixa do horário (fim exclusivo) na unidade e no dia certos', () => {
    const at = minutes => windowAt(DEFAULT_WINDOWS, { dow: 3, unit: 'paulista', minutes });
    expect(at(13 * 60 + 45).start).toBe('13:00');
    expect(at(14 * 60).start).toBe('14:00');
    expect(at(17 * 60)).toBeUndefined();
    expect(windowAt(DEFAULT_WINDOWS, { dow: 3, unit: 'tatuape', minutes: 13 * 60 })).toBeUndefined();
  });

  it('resolveWindows tira o médico com a agenda fechada; resolveAllWindows mantém (para a tela de Configurações)', () => {
    const settings = { agenda_closed_doctors: ['Dr. Henrique Gemelli'] };
    expect(resolveWindows(settings).some(w => w.doctor === 'Dr. Henrique Gemelli')).toBe(false);
    expect(resolveAllWindows(settings).some(w => w.doctor === 'Dr. Henrique Gemelli')).toBe(true);
  });
});
