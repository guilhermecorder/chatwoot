<script setup>
// 💰 Configurações → Tabela de preços (pedido 17/07)
// UM lugar para os preços oficiais da clínica: preço atual e preço
// promocional por procedimento. Vale no Espaço do Paciente (orçamento de
// indicação) e nos prompts dos agentes de IA ({{TABELA_DE_PRECOS}}).
import { ref, computed, onMounted, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import {
  PRICE_UNITS,
  isPerEyeLocked,
  rowProblem,
  tableProblems,
  rowsToSave,
} from './priceRows';

const store = useStore();
// 🔐 rodada 334: quem só VÊ a tabela lê os preços; editar = linhas e salvar
const { canEdit } = useCevicoAccess();
const canEditPrices = computed(() => canEdit('configuracoes.precos'));
const crmSettings = useMapGetter('crm/getSettings');

const rows = ref([]);
const isLoading = ref(true);
const isSaving = ref(false);
const updatedAt = ref(null);
const customized = ref(false);

const hydrate = () => {
  const table = crmSettings.value?.price_table;
  rows.value = (table?.items || []).map(item => ({
    ...item,
    unit: item.unit || '',
  }));
  updatedAt.value = table?.updated_at || null;
  customized.value = table?.customized === true;
};

onMounted(async () => {
  try {
    await store.dispatch('crm/fetchSettings');
    hydrate();
  } catch {
    useAlert('Não consegui carregar a tabela de preços.');
  } finally {
    isLoading.value = false;
  }
});

const groups = computed(() => [
  ...new Set(rows.value.map(r => r.group).filter(Boolean)),
]);

const addRow = () => {
  const group = groups.value[groups.value.length - 1] || 'Outros';
  // 🔢 Rodada 5 (#401): a linha nova herda a unidade das outras do mesmo grupo
  const sameGroup = rows.value.filter(r => r.group === group);
  rows.value.push({
    group,
    name: '',
    price: null,
    promo_price: null,
    unit: sameGroup[sameGroup.length - 1]?.unit || '',
  });
};

// lente fácica (Artisan) é sempre por olho — o seletor fica travado
watch(
  rows,
  list =>
    list.forEach(row => {
      if (isPerEyeLocked(row) && row.unit !== 'por_olho') row.unit = 'por_olho';
    }),
  { deep: true }
);

const removeRow = index => rows.value.splice(index, 1);

const save = async () => {
  // 🔢 Rodada 5 (#401): nada de R$ 0, promoção estranha ou linha sem unidade
  const problems = tableProblems(rows.value);
  if (problems.length) {
    useAlert(
      `Antes de salvar: ${problems.map(p => `${p.name} (${p.problem})`).join('; ')}.`
    );
    return;
  }
  isSaving.value = true;
  try {
    await CrmAPI.updatePriceTable(rowsToSave(rows.value));
    await store.dispatch('crm/fetchSettings');
    hydrate();
    useAlert('Tabela de preços salva! Telas e agentes de IA já usam os novos valores.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar a tabela.');
  } finally {
    isSaving.value = false;
  }
};

// token que os prompts usam para receber a tabela (mostrado na dica)
const PRICE_TOKEN = '{{TABELA_DE_PRECOS}}';

const fmtDate = iso =>
  iso
    ? new Date(iso).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : null;
</script>

<template>
  <div class="flex-1 overflow-y-auto p-6 max-w-3xl">
    <h1 class="text-lg font-semibold text-n-slate-12 flex items-center gap-2">
      <span class="i-lucide-badge-dollar-sign text-amber-500" />
      Tabela de preços
      <CevicoViewOnlyPill v-if="!canEditPrices" />
    </h1>
    <p class="text-sm text-n-slate-10 mt-1 mb-5">
      Os preços oficiais da clínica, num lugar só. Valem no
      <b>Espaço do Paciente</b> (orçamento de indicação) e nos
      <b>agentes de IA</b> que falam de valores. Preencher o preço promocional
      (menor que o normal) faz ele valer no lugar do preço normal. Toda linha
      precisa de preço e da <b>unidade</b> (por olho, dois olhos, por sessão ou
      único) — é assim que a IA passa o valor ao paciente.
    </p>

    <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

    <template v-else>
      <p v-if="!customized" class="text-xs rounded-xl border border-amber-500/40 bg-amber-500/10 text-n-slate-11 px-3 py-2 mb-4">
        Você ainda não salvou uma tabela própria — estes são os valores
        padrão (os mesmos dos prompts). Ajuste e salve para assumir o controle.
      </p>
      <p v-else-if="fmtDate(updatedAt)" class="text-[11px] text-n-slate-9 mb-4">
        última atualização: {{ fmtDate(updatedAt) }}
      </p>

      <!-- cabeçalho -->
      <div class="hidden sm:grid grid-cols-[1.2fr_1.4fr_6.5rem_6.5rem_7rem_2rem] gap-2 px-1 mb-1">
        <span class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9">Grupo</span>
        <span class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9">Procedimento</span>
        <span class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9">Preço (R$)</span>
        <span class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9">Promo (R$)</span>
        <span class="text-[10px] font-semibold uppercase tracking-wide text-n-slate-9">Unidade</span>
        <span />
      </div>

      <div class="space-y-1.5">
        <div
          v-for="(row, i) in rows"
          :key="i"
          class="grid grid-cols-2 sm:grid-cols-[1.2fr_1.4fr_6.5rem_6.5rem_7rem_2rem] gap-2 items-center rounded-xl border border-n-weak bg-n-solid-2 p-2"
        >
          <input
            v-model="row.group"
            list="cevico-price-groups"
            placeholder="Grupo"
            class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
            style="margin-bottom: 0"
          />
          <input
            v-model="row.name"
            placeholder="Nome do procedimento"
            class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-xs text-n-slate-12"
            style="margin-bottom: 0"
          />
          <input
            v-model="row.price"
            type="text"
            inputmode="decimal"
            placeholder="preço"
            class="h-8 rounded-lg border bg-n-solid-1 px-2 text-xs font-bold text-n-slate-12"
            :class="
              rowProblem(row) === 'falta o preço'
                ? 'border-red-500'
                : 'border-n-weak'
            "
            style="margin-bottom: 0"
          />
          <input
            v-model="row.promo_price"
            type="text"
            inputmode="decimal"
            placeholder="—"
            class="h-8 rounded-lg border px-2 text-xs font-bold"
            :class="row.promo_price ? 'border-green-600/50 bg-green-600/10 text-green-700' : 'border-n-weak bg-n-solid-1 text-n-slate-12'"
            style="margin-bottom: 0"
          />
          <!-- 🔢 Rodada 5 (#401): unidade do valor é campo da linha -->
          <select
            v-model="row.unit"
            :disabled="!canEditPrices || isPerEyeLocked(row)"
            :title="
              isPerEyeLocked(row)
                ? 'Lente fácica é sempre por olho'
                : 'Unidade do valor'
            "
            class="h-8 rounded-lg border bg-n-solid-1 px-2 text-xs text-n-slate-12"
            :class="
              rowProblem(row) === 'escolha a unidade'
                ? 'border-red-500'
                : 'border-n-weak'
            "
            style="margin-bottom: 0"
          >
            <option value="" disabled>unidade…</option>
            <option v-for="u in PRICE_UNITS" :key="u.value" :value="u.value">
              {{ u.label }}
            </option>
          </select>
          <button
            v-if="canEditPrices"
            class="i-lucide-trash-2 text-n-slate-9 hover:text-red-500 text-sm justify-self-center"
            title="Remover linha"
            @click="removeRow(i)"
          />
        </div>
      </div>
      <datalist id="cevico-price-groups">
        <option v-for="g in groups" :key="g" :value="g" />
      </datalist>

      <div v-if="canEditPrices" class="flex items-center gap-2 mt-4">
        <button
          class="px-3 h-9 rounded-xl border border-n-weak text-xs font-medium text-n-slate-11 hover:bg-n-alpha-1"
          @click="addRow"
        >
          + Adicionar procedimento
        </button>
        <button
          class="px-4 h-9 rounded-xl text-xs font-bold text-white shadow-sm disabled:opacity-60 ml-auto"
          style="background: linear-gradient(135deg, #B8860B, #D4A017)"
          :disabled="isSaving"
          @click="save"
        >
          {{ isSaving ? 'Salvando…' : 'Salvar tabela' }}
        </button>
      </div>

      <p class="text-[11px] text-n-slate-9 mt-4">
        💡 Nos prompts personalizados dos agentes, escreva
        <code class="text-[10px] bg-n-alpha-1 rounded px-1">{{ PRICE_TOKEN }}</code>
        onde os preços devem entrar — o sistema substitui pela tabela na hora.
      </p>
    </template>
  </div>
</template>
