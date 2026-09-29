import {
  computeMenuPosition,
  shouldUseNativeMenu,
  normalizeItems,
  openMenu,
  closeMenu,
  vCvMenu,
  useCevicoContextMenu,
  LONG_PRESS_MS,
  DEFAULT_RGB,
} from 'dashboard/composables/useCevicoContextMenu';

const { state } = useCevicoContextMenu();

const fakeEvent = (target, extra = {}) => ({
  target,
  currentTarget: target,
  clientX: 120,
  clientY: 80,
  shiftKey: false,
  preventDefault: vi.fn(),
  stopPropagation: vi.fn(),
  ...extra,
});
const noSelection = { getSelection: () => null };
const mount = html => {
  const box = document.createElement('div');
  box.innerHTML = html;
  document.body.appendChild(box);
  return box;
};

describe('menu do botão direito (item 283)', () => {
  afterEach(() => {
    closeMenu();
    document.body.innerHTML = '';
    vi.useRealTimers();
  });

  describe('posição (computeMenuPosition)', () => {
    const screen = { viewportWidth: 1000, viewportHeight: 700 };
    const menu = { width: 240, height: 300 };

    it('abre no ponto do mouse quando cabe', () => {
      const p = computeMenuPosition({ x: 100, y: 90, ...menu, ...screen });
      expect(p).toMatchObject({
        left: 100,
        top: 90,
        flipX: false,
        flipY: false,
      });
    });

    it('vira para a esquerda perto da borda direita', () => {
      const p = computeMenuPosition({ x: 950, y: 90, ...menu, ...screen });
      expect(p.flipX).toBe(true);
      expect(p.left).toBe(710);
      expect(p.left + menu.width).toBeLessThanOrEqual(1000 - 8);
    });

    it('vira para cima perto da borda de baixo', () => {
      const p = computeMenuPosition({ x: 100, y: 650, ...menu, ...screen });
      expect(p.flipY).toBe(true);
      expect(p.top).toBe(350);
    });

    it('vira nos dois sentidos no canto de baixo à direita', () => {
      const p = computeMenuPosition({ x: 990, y: 690, ...menu, ...screen });
      expect(p).toMatchObject({
        flipX: true,
        flipY: true,
        left: 750,
        top: 390,
      });
    });

    it('nunca sai da tela, mesmo em tela pequena (celular)', () => {
      const p = computeMenuPosition({
        x: 300,
        y: 500,
        width: 320,
        height: 900,
        viewportWidth: 360,
        viewportHeight: 640,
      });
      expect(p.left).toBeGreaterThanOrEqual(8);
      expect(p.top).toBe(8);
      expect(p.maxHeight).toBe(624);
    });

    it('respeita a margem quando o clique é colado na borda', () => {
      const p = computeMenuPosition({ x: 0, y: 0, ...menu, ...screen });
      expect(p).toMatchObject({ left: 8, top: 8 });
    });
  });

  describe('quando o navegador fica com o menu (shouldUseNativeMenu)', () => {
    it('não abre em campo de texto, textarea, select e área editável', () => {
      const box = mount(`
        <input id="a" type="text" />
        <textarea id="b"></textarea>
        <select id="c"><option>x</option></select>
        <div id="d" contenteditable="true"><b id="e">texto</b></div>
        <div class="ProseMirror"><p id="f">nota</p></div>
      `);
      ['a', 'b', 'c', 'd', 'e', 'f'].forEach(id => {
        const el = box.querySelector(`#${id}`);
        expect(shouldUseNativeMenu(fakeEvent(el), noSelection)).toBe(true);
      });
    });

    it('não abre em link nem em área marcada com data-cv-native-menu', () => {
      const box = mount(`
        <a href="/x"><span id="a">link</span></a>
        <div data-cv-native-menu><span id="b">livre</span></div>
      `);
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#a')), noSelection)
      ).toBe(true);
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#b')), noSelection)
      ).toBe(true);
    });

    it('Shift + botão direito sempre deixa o menu do navegador', () => {
      const box = mount('<button id="a">Consulta</button>');
      const el = box.querySelector('#a');
      expect(
        shouldUseNativeMenu(fakeEvent(el, { shiftKey: true }), noSelection)
      ).toBe(true);
    });

    it('abre o nosso em cartão, botão e área não editável', () => {
      const box = mount(`
        <button id="a">Consulta</button>
        <div id="b" contenteditable="false">cartão</div>
      `);
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#a')), noSelection)
      ).toBe(false);
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#b')), noSelection)
      ).toBe(false);
    });

    it('texto selecionado no item = menu do navegador (copiar)', () => {
      const box = mount(
        '<div id="card"><p id="name">Maria da Silva</p></div><p id="other">x</p>'
      );
      const name = box.querySelector('#name');
      const selection = {
        isCollapsed: false,
        toString: () => 'Maria',
        anchorNode: name.firstChild,
        focusNode: name.firstChild,
        containsNode: () => false,
      };
      const opts = { getSelection: () => selection };
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#card')), opts)
      ).toBe(true);
      // seleção em OUTRO lugar da tela não atrapalha
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#other')), opts)
      ).toBe(false);
      // seleção vazia (só o cursor) não conta
      const empty = {
        getSelection: () => ({ isCollapsed: true, toString: () => '' }),
      };
      expect(
        shouldUseNativeMenu(fakeEvent(box.querySelector('#card')), empty)
      ).toBe(false);
    });

    it('clique em nó de texto usa o elemento pai', () => {
      const box = mount('<input id="a" /><p id="b">oi</p>');
      const text = box.querySelector('#b').firstChild;
      expect(shouldUseNativeMenu(fakeEvent(text), noSelection)).toBe(false);
    });
  });

  describe('lista de itens (normalizeItems)', () => {
    it('tira vazios, ocultos e separadores sobrando', () => {
      const out = normalizeItems([
        { separator: true },
        { label: 'Abrir' },
        false,
        null,
        { separator: true },
        { separator: true },
        { label: 'Some', hidden: true },
        { label: 'Copiar' },
        { separator: true },
      ]);
      expect(out.map(i => i.label || '—')).toEqual(['Abrir', '—', 'Copiar']);
    });

    it('segundo nível vazio some; com itens fica', () => {
      const out = normalizeItems([
        { label: 'Mover', children: [] },
        { label: 'Mover para', children: [{ label: 'Coluna A' }, null] },
      ]);
      expect(out).toHaveLength(1);
      expect(out[0].children).toEqual([{ label: 'Coluna A' }]);
    });

    it('aceita lixo sem quebrar', () => {
      expect(normalizeItems(undefined)).toEqual([]);
      expect(normalizeItems('x')).toEqual([]);
    });
  });

  describe('openMenu', () => {
    it('abre, segura o menu do navegador e guarda título e itens', () => {
      const box = mount('<button id="a">Consulta</button>');
      const event = fakeEvent(box.querySelector('#a'));
      const opened = openMenu(event, {
        title: 'Maria',
        subtitle: '09:00',
        items: [{ label: 'Abrir' }],
      });
      expect(opened).toBe(true);
      expect(event.preventDefault).toHaveBeenCalled();
      expect(state.open).toBe(true);
      expect(state).toMatchObject({
        x: 120,
        y: 80,
        title: 'Maria',
        subtitle: '09:00',
      });
      expect(state.items).toHaveLength(1);
      expect(state.rgb).toBe(DEFAULT_RGB);
    });

    it('sem itens não abre e não segura o menu do navegador', () => {
      const box = mount('<button id="a">Consulta</button>');
      const event = fakeEvent(box.querySelector('#a'));
      expect(openMenu(event, { items: [] })).toBe(false);
      expect(event.preventDefault).not.toHaveBeenCalled();
      expect(state.open).toBe(false);
    });

    it('em campo de texto não abre', () => {
      const box = mount('<input id="a" />');
      const event = fakeEvent(box.querySelector('#a'));
      expect(openMenu(event, { items: [{ label: 'Abrir' }] })).toBe(false);
      expect(event.preventDefault).not.toHaveBeenCalled();
      expect(state.open).toBe(false);
    });

    it('cor fora do formato "r g b" cai no azul do kit', () => {
      const box = mount('<button id="a">Consulta</button>');
      openMenu(fakeEvent(box.querySelector('#a')), {
        rgb: '1, 2, 3',
        items: [{ label: 'Abrir' }],
      });
      expect(state.rgb).toBe(DEFAULT_RGB);
      openMenu(fakeEvent(box.querySelector('#a')), {
        rgb: '5 150 105',
        items: [{ label: 'Abrir' }],
      });
      expect(state.rgb).toBe('5 150 105');
    });
  });

  describe('diretiva v-cv-menu', () => {
    const bind = (el, value) => {
      vCvMenu.mounted(el, { value });
      return () => vCvMenu.beforeUnmount(el);
    };
    const rightClick = (el, init = {}) => {
      const event = new MouseEvent('contextmenu', {
        bubbles: true,
        cancelable: true,
        clientX: 50,
        clientY: 60,
        ...init,
      });
      el.dispatchEvent(event);
      return event;
    };

    it('botão direito no cartão abre; no campo de texto de dentro, não', () => {
      const box = mount(
        '<div id="card"><span id="name">Maria</span><input id="note" /></div>'
      );
      const card = box.querySelector('#card');
      const build = vi.fn(() => ({
        title: 'Maria',
        items: [{ label: 'Abrir' }],
      }));
      const unbind = bind(card, build);

      const onInput = rightClick(box.querySelector('#note'));
      expect(onInput.defaultPrevented).toBe(false);
      expect(state.open).toBe(false);
      expect(build).not.toHaveBeenCalled();

      const onName = rightClick(box.querySelector('#name'));
      expect(onName.defaultPrevented).toBe(true);
      expect(state.open).toBe(true);
      expect(state.title).toBe('Maria');
      unbind();
    });

    it('Shift + botão direito não abre o nosso', () => {
      const box = mount('<div id="card">Maria</div>');
      const card = box.querySelector('#card');
      const unbind = bind(card, () => [{ label: 'Abrir' }]);
      const event = rightClick(card, { shiftKey: true });
      expect(event.defaultPrevented).toBe(false);
      expect(state.open).toBe(false);
      unbind();
    });

    it('item de dentro ganha do de fora; sem menu, sobe para o de fora', () => {
      const box = mount(
        '<div id="col"><button id="ev">Maria</button><button id="plain">x</button></div>'
      );
      const col = box.querySelector('#col');
      const ev = box.querySelector('#ev');
      const plain = box.querySelector('#plain');
      const a = bind(col, () => ({
        title: 'Horário',
        items: [{ label: 'Nova' }],
      }));
      const b = bind(ev, () => ({
        title: 'Consulta',
        items: [{ label: 'Abrir' }],
      }));
      const c = bind(plain, () => null);

      rightClick(ev);
      expect(state.title).toBe('Consulta');
      closeMenu();
      rightClick(plain);
      expect(state.title).toBe('Horário');
      a();
      b();
      c();
    });

    it('depois de desligada, não abre mais', () => {
      const box = mount('<div id="card">Maria</div>');
      const card = box.querySelector('#card');
      bind(card, () => [{ label: 'Abrir' }])();
      const event = rightClick(card);
      expect(event.defaultPrevented).toBe(false);
      expect(state.open).toBe(false);
    });

    it('toque longo abre; toque curto ou arrastar o dedo, não', () => {
      vi.useFakeTimers();
      const box = mount('<div id="card">Maria</div>');
      const card = box.querySelector('#card');
      const unbind = bind(card, () => ({
        title: 'Maria',
        items: [{ label: 'Abrir' }],
      }));
      const touch = (type, x, y) => {
        const event = new Event(type, { bubbles: true, cancelable: true });
        event.touches = type === 'touchend' ? [] : [{ clientX: x, clientY: y }];
        card.dispatchEvent(event);
      };

      touch('touchstart', 30, 40);
      vi.advanceTimersByTime(200);
      touch('touchend');
      vi.advanceTimersByTime(LONG_PRESS_MS);
      expect(state.open).toBe(false);

      touch('touchstart', 30, 40);
      touch('touchmove', 30, 80);
      vi.advanceTimersByTime(LONG_PRESS_MS + 10);
      expect(state.open).toBe(false);

      touch('touchstart', 30, 40);
      touch('touchmove', 32, 43);
      vi.advanceTimersByTime(LONG_PRESS_MS + 10);
      expect(state.open).toBe(true);
      expect(state).toMatchObject({ x: 30, y: 40, byTouch: true });

      // o clique de quando o dedo sai não chega no cartão
      const onClick = vi.fn();
      card.addEventListener('click', onClick);
      card.dispatchEvent(
        new MouseEvent('click', { bubbles: true, cancelable: true })
      );
      expect(onClick).not.toHaveBeenCalled();
      card.dispatchEvent(
        new MouseEvent('click', { bubbles: true, cancelable: true })
      );
      expect(onClick).toHaveBeenCalledTimes(1);
      unbind();
    });
  });
});
