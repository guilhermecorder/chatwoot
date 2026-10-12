import {
  flattenCatalog,
  effectiveLevel,
  effectiveMap,
  summarize,
  defaultLevel,
  adminLocked,
  descendantsOf,
  subtreeHasMarks,
  LEVEL_LABELS,
  INHERIT,
} from '../cevicoAccessTree';

// um pedaço do catálogo real, no formato que o servidor manda
const CATALOG = [
  { key: 'inicio', label: 'Meu Painel', levels: ['view'], default: 'view' },
  {
    key: 'crm',
    label: 'CRM',
    levels: ['view', 'edit'],
    default: 'edit',
    children: [
      {
        key: 'crm.funis',
        parent: 'crm',
        label: 'Funis',
        levels: ['edit'],
        default: 'none',
      },
      {
        key: 'crm.agendamentos',
        parent: 'crm',
        label: 'Agendamentos',
        levels: ['view'],
        default: 'view',
      },
      {
        key: 'crm.fontes',
        parent: 'crm',
        label: 'Fontes',
        levels: ['view', 'edit'],
        default: 'none',
        admin: true,
      },
    ],
  },
  {
    key: 'relatorios',
    label: 'Relatórios',
    levels: ['view'],
    default: 'none',
    children: [
      {
        key: 'relatorios.crm',
        parent: 'relatorios',
        label: 'Dashboard CRM',
        levels: ['view'],
        default: 'inherit',
      },
      {
        key: 'relatorios.core',
        parent: 'relatorios',
        label: 'Core',
        levels: ['view'],
        admin: true,
      },
    ],
  },
  {
    key: 'empresario',
    label: 'Painel do empresário',
    levels: ['view'],
    admin: true,
    children: [
      {
        key: 'empresario.mesa',
        parent: 'empresario',
        label: 'Mesa',
        levels: ['view'],
        default: 'view',
      },
    ],
  },
  {
    key: 'agenda',
    label: 'Agenda',
    levels: ['view', 'edit'],
    default: 'edit',
    children: [
      {
        key: 'agenda.exames',
        parent: 'agenda',
        label: 'Exames',
        levels: ['view', 'edit'],
        default: 'inherit',
      },
      {
        key: 'agenda.semdefault',
        parent: 'agenda',
        label: 'Sem padrão',
        levels: ['view', 'edit'],
      },
    ],
  },
];

describe('cevicoAccessTree (rodada 334)', () => {
  it('flattenCatalog: achata a árvore com pai e filhos', () => {
    const index = flattenCatalog(CATALOG);
    expect(Object.keys(index)).toContain('crm.funis');
    expect(index['crm.funis'].parent).toBe('crm');
    expect(index.crm.children).toEqual([
      'crm.funis',
      'crm.agendamentos',
      'crm.fontes',
    ]);
    expect(index.inicio.parent).toBeNull();
    // nó sem default e sem admin → 'inherit'; admin sem default → 'none'
    expect(index['agenda.semdefault'].default).toBe(INHERIT);
    expect(index['relatorios.core'].default).toBe('none');
    // aceita o índice já achatado (não achata duas vezes)
    expect(flattenCatalog(index)).toBe(index);
  });

  it('rótulos e constantes', () => {
    expect(LEVEL_LABELS).toEqual({ none: 'Nada', view: 'Ver', edit: 'Editar' });
    expect(INHERIT).toBe('inherit');
  });

  it('admin → o maior nível que o nó aceita', () => {
    const base = { catalog: CATALOG, explicit: {}, roleTree: {}, admin: true };
    expect(effectiveLevel({ ...base, key: 'crm' })).toBe('edit');
    expect(effectiveLevel({ ...base, key: 'inicio' })).toBe('view');
    expect(effectiveLevel({ ...base, key: 'crm.fontes' })).toBe('edit');
    expect(effectiveLevel({ ...base, key: 'empresario' })).toBe('view');
  });

  it('nó só de administradores (ou com pai assim) → nada para quem não é admin', () => {
    const base = {
      catalog: CATALOG,
      explicit: { 'crm.fontes': 'edit', empresario: 'view' },
      roleTree: {},
      admin: false,
    };
    expect(effectiveLevel({ ...base, key: 'crm.fontes' })).toBe('none');
    expect(effectiveLevel({ ...base, key: 'relatorios.core' })).toBe('none');
    expect(effectiveLevel({ ...base, key: 'empresario.mesa' })).toBe('none');
    const index = flattenCatalog(CATALOG);
    expect(adminLocked(index, 'empresario.mesa')).toBe(true);
    expect(adminLocked(index, 'crm')).toBe(false);
  });

  it('padrão do catálogo: inherit sobe; sem default e sem pai → nada', () => {
    const index = flattenCatalog(CATALOG);
    expect(defaultLevel(index, 'relatorios.crm')).toBe('none'); // pai = none
    expect(defaultLevel(index, 'agenda.exames')).toBe('edit'); // pai = edit
    expect(defaultLevel(index, 'agenda.semdefault')).toBe('edit');
    expect(defaultLevel(index, 'crm.agendamentos')).toBe('view');
    expect(defaultLevel(index, 'crm.funis')).toBe('none');
    expect(
      defaultLevel(
        flattenCatalog([{ key: 'solto', levels: ['view'] }]),
        'solto'
      )
    ).toBe('none');
  });

  it('marcação no pai vale para os filhos sem marcação própria', () => {
    const base = {
      catalog: CATALOG,
      explicit: { relatorios: 'view' },
      roleTree: {},
      admin: false,
    };
    expect(effectiveLevel({ ...base, key: 'relatorios' })).toBe('view');
    expect(effectiveLevel({ ...base, key: 'relatorios.crm' })).toBe('view');
    // o filho com marcação própria vence o pai
    const own = {
      ...base,
      explicit: { relatorios: 'view', 'relatorios.crm': 'none' },
    };
    expect(effectiveLevel({ ...own, key: 'relatorios.crm' })).toBe('none');
  });

  it('marcação própria vence a do papel; o papel vence o padrão', () => {
    const base = { catalog: CATALOG, admin: false };
    expect(
      effectiveLevel({
        ...base,
        explicit: {},
        roleTree: { crm: 'view' },
        key: 'crm',
      })
    ).toBe('view');
    expect(
      effectiveLevel({
        ...base,
        explicit: { crm: 'none' },
        roleTree: { crm: 'view' },
        key: 'crm',
      })
    ).toBe('none');
    // o papel marca o pai e a pessoa marca o filho: o filho é da pessoa
    expect(
      effectiveLevel({
        ...base,
        explicit: { 'crm.agendamentos': 'none' },
        roleTree: { crm: 'edit' },
        key: 'crm.agendamentos',
      })
    ).toBe('none');
    // o papel marca o filho e a pessoa marca o pai: a marcação mais perta vale
    expect(
      effectiveLevel({
        ...base,
        explicit: { crm: 'none' },
        roleTree: { 'crm.agendamentos': 'view' },
        key: 'crm.agendamentos',
      })
    ).toBe('view');
  });

  it('trava ao maior nível que o nó aceita', () => {
    const base = { catalog: CATALOG, roleTree: {}, admin: false };
    expect(
      effectiveLevel({ ...base, explicit: { inicio: 'edit' }, key: 'inicio' })
    ).toBe('view');
    expect(
      effectiveLevel({
        ...base,
        explicit: { crm: 'edit' },
        key: 'crm.agendamentos',
      })
    ).toBe('view');
    // valor inválido na marcação é ignorado (volta ao padrão)
    expect(
      effectiveLevel({ ...base, explicit: { crm: 'tudo' }, key: 'crm' })
    ).toBe('edit');
    // chave que não existe no catálogo → nada
    expect(effectiveLevel({ ...base, explicit: {}, key: 'nada.disso' })).toBe(
      'none'
    );
  });

  it('effectiveMap + summarize contam todos os nós', () => {
    const map = effectiveMap({
      catalog: CATALOG,
      explicit: { relatorios: 'view' },
      roleTree: {},
      admin: false,
    });
    expect(Object.keys(map)).toHaveLength(
      Object.keys(flattenCatalog(CATALOG)).length
    );
    expect(map.crm).toBe('edit');
    expect(map['relatorios.crm']).toBe('view');
    expect(map['relatorios.core']).toBe('none');
    const total = summarize(map);
    expect(total.view + total.edit + total.none).toBe(Object.keys(map).length);
    expect(
      summarize({ a: 'view', b: 'edit', c: 'edit', d: 'none', e: 'x' })
    ).toEqual({
      view: 1,
      edit: 2,
      none: 1,
    });
  });

  it('descendentes e marcação própria nos filhos', () => {
    const index = flattenCatalog(CATALOG);
    expect(descendantsOf(index, 'crm')).toEqual([
      'crm.funis',
      'crm.agendamentos',
      'crm.fontes',
    ]);
    expect(subtreeHasMarks(index, { 'crm.funis': 'edit' }, 'crm')).toBe(true);
    expect(subtreeHasMarks(index, { crm: 'edit' }, 'crm')).toBe(false);
  });
});
