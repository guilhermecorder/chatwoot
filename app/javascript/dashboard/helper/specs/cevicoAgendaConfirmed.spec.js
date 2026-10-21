import {
  patientNameOf,
  handConfirmed,
  isConfirmed,
  isDeclined,
  originOf,
} from '../cevicoAgenda';

// item 300: selo "paciente confirmou" e origem CEVICO × Oftalmofácil
describe('cevicoAgenda — confirmou e origem', () => {
  it('tira o prefixo do tipo e o ✅ digitado à mão do nome', () => {
    expect(patientNameOf({ title: 'Consulta: ✅Diego Muller' })).toBe('Diego Muller');
    expect(patientNameOf({ title: '✅ Alex Lopes' })).toBe('Alex Lopes');
    expect(patientNameOf({ title: 'Flora Bispo' })).toBe('Flora Bispo');
  });

  it('confirmou = confirmed_at ou ✅ no nome; cancelada nunca', () => {
    expect(isConfirmed({ title: 'Ana', confirmed_at: '2026-09-29T10:00:00Z' })).toBe(true);
    expect(isConfirmed({ title: '✅Ana' })).toBe(true);
    expect(handConfirmed({ title: 'Ana ✅' })).toBe(false);
    expect(isConfirmed({ title: 'Ana' })).toBe(false);
    expect(isConfirmed({ title: '✅Ana', canceled_at: '2026-09-29T10:00:00Z' })).toBe(false);
  });

  it('disse não só vale enquanto não confirmou', () => {
    expect(isDeclined({ title: 'Ana', declined_at: '2026-09-29T10:00:00Z' })).toBe(true);
    expect(isDeclined({ title: 'Ana', declined_at: 'x', confirmed_at: 'y' })).toBe(false);
  });

  it('origem: a escolhida no formulário ou o parceiro que veio do hub', () => {
    expect(originOf({ origin: 'cevico' }).label).toBe('CEVICO');
    expect(originOf({ source: 'oftalmofacil', source_detail: 'Parceiro X' }).key).toBe('oftalmofacil');
    expect(originOf({ source: 'oftalmofacil' })).toBeNull();
    expect(originOf({})).toBeNull();
  });
});
