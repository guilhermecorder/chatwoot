// Fórmulas dos cards de indicador do Meu Painel (item 141) — avaliador
// SEGURO: sem eval, só números, + - * / parênteses e nomes de indicadores
// do cesto ("appointments_booked / new_leads * 100"). Qualquer coisa fora
// disso devolve null (o card mostra "—" em vez de quebrar).

const TOKEN_RE = /\s*(\d+(?:\.\d+)?|[a-zA-Z_][a-zA-Z0-9_]*|[-+*/()])/g;

export const tokenize = expr => {
  const tokens = [];
  let consumed = 0;
  const src = String(expr || '');
  TOKEN_RE.lastIndex = 0;
  let m = TOKEN_RE.exec(src);
  while (m) {
    if (m.index !== consumed) return null; // caractere estranho no meio
    tokens.push(m[1]);
    consumed = TOKEN_RE.lastIndex;
    m = TOKEN_RE.exec(src);
  }
  if (consumed !== src.length && src.slice(consumed).trim() !== '') return null;
  return tokens;
};

// nomes de indicadores usados na fórmula (pra validar contra o cesto)
export const variablesIn = expr =>
  (tokenize(expr) || []).filter(t => /^[a-zA-Z_]/.test(t));

const PRECEDENCE = { '+': 1, '-': 1, '*': 2, '/': 2 };

// shunting-yard → RPN → avalia com o mapa de valores
export const evaluateFormula = (expr, values) => {
  const tokens = tokenize(expr);
  if (!tokens || !tokens.length) return null;
  const output = [];
  const ops = [];
  let prev = null;
  for (const t of tokens) {
    if (/^\d/.test(t)) output.push(Number(t));
    else if (/^[a-zA-Z_]/.test(t)) {
      const v = values?.[t];
      if (v === undefined || v === null || Number.isNaN(Number(v))) return null;
      output.push(Number(v));
    } else if (t === '(') ops.push(t);
    else if (t === ')') {
      while (ops.length && ops[ops.length - 1] !== '(') output.push(ops.pop());
      if (!ops.length) return null;
      ops.pop();
    } else {
      // menos unário ("-x") vira 0 - x
      if (t === '-' && (prev === null || prev === '(' || PRECEDENCE[prev])) output.push(0);
      while (
        ops.length &&
        PRECEDENCE[ops[ops.length - 1]] &&
        PRECEDENCE[ops[ops.length - 1]] >= PRECEDENCE[t]
      )
        output.push(ops.pop());
      ops.push(t);
    }
    prev = t;
  }
  while (ops.length) {
    const op = ops.pop();
    if (op === '(') return null;
    output.push(op);
  }
  const stack = [];
  for (const item of output) {
    if (typeof item === 'number') stack.push(item);
    else {
      const b = stack.pop();
      const a = stack.pop();
      if (a === undefined || b === undefined) return null;
      if (item === '+') stack.push(a + b);
      else if (item === '-') stack.push(a - b);
      else if (item === '*') stack.push(a * b);
      else if (item === '/') {
        if (b === 0) return null;
        stack.push(a / b);
      }
    }
  }
  if (stack.length !== 1 || !Number.isFinite(stack[0])) return null;
  return stack[0];
};

export const formatKpi = (value, format) => {
  if (value === null || value === undefined) return '—';
  if (format === 'percent') return `${Number(value).toFixed(1).replace('.', ',')}%`;
  if (format === 'currency')
    return Number(value).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
  const n = Number(value);
  return Number.isInteger(n) ? n.toLocaleString('pt-BR') : n.toFixed(1).replace('.', ',');
};
