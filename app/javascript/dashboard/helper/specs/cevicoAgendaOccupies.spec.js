import { occupiesSlot } from '../cevicoAgenda';

// item 297: janela do médico com blocos de 10 min (o caso do print da equipe)
describe('occupiesSlot', () => {
  const doctor = { doctor: 'Dr. Henrique Gemelli', unit: 'paulista', block: 10 };
  const at = hm => {
    const [h, m] = hm.split(':').map(Number);
    return h * 60 + m;
  };
  const slotsOf = (win, taskStart, duration, slots) =>
    slots.filter(slot =>
      occupiesSlot({
        taskStart: at(taskStart),
        duration,
        slotStart: at(slot),
        block: win.block,
        win,
      })
    );
  const slots = ['13:00', '13:10', '13:20', '13:30', '14:00', '14:10', '14:20'];

  it('consulta de 15 min aparece só no bloco em que começa', () => {
    expect(slotsOf(doctor, '13:10', 15, slots)).toEqual(['13:10']);
  });

  it('exame de 30 min não se espalha por três blocos do médico', () => {
    expect(slotsOf(doctor, '14:00', 30, slots)).toEqual(['14:00']);
  });

  it('horário quebrado cai no bloco que o contém', () => {
    expect(slotsOf(doctor, '13:25', 15, slots)).toEqual(['13:20']);
  });

  it('sala cirúrgica e agenda de exames continuam por sobreposição', () => {
    const room = { unit: 'paulista', block: 30 };
    const roomSlots = ['13:00', '13:30', '14:00', '14:30'];
    expect(slotsOf(room, '13:10', 60, roomSlots)).toEqual([
      '13:00',
      '13:30',
      '14:00',
    ]);
    const exams = { exam: true, unit: 'paulista', block: 10 };
    expect(slotsOf(exams, '14:00', 30, slots)).toEqual([
      '14:00',
      '14:10',
      '14:20',
    ]);
  });
});
