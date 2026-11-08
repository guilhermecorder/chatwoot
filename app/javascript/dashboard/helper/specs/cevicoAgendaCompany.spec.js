import {
  DOCTORS,
  MODALITIES,
  TYPES,
  TYPE_BY_KEY,
  companyHasUnits,
  companyWord,
  doctorsFor,
  modalitiesFor,
  typeByKeyFor,
  typesFor,
  unitListFor,
  unitsFor,
  weekendWindowsFor,
} from '../cevicoAgenda';

// ☀️ 08/11: a Agenda da LIFE (unidade, quem atende e tipos da empresa);
// a clínica segue como sempre
const CLINIC_UNITS = { tatuape: { label: 'Tatuapé' } };
const clinic = {
  segment: 'clinica',
  units: [
    { key: 'tatuape', label: 'Tatuapé' },
    { key: 'paulista', label: 'Av. Paulista' },
  ],
  agenda_types: [],
};
const life = {
  segment: 'outro',
  vocabulary: { empresa: 'empresa' },
  units: [{ key: 'piracicaba', label: 'Piracicaba · Av. Dr. Morato, 233' }],
  agenda_types: [
    {
      key: 'avaliacao',
      label: 'Visita técnica',
      noun: 'visita técnica',
      plural: 'visitas técnicas',
      icon: 'i-lucide-house',
    },
    { key: 'retorno', label: 'Fechamento', noun: 'fechamento' },
    { key: 'inventado', label: 'X' },
  ],
};
const lifeWindows = [1, 2, 3, 4, 5].map(dow => ({
  dow,
  unit: 'piracicaba',
  doctor: 'Fernando',
}));

describe('unidades e quem atende por empresa', () => {
  it('clínica (mesmo com unidades gravadas) fica com o de sempre', () => {
    expect(companyHasUnits(clinic)).toBe(false);
    expect(companyHasUnits(null)).toBe(false);
    expect(unitsFor(clinic, CLINIC_UNITS)).toBe(CLINIC_UNITS);
    expect(doctorsFor(clinic, lifeWindows, DOCTORS)).toBe(DOCTORS);
    expect(companyWord(clinic)).toBe('clínica');
    expect(unitListFor(undefined, ['x'])).toEqual(['x']);
  });

  it('LIFE: Piracicaba, Fernando, "empresa"', () => {
    expect(companyHasUnits(life)).toBe(true);
    expect(Object.keys(unitsFor(life, CLINIC_UNITS))).toEqual(['piracicaba']);
    expect(unitsFor(life, CLINIC_UNITS).piracicaba.short).toBe('PIR');
    expect(unitListFor(life, [])[0].key).toBe('piracicaba');
    expect(doctorsFor(life, lifeWindows, DOCTORS)).toEqual([
      expect.objectContaining({ name: 'Fernando', short: 'Fernando' }),
    ]);
    expect(doctorsFor(life, [], DOCTORS)).toBe(DOCTORS);
    expect(companyWord(life)).toBe('empresa');
  });

  it('fim de semana só abre com faixa no sábado/domingo', () => {
    expect(weekendWindowsFor(life, lifeWindows)).toBe(false);
    expect(weekendWindowsFor(life, [...lifeWindows, { dow: 6 }])).toBe(true);
    expect(weekendWindowsFor(clinic, [{ dow: 6 }])).toBe(false);
  });
});

describe('typesFor', () => {
  it('sem lista própria: os 6 tipos de sempre', () => {
    expect(typesFor(clinic)).toBe(TYPES);
    expect(typesFor(null)).toBe(TYPES);
    expect(modalitiesFor(clinic)).toBe(MODALITIES);
    expect(typeByKeyFor(clinic).avaliacao).toBe(TYPE_BY_KEY.avaliacao);
  });

  it('LIFE: só Visita técnica + Fechamento, com cor e trilho de sempre', () => {
    const types = typesFor(life);
    expect(types.map(t => t.key)).toEqual(['avaliacao', 'retorno']);
    expect(types[0]).toMatchObject({
      label: 'Visita técnica',
      noun: 'visita técnica',
      icon: 'i-lucide-house',
      kind: 'consultas',
      modality: 'avaliacao',
      color: TYPE_BY_KEY.avaliacao.color,
    });
    expect(types[1]).toMatchObject({
      label: 'Fechamento',
      plural: TYPE_BY_KEY.retorno.plural,
      icon: TYPE_BY_KEY.retorno.icon,
    });
    // agendamento antigo de tipo escondido ainda tem rótulo
    expect(typeByKeyFor(life).cirurgia.label).toBe('Cirurgia');
    expect(typeByKeyFor(life).avaliacao.label).toBe('Visita técnica');
    expect(modalitiesFor(life).map(m => [m.key, m.label])).toEqual([
      ['avaliacao', 'Visita técnica'],
      ['retorno', 'Fechamento'],
    ]);
  });
});
