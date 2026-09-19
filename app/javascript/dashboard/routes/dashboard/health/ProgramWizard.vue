<script setup>
// ASSISTENTE "CRIE SEU PRÓPRIO TREINO / IMPORTAR TREINO" (rodada 25).
// 4 passos, como um jogo: 1 divisão e dias (+ semanas) · 2 exercícios
// de cada treino (digitando ou COLANDO uma lista) · 3 objetivo =
// parâmetro de sucesso/fracasso · 4 nome (fica no histórico pra vida
// toda). Devolve o `data` do registro kind=program (o servidor sanitiza).
import { ref, computed, watch } from 'vue';
import {
  GOALS, LETTERS, WEEKDAYS, METHOD_LABELS,
  buildPrescriptionSets, schemeText, parseImportText,
} from './warrior';
import { ROYAL, LARANJA, GRAD_ROYAL, GRAD_LARANJA, GRAD_NOITE } from './palette';

const props = defineProps({
  initial: { type: Object, default: null }, // data de um programa existente (editar)
  knownExercises: { type: Array, default: () => [] },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'cancel']);

const todayISO = new Date().toISOString().slice(0, 10);
const step = ref(1);
const STEPS = [
  { n: 1, label: 'Divisão e dias' },
  { n: 2, label: 'Exercícios' },
  { n: 3, label: 'Objetivo' },
  { n: 4, label: 'Nome' },
];

const blankRow = (o = {}) => ({
  name: o.name || '',
  method: o.method || 'sets',
  count: o.count || 3,
  min: o.min || 8,
  max: o.max || 12,
  rest: o.rest || '',
});
// prescrição salva → linha do assistente (pra editar um programa)
const rowFromPrescription = p => {
  const sets = p.sets || [];
  return blankRow({
    name: p.name,
    method: p.method || 'sets',
    count: p.method === 'rest_pause' || p.method === 'pyramid' ? sets.length : sets.length || 3,
    min: sets[0]?.min || 8,
    max: sets[0]?.max || 12,
    rest: p.rest || '',
  });
};

const form = ref({
  weekdays: ['Segunda', 'Quarta', 'Sexta'],
  letters: 3,
  weeks: 12,
  start_date: todayISO,
  goal: 'constancia',
  name: '',
  note: '',
  sessions: {},
});
const init = () => {
  const d = props.initial;
  if (!d) return;
  form.value.weekdays = d.weekdays?.length ? [...d.weekdays] : (d.sessions || []).map(s => s.weekday).filter(Boolean);
  form.value.letters = (d.sessions || []).length || 3;
  form.value.weeks = Number(d.weeks) || 12;
  form.value.start_date = d.start_date || todayISO;
  form.value.goal = d.goal || 'constancia';
  form.value.name = d.name || '';
  form.value.note = d.note || '';
  const sessions = {};
  (d.sessions || []).forEach(s => {
    sessions[s.key] = { label: s.label || '', rows: (s.exercises || []).map(rowFromPrescription) };
  });
  form.value.sessions = sessions;
};
init();

// letras ativas (A..N) e o dia de cada uma (na ordem dos dias marcados)
const letters = computed(() => LETTERS.slice(0, Math.max(1, Math.min(7, form.value.letters))));
const weekdaysOrdered = computed(() => WEEKDAYS.filter(d => form.value.weekdays.includes(d)));
const weekdayOf = i => weekdaysOrdered.value[i] || '';
// A B C A B C… quando marca mais dias que treinos
const rotation = computed(() =>
  weekdaysOrdered.value.map((d, i) => ({ day: d.slice(0, 3), key: letters.value[i % letters.value.length] }))
);
const toggleDay = d => {
  const i = form.value.weekdays.indexOf(d);
  if (i >= 0) form.value.weekdays.splice(i, 1);
  else form.value.weekdays.push(d);
  if (form.value.letters > form.value.weekdays.length && form.value.weekdays.length)
    form.value.letters = form.value.weekdays.length;
};
watch(
  () => form.value.weekdays.length,
  n => {
    if (!props.initial && n) form.value.letters = Math.min(n, 7);
  }
);
const sessionOf = key => {
  if (!form.value.sessions[key]) form.value.sessions[key] = { label: '', rows: [blankRow()] };
  return form.value.sessions[key];
};
const curKey = ref('A');
const cur = computed(() => sessionOf(curKey.value));
watch(letters, ls => {
  if (!ls.includes(curKey.value)) curKey.value = ls[0];
});

const addRow = () => cur.value.rows.push(blankRow());
const removeRow = i => cur.value.rows.splice(i, 1);
const bump = (row, field, delta, lo, hi) => {
  row[field] = Math.max(lo, Math.min(hi, (Number(row[field]) || lo) + delta));
  if (field === 'min' && row.max < row.min) row.max = row.min;
  if (field === 'max' && row.max < row.min) row.min = row.max;
};

// ── IMPORTAR (colar lista) ─────────────────────────────────────────
const pasteOpen = ref(false);
const pasteText = ref('');
const pasteInfo = ref('');
const applyPaste = () => {
  const groups = parseImportText(pasteText.value);
  if (!groups.length) {
    pasteInfo.value = 'Não achei exercícios no texto. Uma linha por exercício, ex.: "Supino reto 3x8-12".';
    return;
  }
  const withKeys = groups.filter(g => g.key);
  if (withKeys.length > 1) {
    // "Treino A / Treino B…" → cada bloco vira uma letra
    const usedKeys = withKeys.map(g => g.key);
    form.value.letters = Math.max(form.value.letters, usedKeys.length);
    withKeys.forEach(g => {
      const s = sessionOf(g.key);
      s.label = g.label || s.label;
      s.rows = g.exercises.map(e => blankRow(e));
    });
    pasteInfo.value = `${withKeys.length} treinos importados (${usedKeys.join(', ')}).`;
  } else {
    const all = groups.flatMap(g => g.exercises);
    const s = cur.value;
    s.rows = [...s.rows.filter(r => r.name.trim()), ...all.map(e => blankRow(e))];
    if (groups[0]?.label && !s.label) s.label = groups[0].label;
    pasteInfo.value = `${all.length} exercícios entraram no Treino ${curKey.value}.`;
  }
  pasteText.value = '';
};

// ── validação por passo ────────────────────────────────────────────
const stepError = computed(() => {
  if (step.value === 1) {
    if (!form.value.weekdays.length) return 'Marque ao menos um dia da semana.';
    if (!(form.value.weeks >= 1)) return 'Quantas semanas? (1 a 104)';
  }
  if (step.value === 2) {
    const empty = letters.value.filter(k => !sessionOf(k).rows.some(r => r.name.trim()));
    if (empty.length) return `Falta exercício no Treino ${empty.join(', ')}.`;
  }
  if (step.value === 4 && !form.value.name.trim()) return 'Dê um nome ao seu treino.';
  return '';
});
const next = () => {
  if (stepError.value) return;
  step.value = Math.min(4, step.value + 1);
  if (step.value === 4 && !form.value.name.trim()) {
    form.value.name = `Meu treino ${letters.value.join('')} · ${form.value.weeks} semanas`;
  }
};
const back = () => {
  step.value = Math.max(1, step.value - 1);
};

const goalSel = computed(() => GOALS.find(g => g.key === form.value.goal) || GOALS[0]);
const totalExercises = computed(() =>
  letters.value.reduce((a, k) => a + sessionOf(k).rows.filter(r => r.name.trim()).length, 0)
);

const build = () => ({
  name: form.value.name.trim(),
  goal: form.value.goal,
  status: props.initial?.status || 'active',
  weeks: Number(form.value.weeks) || 12,
  start_date: form.value.start_date || todayISO,
  note: form.value.note.trim(),
  weekdays: weekdaysOrdered.value,
  sessions: letters.value.map((k, i) => {
    const s = sessionOf(k);
    return {
      key: k,
      label: s.label.trim(),
      weekday: weekdayOf(i),
      exercises: s.rows
        .filter(r => r.name.trim())
        .map(r => {
          const sets = buildPrescriptionSets(r.method, r.count, r.min, r.max);
          return {
            name: r.name.trim(),
            method: r.method,
            scheme: schemeText(r.method, sets),
            sets,
            rest: r.rest.trim(),
            progression_type: 'top_of_ranges',
            progression: 'Bateu o topo da faixa em todas as séries → sobe a carga.',
          };
        }),
    };
  }),
});
const submit = () => {
  if (stepError.value) return;
  emit('save', build());
};
</script>

<template>
  <div class="hub-block p-4 mb-4 hub-wiz">
    <div class="flex items-center justify-between gap-2 flex-wrap mb-3">
      <div>
        <h2 class="text-sm font-bold text-n-slate-12">
          {{ initial ? 'Editar meu treino' : 'Criar / importar meu treino' }}
        </h2>
        <p class="text-[11px] text-n-slate-10">O Warrior continua guardado. Este é o SEU programa, com histórico próprio.</p>
      </div>
      <button class="h-8 px-3 rounded-lg text-xs text-n-slate-11 border border-n-weak hover:bg-n-alpha-1" @click="emit('cancel')">
        Cancelar
      </button>
    </div>

    <!-- trilha dos passos -->
    <div class="hub-wiz-steps mb-4">
      <button
        v-for="s in STEPS"
        :key="s.n"
        class="hub-wiz-step"
        :class="{ 'is-done': s.n < step, 'is-cur': s.n === step }"
        :style="s.n <= step ? { background: s.n === step ? GRAD_LARANJA : GRAD_ROYAL } : {}"
        :disabled="s.n > step"
        @click="s.n < step && (step = s.n)"
      >
        <b>{{ s.n < step ? '✓' : s.n }}</b>
        <span>{{ s.label }}</span>
      </button>
    </div>

    <!-- 1 · divisão, dias, semanas -->
    <template v-if="step === 1">
      <p class="text-xs font-bold text-n-slate-12 mb-1">Quais dias da semana você vai treinar?</p>
      <div class="flex gap-1.5 flex-wrap mb-3">
        <button
          v-for="d in WEEKDAYS"
          :key="d"
          class="h-9 px-3 rounded-full text-xs font-bold border transition"
          :class="form.weekdays.includes(d) ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
          :style="form.weekdays.includes(d) ? { background: GRAD_ROYAL } : {}"
          @click="toggleDay(d)"
        >
          {{ d.slice(0, 3) }}
        </button>
      </div>

      <div class="grid gap-3 sm:grid-cols-2 mb-3">
        <div class="rounded-xl border border-n-weak p-3">
          <p class="text-xs font-bold text-n-slate-12 mb-1">Divisão: quantos treinos diferentes?</p>
          <p class="text-[10px] text-n-slate-10 mb-2">ABC = 3 · ABCD = 4. Mais dias que treinos? Eles se repetem (A B C A…).</p>
          <div class="flex items-center gap-2">
            <button class="hub-wiz-bump" @click="form.letters = Math.max(1, form.letters - 1)">−</button>
            <span class="text-xl font-black" :style="{ color: ROYAL }">{{ letters.join('') }}</span>
            <button class="hub-wiz-bump" @click="form.letters = Math.min(7, form.letters + 1)">+</button>
          </div>
          <p v-if="rotation.length" class="text-[10px] text-n-slate-10 mt-2">
            <span v-for="r in rotation" :key="r.day" class="inline-block mr-2">{{ r.day }} → <b>{{ r.key }}</b></span>
          </p>
        </div>
        <div class="rounded-xl border border-n-weak p-3">
          <p class="text-xs font-bold text-n-slate-12 mb-1">Por quantas semanas?</p>
          <p class="text-[10px] text-n-slate-10 mb-2">8–12 semanas é um bom bloco. Dá pra encerrar antes ou renovar depois.</p>
          <div class="flex items-center gap-2">
            <button class="hub-wiz-bump" @click="form.weeks = Math.max(1, form.weeks - 1)">−</button>
            <span class="text-xl font-black" :style="{ color: ROYAL }">{{ form.weeks }}</span>
            <span class="text-xs text-n-slate-10">semanas</span>
            <button class="hub-wiz-bump" @click="form.weeks = Math.min(104, form.weeks + 1)">+</button>
          </div>
          <label class="flex items-center gap-2 mt-3 text-[11px] text-n-slate-11">
            Começa em
            <input v-model="form.start_date" type="date" class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12" style="width: 9.5rem; margin-bottom: 0" />
          </label>
        </div>
      </div>
    </template>

    <!-- 2 · exercícios de cada treino -->
    <template v-if="step === 2">
      <div class="flex items-center gap-1.5 flex-wrap mb-3">
        <button
          v-for="(k, i) in letters"
          :key="k"
          class="h-9 px-3 rounded-xl text-xs font-black border"
          :class="curKey === k ? 'text-white border-transparent' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
          :style="curKey === k ? { background: GRAD_NOITE } : {}"
          @click="curKey = k"
        >
          {{ k }}
          <span class="font-normal opacity-80 ml-1">{{ weekdayOf(i).slice(0, 3) }}</span>
          <span v-if="sessionOf(k).rows.some(r => r.name.trim())" class="ml-1">✓</span>
        </button>
        <button
          class="h-9 px-3 rounded-xl text-xs font-bold border border-dashed ml-auto"
          :class="pasteOpen ? 'text-white border-transparent' : 'border-n-weak'"
          :style="pasteOpen ? { background: LARANJA } : { color: LARANJA }"
          @click="pasteOpen = !pasteOpen"
        >
          <span class="i-lucide-clipboard-paste hub-ico" /> Importar (colar lista)
        </button>
      </div>

      <div v-if="pasteOpen" class="rounded-xl border border-dashed p-3 mb-3" :style="{ borderColor: LARANJA }">
        <p class="text-[11px] text-n-slate-11 mb-1">
          Cole o treino como veio (do PDF, do WhatsApp, da planilha): <b>uma linha por exercício</b>, ex.
          <b>Supino reto 3x8-12</b>. Linhas <b>"Treino A"</b>, <b>"Treino B"</b> separam os treinos e importam
          tudo de uma vez. Sem faixa de reps vale 3 × 8–12.
        </p>
        <textarea
          v-model="pasteText"
          rows="6"
          class="w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-xs text-n-slate-12"
          style="margin-bottom: 0"
          placeholder="Treino A — Peito e tríceps&#10;Supino inclinado com halteres 3x6-8&#10;Crucifixo na máquina 3x10-12&#10;Tríceps na polia 3x8-12&#10;Treino B — Costas e bíceps&#10;Puxada frente 4x8-10&#10;…"
        />
        <div class="flex items-center gap-2 mt-2 flex-wrap">
          <button class="h-9 px-4 rounded-lg text-xs font-bold text-white" :style="{ background: GRAD_LARANJA }" @click="applyPaste">
            Importar pro Treino {{ curKey }}
          </button>
          <span class="text-[11px] text-n-slate-10">{{ pasteInfo }}</span>
        </div>
      </div>

      <div class="rounded-xl border border-n-weak p-3">
        <div class="flex items-center gap-2 flex-wrap mb-2">
          <span class="w-9 h-9 rounded-xl flex items-center justify-center text-lg font-black text-white" :style="{ background: GRAD_NOITE }">{{ curKey }}</span>
          <input
            v-model="cur.label"
            type="text"
            placeholder="Grupos deste treino, ex.: Peito e tríceps"
            class="h-9 flex-1 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
            style="min-width: 12rem; margin-bottom: 0"
          />
          <span class="text-[11px] text-n-slate-10">{{ weekdayOf(letters.indexOf(curKey)) }}</span>
        </div>

        <div class="flex flex-col gap-2">
          <div v-for="(row, i) in cur.rows" :key="i" class="hub-wiz-row">
            <input
              v-model="row.name"
              type="text"
              list="hub-wiz-known"
              placeholder="Exercício (ex.: Supino reto com halteres)"
              class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12 hub-wiz-name"
              style="margin-bottom: 0"
            />
            <select v-model="row.method" class="h-9 rounded-lg border border-n-weak bg-n-solid-2 px-1 text-xs text-n-slate-12" style="margin-bottom: 0">
              <option v-for="(lbl, k) in METHOD_LABELS" :key="k" :value="k">{{ lbl }}</option>
            </select>
            <template v-if="row.method === 'sets' || row.method === 'rpt'">
              <span class="hub-wiz-mini">
                <button @click="bump(row, 'count', -1, 1, 10)">−</button><b>{{ row.count }}</b><button @click="bump(row, 'count', 1, 1, 10)">+</button>
                <em>séries</em>
              </span>
              <span class="hub-wiz-mini">
                <button @click="bump(row, 'min', -1, 1, 50)">−</button><b>{{ row.min }}</b><button @click="bump(row, 'min', 1, 1, 50)">+</button>
                <em>a</em>
                <button @click="bump(row, 'max', -1, 1, 50)">−</button><b>{{ row.max }}</b><button @click="bump(row, 'max', 1, 1, 50)">+</button>
                <em>reps</em>
              </span>
            </template>
            <template v-else-if="row.method === 'rest_pause'">
              <span class="hub-wiz-mini">
                <em>ativação</em>
                <button @click="bump(row, 'min', -1, 1, 50)">−</button><b>{{ row.min }}</b><button @click="bump(row, 'min', 1, 1, 50)">+</button>
                <em>a</em>
                <button @click="bump(row, 'max', -1, 1, 50)">−</button><b>{{ row.max }}</b><button @click="bump(row, 'max', 1, 1, 50)">+</button>
                <em>+ 3 minis 4–6</em>
              </span>
            </template>
            <span v-else class="text-[11px] text-n-slate-10">12 / 10 / 8 / 6 · mesma carga</span>
            <input
              v-model="row.rest"
              type="text"
              placeholder="descanso"
              class="h-9 w-24 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-xs text-n-slate-12"
              style="margin-bottom: 0"
            />
            <button class="w-8 h-8 rounded-lg text-n-slate-10 hover:bg-n-alpha-1" title="Remover" @click="removeRow(i)">🗑</button>
          </div>
        </div>
        <button class="mt-2 h-9 px-3 rounded-lg text-xs font-bold border border-dashed border-n-weak" :style="{ color: ROYAL }" @click="addRow">
          + exercício
        </button>
        <datalist id="hub-wiz-known">
          <option v-for="n in knownExercises" :key="n" :value="n" />
        </datalist>
      </div>
    </template>

    <!-- 3 · objetivo = parâmetro de sucesso -->
    <template v-if="step === 3">
      <p class="text-xs font-bold text-n-slate-12 mb-1">Qual é o seu parâmetro de sucesso neste treino?</p>
      <p class="text-[11px] text-n-slate-10 mb-3">É por ele que o painel e o histórico vão dizer se o programa deu certo.</p>
      <div class="grid gap-2 sm:grid-cols-2">
        <button
          v-for="g in GOALS"
          :key="g.key"
          class="hub-wiz-goal text-left"
          :class="form.goal === g.key ? 'is-sel' : ''"
          :style="form.goal === g.key ? { background: GRAD_ROYAL, color: '#fff', borderColor: 'transparent' } : {}"
          @click="form.goal = g.key"
        >
          <span class="hub-sec-ico mb-1" :style="form.goal === g.key ? { background: 'rgba(255,255,255,0.2)', color: '#fff' } : {}"><span :class="g.ico" /></span>
          <span class="block text-sm font-black">{{ g.label }}</span>
          <span class="block text-[11px] opacity-90">{{ g.desc }}</span>
        </button>
      </div>
    </template>

    <!-- 4 · nome + resumo -->
    <template v-if="step === 4">
      <p class="text-xs font-bold text-n-slate-12 mb-1">Dê um nome ao seu treino</p>
      <p class="text-[11px] text-n-slate-10 mb-2">Ele fica registrado no histórico — daqui a anos você vai lembrar deste bloco.</p>
      <input
        v-model="form.name"
        type="text"
        maxlength="80"
        placeholder="ex.: Greek God · bloco 1"
        class="h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 text-sm font-bold text-n-slate-12 mb-2"
      />
      <input
        v-model="form.note"
        type="text"
        maxlength="200"
        placeholder="observação (opcional): de onde veio, o que quero provar…"
        class="h-9 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 text-xs text-n-slate-12 mb-3"
      />
      <div class="rounded-xl p-3 text-white" :style="{ background: GRAD_NOITE }">
        <p class="text-sm font-black mb-1">{{ form.name || 'Meu treino' }}</p>
        <p class="text-[11px] opacity-90">
          {{ letters.join('') }} · {{ weekdaysOrdered.map(d => d.slice(0, 3)).join(', ') }} · {{ form.weeks }} semanas
          a partir de {{ form.start_date.split('-').reverse().slice(0, 2).join('/') }} · {{ totalExercises }} exercícios
        </p>
        <p class="text-[11px] mt-1 flex items-center gap-1.5"><span :class="goalSel.ico" style="width: 13px; height: 13px" /><b>{{ goalSel.label }}</b> — {{ goalSel.short }}</p>
      </div>
    </template>

    <p v-if="stepError" class="text-[11px] mt-3" :style="{ color: LARANJA }">{{ stepError }}</p>
    <div class="flex items-center justify-between gap-2 mt-3">
      <button
        class="h-10 px-4 rounded-xl text-xs font-bold text-n-slate-11 border border-n-weak hover:bg-n-alpha-1 disabled:opacity-40"
        :disabled="step === 1"
        @click="back"
      >
        ← Voltar
      </button>
      <button
        v-if="step < 4"
        class="h-10 px-5 rounded-xl text-xs font-bold text-white disabled:opacity-50"
        :style="{ background: GRAD_ROYAL }"
        :disabled="!!stepError"
        @click="next"
      >
        Avançar →
      </button>
      <button
        v-else
        class="h-10 px-5 rounded-xl text-xs font-bold text-white disabled:opacity-50"
        :style="{ background: GRAD_LARANJA }"
        :disabled="!!stepError || saving"
        @click="submit"
      >
        {{ saving ? 'Salvando…' : initial ? '💾 Salvar alterações' : '🚀 Começar este treino' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.hub-wiz-steps {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 6px;
}
.hub-wiz-step {
  display: flex;
  align-items: center;
  gap: 6px;
  height: 36px;
  padding: 0 8px;
  border-radius: 12px;
  border: 1px solid rgba(148, 163, 184, 0.35);
  font-size: 11px;
  color: inherit;
  opacity: 0.55;
  transition: all 0.25s ease;
}
.hub-wiz-step.is-cur,
.hub-wiz-step.is-done {
  color: #fff;
  border-color: transparent;
  opacity: 1;
}
.hub-wiz-step.is-cur {
  box-shadow: 0 6px 18px rgba(255, 138, 0, 0.35);
}
.hub-wiz-step b {
  width: 20px;
  height: 20px;
  border-radius: 50%;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.22);
  font-size: 11px;
  flex-shrink: 0;
}
.hub-wiz-step span {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
@media (max-width: 640px) {
  .hub-wiz-step span {
    display: none;
  }
  .hub-wiz-step {
    justify-content: center;
  }
}
.hub-wiz-bump {
  width: 34px;
  height: 34px;
  border-radius: 10px;
  border: 1px solid rgba(148, 163, 184, 0.4);
  font-weight: 900;
  font-size: 16px;
}
.hub-wiz-bump:hover {
  background: rgba(65, 105, 225, 0.1);
}
.hub-wiz-row {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: wrap;
  padding: 8px;
  border-radius: 12px;
  border: 1px solid rgba(148, 163, 184, 0.3);
}
.hub-wiz-name {
  flex: 1 1 14rem;
  min-width: 12rem;
}
.hub-wiz-mini {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  height: 36px;
  padding: 0 6px;
  border-radius: 10px;
  background: rgba(65, 105, 225, 0.08);
  font-size: 12px;
}
.hub-wiz-mini button {
  width: 24px;
  height: 24px;
  border-radius: 8px;
  font-weight: 900;
  border: 1px solid rgba(148, 163, 184, 0.4);
}
.hub-wiz-mini b {
  min-width: 18px;
  text-align: center;
}
.hub-wiz-mini em {
  font-style: normal;
  font-size: 10px;
  opacity: 0.7;
  margin: 0 2px;
}
.hub-wiz-goal {
  padding: 12px;
  border-radius: 16px;
  border: 1px solid rgba(148, 163, 184, 0.35);
  transition: all 0.2s ease;
}
.hub-wiz-goal:hover {
  transform: translateY(-1px);
}
.hub-wiz-goal.is-sel {
  box-shadow: 0 10px 26px rgba(65, 105, 225, 0.35);
}
</style>
