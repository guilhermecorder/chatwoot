<script setup>
// ✍️ 18/11/2026: aba ESCREVER do Banco de Ganchos. Guilherme: "quero ter a
// liberdade e quero ter a referência". Dois jeitos de escrever a copy ou o
// roteiro, com o MODELO sempre à vista:
//   Livre      = uma página em branco, o modelo fica ao lado como referência;
//   Com modelo = um campo por parte do modelo, na ordem.
// Salva nas Criações (mesma tabela da aba Criar): partes.modelo diz de onde
// veio ('livre' | chave do modelo) e partes.blocos guarda cada parte.
import { ref, computed, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import CbSanfona from './CbSanfona.vue';
import { norm } from './cbMeta';
import {
  MODELOS,
  MODELO,
  PALAVRAS_POR_SEGUNDO,
  contarPalavras,
  bibliotecaDe,
} from './cbRoteiros';

const props = defineProps({
  blocks: { type: Array, required: true },
  podeEditar: { type: Boolean, default: false },
  empresa: { type: Object, default: () => ({ clinica: true }) },
});
const emit = defineEmits(['draftSalvo', 'draftAtualizado']);

const FORMATOS = [
  { key: 'reels', label: 'Vídeo' },
  { key: 'anuncio', label: 'Anúncio' },
  { key: 'carrossel', label: 'Carrossel' },
  { key: 'post', label: 'Post' },
];

const clinica = computed(() => props.empresa?.clinica !== false);
const biblioteca = computed(() => bibliotecaDe(props.empresa));

const modo = ref('livre'); // livre | guiado
const modeloKey = ref('explosivo');
const modelo = computed(() => MODELO[modeloKey.value] || MODELOS[0]);
const titulo = ref('');
const tema = ref('');
const formato = ref('reels');
const livre = ref('');
// um texto por parte, por modelo: trocar de modelo não apaga o que foi escrito
const campos = ref({});
const draftId = ref(null);
const salvando = ref(false);
const refAberta = ref({});
const livreEl = ref(null);

const campo = k => campos.value[modeloKey.value]?.[k] || '';
const setCampo = (k, v) => {
  campos.value = {
    ...campos.value,
    [modeloKey.value]: { ...(campos.value[modeloKey.value] || {}), [k]: v },
  };
};

const textoFinal = computed(() => {
  if (modo.value === 'livre') return livre.value.trim();
  return modelo.value.partes
    .map(p => campo(p.key).trim())
    .filter(Boolean)
    .join('\n\n');
});
const palavras = computed(() => contarPalavras(textoFinal.value));
const segundos = computed(() =>
  Math.round(palavras.value / PALAVRAS_POR_SEGUNDO)
);
const tempoFalado = computed(() => {
  const s = segundos.value;
  if (s < 60) return `${s} s`;
  return `${Math.floor(s / 60)} min ${String(s % 60).padStart(2, '0')} s`;
});
const partesFeitas = computed(
  () => modelo.value.partes.filter(p => campo(p.key).trim()).length
);

const toggleRef = k => {
  refAberta.value = { ...refAberta.value, [k]: !refAberta.value[k] };
};

// põe um texto na página livre, onde o cursor está
const inserirNoLivre = async texto => {
  const el = livreEl.value;
  const atual = livre.value;
  const pos = el && document.activeElement === el ? el.selectionStart : null;
  if (pos === null || pos === undefined) {
    livre.value = atual ? `${atual.replace(/\s+$/, '')}\n\n${texto}` : texto;
  } else {
    livre.value = `${atual.slice(0, pos)}${texto}${atual.slice(pos)}`;
  }
  await nextTick();
  el?.focus();
};

const usarMolde = p => {
  if (modo.value === 'livre') {
    inserirNoLivre(p.molde);
    return;
  }
  const atual = campo(p.key).trim();
  setCampo(p.key, atual ? `${atual}\n${p.molde}` : p.molde);
};

const copiar = async texto => {
  try {
    await navigator.clipboard.writeText(texto);
    useAlert('Copiado ✓');
  } catch {
    useAlert('Não deu para copiar. Selecione o texto e copie à mão.');
  }
};

// ── ganchos do banco, para puxar sem sair da página ──
const buscaGancho = ref('');
const ganchosAchados = computed(() => {
  const q = norm(buscaGancho.value).trim();
  const todos = props.blocks.filter(
    b => b.kind === 'gancho' && b.saude !== 'evitar'
  );
  const lista = q
    ? todos.filter(b => norm(`${b.texto} ${b.exemplo}`).includes(q))
    : todos.filter(b => b.favorito || b.usos > 0);
  return [...lista]
    .sort((a, b) => b.favorito - a.favorito || b.usos - a.usos)
    .slice(0, 6);
});
// o gancho do banco que entrou: conta o uso e vai junto na criação
// (partes.gancho), para o ranking saber de que TIPO de gancho é o anúncio
const ganchoDoBanco = ref(null);
const usarGancho = b => {
  ganchoDoBanco.value = { block_id: b.id, tipo: b.categoria, modelo: b.texto };
  b.usos += 1;
  CrmAPI.useCopyBlock(b.id).catch(() => {});
  if (modo.value === 'livre') {
    inserirNoLivre(b.texto);
    return;
  }
  const primeira = modelo.value.partes[0];
  setCampo(primeira.key, b.texto);
  useAlert(`Gancho colocado em "${primeira.nome}".`);
};

const novo = () => {
  titulo.value = '';
  tema.value = '';
  livre.value = '';
  campos.value = {};
  draftId.value = null;
  ganchoDoBanco.value = null;
};

const salvar = async () => {
  if (!props.podeEditar || salvando.value) return;
  const texto = textoFinal.value;
  if (!texto) {
    useAlert('Escreva alguma coisa antes de salvar.');
    return;
  }
  const nome =
    titulo.value.trim() || texto.split('\n')[0].slice(0, 70) || 'Sem título';
  const payload = {
    titulo: nome,
    tema: tema.value.trim() || null,
    formato: formato.value,
    texto_final: texto,
    partes: {
      modelo: modo.value === 'livre' ? 'livre' : modeloKey.value,
      referencia: modeloKey.value,
      ...(ganchoDoBanco.value ? { gancho: ganchoDoBanco.value } : {}),
      blocos:
        modo.value === 'livre'
          ? { livre: livre.value }
          : { ...(campos.value[modeloKey.value] || {}) },
    },
  };
  salvando.value = true;
  try {
    if (draftId.value) {
      const { data } = await CrmAPI.updateCopyDraft(draftId.value, payload);
      emit('draftAtualizado', data);
    } else {
      const { data } = await CrmAPI.createCopyDraft(payload);
      draftId.value = data.id;
      emit('draftSalvo', data);
    }
    titulo.value = nome;
    useAlert('Salvo nas Criações ✓');
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para salvar.');
  } finally {
    salvando.value = false;
  }
};

// reabrir uma criação escrita aqui (CopyBank chama pelo ref)
const carregar = d => {
  const p = d.partes || {};
  draftId.value = d.id;
  ganchoDoBanco.value = p.gancho?.block_id ? p.gancho : null;
  titulo.value = d.titulo || '';
  tema.value = d.tema || '';
  formato.value = d.formato || 'reels';
  if (MODELO[p.referencia]) modeloKey.value = p.referencia;
  if (p.modelo === 'livre') {
    modo.value = 'livre';
    livre.value = p.blocos?.livre || d.texto_final || '';
  } else {
    modo.value = 'guiado';
    if (MODELO[p.modelo]) modeloKey.value = p.modelo;
    campos.value = {
      ...campos.value,
      [modeloKey.value]: { ...(p.blocos || {}) },
    };
  }
};
defineExpose({ carregar });
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div>
    <!-- como escrever + sobre o quê -->
    <div class="cv-sub p-4 sm:p-5 mb-5 flex flex-col gap-4">
      <div class="flex items-center gap-3 flex-wrap">
        <div class="cv-seg">
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': modo === 'livre' }"
            @click="modo = 'livre'"
          >
            <span class="i-lucide-pen-line" />
            Livre
          </button>
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': modo === 'guiado' }"
            @click="modo = 'guiado'"
          >
            <span class="i-lucide-list-ordered" />
            Com modelo
          </button>
        </div>
        <p class="text-sm text-n-slate-11 flex-1 min-w-[12rem]">
          {{
            modo === 'livre'
              ? 'Página em branco. O modelo fica ao lado, só para consultar.'
              : 'Um campo para cada parte do modelo, na ordem.'
          }}
        </p>
        <button
          v-if="draftId || textoFinal"
          class="cv-btn cv-btn-sm cv-btn-ghost"
          @click="novo"
        >
          <span class="i-lucide-plus" />
          Nova
        </button>
      </div>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div>
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2"
          >
            Nome
          </p>
          <input
            v-model="titulo"
            class="cv-input w-full"
            placeholder="ex.: quem não pode instalar"
          />
        </div>
        <div>
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2"
          >
            Sobre o quê
          </p>
          <input
            v-model="tema"
            class="cv-input w-full"
            :placeholder="`ex.: o principal assunto da ${empresa?.nome || 'empresa'}`"
          />
        </div>
        <div>
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2"
          >
            Formato
          </p>
          <div class="flex flex-wrap gap-2">
            <button
              v-for="f in FORMATOS"
              :key="f.key"
              class="cv-chip"
              :class="{ 'cv-chip-on': formato === f.key }"
              @click="formato = f.key"
            >
              {{ f.label }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- o modelo (referência ou campos) -->
    <p
      class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2"
    >
      {{ modo === 'livre' ? 'Modelo de referência' : 'Modelo' }}
    </p>
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
      <button
        v-for="m in MODELOS"
        :key="m.key"
        type="button"
        class="cv-sub p-4 flex items-center gap-3 text-left min-w-0 border-2"
        :style="{
          borderColor: modeloKey === m.key ? m.color : 'transparent',
        }"
        @click="modeloKey = m.key"
      >
        <span
          class="w-10 h-10 rounded-[13px] flex-shrink-0 flex items-center justify-center text-white"
          :style="{ background: m.color }"
        >
          <span class="text-xl" :class="m.icon" />
        </span>
        <span class="min-w-0">
          <span class="block font-bold text-n-slate-12 leading-tight">
            {{ m.nome }}
          </span>
          <span class="block text-xs text-n-slate-10 mt-0.5">{{ m.sub }}</span>
        </span>
      </button>
    </div>

    <div class="grid grid-cols-1 xl:grid-cols-5 gap-6">
      <!-- ESCREVER -->
      <div class="xl:col-span-3 min-w-0">
        <div v-if="modo === 'livre'" class="cv-sub p-4 sm:p-5">
          <textarea
            ref="livreEl"
            v-model="livre"
            rows="20"
            class="cv-input w-full !h-auto py-3 text-base leading-relaxed"
            placeholder="Escreva a copy ou o roteiro do seu jeito."
          />
        </div>

        <template v-else>
          <div
            v-for="(p, i) in modelo.partes"
            :key="`${modelo.key}-${p.key}`"
            class="cv-sub p-4 sm:p-5 mb-4"
          >
            <div class="flex items-center gap-2 flex-wrap mb-2">
              <span
                class="w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-white text-sm font-bold"
                :style="{ background: modelo.color }"
              >
                <span v-if="campo(p.key).trim()" class="i-lucide-check" />
                <template v-else>{{ i + 1 }}</template>
              </span>
              <p class="font-bold text-n-slate-12 flex-1 min-w-0">
                {{ p.nome }}
              </p>
              <span
                class="text-xs px-2 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-11 font-semibold"
              >
                {{ p.tempo }}
              </span>
            </div>
            <p class="text-sm text-n-slate-11 mb-3">{{ p.faz }}</p>
            <textarea
              :value="campo(p.key)"
              :rows="p.linhas || 3"
              class="cv-input w-full !h-auto py-2 text-base leading-relaxed"
              :placeholder="p.molde"
              @input="setCampo(p.key, $event.target.value)"
            />
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost mt-2"
              @click="usarMolde(p)"
            >
              <span class="i-lucide-text-cursor-input" />
              Começar pela frase-molde
            </button>
          </div>
        </template>

        <!-- contagem + salvar -->
        <div
          class="cv-sub p-4 sm:p-5 mt-4 flex items-center gap-x-6 gap-y-3 flex-wrap"
        >
          <div>
            <p class="text-2xl font-bold text-n-slate-12 leading-none">
              {{ palavras }}
            </p>
            <p class="text-xs text-n-slate-10 mt-1">palavras</p>
          </div>
          <div>
            <p class="text-2xl font-bold text-n-slate-12 leading-none">
              {{ tempoFalado }}
            </p>
            <p class="text-xs text-n-slate-10 mt-1">falando</p>
          </div>
          <div v-if="modo === 'guiado'">
            <p class="text-2xl font-bold text-n-slate-12 leading-none">
              {{ `${partesFeitas} de ${modelo.partes.length}` }}
            </p>
            <p class="text-xs text-n-slate-10 mt-1">partes</p>
          </div>
          <div class="flex flex-wrap gap-2 ml-auto">
            <button
              class="cv-btn cv-btn-ghost"
              :disabled="!textoFinal"
              @click="copiar(textoFinal)"
            >
              <span class="i-lucide-copy" />
              Copiar tudo
            </button>
            <button
              v-if="podeEditar"
              class="cv-btn cv-blue"
              :disabled="!textoFinal || salvando"
              @click="salvar"
            >
              <span class="i-lucide-save" />
              {{ draftId ? 'Salvar alterações' : 'Salvar nas Criações' }}
            </button>
          </div>
        </div>
      </div>

      <!-- REFERÊNCIA -->
      <div class="xl:col-span-2 min-w-0">
        <div class="flex items-center gap-2 flex-wrap mb-3">
          <span class="i-lucide-book-marked text-n-slate-10" />
          <p class="font-bold text-n-slate-12">{{ modelo.nome }}</p>
          <span class="text-xs text-n-slate-10">{{ modelo.origem }}</span>
        </div>
        <CbSanfona
          v-for="(p, i) in modelo.partes"
          :key="`ref-${modelo.key}-${p.key}`"
          size="sm"
          :open="!!refAberta[`${modelo.key}-${p.key}`]"
          :title="`${i + 1} · ${p.nome}`"
          :count="p.tempo"
          :color="modelo.color"
          icon="i-lucide-quote"
          :desc="p.faz"
          :summary="p.faz"
          @toggle="toggleRef(`${modelo.key}-${p.key}`)"
        >
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-1"
          >
            Frase-molde
          </p>
          <p
            class="text-sm text-n-slate-12 whitespace-pre-line rounded-xl bg-n-alpha-2 p-3"
          >
            {{ p.molde }}
          </p>
          <template v-if="clinica && p.exemplo">
            <p
              class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mt-3 mb-1"
            >
              Exemplo da casa
            </p>
            <p class="text-sm text-n-slate-11">{{ p.exemplo }}</p>
          </template>
          <p v-if="p.dica" class="text-sm text-n-slate-11 mt-3">
            {{ p.dica }}
          </p>
          <div class="flex flex-wrap gap-2 mt-3">
            <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="usarMolde(p)">
              <span class="i-lucide-arrow-left-to-line" />
              Usar no texto
            </button>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost"
              @click="copiar(p.molde)"
            >
              <span class="i-lucide-copy" />
              Copiar
            </button>
          </div>
        </CbSanfona>

        <!-- ganchos do banco -->
        <div class="cv-sub p-4 mt-5">
          <div class="flex items-center gap-2 mb-3">
            <span class="i-lucide-anchor text-n-slate-10" />
            <p class="font-bold text-n-slate-12">Ganchos do banco</p>
          </div>
          <input
            v-model="buscaGancho"
            class="cv-input w-full mb-3"
            placeholder="Buscar um gancho…"
          />
          <p v-if="!ganchosAchados.length" class="text-sm text-n-slate-10">
            {{
              buscaGancho
                ? 'Nenhum gancho com essa palavra.'
                : 'Digite uma palavra para buscar. Seus favoritos e os mais usados aparecem aqui.'
            }}
          </p>
          <div
            v-for="b in ganchosAchados"
            :key="b.id"
            class="flex items-start gap-2 py-2 border-t border-n-weak first:border-t-0"
          >
            <p class="text-sm text-n-slate-12 flex-1 min-w-0 break-words">
              {{ b.texto }}
            </p>
            <button
              class="cv-btn cv-btn-sm cv-btn-ghost flex-shrink-0"
              @click="usarGancho(b)"
            >
              Usar
            </button>
          </div>
        </div>

        <!-- pesquisas do negócio -->
        <a
          v-if="biblioteca"
          :href="biblioteca"
          target="_blank"
          rel="noopener noreferrer"
          class="cv-sub p-4 mt-5 flex items-center gap-3 min-w-0"
        >
          <span
            class="w-10 h-10 rounded-[13px] flex-shrink-0 flex items-center justify-center text-white bg-[#0891b2]"
          >
            <span class="i-lucide-search text-xl" />
          </span>
          <span class="min-w-0 flex-1">
            <span class="block font-bold text-n-slate-12 leading-tight">
              Pesquisas e materiais
            </span>
            <span class="block text-xs text-n-slate-10 mt-0.5">
              {{ `Biblioteca da ${empresa?.nome || 'empresa'}` }}
            </span>
          </span>
          <span class="i-lucide-external-link text-n-slate-10" />
        </a>
      </div>
    </div>
  </div>
</template>
