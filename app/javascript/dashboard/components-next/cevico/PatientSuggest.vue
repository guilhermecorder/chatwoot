<script setup>
// 🔎 ITEM 346 (16/10): a busca que PUXA O PACIENTE, em todas as barras de
// pesquisa. Pedido dele: "na barra de pesquisa ele puxe os contatos, para que
// quando existir, seja possível já selecionar a pessoa e fazer tudo no
// contato dela". Fica embaixo da barra (o pai precisa de `relative`).
//   action="open" (padrão) → clicar abre o Espaço do Paciente
//   action="pick"          → clicar devolve o paciente (@pick) para o formulário
import { ref, watch, computed, onBeforeUnmount } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import CrmAPI from 'dashboard/api/crm';
import { frontendURL } from 'dashboard/helper/URLHelper';

const props = defineProps({
  query: { type: String, default: '' },
  // a barra está em foco (o pai controla; some ao sair)
  active: { type: Boolean, default: true },
  action: { type: String, default: 'open' },
  minChars: { type: Number, default: 2 },
  excludeId: { type: [Number, String], default: null },
  title: { type: String, default: 'Pacientes no cadastro' },
});
const emit = defineEmits(['pick', 'results']);

const route = useRoute();
const router = useRouter();
const results = ref([]);
const loading = ref(false);
const highlighted = ref(0);
let timer = null;
let controller = null;

const visible = computed(
  () =>
    props.active &&
    props.query.trim().length >= props.minChars &&
    (results.value.length > 0 || loading.value)
);

const search = async q => {
  controller?.abort();
  controller = new AbortController();
  loading.value = true;
  try {
    const { data } = await CrmAPI.searchPatients(q, {
      signal: controller.signal,
    });
    results.value = (data?.payload || []).filter(
      p => String(p.id) !== String(props.excludeId)
    );
    highlighted.value = 0;
    emit('results', results.value);
  } catch (e) {
    if (e?.name !== 'CanceledError' && e?.name !== 'AbortError') {
      results.value = [];
    }
  } finally {
    loading.value = false;
  }
};

watch(
  () => props.query,
  value => {
    clearTimeout(timer);
    const q = (value || '').trim();
    if (q.length < props.minChars) {
      results.value = [];
      return;
    }
    timer = setTimeout(() => search(q), 250);
  },
  { immediate: true }
);

onBeforeUnmount(() => {
  clearTimeout(timer);
  controller?.abort();
});

const accountId = computed(() => route.params.accountId);

const choose = patient => {
  if (props.action === 'pick') {
    emit('pick', patient);
    return;
  }
  router.push(frontendURL(`accounts/${accountId.value}/patient/${patient.id}`));
};

// teclado: o pai repassa as setas/Enter/Esc da barra
const onKey = event => {
  if (!visible.value || !results.value.length) return false;
  if (event.key === 'ArrowDown') {
    highlighted.value = (highlighted.value + 1) % results.value.length;
  } else if (event.key === 'ArrowUp') {
    highlighted.value =
      (highlighted.value - 1 + results.value.length) % results.value.length;
  } else if (event.key === 'Enter') {
    choose(results.value[highlighted.value]);
  } else {
    return false;
  }
  event.preventDefault();
  return true;
};
defineExpose({ onKey, results });

const fmtWhen = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  const day = d.toLocaleDateString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
  });
  const hour = d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${day.replace('.', '')} ${hour}`;
};
const TYPE_LABEL = { consulta: 'Consulta', cirurgia: 'Cirurgia' };
const appointmentLine = p => {
  const a = p.next_appointment || p.last_appointment;
  if (!a) return '';
  const kind = TYPE_LABEL[a.type] || 'Agendamento';
  const when = p.next_appointment ? 'próx.' : 'última';
  return `${when}: ${kind} ${fmtWhen(a.due_at)}`;
};
</script>

<template>
  <div
    v-if="visible"
    class="absolute left-0 right-0 top-full mt-1.5 z-50 p-2 min-w-[22rem] max-w-[90vw] max-h-[420px] overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-2 shadow-xl"
    @mousedown.prevent
  >
    <p
      class="px-2 pt-1 pb-1.5 text-[10px] font-bold uppercase tracking-wide text-n-slate-10 flex items-center gap-1.5"
    >
      <span class="i-lucide-users-round text-xs" />
      {{ title }}
      <span
        v-if="loading"
        class="i-lucide-loader-circle animate-spin text-xs ml-auto"
      />
    </p>
    <button
      v-for="(p, i) in results"
      :key="p.id"
      class="w-full text-left rounded-xl px-2.5 py-2 flex items-start gap-2.5 transition-colors"
      :class="i === highlighted ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
      @mouseenter="highlighted = i"
      @click="choose(p)"
    >
      <span
        class="flex-shrink-0 w-8 h-8 rounded-lg grid place-items-center bg-n-alpha-2 text-n-slate-11"
      >
        <span class="i-lucide-user-round text-sm" />
      </span>
      <span class="min-w-0 flex-1">
        <span class="flex items-center gap-1.5 flex-wrap">
          <span class="font-semibold text-[13px] text-n-slate-12 truncate">
            {{ p.name || 'Sem nome' }}
          </span>
          <span
            class="rounded-full px-1.5 text-[10px] font-semibold"
            :class="
              p.origin === 'oftalmofacil'
                ? 'bg-n-teal-3 text-n-teal-11'
                : 'bg-n-blue-3 text-n-blue-11'
            "
          >
            {{ p.origin === 'oftalmofacil' ? 'Oftalmofácil' : 'CEVICO' }}
          </span>
          <span
            v-if="p.review"
            class="rounded-full px-1.5 text-[10px] font-semibold bg-n-amber-3 text-n-amber-11"
            title="Cadastro com alerta de conferência (possível duplicado, nome diferente…)"
          >
            ⚠️ conferir
          </span>
        </span>
        <span class="block text-[11.5px] text-n-slate-11 mt-0.5">
          {{ p.phone_number || p.email || 'sem telefone' }}
          <template v-if="p.scheduled_by">
            · agendado por {{ p.scheduled_by }}
          </template>
        </span>
        <span
          v-if="p.stage || appointmentLine(p)"
          class="flex items-center gap-1.5 flex-wrap mt-0.5 text-[11px] text-n-slate-10"
        >
          <span v-if="p.stage" class="flex items-center gap-1">
            <span
              class="w-2 h-2 rounded-full inline-block"
              :style="{ background: p.stage.color || '#94a3b8' }"
            />
            {{ p.stage.name }}
          </span>
          <span v-if="p.stage && appointmentLine(p)">·</span>
          <span v-if="appointmentLine(p)">{{ appointmentLine(p) }}</span>
        </span>
      </span>
      <span
        class="text-[11px] font-semibold text-n-blue-11 flex-shrink-0 self-center"
      >
        {{ action === 'pick' ? 'Usar' : 'Abrir' }}
      </span>
    </button>
  </div>
</template>
