<script setup>
// ✍️ ORIENTAÇÕES DOS ATENDENTES (rodada 191): a fila de "como deveria ter
// respondido" que o admin escreve no Testar agente / tela Sombra (ou que o
// 👎 da Sombra cria sozinho). Aplicar = a regra entra no Roteiro (ou nos
// Passos da etapa) e o agente passa a seguir na próxima conversa. Vive na
// aba Agentes de IA, logo abaixo do Roteiro CEVICO.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmAPI from 'dashboard/api/crm';
import GuidanceModal from './GuidanceModal.vue';
import {
  GUIDANCE_AGENT_LABEL,
  GUIDANCE_SECTIONS,
  sectionLabel,
} from './guidanceSections';

const emit = defineEmits(['test', 'applied']);
const { accountId } = useAccount();

const items = ref([]);
const isLoading = ref(false);
const loadError = ref('');
const agentFilter = ref('all');
const statusFilter = ref('pending');
const busyId = ref(null);
const editing = ref(null); // orientação aberta no GuidanceModal
const expanded = ref(true);

const STATUS_FILTERS = [
  { key: 'pending', label: 'Pendentes' },
  { key: 'applied', label: 'Aplicadas' },
  { key: 'ignored', label: 'Ignoradas' },
];
const AGENT_FILTERS = [
  { key: 'all', label: 'Todos' },
  ...Object.entries(GUIDANCE_AGENT_LABEL).map(([key, label]) => ({
    key,
    label,
  })),
];

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.agentGuidances();
    items.value = Array.isArray(data)
      ? data
      : data?.guidances || data?.items || [];
  } catch {
    // o backend pode não estar no ar ainda: lista vazia + aviso, sem quebrar
    items.value = [];
    loadError.value =
      'Não consegui carregar as orientações — o servidor não respondeu. Tente atualizar.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
defineExpose({ reload: load });

const pendingCount = computed(
  () => items.value.filter(g => (g.status || 'pending') === 'pending').length
);
const filtered = computed(() =>
  items.value.filter(g => {
    if (agentFilter.value !== 'all' && g.agent_key !== agentFilter.value)
      return false;
    return (g.status || 'pending') === statusFilter.value;
  })
);
const countFor = status =>
  items.value.filter(g => (g.status || 'pending') === status).length;

const fmtWhen = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '';
const agentText = g =>
  Array.isArray(g.agent_text) ? g.agent_text.join('\n\n') : g.agent_text || '';
const sectionIcon = key =>
  GUIDANCE_SECTIONS.find(s => s.key === key)?.icon || 'i-lucide-scroll-text';

const replaceItem = (id, next) => {
  const idx = items.value.findIndex(g => g.id === id);
  if (idx >= 0 && next) items.value[idx] = { ...items.value[idx], ...next };
};
// apply devolve { guidance, section, … }; ignore/reopen devolvem a orientação direta
const unwrap = data => data?.guidance || (data?.id ? data : null);

const apply = async g => {
  const where =
    g.target_section === 'stage'
      ? `nos Passos do ${GUIDANCE_AGENT_LABEL[g.agent_key] || g.agent_key}`
      : `na seção "${sectionLabel(g.target_section)}" do Roteiro`;
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `Aplicar esta orientação ${where}? Uma versão de antes fica guardada no Histórico.`
    )
  )
    return;
  busyId.value = g.id;
  try {
    const { data } = await CrmAPI.applyAgentGuidance(g.id);
    replaceItem(g.id, unwrap(data) || { status: 'applied' });
    useAlert(`✅ Aplicada ${where} — vale a partir da próxima conversa.`);
    emit('applied', g);
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui aplicar a orientação.');
  } finally {
    busyId.value = null;
  }
};
const ignore = async g => {
  busyId.value = g.id;
  try {
    const { data } = await CrmAPI.ignoreAgentGuidance(g.id);
    replaceItem(g.id, unwrap(data) || { status: 'ignored' });
  } catch {
    useAlert('Não consegui ignorar a orientação.');
  } finally {
    busyId.value = null;
  }
};
const reopen = async g => {
  busyId.value = g.id;
  try {
    const { data } = await CrmAPI.reopenAgentGuidance(g.id);
    replaceItem(g.id, unwrap(data) || { status: 'pending' });
  } catch {
    useAlert('Não consegui reabrir a orientação.');
  } finally {
    busyId.value = null;
  }
};
const remove = async g => {
  // eslint-disable-next-line no-alert
  if (!window.confirm('Apagar esta orientação? Não dá para desfazer.')) return;
  busyId.value = g.id;
  try {
    await CrmAPI.deleteAgentGuidance(g.id);
    items.value = items.value.filter(x => x.id !== g.id);
  } catch {
    useAlert('Não consegui apagar a orientação.');
  } finally {
    busyId.value = null;
  }
};
const onSaved = saved => {
  if (saved?.id) replaceItem(saved.id, saved);
  load();
};
</script>

<template>
  <div class="cv-block cv-green p-5 sm:p-6">
    <div
      class="flex items-start gap-3 cursor-pointer select-none"
      :class="expanded ? 'mb-4' : ''"
      @click="expanded = !expanded"
    >
      <span class="cv-icon cv-icon-xl"><span class="i-lucide-pen-line text-lg"/></span>
      <div class="flex-1 min-w-0">
        <div class="flex items-center gap-2 flex-wrap">
          <p class="text-base font-bold text-n-slate-12 leading-tight">
            Orientações dos atendentes
          </p>
          <span
            class="cv-chip"
            :class="pendingCount ? 'cv-amber cv-chip-on' : 'cv-slate'"
          >
            {{ pendingCount }} pendente{{ pendingCount === 1 ? '' : 's' }}
          </span>
        </div>
        <p
          class="text-xs text-n-slate-10 mt-1 leading-relaxed"
          :class="expanded ? '' : 'line-clamp-2'"
        >
          Cada vez que o agente responde mal (no 🧪 Testar agente ou na tela
          Sombra), clique em <b>✍️ Orientar</b> e escreva como deveria ter sido.
          Aqui você revisa e <b>Aplica</b>: a regra entra no Roteiro (ou nos
          Passos da etapa) e vale na próxima conversa. O 👎 da Sombra também
          cria uma orientação sozinho.
        </p>
      </div>
      <span
        class="i-lucide-chevron-down text-n-slate-9 text-lg mt-2 flex-shrink-0 transition-transform duration-200"
        :class="expanded ? 'rotate-180' : ''"
      />
    </div>

    <div v-if="expanded">
      <!-- filtros: situação + agente -->
      <div class="flex flex-wrap items-center gap-2 mb-3">
        <div class="cv-seg cv-seg-sm !flex flex-wrap">
          <button
            v-for="f in STATUS_FILTERS"
            :key="f.key"
            class="cv-seg-item"
            :class="statusFilter === f.key ? 'cv-seg-on' : ''"
            @click="statusFilter = f.key"
          >
            {{ f.label }}
            <span class="opacity-70">{{ countFor(f.key) }}</span>
          </button>
        </div>
        <div class="cv-seg cv-seg-sm !flex flex-wrap">
          <button
            v-for="f in AGENT_FILTERS"
            :key="f.key"
            class="cv-seg-item"
            :class="agentFilter === f.key ? 'cv-seg-on' : ''"
            @click="agentFilter = f.key"
          >
            {{ f.label }}
          </button>
        </div>
        <button
          class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
          :disabled="isLoading"
          @click="load"
        >
          <span
            class="i-lucide-refresh-cw text-xs"
            :class="isLoading ? 'animate-spin' : ''"
          />
          Atualizar
        </button>
      </div>

      <div
        v-if="loadError"
        class="cv-sub cv-amber px-3.5 py-2.5 text-xs text-n-slate-12 mb-3"
      >
        ⚠️ {{ loadError }}
      </div>

      <div v-if="!filtered.length" class="cv-sub p-6 text-center">
        <p class="text-sm font-bold text-n-slate-12 mb-1">
          {{
            statusFilter === 'pending'
              ? 'Nenhuma orientação pendente'
              : statusFilter === 'applied'
                ? 'Nenhuma orientação aplicada ainda'
                : 'Nenhuma orientação ignorada'
          }}
        </p>
        <p class="text-xs text-n-slate-9 leading-relaxed">
          Abra o 🧪 Testar agente ou a tela Sombra e clique em ✍️ Orientar numa
          resposta que você faria diferente.
        </p>
      </div>

      <div v-else class="space-y-3">
        <div v-for="g in filtered" :key="g.id" class="cv-sub p-4">
          <div class="flex items-center gap-1.5 flex-wrap mb-2.5">
            <span class="cv-chip cv-chip-on">
              {{ GUIDANCE_AGENT_LABEL[g.agent_key] || g.agent_key }}
            </span>
            <span
              class="cv-chip"
              :class="g.source === 'sombra' ? 'cv-slate' : ''"
            >
              {{
                g.source === 'sombra' ? '🕶️ veio do 👎 da Sombra' : '✍️ manual'
              }}
            </span>
            <span class="cv-chip cv-gold">
              <span
                :class="sectionIcon(g.target_section)"
                class="text-[10px]"
              />
              {{ sectionLabel(g.target_section) }}
            </span>
            <span
              v-if="g.status === 'applied'"
              class="cv-chip cv-green cv-chip-on"
              >✅ aplicada {{ fmtWhen(g.applied_at) }}</span>
            <span v-else-if="g.status === 'ignored'"
class="cv-chip cv-slate"
              >ignorada</span>
            <span class="text-[10px] text-n-slate-9 ml-auto">
              {{ fmtWhen(g.created_at) }}
              <template v-if="g.created_by?.name">· {{ g.created_by.name }}</template>
              <a
                v-if="g.conversation_id"
                :href="`/app/accounts/${accountId}/conversations/${g.conversation_id}`"
                target="_blank"
                rel="noopener noreferrer"
                class="hover:underline"
                >· conversa #{{ g.conversation_id }}</a>
            </span>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-2.5">
            <div
              v-if="g.patient_excerpt"
              class="rounded-xl p-3"
              style="
                background: rgb(var(--cv-rgb) / 0.06);
                border: 1px solid rgb(var(--cv-rgb) / 0.16);
              "
            >
              <p class="cv-label mb-1">🧑 Paciente disse</p>
              <p
                class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
              >
                {{ g.patient_excerpt }}
              </p>
            </div>
            <div
              v-if="agentText(g)"
              class="rounded-xl p-3"
              style="
                background: rgba(220, 38, 38, 0.06);
                border: 1px solid rgba(220, 38, 38, 0.28);
              "
            >
              <p class="cv-label mb-1" style="color: #b91c1c">
                🤖 Agente respondeu
              </p>
              <p
                class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
              >
                {{ agentText(g) }}
              </p>
            </div>
            <div
              v-if="g.ideal_reply"
              class="rounded-xl p-3"
              style="
                background: rgba(5, 150, 105, 0.07);
                border: 1px solid rgba(5, 150, 105, 0.35);
              "
            >
              <p class="cv-label mb-1" style="color: #047857">
                ✅ Deveria responder
              </p>
              <p
                class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed"
              >
                {{ g.ideal_reply }}
              </p>
            </div>
            <div
              v-if="g.rule"
              class="rounded-xl p-3"
              style="
                background: rgba(212, 160, 23, 0.1);
                border: 1px solid rgba(212, 160, 23, 0.4);
              "
            >
              <p class="cv-label mb-1" style="color: #92600a">
                📌 Regra para o futuro
              </p>
              <p
                class="text-xs text-n-slate-12 whitespace-pre-wrap leading-relaxed font-medium"
              >
                {{ g.rule }}
              </p>
            </div>
          </div>

          <div class="flex items-center gap-2 flex-wrap mt-3">
            <template v-if="(g.status || 'pending') === 'pending'">
              <button
                class="cv-btn cv-btn-sm cv-green"
                :disabled="busyId === g.id"
                title="Escreve a regra no Roteiro (ou nos Passos) — guarda uma versão antes"
                @click="apply(g)"
              >
                <span
                  :class="
                    busyId === g.id
                      ? 'i-lucide-loader-circle animate-spin'
                      : 'i-lucide-check'
                  "
                  class="text-xs"
                />
                Aplicar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="busyId === g.id"
                @click="editing = g"
              >
                <span class="i-lucide-pencil text-xs" /> Editar
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :disabled="busyId === g.id"
                @click="ignore(g)"
              >
                <span class="i-lucide-eye-off text-xs" /> Ignorar
              </button>
            </template>
            <button
              v-else
              class="cv-btn cv-btn-sm cv-btn-ghost"
              :disabled="busyId === g.id"
              title="Volta para a fila de pendentes"
              @click="reopen(g)"
            >
              <span class="i-lucide-rotate-ccw text-xs" /> Reabrir
            </button>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost"
              title="Abre o Testar agente com a fala do paciente já digitada"
              @click="emit('test', g.agent_key, g.patient_excerpt || '')"
            >
              <span class="i-lucide-flask-conical text-xs" /> 🧪 Testar de novo
            </button>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger ml-auto"
              :disabled="busyId === g.id"
              title="Apagar esta orientação"
              @click="remove(g)"
            >
              <span class="i-lucide-trash-2 text-xs" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <GuidanceModal
      v-if="editing"
      :guidance="editing"
      :agent-key="editing.agent_key"
      @close="editing = null"
      @saved="onSaved"
    />
  </div>
</template>
