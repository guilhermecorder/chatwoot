import { mount } from '@vue/test-utils';
import AccessTreeEditor from '../AccessTreeEditor.vue';

// o CSS do editor não interessa ao teste (e o postcss do projeto não roda aqui)
vi.mock('../access.scss', () => ({}));

// 🔐 rodada 334 — o editor compila e se comporta: herança, cadeado, travas
const CATALOG = [
  { key: 'inicio', label: 'Meu Painel', levels: ['view'], default: 'view' },
  {
    key: 'crm',
    label: 'CRM',
    hint: 'o quadro',
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
        key: 'crm.fontes',
        parent: 'crm',
        label: 'Fontes',
        levels: ['view', 'edit'],
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
    ],
  },
];

const mountEditor = (props = {}) =>
  mount(AccessTreeEditor, {
    props: { catalog: CATALOG, modelValue: {}, ...props },
  });

const rowOf = (wrapper, label) =>
  wrapper
    .findAll('.cv-acc-row')
    .find(r => r.find('.cv-acc-label').text() === label);

describe('AccessTreeEditor (rodada 334)', () => {
  it('mostra as raízes, começa com os pais fechados e abre ao clicar', async () => {
    const w = mountEditor();
    expect(rowOf(w, 'CRM')).toBeTruthy();
    expect(rowOf(w, 'Funis')).toBeUndefined();
    await rowOf(w, 'CRM').find('.cv-acc-caret').trigger('click');
    expect(rowOf(w, 'Funis')).toBeTruthy();
  });

  it('pai com marcação própria em algum filho já começa aberto', () => {
    const w = mountEditor({ modelValue: { 'crm.funis': 'edit' } });
    expect(rowOf(w, 'Funis')).toBeTruthy();
    // e o pai ganha o "limpar os filhos"
    expect(rowOf(w, 'CRM').find('.cv-acc-clearkids').exists()).toBe(true);
  });

  it('"Herda" mostra o nível que vai valer e "Editar" só onde o nó aceita', () => {
    const w = mountEditor();
    const inicio = rowOf(w, 'Meu Painel');
    const labels = inicio.findAll('.cv-seg-item').map(b => b.text());
    expect(labels).toEqual(['Herda (Ver)', 'Nada', 'Ver']);
    const crm = rowOf(w, 'CRM');
    expect(crm.findAll('.cv-seg-item').map(b => b.text())).toEqual([
      'Herda (Editar)',
      'Nada',
      'Ver',
      'Editar',
    ]);
  });

  it('marcar o PAI só grava no pai; o filho passa a herdar', async () => {
    const w = mountEditor({ modelValue: { relatorios: 'view' } });
    const rel = rowOf(w, 'Relatórios');
    await rel.findAll('.cv-seg-item').at(1).trigger('click'); // Nada
    const emitted = w.emitted('update:modelValue');
    expect(emitted.at(-1)[0]).toEqual({ relatorios: 'none' });
    // o filho (aberto porque buscamos) mostra que herda Nada
    await w.setProps({ modelValue: { relatorios: 'none' } });
    await rel.find('.cv-acc-caret').trigger('click');
    const kid = rowOf(w, 'Dashboard CRM');
    expect(kid.findAll('.cv-seg-item').at(0).text()).toBe('Herda (Nada)');
  });

  it('"Herda" apaga a marcação própria; nível travado ao que o nó aceita', async () => {
    const w = mountEditor({ modelValue: { inicio: 'view', crm: 'edit' } });
    await rowOf(w, 'Meu Painel').findAll('.cv-seg-item').at(0).trigger('click');
    expect(w.emitted('update:modelValue').at(-1)[0]).toEqual({ crm: 'edit' });
  });

  it('nó só de administradores tem cadeado e não emite nada', async () => {
    const w = mountEditor({ modelValue: { crm: 'edit' } });
    await rowOf(w, 'CRM').find('.cv-acc-caret').trigger('click');
    const fontes = rowOf(w, 'Fontes');
    expect(fontes.find('.cv-acc-lock').text()).toContain('só administradores');
    expect(fontes.find('.cv-seg-item').exists()).toBe(false);
  });

  it('a marcação do papel vale por baixo e a própria vence', () => {
    const w = mountEditor({
      roleTree: { crm: 'view' },
      modelValue: { relatorios: 'view' },
    });
    expect(rowOf(w, 'CRM').findAll('.cv-seg-item').at(0).text()).toBe(
      'Herda (Ver)'
    );
    expect(
      rowOf(w, 'CRM').findAll('.cv-seg-item').at(0).attributes('title')
    ).toContain('do papel');
  });

  it('admin: tudo travado no máximo, sem botões de atalho', () => {
    const w = mountEditor({ admin: true });
    expect(w.find('.cv-seg-item').exists()).toBe(false);
    expect(w.text()).toContain('administrador(a)');
    expect(rowOf(w, 'CRM').find('.cv-acc-pill').text()).toContain('Editar');
    expect(rowOf(w, 'Meu Painel').find('.cv-acc-pill').text()).toContain('Ver');
    expect(w.find('.cv-acc-btn-edit').exists()).toBe(false);
  });

  it('readonly com startExpanded: só pílulas com o padrão, tudo aberto', () => {
    const w = mountEditor({ readonly: true, startExpanded: true });
    expect(w.find('.cv-seg-item').exists()).toBe(false);
    expect(rowOf(w, 'Funis').find('.cv-acc-pill').text()).toBe('Nada');
    expect(rowOf(w, 'Dashboard CRM').find('.cv-acc-pill').text()).toBe('Nada');
    expect(rowOf(w, 'CRM').find('.cv-acc-pill').text()).toBe('Editar');
  });

  it('Ver tudo / Editar tudo marcam só as raízes; Limpar tudo zera', async () => {
    const w = mountEditor({ modelValue: { 'crm.funis': 'edit' } });
    await w.find('.cv-acc-btn-view').trigger('click');
    expect(w.emitted('update:modelValue').at(-1)[0]).toEqual({
      inicio: 'view',
      crm: 'view',
      relatorios: 'view',
    });
    await w.find('.cv-acc-btn-edit').trigger('click');
    expect(w.emitted('update:modelValue').at(-1)[0]).toEqual({
      inicio: 'view',
      crm: 'edit',
      relatorios: 'view',
    });
    const buttons = w.findAll('.cv-acc-actions button');
    await buttons.at(buttons.length - 1).trigger('click'); // Limpar tudo
    expect(w.emitted('update:modelValue').at(-1)[0]).toEqual({});
  });

  it('busca filtra e abre o pai do que bateu', async () => {
    const w = mountEditor();
    await w.find('input[type="search"]').setValue('funis');
    expect(rowOf(w, 'Funis')).toBeTruthy();
    expect(rowOf(w, 'Meu Painel')).toBeUndefined();
    expect(rowOf(w, 'Relatórios')).toBeUndefined();
  });
});
