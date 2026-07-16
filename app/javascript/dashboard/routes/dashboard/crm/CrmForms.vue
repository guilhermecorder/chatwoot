<script setup>
// Formulários CEVICO (ex: perguntas pré-operatórias): montagem das
// perguntas, dashboard de respostas e insights de marketing com IA.
import { ref, computed, onMounted } from 'vue';
import CrmAPI from 'dashboard/api/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAlert } from 'dashboard/composables';

const forms = ref([]);
const isLoading = ref(false);
const selectedFormId = ref(null);
const summary = ref(null);
const isLoadingSummary = ref(false);
const isGeneratingInsights = ref(false);

// builder
const showBuilder = ref(false);
const isSavingForm = ref(false);
const draft = ref(null);

const QUESTION_TYPES = [
  { value: 'choice', label: 'Escolha única' },
  { value: 'multi', label: 'Múltipla escolha' },
  { value: 'yesno', label: 'Sim / Não' },
  { value: 'scale', label: 'Escala 0 a 10' },
  { value: 'text', label: 'Resposta aberta' },
  { value: 'message', label: '💬 Card de mensagem (só frase + cor)' },
];

// cores do card de mensagem — mesmas chaves da paleta da página pública
const MESSAGE_COLORS = [
  { key: 'auto', label: 'Sequência', css: 'linear-gradient(135deg, #F97316, #EC4899, #8B5CF6)' },
  { key: 'navy', label: 'Marca', css: 'linear-gradient(135deg, #1E2B5B 55%, #D4AF37)' },
  { key: 'laranja', label: 'Laranja', css: '#F97316' },
  { key: 'turquesa', label: 'Turquesa', css: '#06B6D4' },
  { key: 'magenta', label: 'Magenta', css: '#EC4899' },
  { key: 'lima', label: 'Verde lima', css: '#84CC16' },
  { key: 'roxo', label: 'Roxo', css: '#8B5CF6' },
  { key: 'amarelo', label: 'Amarelo sol', css: '#FACC15' },
  { key: 'coral', label: 'Coral', css: '#FB923C' },
  { key: 'royal', label: 'Azul royal', css: '#2563EB' },
];

const selectedForm = computed(() =>
  forms.value.find(f => f.id === selectedFormId.value) || null
);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getForms();
    forms.value = data;
    if (!selectedFormId.value && data.length) selectForm(data[0].id);
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

const selectForm = async id => {
  selectedFormId.value = id;
  summary.value = null;
  isLoadingSummary.value = true;
  try {
    const { data } = await CrmAPI.getFormSummary(id);
    summary.value = data;
  } finally {
    isLoadingSummary.value = false;
  }
};

// ── Builder ────────────────────────────────────────────────
const newQuestion = () => ({
  id: `q${Date.now()}${Math.floor(Math.random() * 1000)}`,
  label: '',
  type: 'choice',
  options: [],
  optionsText: '',
  required: true,
  text: '',
  color: 'auto',
});

// Template estratégico: novo formulário já nasce com as perguntas que
// geram insight de marketing (dores, desejos, objeções, urgência) —
// é só editar o que quiser
const strategicTemplate = () => [
  { label: 'Há quanto tempo você usa óculos ou lentes de contato?', type: 'choice', required: true,
    optionsText: 'Menos de 5 anos\n5 a 15 anos\nMais de 15 anos\nDesde criança\nNão uso' },
  { label: 'O que você busca resolver?', type: 'choice', required: true,
    optionsText: 'Miopia\nAstigmatismo\nHipermetropia\nVista cansada (presbiopia)\nCatarata\nCeratocone\nNão sei meu grau exato' },
  { label: 'O que MAIS te incomoda no dia a dia com óculos/lentes?', type: 'multi', required: true,
    optionsText: 'Praticidade (acordar enxergando)\nEsporte e atividade física\nEstética / autoestima\nCusto de trocar óculos e lentes\nTrabalho / telas\nDirigir à noite\nEmbaçar (máscara, cozinha, chuva)' },
  { label: 'De 0 a 10, o quanto se livrar dos óculos mudaria sua vida?', type: 'scale', required: true },
  { label: 'Há quanto tempo você pensa em fazer essa cirurgia?', type: 'choice', required: true,
    optionsText: 'Comecei a pesquisar agora\nAlguns meses\nMais de 1 ano\nHá anos — sempre acabo adiando' },
  { label: 'O que te impediu de fazer antes?', type: 'multi', required: false,
    optionsText: 'Preço / momento financeiro\nMedo do procedimento\nFalta de tempo\nNão sabia que era possível pro meu caso\nInsegurança sobre o resultado\nNada me impediu, é a primeira vez que busco' },
  { label: 'Qual é o seu maior receio em relação à cirurgia?', type: 'text', required: false },
  { label: 'Como você imagina sua vida sem óculos? O que faria primeiro?', type: 'text', required: false },
  { label: 'Alguém próximo a você já fez cirurgia nos olhos?', type: 'choice', required: false,
    optionsText: 'Sim, e adorou o resultado\nSim, mas teve problema\nNão conheço ninguém que fez' },
  { label: 'Sobre o investimento na cirurgia, você diria que:', type: 'choice', required: false,
    optionsText: 'Já pesquisei e sei os valores\nTenho uma noção\nNão tenho ideia de quanto custa' },
  { label: 'Se a avaliação mostrar que você é candidato(a), quando gostaria de operar?', type: 'choice', required: true,
    optionsText: 'O quanto antes\nNos próximos 1 a 3 meses\nDaqui a 6 meses ou mais\nAinda estou só pesquisando' },
  { label: 'Tem algo sobre sua saúde (ocular ou geral) que devemos saber antes da consulta?', type: 'text', required: false },
].map(q => ({ ...newQuestion(), ...q }));

const openBuilder = form => {
  draft.value = form
    ? {
        id: form.id,
        name: form.name,
        intro_title: form.intro_title || '',
        intro_text: form.intro_text || '',
        thank_you_text: form.thank_you_text || '',
        active: form.active,
        questions: (form.questions || []).map(q => ({
          ...q,
          optionsText: (q.options || []).join('\n'),
          text: q.text || '',
          color: q.color || 'auto',
        })),
      }
    : {
        id: null,
        name: '',
        intro_title: 'Antes da sua consulta na CEVICO',
        intro_text: 'Suas respostas ajudam nossa equipe a preparar o melhor atendimento para você. Leva menos de 3 minutos.',
        thank_you_text: 'Recebemos suas respostas! Nossa equipe já está se preparando para te receber. Até breve! 💙',
        active: true,
        questions: strategicTemplate(),
      };
  showBuilder.value = true;
};

const moveQuestion = (i, dir) => {
  const qs = draft.value.questions;
  const j = i + dir;
  if (j < 0 || j >= qs.length) return;
  [qs[i], qs[j]] = [qs[j], qs[i]];
};

const needsOptions = type => ['choice', 'multi'].includes(type);

const saveForm = async () => {
  if (!draft.value.name.trim()) {
    useAlert('Dê um nome ao formulário.');
    return;
  }
  const questions = draft.value.questions
    .filter(q => q.label.trim())
    .map(q => ({
      id: q.id,
      label: q.label.trim(),
      type: q.type,
      required: q.type === 'message' ? false : !!q.required,
      options: needsOptions(q.type)
        ? q.optionsText.split('\n').map(o => o.trim()).filter(Boolean)
        : [],
      color: q.color || 'auto',
      ...(q.type === 'message' ? { text: (q.text || '').trim() } : {}),
    }));
  if (!questions.some(q => q.type !== 'message')) {
    useAlert('Adicione pelo menos uma pergunta (cards de mensagem não contam).');
    return;
  }
  const invalid = questions.find(q => needsOptions(q.type) && q.options.length < 2);
  if (invalid) {
    useAlert(`A pergunta "${invalid.label}" precisa de pelo menos 2 opções.`);
    return;
  }

  isSavingForm.value = true;
  const payload = {
    name: draft.value.name.trim(),
    intro_title: draft.value.intro_title,
    intro_text: draft.value.intro_text,
    thank_you_text: draft.value.thank_you_text,
    active: draft.value.active,
    questions,
  };
  try {
    if (draft.value.id) {
      await CrmAPI.updateForm(draft.value.id, payload);
    } else {
      await CrmAPI.createForm(payload);
    }
    showBuilder.value = false;
    await load();
    useAlert('Formulário salvo!');
  } catch {
    useAlert('Erro ao salvar o formulário.');
  } finally {
    isSavingForm.value = false;
  }
};

const removeForm = async form => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir "${form.name}" e todas as respostas? Não dá para desfazer.`)) return;
  await CrmAPI.deleteForm(form.id);
  if (selectedFormId.value === form.id) selectedFormId.value = null;
  await load();
};

const copyTestLink = async form => {
  try {
    const { data } = await CrmAPI.getFormPreviewLink(form.id);
    await navigator.clipboard.writeText(data.link);
    useAlert('Link de teste copiado! Abra numa aba anônima para ver como o paciente vê.');
  } catch {
    useAlert('Erro ao gerar o link.');
  }
};

// ── Insights de IA ─────────────────────────────────────────
const generateInsights = async () => {
  if (isGeneratingInsights.value) return;
  isGeneratingInsights.value = true;
  try {
    const { data } = await CrmAPI.generateFormInsights(selectedFormId.value);
    if (summary.value) summary.value.ai_insight = data.ai_insight;
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Erro ao gerar insights.');
  } finally {
    isGeneratingInsights.value = false;
  }
};

// barra percentual por opção
const pct = (count, total) => (total ? Math.round((count / total) * 100) : 0);
</script>

<template>
  <div class="flex flex-col h-full overflow-y-auto p-6 bg-n-surface-1">
    <!-- Header -->
    <div class="flex items-center gap-3 mb-6 flex-wrap">
      <div>
        <h1 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
          <span class="i-lucide-clipboard-list text-n-brand" />
          Formulários
        </h1>
        <p class="text-xs text-n-slate-10 mt-0.5">
          Perguntas pré-operatórias e pesquisas — respostas viram insights de marketing
        </p>
      </div>
      <div class="flex-1" />
      <button
        class="h-8 flex items-center gap-1.5 text-sm px-3 rounded-lg bg-n-brand text-white hover:bg-n-brand/90"
        @click="openBuilder(null)"
      >
        <span class="i-lucide-plus text-sm" />
        Novo formulário
      </button>
    </div>

    <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

    <template v-else>
      <!-- Lista de formulários -->
      <div class="flex gap-2 flex-wrap mb-5">
        <button
          v-for="f in forms"
          :key="f.id"
          class="flex items-center gap-2 px-3 py-2 rounded-xl border text-sm transition-colors"
          :class="selectedFormId === f.id
            ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
            : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
          @click="selectForm(f.id)"
        >
          {{ f.name }}
          <span class="text-[10px] px-1.5 py-0.5 rounded-full bg-n-alpha-2">{{ f.responses_count }}</span>
          <span v-if="!f.active" class="text-[10px] text-n-slate-9">(inativo)</span>
        </button>
        <p v-if="!forms.length" class="text-sm text-n-slate-10 py-2">
          Nenhum formulário ainda — crie o primeiro e ligue nas automações de coluna (⚡ Modo Programação).
        </p>
      </div>

      <!-- Ações do formulário selecionado -->
      <div v-if="selectedForm" class="flex items-center gap-2 mb-4 flex-wrap">
        <button class="h-8 flex items-center gap-1.5 text-xs px-3 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1" @click="openBuilder(selectedForm)">
          <span class="i-lucide-pencil text-xs" /> Editar perguntas
        </button>
        <button class="h-8 flex items-center gap-1.5 text-xs px-3 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1" @click="copyTestLink(selectedForm)">
          <span class="i-lucide-link text-xs" /> Copiar link de teste
        </button>
        <button class="h-8 flex items-center gap-1.5 text-xs px-3 rounded-lg border border-n-weak text-n-slate-11 hover:text-red-500 hover:bg-n-alpha-1" @click="removeForm(selectedForm)">
          <span class="i-lucide-trash-2 text-xs" /> Excluir
        </button>
        <span class="text-[11px] text-n-slate-9 ml-1">
          Envio automático: CRM → ⚡ Modo Programação → automação "Enviar formulário" na coluna desejada
        </span>
      </div>

      <div v-if="isLoadingSummary" class="flex justify-center py-10"><Spinner /></div>

      <!-- Dashboard de respostas -->
      <template v-else-if="selectedForm && summary">
        <div class="grid grid-cols-2 md:grid-cols-4 gap-5 mb-8">
          <!-- Respostas — azul -->
          <div class="rounded-2xl p-5 text-white shadow-lg" style="background: linear-gradient(135deg, #0F5FA6, #0B4A82)">
            <div class="flex items-center gap-2 mb-2">
              <span class="i-lucide-inbox text-base opacity-80" />
              <p class="text-xs font-medium opacity-80">Respostas</p>
            </div>
            <p class="text-3xl font-bold">{{ summary.total }}</p>
          </div>
          <!-- Última resposta — branco alto contraste -->
          <div class="rounded-2xl p-5 bg-white dark:bg-n-solid-1 border-2 border-n-weak shadow-sm">
            <div class="flex items-center gap-2 mb-2">
              <span class="i-lucide-clock text-base text-[#0F5FA6]" />
              <p class="text-xs font-medium text-n-slate-10">Última resposta</p>
            </div>
            <p class="text-xl font-bold text-n-slate-12">
              {{ summary.last_response_at ? new Date(summary.last_response_at).toLocaleDateString('pt-BR') : '—' }}
            </p>
          </div>
          <!-- Insights — roxo -->
          <div class="rounded-2xl p-5 text-white shadow-lg col-span-2 flex items-center justify-between gap-3" style="background: linear-gradient(135deg, #7C3AED, #5B21B6)">
            <div>
              <div class="flex items-center gap-2 mb-1">
                <span class="i-lucide-sparkles text-base" style="color: #FCD34D" />
                <p class="text-sm font-bold">Insights de marketing</p>
              </div>
              <p class="text-xs opacity-80">Dores, desejos e objeções do seu público — direto das respostas</p>
            </div>
            <button
              class="h-10 flex items-center gap-2 text-sm font-bold px-4 rounded-xl bg-white text-purple-700 hover:bg-purple-50 disabled:opacity-50 flex-shrink-0 shadow"
              :disabled="isGeneratingInsights || !summary.total"
              @click="generateInsights"
            >
              <span :class="isGeneratingInsights ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-sparkles'" class="text-sm" />
              {{ isGeneratingInsights ? 'Analisando…' : (summary.ai_insight ? 'Atualizar' : 'Gerar com IA') }}
            </button>
          </div>
        </div>

        <!-- Insights -->
        <div v-if="summary.ai_insight" class="rounded-2xl border-2 border-purple-500/30 bg-white dark:bg-n-solid-1 p-6 mb-8 shadow-sm">
          <div class="flex items-center gap-2 mb-3">
            <span class="w-8 h-8 rounded-lg flex items-center justify-center" style="background: linear-gradient(135deg, #7C3AED, #5B21B6)">
              <span class="i-lucide-sparkles text-white text-sm" />
            </span>
            <p class="text-sm font-bold text-n-slate-12">
              Insights do público
              <span class="font-normal text-n-slate-10">
                — {{ summary.ai_insight.responses_analyzed }} respostas ·
                {{ summary.ai_insight.generated_at ? new Date(summary.ai_insight.generated_at).toLocaleDateString('pt-BR') : '' }}
              </span>
            </p>
          </div>
          <p class="text-sm text-n-slate-12 leading-relaxed mb-5 pl-1">{{ summary.ai_insight.resumo }}</p>
          <div class="grid md:grid-cols-2 gap-5">
            <div
              v-for="(block, key) in {
                '😣 Dores': { items: summary.ai_insight.dores, color: '#0F5FA6' },
                '✨ Desejos': { items: summary.ai_insight.desejos, color: '#D4A017' },
                '🚧 Objeções': { items: summary.ai_insight.objecoes, color: '#7C3AED' },
                '🎯 Recomendações': { items: summary.ai_insight.recomendacoes, color: '#059669' },
              }"
              :key="key"
              class="rounded-xl p-4 bg-n-alpha-1"
              :style="{ borderLeft: `4px solid ${block.color}` }"
            >
              <p class="text-sm font-bold text-n-slate-12 mb-2">{{ key }}</p>
              <ul class="space-y-1.5">
                <li v-for="(item, i) in block.items" :key="i" class="text-xs text-n-slate-11 leading-relaxed flex gap-2">
                  <span :style="{ color: block.color }" class="font-bold flex-shrink-0">•</span>{{ item }}
                </li>
              </ul>
            </div>
          </div>
        </div>

        <!-- Por pergunta -->
        <div class="grid md:grid-cols-2 gap-6">
          <div
            v-for="q in summary.questions"
            :key="q.id"
            class="rounded-2xl border-2 border-n-weak bg-white dark:bg-n-solid-1 p-6 shadow-sm"
          >
            <div class="flex items-start justify-between gap-3 mb-4">
              <div>
                <p class="text-sm font-bold text-n-slate-12 leading-snug">{{ q.label }}</p>
                <p class="text-[11px] text-n-slate-9 mt-1">{{ q.answered }} respostas</p>
              </div>
              <!-- média em dourado (escalas) -->
              <span
                v-if="q.type === 'scale' && q.average !== null"
                class="flex-shrink-0 text-white text-sm font-bold px-3 py-1.5 rounded-xl shadow"
                style="background: linear-gradient(135deg, #D4A017, #B8860B)"
                title="Média das notas"
              >
                ★ {{ q.average }}
              </span>
            </div>

            <!-- barras: líder em dourado, demais azul→roxo -->
            <div v-if="q.counts" class="space-y-3">
              <div v-for="(count, option, idx) in q.counts" :key="option">
                <div class="flex justify-between items-baseline text-xs mb-1">
                  <span class="truncate pr-2 font-medium text-n-slate-12">
                    <span v-if="idx === 0 && q.answered > 0" title="Resposta mais comum">🏆 </span>{{ option }}
                  </span>
                  <span class="flex-shrink-0 font-bold" :style="{ color: idx === 0 ? '#B8860B' : '#0F5FA6' }">
                    {{ count }} · {{ pct(count, q.answered) }}%
                  </span>
                </div>
                <div class="h-3 bg-n-alpha-1 rounded-full overflow-hidden">
                  <div
                    class="h-full rounded-full transition-all"
                    :style="{
                      width: Math.max(pct(count, q.answered), 3) + '%',
                      background: idx === 0
                        ? 'linear-gradient(90deg, #D4A017, #F0C420)'
                        : 'linear-gradient(90deg, #0F5FA6, #7C3AED)',
                    }"
                  />
                </div>
              </div>
              <p v-if="!Object.keys(q.counts).length" class="text-xs text-n-slate-9">Sem respostas ainda.</p>
            </div>

            <!-- respostas abertas -->
            <div v-else class="space-y-2 max-h-64 overflow-y-auto pr-1">
              <p
                v-for="(a, i) in q.answers"
                :key="i"
                class="text-xs text-n-slate-12 leading-relaxed bg-n-alpha-1 rounded-lg px-3 py-2"
                style="border-left: 3px solid #0F5FA6"
              >
                "{{ a }}"
              </p>
              <p v-if="!q.answers?.length" class="text-xs text-n-slate-9">Sem respostas ainda.</p>
            </div>
          </div>
        </div>
      </template>
    </template>

    <!-- ══ Builder modal ══ -->
    <div
      v-if="showBuilder"
      class="fixed inset-0 bg-black/50 z-40 flex items-center justify-center p-4"
      @click.self="showBuilder = false"
    >
      <div class="bg-n-solid-1 rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-5">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ draft.id ? 'Editar formulário' : 'Novo formulário' }}
          </h2>
          <button class="i-lucide-x text-lg text-n-slate-10 hover:text-n-slate-12" @click="showBuilder = false" />
        </div>

        <div class="space-y-3 mb-4">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Nome (interno)</label>
            <input v-model="draft.name" class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12" placeholder="Perguntas Pré-Operatórias" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Título de abertura (o paciente vê)</label>
              <input v-model="draft.intro_title" class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12" placeholder="Antes da sua consulta na CEVICO" />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1">Mensagem de agradecimento</label>
              <input v-model="draft.thank_you_text" class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12" placeholder="Suas respostas foram enviadas!" />
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1">Texto de abertura</label>
            <input v-model="draft.intro_text" class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12" placeholder="Leva menos de 2 minutos..." />
          </div>
          <label class="flex items-center gap-2 text-xs text-n-slate-11">
            <input v-model="draft.active" type="checkbox" class="rounded accent-n-brand" />
            Formulário ativo (links funcionando)
          </label>
        </div>

        <!-- Perguntas -->
        <p class="text-xs font-semibold text-n-slate-12 mb-2">Perguntas</p>
        <div class="space-y-3 mb-4">
          <div
            v-for="(q, i) in draft.questions"
            :key="q.id"
            class="rounded-xl border border-n-weak p-3"
          >
            <div class="flex items-center gap-2 mb-2">
              <span class="text-[11px] font-semibold text-n-slate-9 flex-shrink-0">{{ q.type === 'message' ? '💬' : `${i + 1}.` }}</span>
              <input
                v-model="q.label"
                class="flex-1 border border-n-weak rounded-lg px-2.5 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
                :placeholder="q.type === 'message' ? 'Frase do card (ex: Você está indo muito bem! 🚀)' : 'Escreva a pergunta...'"
              />
              <button class="i-lucide-chevron-up text-n-slate-10 hover:text-n-slate-12" title="Subir" @click="moveQuestion(i, -1)" />
              <button class="i-lucide-chevron-down text-n-slate-10 hover:text-n-slate-12" title="Descer" @click="moveQuestion(i, 1)" />
              <button class="i-lucide-trash-2 text-n-slate-10 hover:text-red-500" title="Remover" @click="draft.questions.splice(i, 1)" />
            </div>
            <div class="flex items-center gap-3 flex-wrap">
              <select v-model="q.type" class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12">
                <option v-for="t in QUESTION_TYPES" :key="t.value" :value="t.value">{{ t.label }}</option>
              </select>
              <label v-if="q.type !== 'message'" class="flex items-center gap-1.5 text-xs text-n-slate-11">
                <input v-model="q.required" type="checkbox" class="rounded accent-n-brand" />
                Obrigatória
              </label>
            </div>
            <textarea
              v-if="needsOptions(q.type)"
              v-model="q.optionsText"
              rows="3"
              class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12 mt-2"
              placeholder="Uma opção por linha:&#10;Menos de 5 anos&#10;5 a 15 anos&#10;Mais de 15 anos"
            />
            <!-- card de mensagem: texto de apoio embaixo da frase -->
            <input
              v-if="q.type === 'message'"
              v-model="q.text"
              class="w-full border border-n-weak rounded-lg px-2.5 py-1.5 text-xs bg-n-solid-2 text-n-slate-12 mt-2"
              placeholder="Texto de apoio (opcional, aparece menor embaixo da frase)"
            />
            <!-- cor do card em botões em linha — vale p/ QUALQUER tipo;
                 "Sequência" segue os blocos dopamine automáticos -->
            <div class="flex items-center gap-1.5 flex-wrap mt-2">
              <span class="text-[11px] text-n-slate-10 mr-1">Cor do card:</span>
              <button
                v-for="c in MESSAGE_COLORS"
                :key="c.key"
                type="button"
                class="flex items-center gap-1.5 px-2 py-1 rounded-full border text-[11px] transition-colors"
                :class="q.color === c.key
                  ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
                  : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                :title="c.label"
                @click="q.color = c.key"
              >
                <span class="w-3.5 h-3.5 rounded-full border border-black/10" :style="{ background: c.css }" />
                {{ c.label }}
              </button>
            </div>
          </div>
        </div>

        <div class="flex gap-2 mb-4">
          <button
            class="flex-1 border border-dashed border-n-weak rounded-xl py-2 text-xs text-n-slate-10 hover:text-n-brand hover:border-n-brand"
            @click="draft.questions.push(newQuestion())"
          >
            + Adicionar pergunta
          </button>
          <button
            class="flex-1 border border-dashed border-n-weak rounded-xl py-2 text-xs text-n-slate-10 hover:text-n-brand hover:border-n-brand"
            @click="draft.questions.push({ ...newQuestion(), type: 'message', required: false })"
          >
            + 💬 Card de mensagem
          </button>
        </div>

        <button
          class="w-full bg-n-brand text-white rounded-lg py-2.5 text-sm font-medium hover:bg-n-brand/90 disabled:opacity-50"
          :disabled="isSavingForm"
          @click="saveForm"
        >
          {{ isSavingForm ? 'Salvando…' : 'Salvar formulário' }}
        </button>
      </div>
    </div>
  </div>
</template>
