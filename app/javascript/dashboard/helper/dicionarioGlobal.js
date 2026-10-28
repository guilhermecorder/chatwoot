// 🎨 DICIONÁRIO GLOBAL (Personalização por conta, 28/10)
//
// A rede de segurança do vocabulário: troca as palavras da clínica
// ("paciente", "consulta", "cirurgia", "médico"…) pelas da EMPRESA em TODA
// tela do painel — inclusive nas que ainda escrevem o texto à mão — sem
// mexer em cada arquivo. Roda sobre os nós de texto do DOM (e nos títulos
// de dica/placeholder), com um MutationObserver para o que o Vue renderiza
// depois. Idempotente: trocar de novo não muda nada.
//
// O que NUNCA é tocado (conteúdo das pessoas, não da interface):
//   conversas e mensagens, caixas de texto, campos editáveis, scripts e
//   qualquer coisa dentro de [data-sem-dicionario]. Opções de <select>
//   SÃO trocadas (são rótulos da interface, como "Toda a clínica").
//
// Ligado/desligado e os pares (de → para) vêm da empresa
// (company.dictionary) — Configurações → Personalização → Palavras.

const SELETORES_PROTEGIDOS = [
  'script',
  'style',
  'textarea',
  'input',
  'code',
  'pre',
  '[contenteditable]',
  '[data-sem-dicionario]',
  '.conversation-panel', // mensagens da conversa aberta
  '.conversations-list', // prévias das conversas
  '.conversations-list-wrap',
  '.message-text', // bolhas
  '.ProseMirror', // editor de mensagens
  '.contact-panel', // ficha do contato ao lado da conversa
].join(',');

let regex = null;
let mapa = new Map(); // forma minúscula → substituto
let observador = null;
let raiz = null;
let agendado = false;
const pendentes = new Set();

const escapar = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// preserva a caixa da palavra original: Paciente → Cliente, PACIENTE → CLIENTE
const comCaixaDe = (original, troca) => {
  if (original === original.toUpperCase() && original.length > 1) return troca.toUpperCase();
  if (original[0] === original[0].toUpperCase()) return troca.charAt(0).toUpperCase() + troca.slice(1);
  return troca;
};

export const montarDicionario = pares => {
  mapa = new Map();
  (pares || []).forEach(p => {
    const de = String(p?.de || '').trim();
    const para = String(p?.para || '').trim();
    if (!de || !para || de.toLowerCase() === para.toLowerCase()) return;
    mapa.set(de.toLowerCase(), para);
  });
  if (!mapa.size) {
    regex = null;
    return;
  }
  // palavras maiores primeiro (pacientes antes de paciente); fronteira de
  // palavra com acentos (\\p{L}) — "consultas" não casa dentro de "consultar"
  const alternativas = [...mapa.keys()].sort((a, b) => b.length - a.length).map(escapar);
  regex = new RegExp(`(?<![\\p{L}\\p{N}_])(?:${alternativas.join('|')})(?![\\p{L}\\p{N}_])`, 'giu');
};

export const traduzirTexto = texto => {
  if (!regex || !texto) return texto;
  if (!regex.test(texto)) {
    regex.lastIndex = 0;
    return texto;
  }
  regex.lastIndex = 0;
  return texto.replace(regex, m => comCaixaDe(m, mapa.get(m.toLowerCase()) || m));
};

const protegido = el => Boolean(el && el.closest && el.closest(SELETORES_PROTEGIDOS));

const traduzirNoDeTexto = no => {
  const atual = no.data;
  if (!atual || !atual.trim()) return;
  if (no.__dicValor === atual) return; // já é nosso
  const novo = traduzirTexto(atual);
  if (novo !== atual) {
    no.__dicValor = novo;
    no.data = novo;
  }
};

const ATRIBUTOS = ['title', 'placeholder', 'aria-label'];
const traduzirAtributos = el => {
  if (!el.getAttribute) return;
  ATRIBUTOS.forEach(a => {
    if (!el.hasAttribute(a)) return;
    const atual = el.getAttribute(a);
    const novo = traduzirTexto(atual);
    if (novo !== atual) el.setAttribute(a, novo);
  });
};

const varrer = alvo => {
  if (!regex || !alvo) return;
  if (alvo.nodeType === Node.TEXT_NODE) {
    if (!protegido(alvo.parentElement)) traduzirNoDeTexto(alvo);
    return;
  }
  if (alvo.nodeType !== Node.ELEMENT_NODE) return;
  if (protegido(alvo)) return;
  traduzirAtributos(alvo);
  const walker = document.createTreeWalker(alvo, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, {
    acceptNode: no => {
      if (no.nodeType === Node.ELEMENT_NODE) {
        return no.matches && no.matches(SELETORES_PROTEGIDOS)
          ? NodeFilter.FILTER_REJECT
          : NodeFilter.FILTER_ACCEPT;
      }
      return NodeFilter.FILTER_ACCEPT;
    },
  });
  let no = walker.nextNode();
  while (no) {
    if (no.nodeType === Node.TEXT_NODE) traduzirNoDeTexto(no);
    else traduzirAtributos(no);
    no = walker.nextNode();
  }
};

const processarPendentes = () => {
  agendado = false;
  const lote = [...pendentes];
  pendentes.clear();
  lote.forEach(varrer);
};

const agendar = no => {
  pendentes.add(no);
  if (agendado) return;
  agendado = true;
  requestAnimationFrame(processarPendentes);
};

const aoMudar = registros => {
  if (!regex) return;
  registros.forEach(r => {
    if (r.type === 'characterData') {
      agendar(r.target);
    } else if (r.type === 'attributes') {
      agendar(r.target);
    } else {
      r.addedNodes.forEach(agendar);
    }
  });
};

export const pararDicionarioGlobal = () => {
  if (observador) observador.disconnect();
  observador = null;
  pendentes.clear();
};

// (re)aplica a configuração da empresa no painel inteiro
export const aplicarDicionarioGlobal = (company, elementoRaiz = null) => {
  raiz = elementoRaiz || raiz || document.getElementById('app') || document.body;
  const dic = company?.dictionary;
  const ligado = Boolean(dic?.enabled) && Array.isArray(dic?.pairs) && dic.pairs.length;
  pararDicionarioGlobal();
  montarDicionario(ligado ? dic.pairs : []);
  if (!regex) return false;
  varrer(raiz);
  observador = new MutationObserver(aoMudar);
  observador.observe(raiz, {
    childList: true,
    characterData: true,
    subtree: true,
    attributes: true,
    attributeFilter: ATRIBUTOS,
  });
  return true;
};

export const dicionarioAtivo = () => Boolean(regex && observador);
