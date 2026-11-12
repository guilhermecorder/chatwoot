<script setup>
// 📄 11/11/2026 (LIFE, pedido do Guilherme): PARA QUEM É A PROPOSTA, numa tela
// só. Três jeitos de achar o cliente, sem sair do gerador:
//   1. digitar o começo do NOME (a busca vai puxando quem já está na base);
//   2. digitar o TELEFONE (com ou sem DDD, com ou sem o 9);
//   3. clicar em quem está na COLUNA do funil (abre em "Orçamento a fazer").
// Escolhido o cliente, aparece o resumo escrito dele (conta de luz, consumo
// que vai aumentar, telhado…) para ninguém precisar perguntar de novo.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import CrmAPI from 'dashboard/api/crm';
import { stageDeadline } from 'dashboard/helper/taskDue';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import ClientSummaryLines from 'dashboard/components-next/cevico/ClientSummaryLines.vue';

const props = defineProps({
  // { contact_id, name, phone, stage, summary } ou null
  modelValue: { type: Object, default: null },
  // cliente que já vem escolhido pelo link (…/cotador?contact=6)
  initialContactId: { type: [Number, String], default: null },
});
const emit = defineEmits(['update:modelValue']);

const router = useRouter();
const route = useRoute();
const { spaceName, canView } = useCevicoAccess();

const TXT = {
  title: 'Para quem é a proposta?',
  subtitle:
    'Digite o nome ou o telefone, ou escolha quem está na coluna do funil.',
  placeholder: 'Nome ou telefone do cliente',
  searching: 'Procurando',
  noResult: 'Ninguém com esse nome ou telefone na base.',
  column: 'Quem está na coluna',
  emptyColumn: 'Ninguém nesta coluna agora.',
  change: 'Trocar cliente',
  noPhone: 'sem telefone',
  noSummary:
    'Ainda não há resumo deste cliente. O atendente anota durante a conversa.',
};

const query = ref('');
const results = ref([]);
const searching = ref(false);
const searched = ref(false);
const stages = ref([]);
const stageId = ref(null);
const people = ref([]);
const loadingQueue = ref(false);
let searchTimer = null;
let searchSeq = 0;

const selected = computed(() => props.modelValue);
const canOpenSpace = computed(() => canView('pacientes'));
const peopleLabel = n => `${n} ${n === 1 ? 'pessoa' : 'pessoas'}`;
const stageOption = s => `${s.name} (${s.count})`;
const dueOf = person => stageDeadline(person.stage_due_at);

const loadQueue = async (params = {}) => {
  loadingQueue.value = true;
  try {
    const { data } = await CrmAPI.getProposalQueue(params);
    stages.value = data.stages || [];
    stageId.value = data.stage_id;
    people.value = data.people || [];
    return data.selected || null;
  } catch {
    people.value = [];
    return null;
  } finally {
    loadingQueue.value = false;
  }
};

const choose = async contactId => {
  const person = await loadQueue({
    stage_id: stageId.value,
    contact_id: contactId,
  });
  if (!person) return;
  emit('update:modelValue', person);
  query.value = '';
  results.value = [];
  searched.value = false;
};
const clear = () => emit('update:modelValue', null);
const changeStage = () => loadQueue({ stage_id: stageId.value });

const runSearch = async () => {
  const term = query.value.trim();
  if (term.length < 2) {
    results.value = [];
    searched.value = false;
    return;
  }
  searchSeq += 1;
  const seq = searchSeq;
  searching.value = true;
  try {
    const { data } = await CrmAPI.searchPatients(term, { limit: 8 });
    if (seq !== searchSeq) return;
    results.value = data.payload || [];
    searched.value = true;
  } catch {
    if (seq === searchSeq) results.value = [];
  } finally {
    if (seq === searchSeq) searching.value = false;
  }
};
watch(query, () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(runSearch, 250);
});

const openSpace = () =>
  router.push({
    name: 'patient_space',
    params: {
      accountId: route.params.accountId,
      contactId: selected.value.contact_id,
    },
  });

onMounted(async () => {
  const person = await loadQueue(
    props.initialContactId ? { contact_id: props.initialContactId } : {}
  );
  if (person && !selected.value) emit('update:modelValue', person);
});
</script>

<template>
  <section class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 sm:p-6">
    <h2 class="text-sm font-semibold text-n-slate-12">{{ TXT.title }}</h2>

    <!-- cliente escolhido -->
    <div v-if="selected" class="mt-4">
      <div class="flex items-start gap-3 flex-wrap">
        <div class="min-w-0 flex-1">
          <p
            class="text-lg font-bold text-n-slate-12 leading-tight break-words"
          >
            {{ selected.name }}
          </p>
          <p
            class="text-sm text-n-slate-11 mt-0.5 flex items-center gap-2 flex-wrap"
          >
            <span>{{ selected.phone || TXT.noPhone }}</span>
            <span
              v-if="selected.stage"
              class="inline-flex items-center gap-1.5 text-xs font-semibold px-2 py-0.5 rounded-lg border border-n-weak"
            >
              <span
                class="w-2 h-2 rounded-full"
                :style="{ background: selected.stage.color || '#64748b' }"
              />
              {{ selected.stage.name }}
            </span>
          </p>
        </div>
        <div class="flex items-center gap-2 flex-wrap">
          <button
            v-if="canOpenSpace"
            type="button"
            class="h-9 px-3 rounded-xl bg-n-alpha-2 text-xs font-semibold text-n-slate-12 inline-flex items-center gap-1.5 hover:bg-n-alpha-3"
            @click="openSpace"
          >
            <span class="i-lucide-user-round text-sm" />
            {{ spaceName }}
          </button>
          <button
            type="button"
            class="h-9 px-3 rounded-xl bg-n-alpha-2 text-xs font-semibold text-n-slate-11 inline-flex items-center gap-1.5 hover:bg-n-alpha-3"
            @click="clear"
          >
            <span class="i-lucide-repeat text-sm" />
            {{ TXT.change }}
          </button>
        </div>
      </div>
      <ClientSummaryLines
        v-if="selected.summary?.length"
        class="mt-3"
        :lines="selected.summary"
      />
      <p v-else class="mt-3 text-xs text-n-slate-10">{{ TXT.noSummary }}</p>
    </div>

    <!-- escolher -->
    <div v-else class="mt-1">
      <p class="text-xs text-n-slate-10 mb-3">{{ TXT.subtitle }}</p>
      <div class="relative">
        <span
          class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-base text-n-slate-9"
        />
        <input
          v-model="query"
          type="search"
          autocomplete="off"
          class="!mb-0 w-full h-11 rounded-xl border border-n-weak bg-n-solid-1 !pl-10 pr-3 text-base text-n-slate-12"
          :placeholder="TXT.placeholder"
        />
      </div>
      <p v-if="searching" class="mt-2 text-xs text-n-slate-10">
        {{ TXT.searching }}
      </p>
      <p
        v-else-if="searched && !results.length"
        class="mt-2 text-xs text-n-slate-10"
      >
        {{ TXT.noResult }}
      </p>
      <ul
        v-if="results.length"
        class="mt-2 flex flex-col gap-1.5 list-none !m-0 !mt-2 !p-0"
      >
        <li
          v-for="item in results"
          :key="item.id"
          class="rounded-xl border border-n-weak bg-n-solid-1 hover:bg-n-alpha-2"
        >
          <button
            type="button"
            class="w-full text-left px-3 py-2.5 flex items-center gap-3 flex-wrap"
            @click="choose(item.id)"
          >
            <span class="text-sm font-semibold text-n-slate-12 break-words">
              {{ item.name }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ item.phone_number || TXT.noPhone }}
            </span>
            <span
              v-if="item.stage"
              class="ml-auto inline-flex items-center gap-1.5 text-xs font-semibold text-n-slate-11"
            >
              <span
                class="w-2 h-2 rounded-full"
                :style="{ background: item.stage.color || '#64748b' }"
              />
              {{ item.stage.name }}
            </span>
          </button>
        </li>
      </ul>

      <!-- quem está na coluna do funil -->
      <div v-if="stages.length" class="mt-5">
        <div class="flex items-center gap-2 flex-wrap mb-2">
          <span class="text-xs font-semibold text-n-slate-11">
            {{ TXT.column }}
          </span>
          <select
            v-model="stageId"
            class="!mb-0 h-9 rounded-xl border border-n-weak bg-n-solid-1 px-3 text-sm text-n-slate-12 !w-auto max-w-full"
            @change="changeStage"
          >
            <option v-for="s in stages" :key="s.id" :value="s.id">
              {{ stageOption(s) }}
            </option>
          </select>
          <span class="text-xs text-n-slate-10">
            {{ peopleLabel(people.length) }}
          </span>
        </div>
        <p
          v-if="!people.length && !loadingQueue"
          class="text-xs text-n-slate-10"
        >
          {{ TXT.emptyColumn }}
        </p>
        <ul
          v-else
          class="grid grid-cols-1 sm:grid-cols-2 gap-2 list-none !m-0 !p-0"
        >
          <li
            v-for="person in people"
            :key="person.contact_id"
            class="rounded-xl border border-n-weak bg-n-solid-1 hover:bg-n-alpha-2"
          >
            <button
              type="button"
              class="w-full h-full text-left px-3 py-2.5"
              @click="choose(person.contact_id)"
            >
              <span class="flex items-center gap-2 flex-wrap">
                <span class="text-sm font-semibold text-n-slate-12 break-words">
                  {{ person.name }}
                </span>
                <span
                  v-if="dueOf(person)"
                  class="ml-auto text-[11px] font-bold px-2 py-0.5 rounded-full"
                  :class="{
                    'bg-red-500/10 text-red-700': dueOf(person).tone === 'late',
                    'bg-amber-500/15 text-amber-800':
                      dueOf(person).tone === 'soon',
                    'bg-green-500/10 text-green-800':
                      dueOf(person).tone === 'later',
                  }"
                >
                  {{ dueOf(person).text }}
                </span>
              </span>
              <span class="block text-xs text-n-slate-11 mt-0.5">
                {{ person.phone || TXT.noPhone }}
              </span>
              <ClientSummaryLines
                v-if="person.summary?.length"
                class="mt-2"
                :lines="person.summary"
              />
            </button>
          </li>
        </ul>
      </div>
    </div>
  </section>
</template>
