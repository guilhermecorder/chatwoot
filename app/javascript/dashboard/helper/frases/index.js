// 🎨 FRASES DAS TELAS (Personalização por conta, 28/10)
//
// Cada tela adaptada ao vocabulário registra aqui as frases que escreve na
// interface: `{ chave, padrao, tela }`. O código chama
// `frase(chave, padrao)` (helper/segmento) — resolve conta > segmento > o
// padrão (= o texto da clínica de sempre). A tela Configurações →
// Personalização → Frases lista tudo isto para o admin trocar.
import inicio from './inicio';
import agenda from './agenda';
import agendamentos from './agendamentos';
import visaoGeral from './visaoGeral';
import espacoPaciente from './espacoPaciente';
import dashboards from './dashboards';

export const FRASES_DAS_TELAS = [
  ...inicio,
  ...agenda,
  ...agendamentos,
  ...visaoGeral,
  ...espacoPaciente,
  ...dashboards,
];

export const FRASES_POR_TELA = FRASES_DAS_TELAS.reduce((acc, f) => {
  (acc[f.tela] ||= []).push(f);
  return acc;
}, {});
