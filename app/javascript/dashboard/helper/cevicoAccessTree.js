// 🔐 rodada 334 — a ÁRVORE de acessos no front (puro, sem Vue).
//
// Replica a regra do servidor (Cevico::Access + Cevico::AccessCatalog) para
// a tela mostrar, ANTES de salvar, o nível que vai valer em cada nó:
//   1. administrador → o maior nível que o nó aceita;
//   2. nó "só administradores" (ou com um pai assim) → nada;
//   3. marcação própria no nó, senão no pai mais perto (a marcação da
//      pessoa vence a do papel);
//   4. padrão do catálogo ('inherit' sobe para o pai; sem pai → nada);
//   5. tudo travado ao maior nível que o nó aceita (nó só-ver nunca edita).
//
// `catalog` pode ser a árvore que o servidor manda (array de nós com
// children) ou o índice já achatado por flattenCatalog (key → nó).
export const LEVELS = ['none', 'view', 'edit'];
export const LEVEL_RANK = { none: 0, view: 1, edit: 2 };
export const LEVEL_LABELS = { none: 'Nada', view: 'Ver', edit: 'Editar' };
export const INHERIT = 'inherit';

const isLevel = value => LEVELS.includes(value);

// árvore → { 'crm.funis': { key, parent, label, hint, levels, default, admin,
// children: [chaves dos filhos] } }
export function flattenCatalog(catalog) {
  if (!Array.isArray(catalog))
    return catalog && typeof catalog === 'object' ? catalog : {};
  const index = {};
  const walk = (nodes, parent) => {
    (nodes || []).forEach(raw => {
      const key = String(raw.key ?? '');
      if (!key) return;
      const children = raw.children || [];
      index[key] = {
        ...raw,
        key,
        parent: raw.parent ?? parent ?? null,
        levels:
          Array.isArray(raw.levels) && raw.levels.length
            ? raw.levels
            : ['view'],
        default: raw.default || (raw.admin ? 'none' : INHERIT),
        admin: raw.admin === true,
        children: children.map(c => String(c.key)),
      };
      walk(children, key);
    });
  };
  walk(catalog, null);
  return index;
}

const indexOf = catalog => flattenCatalog(catalog);

// o maior nível que o nó aceita
export function maxLevel(node) {
  return node?.levels?.includes('edit') ? 'edit' : 'view';
}

// trava um nível ao que o nó aceita
export function clampLevel(node, level) {
  if (!isLevel(level)) return 'none';
  if (level === 'none') return level;
  const top = maxLevel(node);
  return LEVEL_RANK[level] > LEVEL_RANK[top] ? top : level;
}

// [pai, avô, …] de um nó
export function ancestorsOf(index, key) {
  const out = [];
  let current = index[key]?.parent;
  while (current) {
    out.push(current);
    current = index[current]?.parent;
  }
  return out;
}

// todos os filhos, netos… de um nó
export function descendantsOf(index, key) {
  const kids = index[key]?.children || [];
  return kids.flatMap(k => [k, ...descendantsOf(index, k)]);
}

// nó só de administradores (ele mesmo ou um pai)
export function adminLocked(index, key) {
  if (!index[key]) return false;
  if (index[key].admin) return true;
  return ancestorsOf(index, key).some(anc => index[anc]?.admin);
}

// o padrão de um atendente SEM configuração ('inherit' sobe)
export function defaultLevel(index, key) {
  const node = index[key];
  if (!node) return 'none';
  if (node.admin) return 'none';
  const raw = node.default;
  if (isLevel(raw)) return clampLevel(node, raw);
  if (node.parent) return clampLevel(node, defaultLevel(index, node.parent));
  return 'none';
}

// marcações válidas juntas: a própria (explicit) vence a do papel (roleTree)
export function mergedMarks(index, explicit, roleTree) {
  const merged = { ...(roleTree || {}), ...(explicit || {}) };
  return Object.fromEntries(
    Object.entries(merged).filter(([k, v]) => index[k] && isLevel(v))
  );
}

// a marcação que vale para o nó: nele mesmo ou no pai mais perto
export function explicitLevel(index, marks, key) {
  if (key in marks) return { level: marks[key], from: key };
  const anc = ancestorsOf(index, key).find(a => a in marks);
  return anc ? { level: marks[anc], from: anc } : null;
}

// nível efetivo de UM nó
export function effectiveLevel({ catalog, explicit, roleTree, key, admin }) {
  const index = indexOf(catalog);
  const node = index[key];
  if (!node) return 'none';
  if (admin) return maxLevel(node);
  if (adminLocked(index, key)) return 'none';
  const marks = mergedMarks(index, explicit, roleTree);
  const found = explicitLevel(index, marks, key);
  if (found) return clampLevel(node, found.level);
  return defaultLevel(index, key);
}

// nível efetivo de TODOS os nós: { 'crm': 'edit', … }
export function effectiveMap({ catalog, explicit, roleTree, admin }) {
  const index = indexOf(catalog);
  const marks = mergedMarks(index, explicit, roleTree);
  const out = {};
  Object.keys(index).forEach(key => {
    const node = index[key];
    if (admin) {
      out[key] = maxLevel(node);
    } else if (adminLocked(index, key)) {
      out[key] = 'none';
    } else {
      const found = explicitLevel(index, marks, key);
      out[key] = found
        ? clampLevel(node, found.level)
        : defaultLevel(index, key);
    }
  });
  return out;
}

// { view: n, edit: n, none: n }
export function summarize(effective) {
  const out = { view: 0, edit: 0, none: 0 };
  Object.values(effective || {}).forEach(level => {
    if (level in out) out[level] += 1;
  });
  return out;
}

// marcação própria em algum filho/neto?
export function subtreeHasMarks(index, marks, key) {
  return descendantsOf(index, key).some(k => k in (marks || {}));
}
