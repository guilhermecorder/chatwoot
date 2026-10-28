// Pacote de SEGMENTO (sistema coringa) — injetado pelo Rails em
// window.SEGMENTO (vueapp.html.erb) a partir de config/segmentos/<id>.yml.
// A marca escolhe o segmento (cevico → clinica, life → empresa); sem
// pacote (testes, contexto de widget) vale o preset clínica — os mesmos
// textos que sempre estiveram chumbados no frontend.

import { reactive } from 'vue';

const SEG = (typeof window !== 'undefined' && window.SEGMENTO) || {};

export const SEGMENTO = SEG;

// 🎨 Personalização por CONTA (28/10): a empresa da conta aberta
// (crm/getCompany — Configurações → Personalização) entra ANTES do pacote
// do segmento em todo resolvedor daqui: conta > segmento > clínica.
// `definirEmpresa` é chamado pelo store do CRM quando as settings chegam.
export const EMPRESA = reactive({ atual: null });
export const definirEmpresa = empresa => {
  EMPRESA.atual = empresa && typeof empresa === 'object' ? empresa : null;
};
const empresa = () => EMPRESA.atual;
const empresaConfigurada = () => Boolean(empresa()?.configured);

// vocabulário da conta (chaves da Identidade: paciente, consulta, medico,
// cirurgia, empresa, unidade + _plural) → chaves do segmento
const TERMO_DA_EMPRESA = {
  cliente: 'paciente',
  clientes: 'paciente_plural',
  profissional: 'medico',
  profissionais: 'medico_plural',
  atendimento: 'consulta',
  atendimentos: 'consulta_plural',
  venda: 'cirurgia',
  vendas: 'cirurgia_plural',
  empresa: 'empresa',
  unidade: 'unidade',
  unidades: 'unidade_plural',
};
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

export const termo = chave => {
  if (empresaConfigurada()) {
    const daEmpresa = empresa().vocabulary?.[TERMO_DA_EMPRESA[chave]];
    if (daEmpresa) return daEmpresa;
  }
  return SEG.termos?.[chave] || TERMOS_CLINICA[chave] || chave;
};

// 'paciente' → 'Paciente' (só a primeira letra; preserva acentos)
export const termoCap = chave => {
  const t = termo(chave);
  return t ? t.charAt(0).toUpperCase() + t.slice(1) : t;
};

// frase('novo_atendimento', 'Nova consulta') → rótulo composto do
// segmento; o padrão passado é sempre o texto da clínica (o de sempre)
export const frase = (chave, padrao) =>
  empresa()?.phrases?.[chave] || SEG.frases?.[chave] || padrao || chave;

// nome de um AMBIENTE (item do menu / título da tela) escolhido pela conta:
// nomeAmbiente('Agenda', 'Agenda') → 'Vistorias' na Life
export const nomeAmbiente = (chave, padrao) =>
  empresa()?.labels?.[chave] || padrao || chave;

// imagem da identidade visual da conta ('logo' | 'logo_dark' | 'icon' | 'hero')
export const imagemEmpresa = (tipo, padrao = '') =>
  empresa()?.images?.[tipo] || padrao;

// identidade visual da conta (nome do sistema, paleta, marca d'água)
export const visualEmpresa = () => empresa()?.visual || {};
// a marca d'água (olho CEVICO ou a imagem da conta) aparece?
export const marcaDaguaLigada = () => visualEmpresa().watermark !== false;

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
  // 🎨 Personalização por conta: nome do sistema escolhido pela empresa
  if (empresa()?.visual?.system_name) return empresa().visual.system_name;
  if (empresaConfigurada() && empresa().name) return empresa().name;
  if (SEG.frases?.nome_sistema_hero) return SEG.frases.nome_sistema_hero;
  if (isClinica) return 'CEVICO S.I';
  return (
    (typeof window !== 'undefined' && window.globalConfig?.INSTALLATION_NAME) ||
    'seu sistema'
  );
};
