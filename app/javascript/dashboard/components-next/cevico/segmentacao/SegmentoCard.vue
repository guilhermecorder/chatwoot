<script setup>
// 🧪 item 383: o CARTÃO de um segmento — quem é (teste × escala, situação,
// ritmo), o andamento (barra, fila, próxima leva), os botões (Iniciar,
// Pausar, Mandar a próxima leva agora, Apagar), os resultados por mensagem
// (abrem embaixo), as pessoas e o "Escalar a vencedora".
import { ref, computed } from 'vue';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { frontendURL } from 'dashboard/helper/URLHelper';
import CrmAPI from 'dashboard/api/crm';
import SegmentoResultados from './SegmentoResultados.vue';
import {
  kindMeta, statusMeta, variantColor, memberStatus, fmtInt, fmtPct, fmtPhone, fmtWhen, people, pct, stepSize, paceSentence, variantLabel,
} from './segmentacaoHelpers';

const props = defineProps({
  seg: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
  accountId: { type: [Number, String], required: true },
});
const emit = defineEmits(['changed', 'escalado']);

const router = useRouter();
const busy = ref('');
const confirming = ref(''); // 'start' | 'tick' | 'delete' | 'escalar'
const typed = ref('');
const tickLimit = ref(0);
const showResults = ref(false);
const showPeople = ref(false);
const resultsKey = ref(0);
const results = ref(null);
const members = ref(null);
const membersLoading = ref(false);
const escalaVariant = ref('');
const escalaSize = ref(0);

const kind = computed(() => kindMeta(props.seg.kind));
const status = computed(() => statusMeta(props.seg.status));
const total = computed(() => Number(props.seg.total || 0));
const sent = computed(() => Number(props.seg.sent || 0));
const progress = computed(() => pct(sent.value, total.value));
const proj = computed(() => props.seg.projection || {});
const pace = computed(() => props.seg.pace || {});
const step = computed(() => stepSize(pace.value));
const byVariant = computed(() => props.seg.stats?.by_variant || {});
const warnings = computed(() => (props.seg.stats?.warnings || []).filter(Boolean));
const lastSkip = computed(() => props.seg.stats?.last_skip || '');
const isTest = computed(() => props.seg.kind === 'teste');
const canStart = computed(() => props.canEdit && ['reservado', 'pausado'].includes(props.seg.status));
const canPause = computed(() => props.canEdit && props.seg.status === 'enviando');
const canTick = computed(() => props.canEdit && ['enviando', 'pausado'].includes(props.seg.status) && Number(props.seg.reserved) > 0);
const canDelete = computed(() => props.canEdit && props.seg.status === 'reservado' && sent.value === 0);
const canEscalar = computed(() => props.canEdit && isTest.value && sent.value > 0);
const typedOk = computed(() => typed.value.trim().toUpperCase() === 'ENVIAR');
const winnerKey = computed(() => results.value?.winner || null);

const open = async which => {
  confirming.value = which;
  typed.value = '';
  if (which === 'tick') tickLimit.value = Math.min(step.value, Number(props.seg.reserved || 0)) || step.value;
  if (which === 'escalar') {
    escalaSize.value = 1000; // "de mil em mil"
    if (!results.value) {
      try {
        const { data } = await CrmAPI.getSegmentResults(props.seg.id);
        results.value = data;
      } catch {
        results.value = null;
      }
    }
    escalaVariant.value = winnerKey.value || props.seg.variants?.[0]?.key || 'A';
  }
};
const close = () => {
  confirming.value = '';
  typed.value = '';
};
const fail = (err, fallback) => useAlert(err?.response?.data?.error || fallback);
const run = async (key, fn, okMsg) => {
  busy.value = key;
  try {
    const { data } = await fn();
    if (okMsg) useAlert(typeof okMsg === 'function' ? okMsg(data) : okMsg);
    close();
    emit('changed', data);
    resultsKey.value += 1;
    return data;
  } catch (err) {
    fail(err, 'Não deu certo. Tente de novo.');
    return null;
  } finally {
    busy.value = '';
  }
};
const start = () => run('start', () => CrmAPI.startSegment(props.seg.id), 'Segmento iniciado: a primeira leva sai dentro do horário (ou use “Mandar a próxima leva agora”).');
const pause = () => run('pause', () => CrmAPI.pauseSegment(props.seg.id), 'Segmento pausado.');
// a leva manual sai pelo robô (fora da tela): avisa, e recarrega o cartão em seguida
const tick = async () => {
  const data = await run('tick', () => CrmAPI.tickSegmentNow(props.seg.id, Number(tickLimit.value) || undefined), d =>
    `Leva de até ${people(d.queued || 0)} a caminho: sai nos próximos segundos (veja o cartão).`
  );
  if (data) setTimeout(() => emit('changed', null), 8000);
};
const remove = async () => {
  busy.value = 'delete';
  try {
    await CrmAPI.deleteSegment(props.seg.id);
    useAlert('Segmento apagado: as pessoas voltaram para a base.');
    close();
    emit('changed', null);
  } catch (err) {
    fail(err, 'Não deu para apagar.');
  } finally {
    busy.value = '';
  }
};
const escalar = async () => {
  busy.value = 'escalar';
  try {
    const { data } = await CrmAPI.escalarSegment(props.seg.id, { variant: escalaVariant.value, size: Number(escalaSize.value) || 0 });
    useAlert(`Lote de escala reservado com ${people(data.reserved)} — “${data.name}”. Inicie quando quiser.`);
    close();
    emit('escalado', data);
  } catch (err) {
    fail(err, 'Não deu para escalar.');
  } finally {
    busy.value = '';
  }
};

const toggleResults = () => {
  showResults.value = !showResults.value;
};
const loadPeople = async () => {
  showPeople.value = !showPeople.value;
  if (!showPeople.value || members.value) return;
  membersLoading.value = true;
  try {
    const { data } = await CrmAPI.getSegmentMembers(props.seg.id, { page: 1 });
    members.value = data;
  } catch (err) {
    fail(err, 'Não deu para listar as pessoas.');
  } finally {
    membersLoading.value = false;
  }
};
const openConversation = id => {
  if (id) router.push(frontendURL(`accounts/${props.accountId}/conversations/${id}`));
};
</script>

<template>
  <article class="seg-card" :class="`seg-card-${seg.status}`">
    <!-- cabeçalho -->
    <div class="flex items-start gap-3 flex-wrap">
      <span class="cv-icon flex-shrink-0" :class="kind.tone"><span :class="kind.icon" class="text-base" /></span>
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2 flex-wrap">
          <h3 class="text-base font-bold text-n-slate-12 leading-tight">{{ seg.name }}</h3>
          <span class="cv-chip" :class="kind.tone"><span :class="kind.icon" class="text-xs" />{{ kind.short }}</span>
          <span class="cv-chip" :class="status.tone" :title="status.hint"><span :class="status.icon" class="text-xs" />{{ status.label }}</span>
          <span v-if="seg.parent_id" class="cv-chip" title="Nasceu de um teste">de um teste</span>
        </div>
        <p class="text-[11px] text-n-slate-10 mt-1">
          criado {{ fmtWhen(seg.created_at) }}<template v-if="seg.creator"> por {{ seg.creator }}</template>
          <template v-if="seg.started_at"> · iniciado {{ fmtWhen(seg.started_at) }}</template>
          <template v-if="seg.finished_at"> · concluído {{ fmtWhen(seg.finished_at) }}</template>
        </p>
      </div>
      <div class="text-right flex-shrink-0">
        <b class="block text-xl font-extrabold tabular-nums text-n-slate-12">{{ fmtInt(sent) }}<span class="text-sm font-semibold text-n-slate-10"> / {{ fmtInt(total) }}</span></b>
        <span class="text-[10px] text-n-slate-10">enviadas</span>
      </div>
    </div>

    <!-- barra + mensagens -->
    <div class="seg-bar mt-3"><span :style="{ width: `${progress}%` }" /></div>
    <div class="flex flex-wrap items-center gap-2 mt-3">
      <span v-for="v in seg.variants" :key="v.key" class="seg-variant" :style="{ '--vc': variantColor(v.key) }" :title="v.template">
        <span class="seg-key">{{ v.key }}</span>
        {{ v.label }} <span class="opacity-70 tabular-nums">· {{ fmtInt(byVariant[v.key]) }}</span>
        <span v-if="winnerKey === v.key">🏆</span>
      </span>
    </div>

    <!-- números -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-2 mt-4">
      <div class="seg-num"><b>{{ fmtInt(seg.reserved) }}</b><span>na fila</span></div>
      <div class="seg-num"><b>{{ fmtInt(step) }}</b><span>por leva</span></div>
      <div class="seg-num"><b>{{ proj.days_left ? `${proj.days_left}d` : '—' }}</b><span>para acabar</span></div>
      <div class="seg-num"><b class="!text-sm">{{ proj.next_at ? fmtWhen(proj.next_at) : (seg.status === 'enviando' ? 'agora' : '—') }}</b><span>próxima leva</span></div>
    </div>
    <p class="text-[11px] text-n-slate-10 mt-2">
      <span class="i-lucide-timer text-xs" /> {{ paceSentence(pace) }}
      <template v-if="seg.status === 'enviando'"> · {{ proj.window_now }}</template>
    </p>
    <p v-if="lastSkip && seg.status !== 'concluido'" class="seg-note seg-note-amber mt-2"><span class="i-lucide-info text-sm flex-shrink-0" />Última checagem: {{ lastSkip }}.</p>
    <p v-for="w in warnings.slice(0, 3)" :key="w" class="seg-note seg-note-amber mt-1"><span class="i-lucide-triangle-alert text-sm flex-shrink-0" />{{ w }}</p>
    <p v-if="seg.failed" class="seg-note seg-note-red mt-2"><span class="i-lucide-x-circle text-sm flex-shrink-0" />{{ people(seg.failed) }} falharam (a Meta recusou ou o número não existe).</p>

    <!-- ações -->
    <div class="flex flex-wrap items-center gap-2 mt-4">
      <template v-if="confirming === 'start'">
        <span class="text-xs text-n-slate-11">O robô vai mandar {{ fmtInt(step) }} por leva dentro do horário. Começar?</span>
        <button class="cv-btn cv-btn-sm" :disabled="busy !== ''" @click="start"><span class="i-lucide-play text-sm" />{{ busy === 'start' ? 'Iniciando…' : 'Sim, iniciar' }}</button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="close">Voltar</button>
      </template>
      <template v-else-if="confirming === 'tick'">
        <label class="flex items-center gap-2 text-xs text-n-slate-11">
          Mandar agora
          <input v-model.number="tickLimit" type="number" min="1" :max="seg.reserved" class="cv-input !h-8 w-20 text-right" />
          pessoas (ignora o horário; o teto do dia vale; sai pelo robô em segundos). Digite ENVIAR:
        </label>
        <input v-model="typed" class="cv-input !h-8 w-28 font-mono uppercase" placeholder="ENVIAR" />
        <button class="cv-btn cv-btn-sm" :disabled="!typedOk || busy !== ''" @click="tick"><span class="i-lucide-send text-sm" />{{ busy === 'tick' ? 'Enviando…' : 'Enviar agora' }}</button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="close">Voltar</button>
      </template>
      <template v-else-if="confirming === 'delete'">
        <span class="text-xs text-n-slate-11">Apagar este segmento? As {{ people(seg.reserved) }} voltam para a base.</span>
        <button class="cv-btn cv-btn-sm cv-btn-danger" :disabled="busy !== ''" @click="remove"><span class="i-lucide-trash-2 text-sm" />{{ busy === 'delete' ? 'Apagando…' : 'Sim, apagar' }}</button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="close">Voltar</button>
      </template>
      <template v-else-if="confirming === 'escalar'">
        <div class="seg-escalar w-full">
          <p class="text-sm font-bold text-n-slate-12 mb-2">🏆 Escalar a vencedora</p>
          <p class="text-xs text-n-slate-11 mb-3">
            Um lote novo (escala) com a MESMA peneira deste teste, só com a mensagem escolhida, para quem ainda não recebeu. O lote nasce reservado: você inicia quando quiser, no ritmo que quiser.
          </p>
          <div class="flex flex-wrap items-center gap-3">
            <label class="flex items-center gap-2 text-xs text-n-slate-11">
              Mensagem
              <select v-model="escalaVariant" class="cv-input !h-8">
                <option v-for="v in seg.variants" :key="v.key" :value="v.key">{{ v.label }}{{ winnerKey === v.key ? ' 🏆' : '' }}</option>
              </select>
            </label>
            <label class="flex items-center gap-2 text-xs text-n-slate-11">
              Quantas pessoas
              <input v-model.number="escalaSize" type="number" min="0" max="50000" class="cv-input !h-8 w-24 text-right" />
              <span class="text-n-slate-10">(0 = todas que podem)</span>
            </label>
            <button class="cv-btn cv-btn-sm" :disabled="busy !== ''" @click="escalar"><span class="i-lucide-rocket text-sm" />{{ busy === 'escalar' ? 'Reservando…' : 'Reservar lote de escala' }}</button>
            <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="close">Voltar</button>
          </div>
        </div>
      </template>
      <template v-else>
        <button v-if="canStart" class="cv-btn cv-btn-sm" @click="open('start')"><span class="i-lucide-play text-sm" />{{ seg.status === 'pausado' ? 'Retomar' : 'Iniciar' }}</button>
        <button v-if="canPause" class="cv-btn cv-btn-sm cv-btn-ghost" :disabled="busy !== ''" @click="pause"><span class="i-lucide-pause text-sm" />{{ busy === 'pause' ? 'Pausando…' : 'Pausar' }}</button>
        <button v-if="canTick" class="cv-btn cv-btn-sm cv-btn-ghost" @click="open('tick')"><span class="i-lucide-send text-sm" />Mandar a próxima leva agora</button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="toggleResults"><span class="i-lucide-bar-chart-2 text-sm" />{{ showResults ? 'Fechar resultados' : 'Resultados' }}</button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="loadPeople"><span class="i-lucide-users text-sm" />{{ showPeople ? 'Fechar pessoas' : 'Pessoas' }}</button>
        <button v-if="canEscalar" class="cv-btn cv-btn-sm cv-btn-ghost" @click="open('escalar')"><span class="i-lucide-rocket text-sm" />Escalar a vencedora</button>
        <div class="flex-1" />
        <button v-if="canDelete" class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger" title="Só enquanto nada saiu" @click="open('delete')"><span class="i-lucide-trash-2 text-sm" />Apagar</button>
      </template>
    </div>

    <!-- resultados -->
    <div v-if="showResults" class="seg-panel mt-4">
      <SegmentoResultados :segment-id="seg.id" :refresh-key="resultsKey" @loaded="results = $event" />
    </div>

    <!-- pessoas -->
    <div v-if="showPeople" class="seg-panel mt-4">
      <p v-if="membersLoading" class="text-xs text-n-slate-10">Listando…</p>
      <template v-else-if="members">
        <p class="text-[11px] text-n-slate-10 mb-2">{{ people(members.total) }} neste segmento<template v-if="members.total > 500"> · mostrando as 500 primeiras</template>.</p>
        <div class="overflow-x-auto -mx-1 px-1 max-h-80 overflow-y-auto">
          <table class="w-full text-xs seg-tabela">
            <thead>
              <tr class="text-left">
                <th class="py-2 pr-3 cv-label">Nome</th>
                <th class="py-2 pr-3 cv-label">Telefone</th>
                <th class="py-2 pr-3 cv-label">Mensagem</th>
                <th class="py-2 pr-3 cv-label">Situação</th>
                <th class="py-2 cv-label">Quando</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="m in members.rows" :key="m.id" class="border-t text-n-slate-12">
                <td class="py-1.5 pr-3 font-medium whitespace-nowrap">{{ m.name }}</td>
                <td class="py-1.5 pr-3 tabular-nums whitespace-nowrap text-n-slate-11">{{ fmtPhone(m.phone) }}</td>
                <td class="py-1.5 pr-3 whitespace-nowrap"><span class="seg-key" :style="{ background: variantColor(m.variant) }">{{ m.variant }}</span> {{ variantLabel(seg.variants, m.variant) }}</td>
                <td class="py-1.5 pr-3 whitespace-nowrap"><span class="cv-chip" :class="memberStatus(m.status).tone">{{ memberStatus(m.status).label }}</span></td>
                <td class="py-1.5 whitespace-nowrap text-n-slate-11">
                  {{ m.sent_at ? fmtWhen(m.sent_at) : '—' }}
                  <button v-if="m.conversation_id" class="ml-2 underline text-n-slate-10 hover:text-n-slate-12" @click="openConversation(m.conversation_id)">abrir conversa</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>
  </article>
</template>

<style scoped>
.seg-card {
  padding: 18px 20px;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.55);
  border: 1px solid rgb(var(--cv-rgb) / 0.18);
}
.dark .seg-card {
  background: rgba(255, 255, 255, 0.03);
}
.seg-card-enviando {
  border-color: rgba(5, 150, 105, 0.45);
}
.seg-bar {
  height: 8px;
  border-radius: 9999px;
  background: rgb(var(--cv-rgb) / 0.14);
  overflow: hidden;
}
.seg-bar > span {
  display: block;
  height: 100%;
  border-radius: 9999px;
  background: var(--cv-grad);
  transition: width 0.4s ease;
}
.seg-variant {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 3px 10px 3px 4px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 600;
  color: var(--vc);
  background: color-mix(in srgb, var(--vc) 12%, transparent);
  border: 1px solid color-mix(in srgb, var(--vc) 35%, transparent);
}
.seg-key {
  width: 20px;
  height: 20px;
  border-radius: 7px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  font-weight: 800;
  color: #fff;
  background: var(--vc, #64748b);
  flex-shrink: 0;
}
.seg-num {
  padding: 8px 10px;
  border-radius: 12px;
  background: rgb(var(--cv-rgb) / 0.08);
  border: 1px solid rgb(var(--cv-rgb) / 0.16);
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.seg-num b {
  font-size: 16px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  line-height: 1.15;
  white-space: nowrap;
}
.seg-num span {
  font-size: 10px;
  opacity: 0.7;
}
.seg-note {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  padding: 6px 10px;
  border-radius: 10px;
  font-size: 11px;
  line-height: 1.4;
}
.seg-note-amber {
  color: #92400e;
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.35);
}
.seg-note-red {
  color: #991b1b;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.35);
}
.dark .seg-note-amber {
  color: #fcd34d;
}
.dark .seg-note-red {
  color: #fca5a5;
}
.seg-panel {
  padding: 14px 16px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.5);
  border: 1px solid rgb(var(--cv-rgb) / 0.14);
}
.dark .seg-panel {
  background: rgba(255, 255, 255, 0.03);
}
.seg-escalar {
  padding: 14px 16px;
  border-radius: 14px;
  background: rgba(212, 175, 55, 0.1);
  border: 1px solid rgba(212, 175, 55, 0.4);
}
.seg-tabela tbody tr {
  border-color: rgb(var(--cv-rgb) / 0.18);
}
</style>
