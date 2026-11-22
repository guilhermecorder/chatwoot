<script setup>
// 🧾 item 397 (18/11): "ENTENDER O PÚBLICO" — escolhe um formulário e
// "Puxar o que importa": a IA lê as respostas e devolve o que serve para
// escrever (público, números contados pelo sistema, dores/desejos/objeções
// com frequência, frases literais, palavras, ângulos com tipo de gancho).
// O que o time marca vira CONTEXTO da IA (v-model = lista de frases).
import { ref, computed, onMounted, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { TIPO } from './cbMeta';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
  podeEditar: { type: Boolean, default: false },
  formInicial: { type: [Number, String], default: null },
});
const emit = defineEmits(['update:modelValue', 'verTipo', 'usarGancho']);

const forms = ref([]);
const carregando = ref(true);
const formId = ref(null);
const puxando = ref(false);

const load = async () => {
  carregando.value = true;
  try {
    const { data } = await CrmAPI.getCopyBankForms();
    forms.value = data.forms || [];
    const inicial = forms.value.find(f => String(f.id) === String(props.formInicial));
    const comResposta = forms.value.find(f => f.respostas > 0);
    formId.value = (inicial || comResposta || forms.value[0])?.id || null;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para listar os formulários.');
  } finally {
    carregando.value = false;
  }
};
onMounted(load);
watch(
  () => props.formInicial,
  v => {
    if (v && forms.value.some(f => String(f.id) === String(v))) formId.value = Number(v);
  }
);

const form = computed(() => forms.value.find(f => f.id === formId.value));
const brief = computed(() => form.value?.brief || null);

const puxar = async () => {
  if (!form.value) return;
  puxando.value = true;
  try {
    const { data } = await CrmAPI.pullFormBrief(form.value.id);
    form.value.brief = data.brief;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não consegui ler o formulário agora.');
  } finally {
    puxando.value = false;
  }
};

// marcar = levar para a copy
const marcado = t => props.modelValue.includes(t);
const marcar = t => {
  const l = props.modelValue;
  emit('update:modelValue', marcado(t) ? l.filter(x => x !== t) : [...l, t]);
};
const GRUPOS = [
  { key: 'dores', label: 'Dores', prefixo: 'Dor', cor: '#DC2626' },
  { key: 'desejos', label: 'Desejos', prefixo: 'Desejo', cor: '#059669' },
  { key: 'objecoes', label: 'Objeções', prefixo: 'Objeção', cor: '#D97706' },
];
const itemTexto = (g, i) => `${g.prefixo}: ${i.texto}${i.frequencia ? ` (${i.frequencia})` : ''}`;
const fraseTexto = f => `Frase do público: "${f}"`;
const dado = (n, t) => `Dado: ${t.pct}% responderam "${t.opcao}" em "${n.pergunta}"`;
const marcarTudo = () => {
  if (!brief.value) return;
  const todos = [
    ...GRUPOS.flatMap(g => (brief.value[g.key] || []).slice(0, 3).map(i => itemTexto(g, i))),
    ...(brief.value.frases || []).slice(0, 4).map(fraseTexto),
  ];
  emit('update:modelValue', [...new Set([...props.modelValue, ...todos])]);
};
const fmtData = s => (s ? new Date(s).toLocaleString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' }) : '');
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div class="flex flex-col gap-5">
    <p v-if="carregando" class="text-sm text-n-slate-10">Carregando formulários…</p>
    <p v-else-if="!forms.length" class="text-sm text-n-slate-10">Nenhum formulário ainda. Crie um em CRM → Formulários.</p>

    <template v-else>
      <div class="flex flex-wrap items-center gap-3">
        <select v-model="formId" class="cv-input flex-1 min-w-[220px]">
          <option v-for="f in forms" :key="f.id" :value="f.id">{{ `${f.name} · ${f.respostas} respostas` }}</option>
        </select>
        <button class="cv-btn cv-blue" :disabled="!form || !form.respostas || puxando || !podeEditar" @click="puxar">
          <span class="i-lucide-sparkles" />
          {{ puxando ? 'Lendo as respostas…' : brief ? 'Puxar de novo' : 'Puxar o que importa' }}
        </button>
      </div>
      <p v-if="form && !form.respostas" class="text-sm text-n-slate-10">Este formulário ainda não tem respostas.</p>
      <p v-else-if="brief" class="text-xs text-n-slate-10">
        {{ `Leitura de ${brief.respostas} respostas · ${fmtData(brief.generated_at)} · clique no que quer levar para a copy` }}
      </p>

      <template v-if="brief">
        <div class="rounded-2xl bg-n-alpha-1 p-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-1">Quem é o público</p>
          <p class="text-[15px] text-n-slate-12 leading-relaxed">{{ brief.publico }}</p>
        </div>

        <!-- números contados pelo sistema -->
        <div v-if="brief.numeros?.length">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Números das respostas (contados pelo sistema)</p>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div v-for="n in brief.numeros" :key="n.pergunta" class="rounded-xl bg-n-alpha-1 p-3 min-w-0">
              <p class="text-sm font-semibold text-n-slate-12 break-words">{{ n.pergunta }}</p>
              <button
                v-for="t in n.top"
                :key="t.opcao"
                class="w-full flex items-center gap-2 mt-2 text-left"
                :title="'Levar para a copy'"
                @click="marcar(dado(n, t))"
              >
                <span class="text-xs font-bold w-10 text-right text-[#2563eb]">{{ `${t.pct}%` }}</span>
                <span class="flex-1 h-2 rounded-full bg-n-alpha-2 overflow-hidden">
                  <span class="block h-full rounded-full bg-[#2563eb]" :style="{ width: `${t.pct}%` }" />
                </span>
                <span class="text-xs text-n-slate-11 flex-[2] min-w-0 truncate" :class="{ 'font-bold text-n-slate-12': marcado(dado(n, t)) }">
                  {{ t.opcao }}
                </span>
              </button>
            </div>
          </div>
        </div>

        <!-- dores, desejos, objeções -->
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div v-for="g in GRUPOS" :key="g.key">
            <p class="text-xs font-semibold uppercase tracking-wide mb-2" :style="{ color: g.cor }">{{ g.label }}</p>
            <div class="flex flex-col gap-2">
              <button
                v-for="i in brief[g.key] || []"
                :key="i.texto"
                class="text-left text-sm rounded-xl px-3 py-2 border transition-colors"
                :class="marcado(itemTexto(g, i)) ? 'border-[#2563eb] bg-[#2563eb14] text-n-slate-12' : 'border-n-weak text-n-slate-11 hover:border-n-slate-8'"
                @click="marcar(itemTexto(g, i))"
              >
                <span v-if="marcado(itemTexto(g, i))" class="i-lucide-check text-[#2563eb] mr-1" />
                {{ i.texto }}
                <span v-if="i.frequencia" class="text-xs text-n-slate-10 whitespace-nowrap">{{ ` · ${i.frequencia}` }}</span>
              </button>
            </div>
          </div>
        </div>

        <!-- frases literais e palavras -->
        <div v-if="brief.frases?.length">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Frases do público (do jeito que escreveram)</p>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
            <button
              v-for="f in brief.frases"
              :key="f"
              class="text-left text-sm italic rounded-xl px-3 py-2 border"
              :class="marcado(fraseTexto(f)) ? 'border-[#2563eb] bg-[#2563eb14] text-n-slate-12' : 'border-n-weak text-n-slate-11 hover:border-n-slate-8'"
              @click="marcar(fraseTexto(f))"
            >
              {{ `"${f}"` }}
            </button>
          </div>
        </div>
        <div v-if="brief.palavras?.length">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Palavras que eles usam</p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="w in brief.palavras"
              :key="w"
              class="cv-chip"
              :class="{ 'cv-chip-on': marcado(`Palavra do público: ${w}`) }"
              @click="marcar(`Palavra do público: ${w}`)"
            >
              {{ w }}
            </button>
          </div>
        </div>

        <!-- ângulos de narrativa -->
        <div v-if="brief.angulos?.length">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Ângulos de narrativa</p>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <div v-for="a in brief.angulos" :key="a.titulo" class="rounded-2xl border border-n-weak p-4 flex flex-col gap-2 min-w-0">
              <p class="font-bold text-n-slate-12">{{ a.titulo }}</p>
              <p class="text-sm text-n-slate-11">{{ a.porque }}</p>
              <p class="text-sm text-n-slate-12 italic">{{ `"${a.gancho_exemplo}"` }}</p>
              <div class="flex flex-wrap gap-2 mt-auto pt-1">
                <button class="cv-btn cv-btn-sm cv-blue" @click="emit('usarGancho', a.gancho_exemplo)">Usar este gancho</button>
                <button v-if="TIPO[a.tipo_gancho]" class="cv-btn cv-btn-sm cv-btn-ghost" @click="emit('verTipo', a.tipo_gancho)">
                  <span :class="TIPO[a.tipo_gancho].icon" />
                  {{ `Ver ganchos: ${TIPO[a.tipo_gancho].label}` }}
                </button>
                <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="marcar(`Ângulo escolhido: ${a.titulo} — ${a.porque}`)">
                  {{ marcado(`Ângulo escolhido: ${a.titulo} — ${a.porque}`) ? '✓ Ângulo na copy' : 'Levar o ângulo' }}
                </button>
              </div>
            </div>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-3">
          <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="marcarTudo">Levar o principal (3 de cada + 4 frases)</button>
          <button v-if="modelValue.length" class="cv-btn cv-btn-sm cv-btn-ghost" @click="emit('update:modelValue', [])">Desmarcar tudo</button>
        </div>
      </template>
    </template>
  </div>
</template>
