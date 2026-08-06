// Pacote de SEGMENTO (sistema coringa) — injetado pelo Rails em
// window.SEGMENTO (vueapp.html.erb) a partir de config/segmentos/<id>.yml.
// A marca escolhe o segmento (cevico → clinica, life → empresa); sem
// pacote (testes, contexto de widget) vale o preset clínica — os mesmos
// textos que sempre estiveram chumbados no frontend.

const SEG = (typeof window !== 'undefined' && window.SEGMENTO) || {};

export const SEGMENTO = SEG;
export const segmentoId = SEG.id || 'clinica';
export const isClinica = segmentoId === 'clinica';

// termo('cliente') → 'paciente' na clínica / 'cliente' na empresa.
// Sem pacote, a chave e o termo da clínica coincidem com o texto antigo.
const TERMOS_CLINICA = {
  cliente: 'paciente',
  clientes: 'pacientes',
  profissional: 'médico',
  profissionais: 'médicos',
  atendimento: 'consulta',
  atendimentos: 'consultas',
  venda: 'cirurgia',
  vendas: 'cirurgias',
  empresa: 'clínica',
  unidade: 'unidade',
  unidades: 'unidades',
};

export const termo = chave => SEG.termos?.[chave] || TERMOS_CLINICA[chave] || chave;

// 'paciente' → 'Paciente' (só a primeira letra; preserva acentos)
export const termoCap = chave => {
  const t = termo(chave);
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : t;
};

// frase('novo_atendimento', 'Nova consulta') → rótulo composto do
// segmento; o padrão passado é sempre o texto da clínica (o de sempre)
export const frase = (chave, padrao) => SEG.frases?.[chave] || padrao || chave;

// metas do segmento (ex.: meta('vendas_mes', 100))
export const meta = (chave, padrao) => {
  const v = Number(SEG.metas?.[chave]);
  return Number.isFinite(v) && v > 0 ? v : padrao;
};

// nome de quem cuida de um painel do Início ('' = sem nome exibido)
export const painelQuem = (chave, padrao = '') => {
  const paineis = SEG.paineis || {};
  return chave in paineis ? String(paineis[chave] || '') : padrao;
};

// listas do segmento com fallback (usadas por cevicoAgenda.js e telas)
export const listaSegmento = (chave, padrao = []) =>
  Array.isArray(SEG[chave]) && SEG[chave].length ? SEG[chave] : padrao;

// nome do sistema no hero do Início: clínica mantém o "CEVICO S.I" de
// sempre; outros segmentos usam o nome da instalação (pacote de marca)
export const nomeSistemaHero = () => {
  if (SEG.frases?.nome_sistema_hero) return SEG.frases.nome_sistema_hero;
  if (isClinica) return 'CEVICO S.I';
  return (
    (typeof window !== 'undefined' && window.globalConfig?.INSTALLATION_NAME) ||
    'seu sistema'
  );
};
