<script setup>
// 🏷️ FONTES DE PACIENTES (item 322, 04/10/2026 — só admin). Pedido do
// Guilherme: "gerenciar pacientes de diversas fontes; cada fonte com o seu
// ambiente isolado", começando pelo Oftalmofácil.
//   1. Fontes  → cada fonte com o seu ambiente (funis e caixas), quanto tem
//                de cada coisa e COMO as entradas em coluna nasceram
//   2. Carimbo → quanto do banco ainda está sem carimbo + prévia + gravar,
//                e a conferência carimbo × cerca dos parceiros
//   3. Nova fonte / editar → nome, cor, funis e caixas
import { ref, computed, onMounted, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import DashKpi from 'dashboard/components-next/cevico/DashKpi.vue';
import ShareBar from 'dashboard/components-next/cevico/ShareBar.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';

const isLoading = ref(true);
const isWorking = ref(false);
const data = ref(null);
const preview = ref(null); // prévia do carimbo: { tabela: { fonte: n } }
const form = ref(null); // fonte em criação/edição
const formBlock = ref(null); // o formulário fica no fim da página: "Editar" leva até ele

const pal = useCevicoPalette({
  scope: 'crm:sources',
  blocks: [
    { id: 'fontes', label: 'Fontes', icon: 'i-lucide-git-fork' },
    { id: 'carimbo', label: 'Carimbo', icon: 'i-lucide-stamp' },
    { id: 'nova', label: 'Nova fonte', icon: 'i-lucide-plus' },
  ],
});
const { cvVars, blockVars, blockFamily } = pal;

// COMO NASCEU — nome e cor de cada jeito ('' = registro anterior ao carimbo)
const VIAS = {
  paciente: { label: 'Paciente escreveu', color: '#2563EB' },
  equipe: { label: 'Equipe', color: '#16A34A' },
  robo: { label: 'Robô / sistema', color: '#7C3AED' },
  sync: { label: 'Sincronização', color: '#0D9488' },
  carga: { label: 'Carga em massa', color: '#D97706' },
  integracao: { label: 'Integração (N8N)', color: '#DB2777' },
  '': { label: 'Antes do carimbo', color: '#94A3B8' },
};
const TABLES = [
  { key: 'contacts', label: 'Pacientes' },
  { key: 'cards', label: 'Cards do CRM' },
  { key: 'stage_logs', label: 'Entradas em coluna' },
  { key: 'tasks', label: 'Agendamentos e tarefas' },
  { key: 'surgeries', label: 'Itens do hub' },
];
const COLORS = [
  '#0D9488',
  '#2563EB',
  '#7C3AED',
  '#DB2777',
  '#EA580C',
  '#16A34A',
];

const load = async () => {
  try {
    const { data: payload } = await CrmAPI.getSources();
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar as fontes de pacientes.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

const sources = computed(() => data.value?.sources || []);
const pending = computed(() => data.value?.pending || {});
const pendingTotal = computed(() =>
  Object.values(pending.value).reduce((s, n) => s + Number(n || 0), 0)
);
const fence = computed(() => data.value?.fence);
const fenceOk = computed(
  () => fence.value && !fence.value.only_stamp && !fence.value.only_fence
);
const nameOf = (list, id) =>
  (data.value?.[list] || []).find(item => item.id === id)?.name || `#${id}`;
const sourceName = key => sources.value.find(s => s.key === key)?.name || key;
const fmt = n => Number(n || 0).toLocaleString('pt-BR');

const viaSlices = source =>
  Object.entries(source.entries?.by_via || {}).map(([via, value]) => ({
    label: (VIAS[via] || VIAS['']).label,
    color: (VIAS[via] || VIAS['']).color,
    value,
  }));

// ── carimbo: prévia → gravar ─────────────────────────────────────────
const runBackfill = async apply => {
  isWorking.value = true;
  try {
    const { data: payload } = await CrmAPI.backfillSources(apply);
    if (apply) {
      preview.value = null;
      useAlert('Passado carimbado.');
      await load();
    } else {
      preview.value = payload.result;
    }
  } catch {
    useAlert('Não consegui carimbar agora. Nada foi alterado.');
  } finally {
    isWorking.value = false;
  }
};
const previewRows = computed(() =>
  TABLES.map(t => ({ ...t, by: preview.value?.[t.key] || {} })).filter(
    t => Object.keys(t.by).length
  )
);

// ── nova fonte / editar ──────────────────────────────────────────────
// funis e caixas livres = os da casa (ninguém pegou) + os desta fonte
const own = computed(() => sources.value.find(s => s.kind === 'own'));
// (o funil principal da casa nunca muda de dono)
const freeIds = (list, current) =>
  [...new Set([...(own.value?.[list] || []), ...(current || [])])].filter(
    id =>
      list !== 'pipeline_ids' ||
      !(data.value?.main_pipeline_ids || []).includes(id)
  );
const openForm = source => {
  form.value = source
    ? {
        id: source.id,
        name: source.name,
        color: source.color || COLORS[0],
        pipeline_ids: [...source.pipeline_ids],
        inbox_ids: [...source.inbox_ids],
        fixed: source.kind === 'own' || source.legacy_partner,
        pipelines: freeIds('pipeline_ids', source.pipeline_ids),
        inboxes: freeIds('inbox_ids', source.inbox_ids),
      }
    : {
        id: null,
        name: '',
        color: COLORS[1],
        pipeline_ids: [],
        inbox_ids: [],
        fixed: false,
        pipelines: freeIds('pipeline_ids'),
        inboxes: freeIds('inbox_ids'),
      };
};
const openFormAndShow = async source => {
  openForm(source);
  await nextTick();
  formBlock.value?.scrollIntoView({ block: 'start' });
};
const toggle = (list, id) => {
  const ids = form.value[list];
  form.value[list] = ids.includes(id)
    ? ids.filter(i => i !== id)
    : [...ids, id];
};
const save = async () => {
  if (!form.value.name.trim()) {
    useAlert('Dê um nome para a fonte.');
    return;
  }
  isWorking.value = true;
  const payload = {
    name: form.value.name.trim(),
    color: form.value.color,
    pipeline_ids: form.value.pipeline_ids,
    inbox_ids: form.value.inbox_ids,
  };
  try {
    const { data: fresh } = form.value.id
      ? await CrmAPI.updateSource(form.value.id, payload)
      : await CrmAPI.createSource(payload);
    data.value = fresh;
    form.value = null;
    useAlert('Fonte salva.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui salvar a fonte.');
  } finally {
    isWorking.value = false;
  }
};
</script>

<template>
  <div class="cv-page cv-overlay" :style="cvVars">
    <CevicoHero
      :pal="pal"
      title="Fontes de pacientes"
      subtitle="de quem é cada paciente · o ambiente de cada fonte · como cada dado nasceu"
      icon="i-lucide-git-fork"
    />

    <SkeletonScreen v-if="isLoading" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ 1. FONTES: cada uma com o seu ambiente ══ -->
      <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('fontes')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-git-fork text-base" />
          </span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Fontes
          </h2>
        </div>
        <p class="text-xs text-n-slate-10 mb-6">
          cada fonte é dona dos seus funis e das suas caixas de entrada. Tudo o
          que nasce dentro deles já sai carimbado com o nome dela.
        </p>

        <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
          <div
            v-for="source in sources"
            :key="source.id"
            class="cv-sub p-5 sm:p-6"
            :style="{ borderColor: source.color }"
          >
            <div class="flex items-center gap-3 mb-4 flex-wrap">
              <span
                class="w-3.5 h-3.5 rounded-full flex-shrink-0"
                :style="{ background: source.color }"
              />
              <h3 class="text-lg font-bold text-n-slate-12">
                {{ source.name }}
              </h3>
              <span class="cv-tag cv-tag-tint">
                {{ source.kind === 'own' ? 'fonte da casa' : 'fonte parceira' }}
              </span>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
                @click="openFormAndShow(source)"
              >
                <span class="i-lucide-pencil text-xs" /> Editar
              </button>
            </div>

            <p
              class="text-[11px] font-semibold uppercase text-n-slate-9 mb-1.5"
            >
              Ambiente
            </p>
            <div class="flex flex-wrap gap-1.5 mb-1.5">
              <span
                v-for="id in source.pipeline_ids"
                :key="`p${id}`"
                class="cv-tag cv-tag-ghost"
              >
                <span class="i-lucide-kanban text-[10px]" />
                {{ nameOf('pipelines', id) }}
              </span>
              <span
                v-for="id in source.inbox_ids"
                :key="`i${id}`"
                class="cv-tag cv-tag-ghost"
              >
                <span class="i-lucide-inbox text-[10px]" />
                {{ nameOf('inboxes', id) }}
              </span>
              <span
                v-if="!source.pipeline_ids.length && !source.inbox_ids.length"
                class="text-xs text-n-slate-9"
              >
                nenhum funil nem caixa ainda
              </span>
            </div>
            <p
              v-if="source.kind === 'own'"
              class="text-[11px] text-n-slate-9 mb-5"
            >
              a casa fica com todo funil e toda caixa que nenhuma outra fonte
              pegou
            </p>
            <p
              v-else-if="source.legacy_partner"
              class="text-[11px] text-n-slate-9 mb-5"
            >
              funil e caixas escolhidos no card OftalmoFácil, em Integrações
            </p>
            <div v-else class="mb-5" />

            <div class="grid grid-cols-2 gap-3 mb-5">
              <DashKpi
                compact
                glass
                label="Pacientes"
                :value="fmt(source.counts.patients)"
                sub="carimbados com esta fonte"
                :grad="blockFamily('fontes')[0]"
              />
              <DashKpi
                compact
                glass
                label="Cards no CRM"
                :value="fmt(source.counts.cards)"
                sub="nos funis desta fonte"
                :grad="blockFamily('fontes')[1]"
              />
              <DashKpi
                compact
                glass
                label="Agendamentos"
                :value="fmt(source.counts.appointments)"
                sub="consultas e cirurgias"
                :grad="blockFamily('fontes')[2]"
              />
              <DashKpi
                compact
                glass
                label="Itens do hub"
                :value="fmt(source.counts.hub_items)"
                sub="espelho do Oftalmofácil"
                :grad="blockFamily('fontes')[3]"
              />
            </div>

            <p class="text-xs font-bold text-n-slate-12 mb-0.5">
              Entradas em coluna · últimos 30 dias
            </p>
            <p class="text-[11px] text-n-slate-9 mb-3">
              {{ fmt(source.entries.total) }} entradas, separadas por como
              nasceram
            </p>
            <ShareBar
              v-if="source.entries.total"
              :items="viaSlices(source)"
              :format="fmt"
            />
            <p v-else class="text-xs text-n-slate-9">
              nenhuma entrada carimbada nos últimos 30 dias
            </p>
          </div>
        </div>
      </div>

      <!-- ══ 2. CARIMBO: o passado + conferência com a cerca ══ -->
      <div class="cv-block p-6 sm:p-9 mb-10" :style="blockVars('carimbo')">
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-stamp text-base" />
          </span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Carimbo
          </h2>
        </div>
        <p class="text-xs text-n-slate-10 mb-6">
          tudo o que nasce agora já sai carimbado. O que nasceu antes ganha a
          fonte pelas mesmas regras que separam os dados hoje — sem reescrever
          nada que já tenha carimbo.
        </p>

        <div class="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-5">
          <DashKpi
            v-for="(t, i) in TABLES"
            :key="t.key"
            compact
            glass
            :label="t.label"
            :value="fmt(pending[t.key])"
            sub="sem carimbo"
            :grad="blockFamily('carimbo')[i % 4]"
          />
        </div>

        <div
          class="cv-strip px-4 py-3.5 flex items-center gap-3 flex-wrap mb-5"
        >
          <span class="cv-icon cv-icon-sm">
            <span
              :class="pendingTotal ? 'i-lucide-info' : 'i-lucide-check'"
              class="text-xs"
            />
          </span>
          <p class="text-xs text-n-slate-11 flex-1 min-w-0">
            <template v-if="pendingTotal">
              <b>{{ fmt(pendingTotal) }}</b> registros ainda sem carimbo. O robô
              da madrugada carimba sozinho; aqui dá para ver antes e gravar
              agora.
            </template>
            <template v-else>Tudo carimbado. Nada pendente.</template>
          </p>
          <button
            v-if="pendingTotal"
            class="cv-btn cv-btn-sm"
            :disabled="isWorking"
            @click="runBackfill(false)"
          >
            <span class="i-lucide-eye text-xs" /> Ver o que será carimbado
          </button>
        </div>

        <div v-if="preview" class="cv-sub p-5 mb-5">
          <p class="text-xs font-bold text-n-slate-12 mb-3">
            Prévia — nada foi gravado ainda
          </p>
          <p v-if="!previewRows.length" class="text-xs text-n-slate-9">
            nada a carimbar
          </p>
          <div
            v-for="row in previewRows"
            :key="row.key"
            class="flex items-baseline gap-3 flex-wrap py-1.5 text-xs"
          >
            <span class="w-44 text-n-slate-11">{{ row.label }}</span>
            <span
              v-for="(n, key) in row.by"
              :key="key"
              class="text-n-slate-12 whitespace-nowrap"
            >
              {{ sourceName(key) }} <b>{{ fmt(n) }}</b>
            </span>
          </div>
          <div class="flex items-center gap-2 mt-4">
            <button
              class="cv-btn cv-blue cv-btn-sm"
              :disabled="isWorking || !previewRows.length"
              @click="runBackfill(true)"
            >
              <span class="i-lucide-stamp text-xs" />
              {{ isWorking ? 'Carimbando…' : 'Carimbar agora' }}
            </button>
            <button
              class="cv-btn cv-btn-ghost cv-btn-sm"
              @click="preview = null"
            >
              Fechar
            </button>
          </div>
        </div>

        <div v-if="fence" class="cv-sub p-5">
          <p class="text-xs font-bold text-n-slate-12 mb-0.5">
            Conferência: carimbo × cerca dos parceiros
          </p>
          <p class="text-[11px] text-n-slate-9 mb-3">
            hoje as telas ainda separam o Oftalmofácil pela cerca. Antes de as
            telas passarem a ler o carimbo, os dois precisam dizer a mesma coisa
            sobre cada paciente.
          </p>
          <div class="flex items-baseline gap-x-6 gap-y-1 flex-wrap text-xs">
            <span class="whitespace-nowrap">
              carimbados Oftalmofácil <b>{{ fmt(fence.stamped) }}</b>
            </span>
            <span class="whitespace-nowrap">
              na cerca <b>{{ fmt(fence.fenced) }}</b>
            </span>
            <span class="whitespace-nowrap">
              só no carimbo <b>{{ fmt(fence.only_stamp) }}</b>
            </span>
            <span class="whitespace-nowrap">
              só na cerca <b>{{ fmt(fence.only_fence) }}</b>
            </span>
            <span
              class="cv-tag"
              :class="fenceOk ? 'cv-tag-tint' : 'cv-tag-solid'"
            >
              {{ fenceOk ? 'batem' : 'há diferenças' }}
            </span>
          </div>
        </div>
      </div>

      <!-- ══ 3. NOVA FONTE / EDITAR ══ -->
      <div
        ref="formBlock"
        class="cv-block p-6 sm:p-9 mb-10"
        :style="blockVars('nova')"
      >
        <div class="flex items-center gap-2 mb-1 flex-wrap">
          <span class="cv-icon">
            <span class="i-lucide-plus text-base" />
          </span>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            {{ form?.id ? `Editar: ${form.name}` : 'Nova fonte' }}
          </h2>
          <button
            v-if="!form"
            class="cv-btn cv-blue cv-btn-sm ml-auto"
            @click="openFormAndShow(null)"
          >
            <span class="i-lucide-plus text-xs" /> Criar fonte
          </button>
        </div>
        <p class="text-xs text-n-slate-10 mb-6">
          outro parceiro, outra unidade, outra origem de pacientes: dê um nome e
          entregue a ela os funis e as caixas dela.
        </p>

        <div v-if="form" class="cv-sub p-5 sm:p-6">
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div>
              <p
                class="text-[11px] font-semibold uppercase text-n-slate-9 mb-1.5"
              >
                Nome
              </p>
              <input
                v-model="form.name"
                class="cv-input w-full text-sm"
                maxlength="60"
                placeholder="ex.: Clínica parceira Zona Norte"
              />
            </div>
            <div>
              <p
                class="text-[11px] font-semibold uppercase text-n-slate-9 mb-1.5"
              >
                Cor
              </p>
              <div class="flex gap-2 flex-wrap">
                <button
                  v-for="c in COLORS"
                  :key="c"
                  class="w-8 h-8 rounded-full flex items-center justify-center"
                  :style="{ background: c }"
                  :title="c"
                  @click="form.color = c"
                >
                  <span
                    v-if="form.color === c"
                    class="i-lucide-check text-white text-sm"
                  />
                </button>
              </div>
            </div>
          </div>

          <template v-if="!form.fixed">
            <p
              class="text-[11px] font-semibold uppercase text-n-slate-9 mb-1.5"
            >
              Funis desta fonte
            </p>
            <div class="flex flex-wrap gap-1.5 mb-5">
              <button
                v-for="id in form.pipelines"
                :key="id"
                class="cv-chip"
                :class="{ 'cv-chip-on': form.pipeline_ids.includes(id) }"
                @click="toggle('pipeline_ids', id)"
              >
                {{ nameOf('pipelines', id) }}
              </button>
              <span
                v-if="!form.pipelines.length"
                class="text-xs text-n-slate-9"
              >
                nenhum funil livre — crie o funil desta fonte no CRM primeiro (o
                funil principal da casa não muda de dono)
              </span>
            </div>
            <p
              class="text-[11px] font-semibold uppercase text-n-slate-9 mb-1.5"
            >
              Caixas de entrada desta fonte
            </p>
            <div class="flex flex-wrap gap-1.5 mb-5">
              <button
                v-for="id in form.inboxes"
                :key="id"
                class="cv-chip"
                :class="{ 'cv-chip-on': form.inbox_ids.includes(id) }"
                @click="toggle('inbox_ids', id)"
              >
                {{ nameOf('inboxes', id) }}
              </button>
            </div>
            <p class="text-[11px] text-n-slate-9 mb-5">
              ao salvar, os cards e as entradas em coluna dos funis escolhidos
              passam a ser desta fonte. O paciente não muda: a fonte dele é a da
              primeira vez em que apareceu.
            </p>
          </template>
          <p v-else class="text-[11px] text-n-slate-9 mb-5">
            o ambiente desta fonte não se escolhe aqui — só o nome e a cor.
          </p>

          <div class="flex items-center gap-2">
            <button
              class="cv-btn cv-blue cv-btn-sm"
              :disabled="isWorking"
              @click="save"
            >
              <span class="i-lucide-check text-xs" />
              {{ isWorking ? 'Salvando…' : 'Salvar fonte' }}
            </button>
            <button class="cv-btn cv-btn-ghost cv-btn-sm" @click="form = null">
              Cancelar
            </button>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
