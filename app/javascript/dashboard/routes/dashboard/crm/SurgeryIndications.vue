<script setup>
// 🎯 ITEM 402 (23/11): INDICAÇÕES CIRÚRGICAS. Pedido dele: "um ambiente
// parecido com a lista da Agenda em que a Elisângela só vai apontando quem tem
// indicação e quem não tem… e indicação de quê". Fila de quem COMPARECEU e
// espera a resposta do médico; um toque marca a decisão na consulta e o card
// anda no CRM (colunas de Agenda → Conferência do dia). Balão de conversa em
// cada linha. Ainda não envia mensagem: o modelo entra na etapa seguinte.
import { ref, computed, watch, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { openPatientChat } from 'dashboard/composables/useCevicoPatientChat';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';

const { canEdit } = useCevicoAccess();
const editable = computed(() => canEdit('agenda.indicacoes'));

const pal = useCevicoPalette({
  scope: 'crm:indicacoes',
  blocks: [{ id: 'fila', label: 'Fila', icon: 'i-lucide-list-checks' }],
});
const pageStyle = computed(() => pal.cvVars.value);

const TABS = [
  { key: 'pendente', label: 'Para decidir', icon: 'i-lucide-hourglass' },
  {
    key: 'aguardando_exame',
    label: 'Aguardando exame',
    icon: 'i-lucide-scan-eye',
  },
  { key: 'indicado', label: 'Com indicação', icon: 'i-lucide-target' },
  {
    key: 'sem_indicacao',
    label: 'Sem indicação',
    icon: 'i-lucide-circle-slash',
  },
];
const EMPTY = {
  pendente: 'Ninguém esperando resposta neste período.',
  aguardando_exame: 'Ninguém aguardando exame neste período.',
  indicado: 'Nenhuma indicação marcada neste período.',
  sem_indicacao: 'Ninguém sem indicação neste período.',
};

const period = ref({ preset: 'last7', from: '', to: '' });
const tab = ref('pendente');
const rows = ref([]);
const procedures = ref([]);
const moves = ref({});
const isLoading = ref(false);
const loadError = ref('');
const savingId = ref(0);
const pickerId = ref(0);

const load = async () => {
  isLoading.value = true;
  loadError.value = '';
  try {
    const { data } = await CrmAPI.surgeryIndications({
      preset: period.value.preset,
      from: period.value.from,
      to: period.value.to,
    });
    rows.value = data.rows || [];
    procedures.value = data.procedures || [];
    moves.value = data.moves || {};
  } catch {
    loadError.value = 'Não deu para carregar a fila agora.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
watch(period, load, { deep: true });

const counts = computed(() =>
  TABS.reduce(
    (acc, t) => ({
      ...acc,
      [t.key]: rows.value.filter(r => r.status === t.key).length,
    }),
    {}
  )
);
// quem espera há mais tempo aparece primeiro na fila; nas outras abas, o mais recente
const visible = computed(() => {
  const list = rows.value.filter(r => r.status === tab.value);
  const dir =
    tab.value === 'pendente' || tab.value === 'aguardando_exame' ? 1 : -1;
  return [...list].sort(
    (a, b) => dir * (new Date(a.due_at) - new Date(b.due_at))
  );
});

const when = iso =>
  new Date(iso)
    .toLocaleString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Sao_Paulo',
    })
    .replace(',', ' ·');
const waiting = days => {
  if (days <= 0) return 'hoje';
  return days === 1 ? 'há 1 dia' : `há ${days} dias`;
};
const moveHint = key =>
  moves.value[key]
    ? `card vai para “${moves.value[key]}”`
    : 'card não muda de coluna';

const VALUE = {
  pendente: null,
  aguardando_exame: 'awaiting_exam',
  indicado: 'indicated',
  sem_indicacao: 'not_indicated',
};
const DONE = {
  pendente: 'Voltou para a fila.',
  aguardando_exame: '🔬 Aguardando exame',
  indicado: '🎯 Indicação marcada',
  sem_indicacao: 'Sem indicação marcada',
};
const mark = async (row, status, procedure = null) => {
  if (!editable.value || savingId.value) return;
  if (status === 'indicado' && !procedure) {
    pickerId.value = pickerId.value === row.id ? 0 : row.id;
    return;
  }
  savingId.value = row.id;
  try {
    const { data } = await CrmAPI.updateSurgeryIndication(row.id, {
      surgery_indication: VALUE[status],
      indicated_procedure: procedure,
    });
    rows.value = rows.value.map(r => (r.id === row.id ? data : r));
    pickerId.value = 0;
    const where = data.card?.stage ? ` · card em “${data.card.stage}”` : '';
    useAlert(
      `${DONE[status]}${procedure ? `: ${procedure}` : ''}${status === 'pendente' ? '' : where}`
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não deu para salvar. Tente de novo.');
  } finally {
    savingId.value = 0;
  }
};
const openChat = row =>
  openPatientChat({ contactId: row.contact_id, phone: row.phone });
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-6xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Indicações cirúrgicas"
        subtitle="Quem compareceu e espera a resposta do médico. Um toque marca a decisão e o card anda sozinho no CRM."
        icon="i-lucide-target"
        :palette="false"
      >
        <template #chips>
          <span class="cv-glass-chip">
            <span class="i-lucide-hourglass text-xs" />
            {{ counts.pendente }} para decidir
          </span>
          <span v-if="counts.aguardando_exame" class="cv-glass-chip">
            <span class="i-lucide-scan-eye text-xs" />
            {{ counts.aguardando_exame }} aguardando exame
          </span>
          <CevicoViewOnlyPill v-if="!editable" />
        </template>
        <PeriodRuler v-model="period" glass />
      </CevicoHero>

      <SkeletonScreen v-if="isLoading && !rows.length" variant="list" />

      <template v-else>
        <div
          v-if="loadError"
          class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3"
        >
          <p class="text-xs text-n-slate-11 flex-1">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="load">Tentar de novo</button>
        </div>

        <section class="cv-ag-block p-4 sm:p-7 mb-8">
          <div class="flex flex-wrap items-center gap-3 mb-4">
            <h2 class="cv-ag-block-title !mb-0">Fila do período</h2>
            <div class="cv-seg cv-seg-sm sm:ml-auto flex-wrap">
              <button
                v-for="t in TABS"
                :key="t.key"
                class="cv-seg-item"
                :class="tab === t.key ? 'cv-seg-on' : ''"
                @click="
                  tab = t.key;
                  pickerId = 0;
                "
              >
                <span :class="t.icon" class="text-xs" />
                {{ t.label }}
                <span class="opacity-70">{{ counts[t.key] }}</span>
              </button>
            </div>
          </div>

          <p
            v-if="editable && tab !== 'indicado' && tab !== 'sem_indicacao'"
            class="text-[11px] text-n-slate-10 mb-4"
          >
            Indicação: {{ moveHint('indicado') }} · Sem indicação:
            {{ moveHint('sem_indicacao') }} · Aguardando exame:
            {{ moveHint('aguardando_exame') }}. As colunas são escolhidas em
            Agenda → Configurações → Conferência do dia.
          </p>

          <div
            v-if="!visible.length"
            class="cv-sub p-8 text-center text-n-slate-10"
          >
            <span class="i-lucide-badge-check text-3xl block mx-auto mb-2" />
            <p class="text-sm">{{ EMPTY[tab] }}</p>
          </div>

          <ul v-else class="space-y-2.5 list-none m-0 p-0">
            <li
              v-for="row in visible"
              :key="row.id"
              class="cv-sub p-3.5 sm:p-4"
            >
              <div class="flex flex-wrap items-start gap-x-4 gap-y-3">
                <div class="min-w-0 flex-1 basis-56">
                  <div class="flex items-center gap-2 flex-wrap">
                    <span
                      class="text-sm font-semibold text-n-slate-12 truncate"
                      >{{ row.name }}</span
                    >
                    <span
                      v-if="row.partner"
                      class="cv-chip cv-slate"
                      title="Paciente de parceiro: sem IA, só a caixa Oftalmofácil fala com ele"
                    >
                      Oftalmofácil
                    </span>
                    <span
                      v-if="
                        row.status === 'indicado' && row.indicated_procedure
                      "
                      class="cv-chip cv-gold cv-chip-on"
                    >
                      🎯 {{ row.indicated_procedure }}
                    </span>
                  </div>
                  <p class="text-xs text-n-slate-11 mt-1">
                    Consulta {{ when(row.due_at) }} ·
                    {{ waiting(row.waiting_days) }}
                    <template v-if="row.doctor"> · {{ row.doctor }}</template>
                    <template v-if="row.unit_label">
                      · {{ row.unit_label }}
                    </template>
                  </p>
                  <p class="text-[11px] text-n-slate-10 mt-0.5">
                    <template v-if="row.phone">{{ row.phone }}</template>
                    <template v-if="row.card?.stage">
                      · no CRM: {{ row.card.stage }}
                    </template>
                    <template v-else> · sem card no CRM</template>
                  </p>
                </div>

                <div class="flex items-center gap-1.5 flex-wrap">
                  <button
                    class="flex items-center justify-center w-8 h-8 rounded-lg transition-transform hover:scale-110"
                    style="color: #2563eb; background: rgba(37, 99, 235, 0.1)"
                    title="Abrir conversa"
                    @click.stop="openChat(row)"
                  >
                    <span class="i-lucide-message-circle-more text-lg" />
                  </button>
                  <template v-if="editable">
                    <template
                      v-if="
                        row.status === 'pendente' ||
                        row.status === 'aguardando_exame'
                      "
                    >
                      <button
                        class="cv-ag-act"
                        style="--a: #b8860b"
                        :class="pickerId === row.id ? 'cv-ag-act-on' : ''"
                        :disabled="savingId === row.id"
                        @click="mark(row, 'indicado')"
                      >
                        🎯 Indicação
                      </button>
                      <button
                        class="cv-ag-act"
                        style="--a: #64748b"
                        :disabled="savingId === row.id"
                        @click="mark(row, 'sem_indicacao')"
                      >
                        Sem indicação
                      </button>
                      <button
                        v-if="row.status === 'pendente'"
                        class="cv-ag-act"
                        style="--a: #2563eb"
                        :disabled="savingId === row.id"
                        @click="mark(row, 'aguardando_exame')"
                      >
                        🔬 Aguardando exame
                      </button>
                    </template>
                    <button
                      v-else
                      class="cv-ag-act"
                      style="--a: #64748b"
                      :disabled="savingId === row.id"
                      title="Volta para a fila Para decidir"
                      @click="mark(row, 'pendente')"
                    >
                      Desfazer
                    </button>
                  </template>
                </div>
              </div>

              <div
                v-if="pickerId === row.id"
                class="flex flex-wrap gap-1.5 mt-3 pt-3 border-t border-n-weak"
              >
                <span class="text-[11px] text-n-slate-10 w-full"
                  >Qual procedimento foi indicado?</span
                >
                <button
                  v-for="proc in procedures"
                  :key="proc"
                  class="cv-chip cv-gold"
                  :disabled="savingId === row.id"
                  @click="mark(row, 'indicado', proc)"
                >
                  {{ proc }}
                </button>
              </div>
            </li>
          </ul>
        </section>
      </template>
    </div>
  </div>
</template>
