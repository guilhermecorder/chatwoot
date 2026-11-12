import { spaceWords } from '../useCevicoSpaceName';

describe('useCevicoSpaceName (🏠 nome do ambiente da pessoa)', () => {
  it('sem configuração vale o nome de sempre da clínica', () => {
    expect(spaceWords(undefined)).toEqual({
      name: 'Espaço do Paciente',
      withArticle: 'o Espaço do Paciente',
      open: 'Abrir o Espaço do Paciente',
    });
  });

  it('LIFE (ramo outro): Central do cliente, com o artigo certo', () => {
    expect(
      spaceWords({
        espaco: 'Central do cliente',
        o_espaco: 'a Central do cliente',
      })
    ).toEqual({
      name: 'Central do cliente',
      withArticle: 'a Central do cliente',
      open: 'Abrir a Central do cliente',
    });
  });

  it('só o nome trocado: o artigo padrão acompanha', () => {
    expect(spaceWords({ espaco: 'Painel do cliente' }).open).toBe(
      'Abrir o Painel do cliente'
    );
  });
});
