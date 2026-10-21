// 🔔 TOQUES DE CHAMADA (item 273, 28/09 — pedido: "precisamos mudar o toque do
// telefonema… um ring ring das antigas… uma biblioteca com uns 5 pra gente
// escolher: um mais moderno, um mais clássico etc.").
//
// Tudo sintetizado em WebAudio (sem arquivo de áudio, sem direito autoral):
// cada toque é uma função que desenha UM ciclo a partir do instante `at` e
// devolve quantos segundos dura o ciclo (o chamador repete). A escolha fica
// no navegador de cada pessoa (localStorage) — cada atendente escolhe o seu.

const STORAGE_KEY = 'cevico_ringtone';
export const DEFAULT_RINGTONE = 'classico';

// envelope simples: sobe rápido, segura, cai
const env = (ctx, at, dur, peak = 0.2, attack = 0.01, release = 0.05) => {
  const g = ctx.createGain();
  g.gain.setValueAtTime(0, at);
  g.gain.linearRampToValueAtTime(peak, at + attack);
  g.gain.setValueAtTime(peak, Math.max(at + attack, at + dur - release));
  g.gain.linearRampToValueAtTime(0, at + dur);
  g.connect(ctx.destination);
  return g;
};

const tone = (ctx, at, dur, freqs, { type = 'sine', peak = 0.2 } = {}) => {
  const g = env(ctx, at, dur, peak);
  freqs.forEach(f => {
    const o = ctx.createOscillator();
    o.type = type;
    o.frequency.value = f;
    o.connect(g);
    o.start(at);
    o.stop(at + dur + 0.05);
  });
};

// nota percussiva (marimba/sino): parciais com decaimento exponencial
const strike = (
  ctx,
  at,
  freq,
  dur = 0.5,
  peak = 0.22,
  partials = [1, 2.76, 5.4]
) => {
  partials.forEach((mult, i) => {
    const g = ctx.createGain();
    const p = peak / (i + 1) ** 1.6;
    g.gain.setValueAtTime(p, at);
    g.gain.exponentialRampToValueAtTime(0.0008, at + dur / (i + 1));
    g.connect(ctx.destination);
    const o = ctx.createOscillator();
    o.type = 'sine';
    o.frequency.value = freq * mult;
    o.connect(g);
    o.start(at);
    o.stop(at + dur + 0.05);
  });
};

// sino de telefone de disco: duas campainhas batidas ~20x por segundo
const bellBurst = (ctx, at, dur) => {
  const hits = Math.floor(dur / 0.05);
  for (let i = 0; i < hits; i += 1) {
    const t = at + i * 0.05;
    strike(ctx, t, i % 2 ? 1180 : 1480, 0.09, 0.16, [1, 1.9]);
  }
};

export const RINGTONES = [
  {
    key: 'classico',
    label: 'Ring ring clássico',
    hint: 'telefone de disco: duas campainhas de verdade, ring… ring…',
    icon: 'i-lucide-phone',
    play(ctx, at) {
      bellBurst(ctx, at, 0.9);
      bellBurst(ctx, at + 1.15, 0.9);
      return 4.2;
    },
  },
  {
    key: 'fixo',
    label: 'Telefone fixo',
    hint: 'o "trim-trim" do fixo de casa (dois toques curtos)',
    icon: 'i-lucide-phone-call',
    play(ctx, at) {
      tone(ctx, at, 0.4, [400, 450], { peak: 0.2 });
      tone(ctx, at + 0.6, 0.4, [400, 450], { peak: 0.2 });
      return 3.0;
    },
  },
  {
    key: 'moderno',
    label: 'Moderno',
    hint: 'marimba suave subindo, estilo celular de hoje',
    icon: 'i-lucide-smartphone',
    play(ctx, at) {
      [523.25, 659.25, 783.99, 1046.5].forEach((f, i) =>
        strike(ctx, at + i * 0.16, f, 0.55, 0.2)
      );
      [1046.5, 783.99].forEach((f, i) =>
        strike(ctx, at + 0.95 + i * 0.16, f, 0.6, 0.16)
      );
      return 3.4;
    },
  },
  {
    key: 'discreto',
    label: 'Discreto',
    hint: 'dois sininhos leves, para quem atende perto de paciente',
    icon: 'i-lucide-bell',
    play(ctx, at) {
      strike(ctx, at, 1318.5, 0.9, 0.14);
      strike(ctx, at + 0.35, 1046.5, 1.1, 0.14);
      return 3.0;
    },
  },
  {
    key: 'retro',
    label: 'Retrô digital',
    hint: 'trinado de celular dos anos 2000 (onda quadrada)',
    icon: 'i-lucide-gamepad-2',
    play(ctx, at) {
      const notes = [880, 1108.7, 880, 1108.7, 880, 1108.7, 1318.5, 1108.7];
      notes.forEach((f, i) =>
        tone(ctx, at + i * 0.09, 0.08, [f], { type: 'square', peak: 0.06 })
      );
      notes.forEach((f, i) =>
        tone(ctx, at + 0.95 + i * 0.09, 0.08, [f], {
          type: 'square',
          peak: 0.06,
        })
      );
      return 3.2;
    },
  },
  {
    key: 'atual',
    label: 'Tum-tum (o de antes)',
    hint: 'o toque que o sistema usava até agora',
    icon: 'i-lucide-audio-lines',
    play(ctx, at) {
      tone(ctx, at, 0.22, [440, 480], { peak: 0.18 });
      tone(ctx, at + 0.34, 0.22, [440, 480], { peak: 0.18 });
      return 2.6;
    },
  },
];

export const ringtoneByKey = key =>
  RINGTONES.find(r => r.key === key) || RINGTONES[0];

export const getRingtoneKey = () => {
  try {
    const k = localStorage.getItem(STORAGE_KEY);
    return RINGTONES.some(r => r.key === k) ? k : DEFAULT_RINGTONE;
  } catch {
    return DEFAULT_RINGTONE;
  }
};

export const setRingtoneKey = key => {
  try {
    localStorage.setItem(STORAGE_KEY, key);
  } catch {
    // navegador sem storage: fica só na sessão
  }
};

const newCtx = () => {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return null;
  const ctx = new Ctx();
  if (ctx.state === 'suspended') {
    const r = ctx.resume();
    if (r && r.catch) r.catch(() => {});
  }
  return ctx;
};

// toca em LOOP até chamar o stop devolvido (usado na chamada de verdade)
export const startRingtoneLoop = (key = getRingtoneKey()) => {
  const ctx = newCtx();
  if (!ctx) return () => {};
  const ring = ringtoneByKey(key);
  let timer = null;
  const cycle = () => {
    try {
      const period = ring.play(ctx, ctx.currentTime + 0.05);
      timer = setTimeout(cycle, Math.max(1, period) * 1000);
    } catch {
      timer = null;
    }
  };
  cycle();
  return () => {
    if (timer) clearTimeout(timer);
    timer = null;
    const closing = ctx.close();
    if (closing && closing.catch) closing.catch(() => {});
  };
};

// prévia: um ciclo só (a escolha da biblioteca)
export const previewRingtone = key => {
  const ctx = newCtx();
  if (!ctx) return () => {};
  const period = ringtoneByKey(key).play(ctx, ctx.currentTime + 0.05);
  const timer = setTimeout(
    () => {
      const closing = ctx.close();
      if (closing && closing.catch) closing.catch(() => {});
    },
    (period + 0.5) * 1000
  );
  return () => {
    clearTimeout(timer);
    const closing = ctx.close();
    if (closing && closing.catch) closing.catch(() => {});
  };
};
