// 👓 Sua Ótica — peças comuns das 3 telas da fase 1 (Venda, Produtos,
// Produção): dinheiro em R$ com vírgula, datas dd/mm/aaaa, cores e ícones
// de cada status/tipo e a classe padrão dos campos de formulário.

export const fmtMoney = v =>
  `R$ ${Number(v || 0).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;

// número → texto editável no campo ("1.234,56"); vazio quando não há valor
export const moneyInput = v =>
  v === null || v === undefined || v === ''
    ? ''
    : Number(v).toLocaleString('pt-BR', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      });

export const fmtDate = iso => {
  if (!iso) return '—';
  const d = iso.length === 10 ? new Date(`${iso}T12:00:00`) : new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('pt-BR');
};

export const fmtDateTime = iso => {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return `${d.toLocaleDateString('pt-BR')} ${d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  })}`;
};

// hoje em AAAA-MM-DD, no fuso do navegador (campos type=date)
export const todayISO = () => {
  const d = new Date();
  const pad = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

export const daysFromNow = n => {
  const d = new Date();
  d.setDate(d.getDate() + n);
  const pad = x => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};

// data (AAAA-MM-DD) já passou?
export const isPast = iso => {
  if (!iso) return false;
  return iso.slice(0, 10) < todayISO();
};

export const VERDE = '#059669';
export const AZUL = '#0F5FA6';
export const ROXO = '#7C3AED';
export const VERMELHO = '#DC2626';
export const AMBAR = '#D97706';
export const CINZA = '#64748B';
export const OURO = '#D4A017';

export const STATUS_META = {
  orcamento: { color: CINZA, icon: 'i-lucide-file-pen-line' },
  aberta: { color: AZUL, icon: 'i-lucide-receipt-text' },
  em_producao: { color: ROXO, icon: 'i-lucide-factory' },
  pronta: { color: AMBAR, icon: 'i-lucide-package-check' },
  entregue: { color: VERDE, icon: 'i-lucide-smile' },
  cancelada: { color: CINZA, icon: 'i-lucide-x' },
  devolvida: { color: VERMELHO, icon: 'i-lucide-undo-2' },
};

export const LAB_META = {
  pendente: { color: AMBAR, icon: 'i-lucide-clock' },
  enviado: { color: ROXO, icon: 'i-lucide-truck' },
  recebido: { color: VERDE, icon: 'i-lucide-package-check' },
  cancelado: { color: CINZA, icon: 'i-lucide-x' },
};

export const KIND_META = {
  armacao: { color: AZUL, icon: 'i-lucide-glasses' },
  solar: { color: AMBAR, icon: 'i-lucide-sun' },
  lente: { color: ROXO, icon: 'i-lucide-aperture' },
  lente_contato: { color: '#0F766E', icon: 'i-lucide-circle-dot' },
  servico: { color: '#B45309', icon: 'i-lucide-wrench' },
  outro: { color: CINZA, icon: 'i-lucide-box' },
};

export const METHOD_META = {
  pix: { color: '#0F766E', icon: 'i-lucide-qr-code' },
  dinheiro: { color: VERDE, icon: 'i-lucide-banknote' },
  debito: { color: AZUL, icon: 'i-lucide-credit-card' },
  credito: { color: ROXO, icon: 'i-lucide-credit-card' },
  crediario: { color: AMBAR, icon: 'i-lucide-calendar-days' },
  boleto: { color: CINZA, icon: 'i-lucide-barcode' },
};

// campos de formulário no padrão das telas do kit (StockTab)
export const INPUT =
  'mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12';
export const LABEL = 'text-[11px] font-medium text-n-slate-11';

// telefone só com dígitos, para comparar e montar links
export const phoneDigits = p => String(p || '').replace(/\D/g, '');

// a O.S. está atrasada? (não entregue e previsão já passou)
export const orderLate = o =>
  Boolean(o?.late) ||
  (['aberta', 'em_producao', 'pronta'].includes(o?.status) &&
    isPast(o?.due_on));

export const stageOfKind = kind =>
  ['lente', 'lente_contato'].includes(kind) ? 'lab' : 'loja';
