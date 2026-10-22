import { effectiveAppointmentPrice, humanNotes } from '../cevicoAgenda';

// 💰 item 340 (13/10): o card da Agenda mostra o MESMO valor que a confirmação
// manda (Crm::AppointmentPrice): o "R$ 350" do tipo de consulta conta e o
// "Valor da consulta: R$ 150" que a IA gravava nos blocos antigos não conta.
describe('effectiveAppointmentPrice (item 340)', () => {
  const prices = { avaliacao: '150,00', retorno: 'sem custo', exames: [] };
  const appt = attrs => ({
    kind: 'consultas',
    modality: 'avaliacao',
    ...attrs,
  });

  it('lê o valor escrito no tipo de consulta antes do pré-configurado', () => {
    const result = effectiveAppointmentPrice(
      prices,
      appt({ procedure: 'CONSULTA | JÁ PAC | R$350' })
    );
    expect(result).toMatchObject({
      text: '350,00',
      source: 'procedimento',
      label: 'escrito no tipo de consulta',
    });
  });

  it('ignora o bloco antigo "Reagendada pela IA" e a linha fixa da IA', () => {
    const description =
      'Paciente prefere manhã\n\nReagendada pela IA:\nValor da consulta: R$ 150\nConversa #12 — agendado pela IA';
    expect(humanNotes(description)).toBe('Paciente prefere manhã');
    const result = effectiveAppointmentPrice(
      prices,
      appt({ description, procedure: 'CONSULTA | JÁ PAC | R$350' })
    );
    expect(result.text).toBe('350,00');
    expect(result.source).toBe('procedimento');
  });

  it('"Valor: X" escrito pela equipe vence o tipo de consulta', () => {
    const result = effectiveAppointmentPrice(
      prices,
      appt({ description: 'Valor: 280', procedure: 'CONSULTA | R$350' })
    );
    expect(result).toMatchObject({ text: '280,00', source: 'observacao' });
  });

  it('avaliação com especialista: o problema escrito puxa o valor (só na avaliação)', () => {
    const withSpecials = {
      ...prices,
      especiais: [{ name: 'retina', price: '300,00' }],
    };
    expect(
      effectiveAppointmentPrice(
        withSpecials,
        appt({ procedure: 'avaliação retina' })
      )
    ).toMatchObject({
      text: '300,00',
      source: 'preset',
      label: 'pré-configurado · avaliação de retina',
    });
    expect(
      effectiveAppointmentPrice(
        withSpecials,
        appt({ modality: 'retorno', procedure: 'retorno retina' })
      )
    ).toMatchObject({ text: 'sem custo' });
  });

  it('"R$ X" solto na observação fica depois do pré-configurado', () => {
    const result = effectiveAppointmentPrice(
      prices,
      appt({ description: 'trouxe R$ 90 de troco' })
    );
    expect(result).toMatchObject({ text: '150,00', source: 'preset' });
  });
});
