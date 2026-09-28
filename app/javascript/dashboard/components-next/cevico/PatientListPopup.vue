<script setup>
// 👥 item 271 (28/09): "nenhum número sem nome atrás" — popup com a LISTA de
// pacientes por trás de um indicador (card do Resumo, etapa de um funil…).
// Cada linha: nome, telefone, por onde chegou, quando, e um atalho para a
// conversa / Espaço do Paciente. Kit .cv-modal (o mesmo do resgate de perdas).
import { computed, onMounted, onBeforeUnmount, ref } from 'vue';
import { useRouter } from 'vue-router';
import { frontendURL } from 'dashboard/helper/URLHelper';

const props = defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  // [{ id, name, phone, origin, when, meta, conversation_id, contact_id }]
  people: { type: Array, default: () => [] },
  grad: { type: String, default: 'linear-gradient(135deg, #1d4ed8, #60a5fa)' },
  icon: { type: String, default: 'i-lucide-users' },
  emptyText: { type: String, default: 'Ninguém neste recorte.' },
  accountId: { type: [Number, String], required: true },
  // colunas extras à direita (função por pessoa → texto)
  right: { type: Function, default: null },
});
const emit = defineEmits(['close']);
const router = useRouter();
const q = ref('');

const list = computed(() => {
  const term = q.value.trim().toLowerCase();
  const digits = term.replace(/\D/g, '');
  if (!term) return props.people;
  return props.people.filter(
    p =>
      (p.name || '').toLowerCase().includes(term) ||
      (digits.length >= 3 &&
        (p.phone || '').replace(/\D/g, '').includes(digits))
  );
});

const initials = name =>
  (name || '?')
    .split(' ')
    .filter(Boolean)
    .map(w => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();

const fmtWhen = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    timeZone: 'America/Sao_Paulo',
  });
};

const open = p => {
  const cid = p.contact_id || p.id;
  if (p.conversation_id) {
    router.push(
      frontendURL(
        `accounts/${props.accountId}/conversations/${p.conversation_id}`
      )
    );
  } else if (cid && cid > 0) {
    router.push(frontendURL(`accounts/${props.accountId}/patient/${cid}`));
  }
  emit('close');
};

const onKey = e => {
  if (e.key === 'Escape') emit('close');
};
onMounted(() => window.addEventListener('keydown', onKey));
onBeforeUnmount(() => window.removeEventListener('keydown', onKey));

const copyList = async () => {
  const text = list.value
    .map(p =>
      [p.name, p.phone, p.origin, fmtWhen(p.when)].filter(Boolean).join(' · ')
    )
    .join('\n');
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // sem clipboard (http): silêncio — a lista continua na tela
  }
};
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page cv-overlay fixed inset-0 z-[80] flex items-center justify-center bg-black/50 p-4"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-lg max-h-[85vh] flex flex-col">
        <div class="cv-modal-head !p-5" :style="{ background: grad }">
          <div class="flex items-center gap-2 text-white/90">
            <span :class="icon" class="text-base" />
            <p class="text-sm font-bold flex-1">{{ title }}</p>
            <button
              class="cv-glass-btn cv-iconbtn"
              aria-label="Fechar"
              @click="emit('close')"
            >
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <p class="text-xs text-white/85 mt-1">
            {{ people.length }} paciente{{ people.length === 1 ? '' : 's' }}
            <template v-if="subtitle"> · {{ subtitle }}</template>
          </p>
          <div class="flex items-center gap-2 mt-3">
            <input
              v-model="q"
              type="search"
              placeholder="buscar por nome ou telefone"
              class="flex-1 min-w-0 rounded-lg px-3 py-1.5 text-xs bg-white/20 text-white placeholder:text-white/70 outline-none focus:bg-white/30"
            />
            <button
              class="cv-glass-btn text-[11px]"
              title="Copiar a lista (nome · telefone · origem · data)"
              @click="copyList"
            >
              <span class="i-lucide-copy text-xs" /> copiar
            </button>
          </div>
        </div>
        <div class="p-4 overflow-y-auto">
          <button
            v-for="p in list"
            :key="p.task_id || p.id"
            class="cv-sub cv-sub-hover w-full flex items-center gap-2.5 px-3 py-2 mb-1.5 text-left"
            :title="
              p.conversation_id
                ? 'Abrir a conversa'
                : 'Abrir o Espaço do Paciente'
            "
            @click="open(p)"
          >
            <span
              class="w-7 h-7 rounded-full flex items-center justify-center text-white text-[10px] font-bold flex-shrink-0"
              :style="{ background: grad }"
            >
              {{ initials(p.name) }}
            </span>
            <span class="flex-1 min-w-0">
              <span
                class="block text-xs font-semibold text-n-slate-12 truncate"
              >
                {{ p.name || 'Sem nome' }}
              </span>
              <span class="block text-[10px] text-n-slate-10 truncate">
                {{ p.phone || 'sem telefone' }}
                <template v-if="p.origin">
                  · chegou por {{ p.origin }}
                </template>
                <template v-if="p.meta"> · {{ p.meta }}</template>
              </span>
            </span>
            <span
              v-if="right && right(p)"
              class="text-[10px] font-semibold text-n-slate-11 flex-shrink-0 text-right"
              >{{ right(p) }}</span
            >
            <span
              v-else-if="p.when"
              class="text-[10px] text-n-slate-9 flex-shrink-0"
            >
              {{ fmtWhen(p.when) }}
            </span>
          </button>
          <p
            v-if="!list.length"
            class="text-center text-xs text-n-slate-10 py-6"
          >
            {{ emptyText }}
          </p>
        </div>
      </div>
    </div>
  </Teleport>
</template>
