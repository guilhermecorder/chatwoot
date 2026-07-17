<script setup>
// ESPAÇO DE VIDA (privado da pessoa): Roda da Vida com histórico e
// comparação, objetivos por horizonte (20 anos → agora) e a ficha
// estratégica de hábitos/crenças — técnicas de coaching e planejamento
// de vida pra construir, analisar, registrar e dar o salto.
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import LifeWheel from './LifeWheel.vue';
import { WHEEL_AREAS, HORIZONS, HABIT_QUESTIONS, HABIT_PRICES } from './discQuiz';

const props = defineProps({
  person: { type: Object, required: true },
});

const life = computed(() => props.person.life || {});

const SUBTABS = [
  { key: 'roda', label: 'Roda da Vida', icon: 'i-lucide-loader-pinwheel' },
  { key: 'horizontes', label: 'Objetivos de vida', icon: 'i-lucide-telescope' },
  { key: 'habitos', label: 'Hábitos & crenças', icon: 'i-lucide-refresh-ccw-dot' },
];
const sub = ref('roda');

// ── Roda da Vida ──
const wheelHistory = computed(() => life.value.wheel_history || []);
const latestWheel = computed(() => wheelHistory.value[wheelHistory.value.length - 1] || null);
const previousWheel = computed(() =>
  wheelHistory.value.length > 1 ? wheelHistory.value[wheelHistory.value.length - 2] : null
);
const assessing = ref(false);
const draftWheel = ref({});
const draftNote = ref('');
const startAssessment = () => {
  draftWheel.value = WHEEL_AREAS.reduce((acc, a) => {
    acc[a.key] = latestWheel.value?.scores?.[a.key] ?? 5;
    return acc;
  }, {});
  draftNote.value = '';
  assessing.value = true;
};
const savingWheel = ref(false);
const saveWheel = async () => {
  savingWheel.value = true;
  try {
    const { data } = await CrmAPI.saveLife({ wheel: draftWheel.value, wheel_note: draftNote.value });
    props.person.life = data.life;
    assessing.value = false;
    useAlert('Roda registrada! Compare com a anterior e planeje o salto. 🚀');
  } catch {
    useAlert('Não consegui salvar a avaliação.');
  } finally {
    savingWheel.value = false;
  }
};
const avgOf = entry => {
  const vals = WHEEL_AREAS.map(a => Number(entry?.scores?.[a.key]) || 0);
  return Math.round((vals.reduce((s, v) => s + v, 0) / WHEEL_AREAS.length) * 10) / 10;
};
const fmtAt = iso => new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });

// ── Objetivos por horizonte ──
const horizons = ref({ ...(life.value.horizons || {}) });
const savingHorizons = ref(false);
const saveHorizons = async () => {
  savingHorizons.value = true;
  try {
    const { data } = await CrmAPI.saveLife({ horizons: horizons.value });
    props.person.life = data.life;
  } catch {
    useAlert('Não consegui salvar os objetivos.');
  } finally {
    savingHorizons.value = false;
  }
};

// ── Hábitos & crenças ──
const habits = ref((life.value.habits || []).map(h => ({ ...h })));
const expandedHabit = ref(null);
const newHabit = ref({ name: '', kind: 'habito' });
const saveHabits = async () => {
  try {
    const { data } = await CrmAPI.saveLife({ habits: habits.value });
    props.person.life = data.life;
  } catch {
    useAlert('Não consegui salvar.');
  }
};
const addHabit = async () => {
  if (!newHabit.value.name.trim()) return;
  habits.value.push({
    id: `${Date.now()}`,
    name: newHabit.value.name.trim(),
    kind: newHabit.value.kind,
    status: 'ativo',
    answers: {},
    prices: { price_physical: 5, price_emotional: 5, price_financial: 5, price_relational: 5 },
  });
  newHabit.value.name = '';
  expandedHabit.value = habits.value[habits.value.length - 1].id;
  await saveHabits();
};
const removeHabit = async habit => {
  if (!window.confirm(`Excluir a ficha "${habit.name}"?`)) return;
  habits.value = habits.value.filter(h => h.id !== habit.id);
  await saveHabits();
};
const priceColor = v => (v >= 7 ? '#DC2626' : v >= 4 ? '#B45309' : '#047857');
</script>

<template>
  <div>
    <!-- aviso de privacidade + sub-abas -->
    <div class="flex items-center gap-2 flex-wrap mb-4">
      <div class="flex items-center bg-n-solid-1 border border-n-weak rounded-xl p-0.5 gap-0.5">
        <button
          v-for="t in SUBTABS"
          :key="t.key"
          class="px-3 h-8 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex items-center gap-1.5"
          :class="sub === t.key ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="sub === t.key ? { background: 'linear-gradient(135deg, #0F766E, #2DD4BF)' } : {}"
          @click="sub = t.key"
        >
          <span :class="t.icon" class="text-sm" />
          {{ t.label }}
        </button>
      </div>
      <span class="text-[10px] text-n-slate-9 flex items-center gap-1 ml-auto">
        <span class="i-lucide-lock text-[10px]" /> só você vê este espaço
      </span>
    </div>

    <!-- ═══ RODA DA VIDA ═══ -->
    <template v-if="sub === 'roda'">
      <!-- avaliação nova -->
      <div v-if="assessing" class="max-w-2xl mx-auto">
        <p class="text-sm font-bold text-n-slate-12 mb-1">Como está cada área da sua vida HOJE?</p>
        <p class="text-[11px] text-n-slate-10 mb-4">0 = abandonada · 10 = exatamente como deveria ser. Responda com o coração, não com a agenda.</p>
        <div v-for="area in WHEEL_AREAS" :key="area.key" class="rounded-xl border border-n-weak bg-n-solid-1 p-3 mb-2">
          <div class="flex items-center gap-2 mb-1">
            <span class="w-2.5 h-2.5 rounded-full" :style="{ background: area.color }" />
            <p class="text-xs font-bold text-n-slate-12 flex-1">{{ area.label }}</p>
            <span class="text-base font-black" :style="{ color: area.color }">{{ draftWheel[area.key] }}</span>
          </div>
          <p class="text-[10px] text-n-slate-9 italic mb-1.5">{{ area.ask }}</p>
          <input
            v-model.number="draftWheel[area.key]"
            type="range"
            min="0"
            max="10"
            step="1"
            class="w-full"
            :style="{ accentColor: area.color }"
          />
        </div>
        <textarea
          v-model="draftNote"
          rows="2"
          placeholder="O momento de vida (opcional): o que está acontecendo, o que essa foto significa…"
          class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 resize-y mb-2"
        />
        <div class="flex items-center justify-end gap-2">
          <button class="px-3 h-9 rounded-lg text-xs text-n-slate-10 hover:bg-n-alpha-1" @click="assessing = false">Cancelar</button>
          <button
            class="px-4 h-9 rounded-xl text-xs font-bold text-white disabled:opacity-60"
            style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
            :disabled="savingWheel"
            @click="saveWheel"
          >
            Registrar minha Roda
          </button>
        </div>
      </div>

      <!-- roda atual + histórico -->
      <template v-else>
        <div v-if="latestWheel" class="grid grid-cols-1 lg:grid-cols-[1fr,240px] gap-4 items-start">
          <div class="rounded-2xl border border-n-weak bg-n-solid-1 p-4">
            <LifeWheel :scores="latestWheel.scores" :previous="previousWheel?.scores || null" />
            <p v-if="previousWheel" class="text-[10px] text-n-slate-9 text-center mt-1">
              a linha escura é a avaliação anterior ({{ fmtAt(previousWheel.at) }}) — a evolução é visível
            </p>
          </div>
          <div>
            <button
              class="w-full px-4 h-10 rounded-xl text-xs font-bold text-white mb-3"
              style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
              @click="startAssessment"
            >
              Nova avaliação
            </button>
            <p class="text-[10px] font-semibold text-n-slate-9 uppercase tracking-wide mb-1.5">Histórico (momentos da vida)</p>
            <div v-for="(entry, ei) in [...wheelHistory].reverse()" :key="ei" class="rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 mb-1.5">
              <div class="flex items-center gap-2">
                <span class="text-xs font-bold text-n-slate-12">{{ fmtAt(entry.at) }}</span>
                <span class="text-[10px] px-1.5 py-0.5 rounded-full font-bold ml-auto" style="background: rgba(20,184,166,0.12); color: #0F766E">
                  média {{ avgOf(entry) }}
                </span>
              </div>
              <p v-if="entry.note" class="text-[11px] text-n-slate-10 italic mt-0.5">{{ entry.note }}</p>
            </div>
          </div>
        </div>
        <div v-else class="text-center py-10">
          <p class="text-sm font-semibold text-n-slate-12 mb-1">Tire a primeira foto da sua vida</p>
          <p class="text-xs text-n-slate-10 max-w-md mx-auto mb-4">
            A Roda da Vida mostra, numa imagem só, onde a vida está redonda e onde está capenga.
            Avalie as 8 áreas, registre o momento — e daqui a alguns meses compare a evolução.
          </p>
          <button
            class="px-5 h-10 rounded-xl text-sm font-bold text-white shadow-md"
            style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
            @click="startAssessment"
          >
            Avaliar minha Roda da Vida →
          </button>
        </div>
      </template>
    </template>

    <!-- ═══ OBJETIVOS POR HORIZONTE ═══ -->
    <template v-else-if="sub === 'horizontes'">
      <p class="text-[11px] text-n-slate-10 mb-3">
        do sonho de 20 anos até o AGORA — cada horizonte puxa o de baixo. Escreva livre (um objetivo por linha) e salve.
      </p>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div v-for="h in HORIZONS" :key="h.key" class="rounded-xl border border-n-weak bg-n-solid-1 p-3">
          <p class="text-xs font-black text-n-slate-12 mb-1.5 flex items-center gap-1.5">
            <span class="i-lucide-telescope text-sm" style="color: #0F766E" />
            {{ h.label }}
          </p>
          <textarea
            v-model="horizons[h.key]"
            :rows="['h20', 'h10', 'h5'].includes(h.key) ? 3 : 2"
            :placeholder="h.key === 'now' ? 'O que você faz AGORA que te aproxima de tudo isso?' : `Onde você quer estar em ${h.label.toLowerCase()}?`"
            class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1.5 text-xs text-n-slate-12 resize-y"
          />
        </div>
      </div>
      <div class="flex justify-end mt-3">
        <button
          class="px-4 h-9 rounded-xl text-xs font-bold text-white disabled:opacity-60"
          style="background: linear-gradient(135deg, #0F766E, #2DD4BF)"
          :disabled="savingHorizons"
          @click="saveHorizons"
        >
          {{ savingHorizons ? 'Salvando…' : 'Salvar objetivos' }}
        </button>
      </div>
    </template>

    <!-- ═══ HÁBITOS & CRENÇAS ═══ -->
    <template v-else>
      <p class="text-[11px] text-n-slate-10 mb-3">
        fiche o hábito ou a crença que você quer mudar: as perguntas estratégicas tiram a autoridade dele,
        e o PREÇO que você paga (nas 4 áreas) mostra suas forças e fraquezas.
      </p>
      <div v-for="habit in habits" :key="habit.id" class="rounded-xl border border-n-weak bg-n-solid-1 mb-2 overflow-hidden">
        <div class="flex items-center gap-2 px-3 py-2.5 cursor-pointer hover:bg-n-alpha-1" @click="expandedHabit = expandedHabit === habit.id ? null : habit.id">
          <span :class="habit.kind === 'crenca' ? 'i-lucide-brain' : 'i-lucide-refresh-ccw-dot'" class="text-sm" style="color: #B45309" />
          <p class="text-xs font-bold text-n-slate-12 flex-1">{{ habit.name }}</p>
          <span class="text-[10px] px-1.5 py-0.5 rounded-full font-semibold" :style="habit.status === 'vencido' ? 'background: rgba(16,185,129,0.14); color:#047857' : 'background: rgba(245,158,11,0.14); color:#B45309'">
            {{ habit.status === 'vencido' ? 'vencido 🏆' : 'em batalha' }}
          </span>
          <!-- mini-barras do preço pago -->
          <span class="flex items-end gap-[2px] h-4">
            <span
              v-for="p in HABIT_PRICES"
              :key="p.key"
              class="w-1 rounded-t-sm"
              :style="{ height: `${Math.max(((habit.prices?.[p.key] || 0) / 10) * 100, 12)}%`, background: priceColor(habit.prices?.[p.key] || 0) }"
            />
          </span>
        </div>
        <div v-if="expandedHabit === habit.id" class="px-3 pb-3 pt-1 border-t border-n-weak space-y-2.5">
          <label v-for="q in HABIT_QUESTIONS" :key="q.key" class="block">
            <span class="text-[10px] font-semibold text-n-slate-10">{{ q.label }}</span>
            <textarea
              v-model="habit.answers[q.key]"
              rows="2"
              class="mt-0.5 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1.5 text-xs text-n-slate-12 resize-y"
              @change="saveHabits"
            />
          </label>
          <p class="text-[10px] font-semibold text-n-slate-10">Qual o preço que você está pagando? (0 = nenhum · 10 = altíssimo)</p>
          <div v-for="p in HABIT_PRICES" :key="p.key" class="flex items-center gap-2">
            <span class="text-[11px] text-n-slate-11 w-44 flex-shrink-0">{{ p.label }}</span>
            <input
              v-model.number="habit.prices[p.key]"
              type="range"
              min="0"
              max="10"
              class="flex-1"
              :style="{ accentColor: priceColor(habit.prices[p.key] || 0) }"
              @change="saveHabits"
            />
            <b class="text-xs w-6 text-right" :style="{ color: priceColor(habit.prices[p.key] || 0) }">{{ habit.prices[p.key] || 0 }}</b>
          </div>
          <div class="flex items-center gap-2 pt-1">
            <button
              class="text-[11px] font-bold px-2.5 py-1 rounded-full"
              :style="habit.status === 'vencido' ? 'background: rgba(245,158,11,0.14); color:#B45309' : 'background: rgba(16,185,129,0.14); color:#047857'"
              @click="habit.status = habit.status === 'vencido' ? 'ativo' : 'vencido'; saveHabits()"
            >
              {{ habit.status === 'vencido' ? 'Voltou à batalha' : 'Marcar como VENCIDO 🏆' }}
            </button>
            <button class="ml-auto text-[11px] text-red-500 hover:text-red-600" @click="removeHabit(habit)">excluir ficha</button>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-1.5 mt-3">
        <select v-model="newHabit.kind" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-1.5 text-[11px] text-n-slate-12" style="width: 6.5rem">
          <option value="habito">Hábito</option>
          <option value="crenca">Crença</option>
        </select>
        <input
          v-model="newHabit.name"
          type="text"
          placeholder="O que você quer vencer? (ex.: procrastinar decisões difíceis)"
          class="flex-1 min-w-0 h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
          @keyup.enter="addHabit"
        />
        <button
          class="px-3 h-8 rounded-lg text-[11px] font-bold text-white disabled:opacity-50"
          style="background: linear-gradient(135deg, #B45309, #F59E0B)"
          :disabled="!newHabit.name.trim()"
          @click="addHabit"
        >
          Fichar
        </button>
      </div>
    </template>
  </div>
</template>
