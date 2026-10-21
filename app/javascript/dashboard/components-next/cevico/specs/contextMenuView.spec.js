import { mount } from '@vue/test-utils';
import { nextTick, reactive } from 'vue';
import CevicoContextMenu from '../CevicoContextMenu.vue';
import {
  openMenu,
  closeMenu,
  requestHint,
  useCevicoContextMenu,
} from 'dashboard/composables/useCevicoContextMenu';

const route = reactive({ fullPath: '/app/accounts/3/agenda' });
vi.mock('vue-router', () => ({ useRoute: () => route }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { id: 7 } }),
}));

const { state } = useCevicoContextMenu();
const HINT_KEY = 'cevico_ctxmenu_hint_seen_7';

const settle = async () => {
  await nextTick();
  await nextTick();
  await nextTick();
};
const press = key =>
  document.dispatchEvent(
    new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })
  );
const rightClickOn = (items, extra = {}) => {
  const target = document.createElement('button');
  document.body.appendChild(target);
  return openMenu(
    {
      target,
      currentTarget: target,
      clientX: 100,
      clientY: 100,
      preventDefault: () => {},
      stopPropagation: () => {},
    },
    { title: 'Maria', subtitle: '09:00 · Avaliação', items, ...extra }
  );
};
const labels = () =>
  [...document.querySelectorAll('.cevico-ctx [role="menuitem"]')].map(el =>
    el.querySelector('.cevico-ctx-label').textContent.trim()
  );
const activeLabel = () =>
  document
    .querySelector('.cevico-ctx-active .cevico-ctx-label')
    ?.textContent.trim();

describe('CevicoContextMenu — a tela do menu (item 283)', () => {
  let wrapper;
  beforeEach(() => {
    localStorage.clear();
    localStorage.setItem(HINT_KEY, '1'); // sem a dica, salvo no teste dela
    route.fullPath = '/app/accounts/3/agenda';
    wrapper = mount(CevicoContextMenu, { attachTo: document.body });
  });
  afterEach(() => {
    closeMenu();
    wrapper.unmount();
    document.body.innerHTML = '';
  });

  it('desenha título, itens e separador com os papéis de acessibilidade', async () => {
    rightClickOn([
      { label: 'Abrir detalhes', action: () => {} },
      { separator: true },
      { label: 'Cancelar', danger: true, action: () => {} },
    ]);
    await settle();
    const menu = document.querySelector('.cevico-ctx');
    expect(menu.getAttribute('role')).toBe('menu');
    expect(menu.textContent).toContain('Maria');
    expect(menu.textContent).toContain('09:00 · Avaliação');
    expect(labels()).toEqual(['Abrir detalhes', 'Cancelar']);
    expect(document.querySelectorAll('[role="separator"]')).toHaveLength(1);
    expect(document.querySelector('.cevico-ctx-danger')).not.toBeNull();
    expect(menu.style.visibility).toBe('visible');
  });

  it('clique no item roda a ação e fecha', async () => {
    const action = vi.fn();
    rightClickOn([{ label: 'Abrir detalhes', action }]);
    await settle();
    document.querySelector('[role="menuitem"]').click();
    await settle();
    expect(action).toHaveBeenCalledTimes(1);
    expect(state.open).toBe(false);
    expect(document.querySelector('.cevico-ctx')).toBeNull();
  });

  it('item desligado não roda nem fecha', async () => {
    const action = vi.fn();
    rightClickOn([{ label: 'Compareceu', disabled: true, action }]);
    await settle();
    document.querySelector('[role="menuitem"]').click();
    await settle();
    expect(action).not.toHaveBeenCalled();
    expect(state.open).toBe(true);
  });

  it('teclado: setas pulam separador e desligado, Enter escolhe', async () => {
    const first = vi.fn();
    const last = vi.fn();
    rightClickOn([
      { label: 'Abrir', action: first },
      { separator: true },
      { label: 'Desligado', disabled: true, action: () => {} },
      { label: 'Copiar', action: last },
    ]);
    await settle();
    press('ArrowDown');
    await settle();
    expect(activeLabel()).toBe('Abrir');
    press('ArrowDown');
    await settle();
    expect(activeLabel()).toBe('Copiar');
    press('ArrowDown'); // dá a volta
    await settle();
    expect(activeLabel()).toBe('Abrir');
    press('ArrowUp');
    await settle();
    expect(activeLabel()).toBe('Copiar');
    press('Enter');
    await settle();
    expect(last).toHaveBeenCalledTimes(1);
    expect(first).not.toHaveBeenCalled();
    expect(state.open).toBe(false);
  });

  it('fecha com Esc, clique fora, rolagem e troca de tela', async () => {
    const items = [{ label: 'Abrir', action: () => {} }];

    rightClickOn(items);
    await settle();
    press('Escape');
    expect(state.open).toBe(false);

    rightClickOn(items);
    await settle();
    document.body.dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(state.open).toBe(false);

    rightClickOn(items);
    await settle();
    // clique DENTRO do menu não fecha por "clique fora"
    document
      .querySelector('.cevico-ctx')
      .dispatchEvent(new Event('pointerdown', { bubbles: true }));
    expect(state.open).toBe(true);
    window.dispatchEvent(new Event('scroll'));
    expect(state.open).toBe(false);

    rightClickOn(items);
    await settle();
    route.fullPath = '/app/accounts/3/crm';
    await settle();
    expect(state.open).toBe(false);
  });

  it('segundo nível: entra, volta e escolhe', async () => {
    const move = vi.fn();
    rightClickOn([
      { label: 'Abrir', action: () => {} },
      {
        label: 'Mover para a coluna',
        children: [
          { label: 'Agendado', action: move },
          { label: 'Compareceu', action: () => {} },
        ],
      },
    ]);
    await settle();
    const parent = document.querySelectorAll('[role="menuitem"]')[1];
    expect(parent.getAttribute('aria-haspopup')).toBe('menu');
    parent.click();
    await settle();
    expect(state.open).toBe(true);
    expect(labels()).toEqual(['Agendado', 'Compareceu']);

    press('ArrowLeft');
    await settle();
    expect(labels()).toEqual(['Abrir', 'Mover para a coluna']);
    expect(activeLabel()).toBe('Mover para a coluna');

    press('ArrowRight');
    await settle();
    press('ArrowDown');
    press('Enter');
    await settle();
    expect(move).toHaveBeenCalledTimes(1);
    expect(state.open).toBe(false);
  });

  it('erro na ação da tela não trava o menu', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    rightClickOn([
      {
        label: 'Quebra',
        action: () => {
          throw new Error('x');
        },
      },
    ]);
    await settle();
    expect(() =>
      document.querySelector('[role="menuitem"]').click()
    ).not.toThrow();
    expect(state.open).toBe(false);
    spy.mockRestore();
  });

  it('toque longo: o clique de quando o dedo sai não escolhe item', async () => {
    const action = vi.fn();
    const target = document.createElement('button');
    document.body.appendChild(target);
    openMenu(
      {
        target,
        currentTarget: target,
        clientX: 10,
        clientY: 10,
        isLongPress: true,
      },
      { items: [{ label: 'Abrir', action }] }
    );
    await settle();
    document.querySelector('[role="menuitem"]').click();
    expect(action).not.toHaveBeenCalled();
    expect(state.open).toBe(true);
  });

  describe('item paleta (item 290)', () => {
    const COLORS = [
      { value: '#DC2626', label: 'Tomate' },
      { value: '#16A34A', label: 'Kiwi' },
      { value: '#2563EB', label: 'Mirtilo' },
    ];
    const swatches = () => [...document.querySelectorAll('.cevico-ctx-swatch')];
    const defaultBtn = () => document.querySelector('.cevico-ctx-default');

    it('desenha as bolinhas, o "Padrão" e marca a cor atual', async () => {
      rightClickOn([
        { label: 'Abrir', action: () => {} },
        { palette: COLORS, value: '#16a34a', label: 'Cor', onPick: () => {} },
      ]);
      await settle();
      expect(swatches()).toHaveLength(3);
      expect(swatches().map(el => el.getAttribute('aria-label'))).toEqual([
        'Tomate',
        'Kiwi',
        'Mirtilo',
      ]);
      expect(swatches().map(el => el.getAttribute('aria-checked'))).toEqual([
        'false',
        'true',
        'false',
      ]);
      expect(defaultBtn().textContent.trim()).toBe('Padrão');
      expect(defaultBtn().getAttribute('aria-checked')).toBe('false');
      expect(document.querySelector('.cevico-ctx').textContent).toContain(
        'Cor'
      );
    });

    it('sem cor escolhida, o "Padrão" é que fica marcado', async () => {
      rightClickOn([{ palette: COLORS, value: null, onPick: () => {} }]);
      await settle();
      expect(defaultBtn().getAttribute('aria-checked')).toBe('true');
      expect(
        swatches().every(el => el.getAttribute('aria-checked') === 'false')
      ).toBe(true);
    });

    it('clicar numa bolinha entrega a cor e fecha', async () => {
      const onPick = vi.fn();
      rightClickOn([{ palette: COLORS, value: null, onPick }]);
      await settle();
      swatches()[2].click();
      await settle();
      expect(onPick).toHaveBeenCalledWith('#2563EB');
      expect(state.open).toBe(false);
    });

    it('"Padrão" entrega null (volta à cor do tipo)', async () => {
      const onPick = vi.fn();
      rightClickOn([{ palette: COLORS, value: '#DC2626', onPick }]);
      await settle();
      defaultBtn().click();
      await settle();
      expect(onPick).toHaveBeenCalledWith(null);
      expect(state.open).toBe(false);
    });

    it('teclado: desce até a paleta, anda nas bolinhas e Enter escolhe', async () => {
      const onPick = vi.fn();
      const open = vi.fn();
      rightClickOn([
        { label: 'Abrir', action: open },
        { palette: COLORS, value: '#16A34A', onPick },
      ]);
      await settle();
      press('ArrowDown');
      press('ArrowDown'); // paleta: começa na cor atual (Kiwi)
      await settle();
      expect(
        document
          .querySelector('.cevico-ctx-swatch-focus')
          .getAttribute('aria-label')
      ).toBe('Kiwi');
      press('ArrowRight'); // Mirtilo
      press('ArrowRight'); // Padrão
      press('ArrowRight'); // dá a volta: Tomate
      await settle();
      expect(state.open).toBe(true); // seta para o lado não fecha nem volta
      press('Enter');
      await settle();
      expect(onPick).toHaveBeenCalledWith('#DC2626');
      expect(open).not.toHaveBeenCalled();
    });

    it('teclado: seta para a esquerda chega no "Padrão"', async () => {
      const onPick = vi.fn();
      rightClickOn([{ palette: COLORS, value: '#DC2626', onPick }]);
      await settle();
      press('ArrowDown');
      press('ArrowLeft');
      press('Enter');
      await settle();
      expect(onPick).toHaveBeenCalledWith(null);
    });

    it('aceita cores como texto simples e ignora paleta vazia', async () => {
      const onPick = vi.fn();
      rightClickOn([
        { label: 'Abrir', action: () => {} },
        { palette: [], onPick },
        { palette: ['#DC2626', '#16A34A'], onPick },
      ]);
      await settle();
      expect(document.querySelectorAll('.cevico-ctx-palette')).toHaveLength(1);
      expect(swatches()).toHaveLength(2);
    });

    it('paleta desligada não escolhe', async () => {
      const onPick = vi.fn();
      rightClickOn([
        { label: 'Abrir', action: () => {} },
        { palette: COLORS, disabled: true, onPick },
      ]);
      await settle();
      swatches()[0].click();
      expect(onPick).not.toHaveBeenCalled();
      expect(state.open).toBe(true);
    });
  });

  it('dica aparece uma vez por pessoa e some no "Entendi"', async () => {
    localStorage.clear();
    requestHint();
    await settle();
    const tip = document.querySelector('.cevico-ctx-tip');
    expect(tip.textContent).toContain(
      'Dica: clique com o botão direito para ver os atalhos'
    );
    expect(localStorage.getItem(HINT_KEY)).toBe('1');
    tip.querySelector('button').click();
    await settle();
    expect(document.querySelector('.cevico-ctx-tip')).toBeNull();

    // entrou de novo no sistema (menu montado outra vez): já viu, não volta
    wrapper.unmount();
    wrapper = mount(CevicoContextMenu, { attachTo: document.body });
    requestHint();
    await settle();
    expect(document.querySelector('.cevico-ctx-tip')).toBeNull();
  });
});
