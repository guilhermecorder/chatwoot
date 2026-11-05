<script setup>
// 🎓 MOTOR DE EDUCAÇÃO (item 389): todo dia de manhã lê as conversas de
// ontem, compara quem agendou com quem não agendou e sugere aprendizados.
// O admin aprova com um toque (foto antes, Histórico abaixo); os aprovados
// valem SÓ nas caixas marcadas "Com o motor", no Atendente de Agendamento. O placar compara a
// piloto com a caixa de comparação, antes e depois dos aprendizados.
// Vive na aba Agentes de IA, logo abaixo das Orientações.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  canEdit: { type: Boolean, default: true },
});

const { accountId } = useAccount();

const data = ref(null);
const isLoading = ref(false);
const loadError = ref('');
const saving = ref(false);
const busyId = ref(null);
const running = ref(false);
const expanded = ref(true);
const openExample = ref({});
const editingRules = ref(false);
const rulesDraft = ref('');
const showHistory = ref(false);
let pollTimer = null;

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const res = await CrmAPI.educationEngine();
    data.value = res.data;
  } catch {
    loadError.value =
      'Não consegui carregar o motor — o servidor não respondeu. Tente atualizar.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
onBeforeUnmount(() => clearInterval(pollTimer));

const inboxes = computed(() => data.value?.inboxes || []);
const inboxName = id =>
  inboxes.value.find(i => i.id === id)?.name || `Caixa ${id}`;
// cada caixa: roteiro normal, com o motor (piloto) ou comparação — ele escolhe
const pilotIds = computed(() => data.value?.pilot_inbox_ids || []);
const controlIds = computed(() => data.value?.control_inbox_ids || []);
const groupName = ids =>
  ids.length ? ids.map(id => inboxName(id)).join(' + ') : 'nenhuma escolhida';
const MODES = [
  { key: 'normal', label: 'Roteiro normal' },
  { key: 'motor', label: 'Com o motor' },
  { key: 'compare', label: 'Comparação' },
];
const modeOf = id => {
  if (pilotIds.value.includes(id)) return 'motor';
  if (controlIds.value.includes(id)) return 'compare';
  return 'normal';
};
const ruleLines = computed(() =>
  (data.value?.rules || '')
    .split('\n')
    .map(l => l.replace(/^-\s*/, '').trim())
    .filter(Boolean)
);
const pending = computed(() => data.value?.pending || []);
const lastDay = computed(() => data.value?.days?.[0] || null);
const board = computed(() => data.value?.scoreboard || null);

const rate = part =>
  part && part.n ? Math.round((1000 * part.booked) / part.n) / 10 : null;
const fmtRate = part => (rate(part) === null ? '—' : `${rate(part)}%`);
const fmtDay = iso =>
  iso
    ? new Date(`${iso}T12:00:00`).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';
const fmtWhen = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';

const DAY_STATUS = {
  ok: 'lido',
  'sem conversas': 'sem conversas',
  erro: 'deu erro',
};

const save = async patch => {
  saving.value = true;
  try {
    const res = await CrmAPI.updateEducationEngine(patch);
    data.value = res.data;
  } catch {
    useAlert('Não consegui salvar o motor.');
  } finally {
    saving.value = false;
  }
};
const toggle = () => {
  if (!data.value.enabled && !pilotIds.value.length) {
    useAlert('Marque primeiro pelo menos uma caixa "Com o motor".');
    return;
  }
  save({ enabled: !data.value.enabled });
};
const setMode = (id, mode) => {
  if (modeOf(id) === mode) return;
  const pilots = pilotIds.value.filter(x => x !== id);
  const controls = controlIds.value.filter(x => x !== id);
  if (mode === 'motor') pilots.push(id);
  if (mode === 'compare') controls.push(id);
  save({ pilot_inbox_ids: pilots, control_inbox_ids: controls });
};

// "Ler ontem agora": roda em segundo plano; a tela confere a cada 10 s
const runNow = async () => {
  running.value = true;
  const before = data.value?.last_run_at || null;
  try {
    await CrmAPI.runEducationEngine();
    useAlert('Lendo as conversas de ontem… leva uns 2 minutos.');
    let ticks = 0;
    clearInterval(pollTimer);
    pollTimer = setInterval(async () => {
      ticks += 1;
      await load();
      if (data.value?.last_run_at !== before || ticks > 30) {
        clearInterval(pollTimer);
        running.value = false;
      }
    }, 10000);
  } catch {
    running.value = false;
    useAlert('Não consegui pedir a leitura agora.');
  }
};

const approve = async g => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `Aprovar este aprendizado? Ele passa a valer em ${groupName(pilotIds.value)} na próxima conversa. A versão de antes fica guardada.`
    )
  )
    return;
  busyId.value = g.id;
  try {
    await CrmAPI.applyAgentGuidance(g.id);
    useAlert(
      '✅ Aprovado — vale a partir da próxima conversa das caixas com o motor.'
    );
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui aprovar.');
  } finally {
    busyId.value = null;
  }
};
const ignore = async g => {
  busyId.value = g.id;
  try {
    await CrmAPI.ignoreAgentGuidance(g.id);
    await load();
  } catch {
    useAlert('Não consegui ignorar.');
  } finally {
    busyId.value = null;
  }
};

const startEdit = () => {
  rulesDraft.value = data.value?.rules || '';
  editingRules.value = true;
};
const saveRules = async () => {
  saving.value = true;
  try {
    const res = await CrmAPI.updateEducationRules(rulesDraft.value);
    data.value = res.data;
    editingRules.value = false;
    useAlert('Aprendizados salvos — a versão de antes ficou no Histórico.');
  } catch {
    useAlert('Não consegui salvar os aprendizados.');
  } finally {
    saving.value = false;
  }
};
const restore = async v => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Voltar os aprendizados para esta versão?')) return;
  busyId.value = `v${v.id}`;
  try {
    await CrmAPI.restoreScriptVersion(v.id);
    useAlert('Voltou. A versão de agora ficou guardada no Histórico.');
    await load();
  } catch {
    useAlert('Não consegui voltar para esta versão.');
  } finally {
    busyId.value = null;
  }
};
defineExpose({ reload: load });
</script>

<template>
  <div class="cv-block p-5 sm:p-6">
    <div
      class="flex items-start gap-3 cursor-pointer select-none"
      :class="expanded ? 'mb-4' : ''"
      @click="expanded = !expanded"
    >
      <span class="cv-icon cv-icon-xl">
        <span class="i-lucide-graduation-cap text-lg" />
      </span>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <p class="text-base font-bold text-n-slate-12 leading-tight">
            Motor de educação
          </p>
          <span
            v-if="data"
            class="cv-chip"
            :class="data.enabled ? 'cv-green cv-chip-on' : 'cv-slate'"
          >
            {{ data.enabled ? 'ligado' : 'desligado' }}
          </span>
          <span v-if="pending.length" class="cv-chip cv-amber cv-chip-on">
            {{ pending.length }} para aprovar
          </span>
        </div>
        <p
          class="text-xs text-n-slate-10 mt-1 leading-relaxed"
          :class="expanded ? '' : 'line-clamp-2'"
        >
          Todo dia às 8h ele lê as conversas de ontem, compara quem
          <b>agendou</b> com quem <b>não agendou</b> e sugere até 5
          aprendizados, cada um com a conversa de exemplo. Nada muda sozinho:
          você aprova com um toque e o aprendizado vale só nas caixas que você
          marcar <b>Com o motor</b>. O placar mostra se elas passaram a agendar
          mais que as de <b>Comparação</b>.
        </p>
      </div>
      <span
        class="i-lucide-chevron-down text-n-slate-9 text-lg mt-2 flex-shrink-0 transition-transform duration-200"
        :class="expanded ? 'rotate-180' : ''"
      />
    </div>

    <div v-if="expanded">
      <div
        v-if="loadError"
        class="cv-sub cv-amber px-3.5 py-2.5 text-xs text-n-slate-12 mb-3"
      >
        ⚠️ {{ loadError }}
      </div>
      <div
        v-else-if="!data"
        class="cv-sub p-6 text-center text-xs text-n-slate-9"
      >
        Carregando…
      </div>

      <template v-else>
        <!-- 1. ligar + caixas -->
        <div class="cv-sub p-4 mb-3">
          <div class="flex items-center gap-2 mb-3">
            <button
              class="cv-switch cv-switch-lg"
              :class="data.enabled ? 'cv-switch-on' : ''"
              :disabled="saving || !props.canEdit"
              :aria-pressed="data.enabled"
              :title="data.enabled ? 'Desligar o motor' : 'Ligar o motor'"
              @click="toggle"
            />
            <span class="text-sm font-bold text-n-slate-12">
              {{ data.enabled ? 'Ligado' : 'Desligado' }}
            </span>
          </div>
          <p class="cv-label mb-1.5">Em cada caixa, o atendente usa</p>
          <div class="divide-y divide-n-weak">
            <div
              v-for="i in inboxes"
              :key="i.id"
              class="flex items-center gap-2 flex-wrap py-2"
            >
              <span
                class="text-sm text-n-slate-12 flex-1 min-w-[9rem] truncate"
                >{{ i.name }}</span
              >
              <div class="cv-seg cv-seg-sm !flex flex-nowrap w-full sm:w-auto">
                <button
                  v-for="m in MODES"
                  :key="m.key"
                  class="cv-seg-item flex-1 justify-center whitespace-nowrap"
                  :class="modeOf(i.id) === m.key ? 'cv-seg-on' : ''"
                  :disabled="saving || !props.canEdit"
                  @click="setMode(i.id, m.key)"
                >
                  {{ m.label }}
                </button>
              </div>
            </div>
            <p v-if="!inboxes.length" class="text-xs text-n-slate-9 py-2">
              Nenhuma caixa de WhatsApp nesta conta.
            </p>
          </div>
          <p class="text-[11px] text-n-slate-9 leading-relaxed mt-1.5">
            <b>Com o motor</b>: roteiro + aprendizados aprovados.
            <b>Comparação</b>: roteiro normal, entra no placar para comparar.
          </p>
          <div class="flex items-center gap-2 flex-wrap mt-3">
            <p
              class="text-[11px] text-n-slate-9 leading-relaxed flex-1 min-w-[12rem]"
            >
              <template v-if="data.last_run_at">
                Última leitura {{ fmtWhen(data.last_run_at) }}.
              </template>
              <template v-else>Ainda não leu nenhum dia.</template>
              Desligar tira os aprendizados das caixas na hora.
            </p>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost"
              :disabled="running || !data.enabled || !props.canEdit"
              :title="
                data.enabled
                  ? 'Lê as conversas de ontem agora (leva uns 2 minutos)'
                  : 'Ligue o motor primeiro'
              "
              @click="runNow"
            >
              <span
                :class="
                  running
                    ? 'i-lucide-loader-circle animate-spin'
                    : 'i-lucide-play'
                "
                class="text-xs"
              />
              Ler ontem agora
            </button>
          </div>
          <p
            v-if="!data.has_api_key"
            class="text-[11px] mt-2"
            style="color: #b45309"
          >
            ⚠️ Falta a chave da Claude em Integrações → Claude.
          </p>
        </div>

        <!-- 2. placar -->
        <div
          v-if="board && pilotIds.length"
          class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3"
        >
          <div
            v-for="side in [
              { key: 'pilot', title: 'Com o motor', ids: pilotIds },
              { key: 'control', title: 'Comparação', ids: controlIds },
            ]"
            :key="side.key"
            class="cv-sub p-4"
          >
            <p class="cv-label mb-1">
              {{ side.title }} ·
              {{ groupName(side.ids) }}
            </p>
            <div class="flex items-end gap-4">
              <div>
                <p class="text-[11px] text-n-slate-9">
                  {{ board.since ? 'antes' : 'até agora' }}
                </p>
                <p class="text-2xl font-bold text-n-slate-12 leading-tight">
                  {{ fmtRate(board.totals[side.key].before) }}
                </p>
                <p class="text-[11px] text-n-slate-9">
                  {{ board.totals[side.key].before.booked }} de
                  {{ board.totals[side.key].before.n }} agendaram
                </p>
              </div>
              <div v-if="board.since">
                <p class="text-[11px] text-n-slate-9">
                  depois de {{ fmtDay(board.since) }}
                </p>
                <p class="text-2xl font-bold text-n-slate-12 leading-tight">
                  {{ fmtRate(board.totals[side.key].after) }}
                </p>
                <p class="text-[11px] text-n-slate-9">
                  {{ board.totals[side.key].after.booked }} de
                  {{ board.totals[side.key].after.n }} agendaram
                </p>
              </div>
            </div>
          </div>
          <div
            v-if="board.alert"
            class="cv-sub cv-amber px-3.5 py-2.5 text-xs text-n-slate-12 sm:col-span-2"
          >
            ⚠️ {{ board.alert }}
          </div>
        </div>

        <!-- 3. leitura do último dia -->
        <div v-if="lastDay" class="cv-sub p-4 mb-3">
          <div class="flex items-center gap-2 flex-wrap mb-1.5">
            <p class="text-sm font-bold text-n-slate-12">
              Leitura de {{ fmtDay(lastDay.day) }}
            </p>
            <span class="cv-chip cv-slate">{{
              DAY_STATUS[lastDay.status] || lastDay.status
            }}</span>
            <span v-if="lastDay.read" class="text-[11px] text-n-slate-9">
              {{ lastDay.read.booked }} que agendaram ·
              {{ lastDay.read.lost }} que não agendaram
            </span>
          </div>
          <p
            v-if="lastDay.summary"
            class="text-xs text-n-slate-11 leading-relaxed"
          >
            {{ lastDay.summary }}
          </p>
          <p v-if="lastDay.error" class="text-xs" style="color: #b91c1c">
            {{ lastDay.error }}
          </p>
          <div
            v-if="lastDay.won?.length || lastDay.lost?.length"
            class="grid grid-cols-1 lg:grid-cols-2 gap-2.5 mt-2.5"
          >
            <div v-if="lastDay.won?.length">
              <p class="cv-label mb-1" style="color: #047857">
                O que fez agendar
              </p>
              <ul class="text-xs text-n-slate-11 space-y-1 list-disc pl-4">
                <li v-for="(t, i) in lastDay.won" :key="i">{{ t }}</li>
              </ul>
            </div>
            <div v-if="lastDay.lost?.length">
              <p class="cv-label mb-1" style="color: #b91c1c">
                O que fez perder
              </p>
              <ul class="text-xs text-n-slate-11 space-y-1 list-disc pl-4">
                <li v-for="(t, i) in lastDay.lost" :key="i">{{ t }}</li>
              </ul>
            </div>
          </div>
        </div>

        <!-- 4. para aprovar -->
        <p class="text-sm font-bold text-n-slate-12 mb-2 mt-4">
          Para aprovar
          <span class="text-n-slate-9 font-normal text-xs">
            · {{ pending.length }}</span
          >
        </p>
        <div v-if="!pending.length" class="cv-sub p-5 text-center mb-3">
          <p class="text-xs text-n-slate-9 leading-relaxed">
            Nenhum aprendizado esperando. Com o motor ligado, as sugestões
            chegam todo dia às 8h.
          </p>
        </div>
        <div v-else class="space-y-3 mb-3">
          <div v-for="g in pending" :key="g.id" class="cv-sub p-4">
            <div class="flex items-center gap-1.5 flex-wrap mb-2">
              <span
                class="cv-chip"
                :class="
                  g.confidence === 'alta' ? 'cv-green cv-chip-on' : 'cv-slate'
                "
              >
                {{
                  g.confidence === 'alta'
                    ? 'visto em várias conversas'
                    : 'caso isolado'
                }}
              </span>
              <span class="text-[10px] text-n-slate-9 ml-auto">
                {{ fmtWhen(g.created_at) }}
                <a
                  v-if="g.conversation_id"
                  :href="`/app/accounts/${accountId}/conversations/${g.conversation_id}`"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="hover:underline"
                  >· conversa #{{ g.conversation_id }}</a
                >
              </span>
            </div>
            <p class="text-sm font-semibold text-n-slate-12 leading-relaxed">
              {{ g.rule }}
            </p>
            <p
              v-if="g.why"
              class="text-xs text-n-slate-10 mt-1 leading-relaxed"
            >
              {{ g.why }}
            </p>
            <button
              class="text-[11px] text-n-slate-9 hover:underline mt-2"
              @click="openExample[g.id] = !openExample[g.id]"
            >
              {{ openExample[g.id] ? 'Esconder o exemplo' : 'Ver o exemplo' }}
            </button>
            <div
              v-if="openExample[g.id]"
              class="grid grid-cols-1 lg:grid-cols-3 gap-2.5 mt-2"
            >
              <div class="rounded-xl p-3 bg-n-alpha-1">
                <p class="cv-label mb-1">Paciente disse</p>
                <p
                  class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
                >
                  {{ g.patient_excerpt }}
                </p>
              </div>
              <div
                class="rounded-xl p-3"
                style="
                  background: rgba(220, 38, 38, 0.06);
                  border: 1px solid rgba(220, 38, 38, 0.24);
                "
              >
                <p class="cv-label mb-1" style="color: #b91c1c">
                  Atendente disse
                </p>
                <p
                  class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
                >
                  {{ g.agent_text }}
                </p>
              </div>
              <div
                class="rounded-xl p-3"
                style="
                  background: rgba(5, 150, 105, 0.07);
                  border: 1px solid rgba(5, 150, 105, 0.3);
                "
              >
                <p class="cv-label mb-1" style="color: #047857">
                  Deveria dizer
                </p>
                <p
                  class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
                >
                  {{ g.ideal_reply }}
                </p>
              </div>
            </div>
            <div
              v-if="props.canEdit"
              class="flex items-center gap-2 flex-wrap mt-3"
            >
              <button
                class="cv-btn cv-btn-sm cv-green"
                :disabled="busyId === g.id"
                @click="approve(g)"
              >
                <span class="i-lucide-check text-xs" />
                Aprovar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="busyId === g.id"
                @click="ignore(g)"
              >
                Ignorar
              </button>
            </div>
          </div>
        </div>

        <!-- 5. em vigor -->
        <div class="flex items-center gap-2 flex-wrap mb-2 mt-4">
          <p class="text-sm font-bold text-n-slate-12">
            Em vigor nas caixas com o motor
            <span class="text-n-slate-9 font-normal text-xs">
              · {{ ruleLines.length }}</span
            >
          </p>
          <div class="ml-auto flex items-center gap-2">
            <button
              v-if="props.canEdit && !editingRules"
              class="cv-btn cv-btn-sm cv-btn-ghost"
              @click="startEdit"
            >
              <span class="i-lucide-pencil text-xs" />
              Editar
            </button>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost"
              @click="showHistory = !showHistory"
            >
              <span class="i-lucide-history text-xs" />
              Histórico
            </button>
          </div>
        </div>
        <div class="cv-sub p-4">
          <template v-if="editingRules">
            <textarea
              v-model="rulesDraft"
              rows="8"
              class="cv-input w-full text-xs leading-relaxed"
              placeholder="Um aprendizado por linha"
            />
            <div class="flex items-center gap-2 mt-2">
              <button
                class="cv-btn cv-btn-sm cv-green"
                :disabled="saving"
                @click="saveRules"
              >
                Salvar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                @click="editingRules = false"
              >
                Cancelar
              </button>
            </div>
          </template>
          <ul
            v-else-if="ruleLines.length"
            class="text-xs text-n-slate-11 space-y-1.5 list-disc pl-4 leading-relaxed"
          >
            <li v-for="(line, i) in ruleLines" :key="i">{{ line }}</li>
          </ul>
          <p v-else class="text-xs text-n-slate-9">
            Nenhum aprendizado aprovado ainda.
          </p>

          <div v-if="showHistory" class="mt-3 pt-3 border-t border-n-weak">
            <p v-if="!data.versions?.length" class="text-xs text-n-slate-9">
              Nenhuma versão guardada ainda.
            </p>
            <div
              v-for="v in data.versions"
              :key="v.id"
              class="flex items-center gap-2 py-1.5 flex-wrap"
            >
              <span class="text-xs text-n-slate-11 flex-1 min-w-[10rem]">
                {{ fmtWhen(v.created_at) }} · {{ v.note }}
                <template v-if="v.author?.name">· {{ v.author.name }}</template>
              </span>
              <button
                v-if="props.canEdit"
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="busyId === `v${v.id}`"
                @click="restore(v)"
              >
                <span class="i-lucide-undo-2 text-xs" />
                Voltar para esta
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
