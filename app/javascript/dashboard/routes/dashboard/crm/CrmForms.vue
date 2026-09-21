<script setup>
// Formulários CEVICO (ex: perguntas pré-operatórias): montagem das
// perguntas, dashboard de respostas e insights de marketing com IA.
// 20/09: visual no kit CEVICO (cv-*) — hero, 3 blocos, paleta por bloco.
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAlert } from 'dashboard/composables';

// paleta da página: um bloco por área da tela (admin escolhe no chip do hero)
const FORM_BLOCKS = [
  {
    id: 'formularios',
    label: 'Seus formulários',
    icon: 'i-lucide-clipboard-list',
  },
  { id: 'respostas', label: 'Respostas', icon: 'i-lucide-inbox' },
  {
    id: 'perguntas',
    label: 'Pergunta a pergunta',
    icon: 'i-lucide-list-checks',
  },
];
const pal = useCevicoPalette({ scope: 'crm:formularios', blocks: FORM_BLOCKS });
const { cvVars, blockVars } = pal;

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
  {
    key: 'auto',
    label: 'Sequência',
    css: 'linear-gradient(135deg, #F97316, #EC4899, #8B5CF6)',
  },
  {
    key: 'navy',
    label: 'Marca',
    css: 'linear-gradient(135deg, #1E2B5B 55%, #D4AF37)',
  },
  { key: 'laranja', label: 'Laranja', css: '#F97316' },
  { key: 'turquesa', label: 'Turquesa', css: '#06B6D4' },
  { key: 'magenta', label: 'Magenta', css: '#EC4899' },
  { key: 'lima', label: 'Verde lima', css: '#84CC16' },
  { key: 'roxo', label: 'Roxo', css: '#8B5CF6' },
  { key: 'amarelo', label: 'Amarelo sol', css: '#FACC15' },
  { key: 'coral', label: 'Coral', css: '#FB923C' },
  { key: 'royal', label: 'Azul royal', css: '#2563EB' },
];

// grupos do insight de IA: ícone lucide + tom semântico do kit
const INSIGHT_GROUPS = [
  { key: 'dores', label: 'Dores', icon: 'i-lucide-frown', tone: 'cv-red' },
  {
    key: 'desejos',
    label: 'Desejos',
    icon: 'i-lucide-sparkles',
    tone: 'cv-gold',
  },
  {
    key: 'objecoes',
    label: 'Objeções',
    icon: 'i-lucide-shield-alert',
    tone: 'cv-amber',
  },
  {
    key: 'recomendacoes',
    label: 'Recomendações',
    icon: 'i-lucide-target',
    tone: 'cv-green',
  },
];

const selectedForm = computed(
  () => forms.value.find(f => f.id === selectedFormId.value) || null
);
// chips do hero
const totalResponses = computed(() =>
  forms.value.reduce((sum, f) => sum + (f.responses_count || 0), 0)
);
const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const fmtDate = iso => (iso ? new Date(iso).toLocaleDateString('pt-BR') : '—');

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
const strategicTemplate = () =>
  [
    {
      label: 'Há quanto tempo você usa óculos ou lentes de contato?',
      type: 'choice',
      required: true,
      optionsText:
        'Menos de 5 anos\n5 a 15 anos\nMais de 15 anos\nDesde criança\nNão uso',
    },
    {
      label: 'O que você busca resolver?',
      type: 'choice',
      required: true,
      optionsText:
        'Miopia\nAstigmatismo\nHipermetropia\nVista cansada (presbiopia)\nCatarata\nCeratocone\nNão sei meu grau exato',
    },
    {
      label: 'O que MAIS te incomoda no dia a dia com óculos/lentes?',
      type: 'multi',
      required: true,
      optionsText:
        'Praticidade (acordar enxergando)\nEsporte e atividade física\nEstética / autoestima\nCusto de trocar óculos e lentes\nTrabalho / telas\nDirigir à noite\nEmbaçar (máscara, cozinha, chuva)',
    },
    {
      label: 'De 0 a 10, o quanto se livrar dos óculos mudaria sua vida?',
      type: 'scale',
      required: true,
    },
    {
      label: 'Há quanto tempo você pensa em fazer essa cirurgia?',
      type: 'choice',
      required: true,
      optionsText:
        'Comecei a pesquisar agora\nAlguns meses\nMais de 1 ano\nHá anos — sempre acabo adiando',
    },
    {
      label: 'O que te impediu de fazer antes?',
      type: 'multi',
      required: false,
      optionsText:
        'Preço / momento financeiro\nMedo do procedimento\nFalta de tempo\nNão sabia que era possível pro meu caso\nInsegurança sobre o resultado\nNada me impediu, é a primeira vez que busco',
    },
    {
      label: 'Qual é o seu maior receio em relação à cirurgia?',
      type: 'text',
      required: false,
    },
    {
      label: 'Como você imagina sua vida sem óculos? O que faria primeiro?',
      type: 'text',
      required: false,
    },
    {
      label: 'Alguém próximo a você já fez cirurgia nos olhos?',
      type: 'choice',
      required: false,
      optionsText:
        'Sim, e adorou o resultado\nSim, mas teve problema\nNão conheço ninguém que fez',
    },
    {
      label: 'Sobre o investimento na cirurgia, você diria que:',
      type: 'choice',
      required: false,
      optionsText:
        'Já pesquisei e sei os valores\nTenho uma noção\nNão tenho ideia de quanto custa',
    },
    {
      label:
        'Se a avaliação mostrar que você é candidato(a), quando gostaria de operar?',
      type: 'choice',
      required: true,
      optionsText:
        'O quanto antes\nNos próximos 1 a 3 meses\nDaqui a 6 meses ou mais\nAinda estou só pesquisando',
    },
    {
      label:
        'Tem algo sobre sua saúde (ocular ou geral) que devemos saber antes da consulta?',
      type: 'text',
      required: false,
    },
  ].map(q => ({ ...newQuestion(), ...q }));

const openBuilder = form => {
  draft.value = form
    ? {
        id: form.id,
        name: form.name,
        slug: form.slug || '',
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
        slug: '',
        intro_title: 'Antes da sua consulta na CEVICO',
        intro_text:
          'Suas respostas ajudam nossa equipe a preparar o melhor atendimento para você. Leva menos de 3 minutos.',
        thank_you_text:
          'Recebemos suas respostas! Nossa equipe já está se preparando para te receber. Até breve! 💙',
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
        ? q.optionsText
            .split('\n')
            .map(o => o.trim())
            .filter(Boolean)
        : [],
      color: q.color || 'auto',
      ...(q.type === 'message' ? { text: (q.text || '').trim() } : {}),
    }));
  if (!questions.some(q => q.type !== 'message')) {
    useAlert(
      'Adicione pelo menos uma pergunta (cards de mensagem não contam).'
    );
    return;
  }
  const invalid = questions.find(
    q => needsOptions(q.type) && q.options.length < 2
  );
  if (invalid) {
    useAlert(`A pergunta "${invalid.label}" precisa de pelo menos 2 opções.`);
    return;
  }

  isSavingForm.value = true;
  const payload = {
    name: draft.value.name.trim(),
    // endereço do link limpo: vazio no criar = o sistema gera sozinho
    ...(draft.value.slug?.trim() ? { slug: draft.value.slug.trim() } : {}),
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
  const msg = `Excluir "${form.name}" e todas as respostas? Não dá para desfazer.`;
  // eslint-disable-next-line no-alert
  if (!window.confirm(msg)) return;
  await CrmAPI.deleteForm(form.id);
  if (selectedFormId.value === form.id) selectedFormId.value = null;
  await load();
};

const copyTestLink = async form => {
  try {
    const { data } = await CrmAPI.getFormPreviewLink(form.id);
    await navigator.clipboard.writeText(data.link);
    useAlert(
      'Link de teste copiado! Abra numa aba anônima para ver como o paciente vê.'
    );
  } catch {
    useAlert('Erro ao gerar o link.');
  }
};

// link LIMPO (sem token): o que se manda pro paciente no WhatsApp —
// quem abre se identifica com nome + WhatsApp no próprio formulário
const copyShortLink = async form => {
  try {
    await navigator.clipboard.writeText(form.short_link);
    useAlert('Link copiado! É esse que você manda pro paciente no WhatsApp.');
  } catch {
    useAlert('Erro ao copiar o link.');
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

// ── item 73: hub inicial — envio × respostas × conversão + retenção ──
const convPct = f =>
  f.sent_count ? Math.round((f.responses_count / f.sent_count) * 100) : null;
// retenção card a card: % de quem ABRIU que chegou em cada card
const funnelRows = f => {
  const fs = f.funnel_stats || {};
  const open = fs.open || 0;
  if (!open) return [];
  return (f.questions || []).map(q => {
    const reached = Math.min(fs[`q:${q.id}`] || 0, open);
    return {
      id: q.id,
      label: q.label,
      message: q.type === 'message',
      reached,
      pctReached: Math.round((reached / open) * 100),
    };
  });
};
const abandonPct = f => {
  const fs = f.funnel_stats || {};
  if (!fs.open) return null;
  return Math.max(0, 100 - Math.round(((fs.done || 0) / fs.open) * 100));
};
// % de quem abre que conclui (o inverso do abandono)
const donePct = f => (abandonPct(f) === null ? null : 100 - abandonPct(f));
// tom da barra de retenção: verde ≥ 70, âmbar ≥ 40, vermelho abaixo
const retentionTone = p => {
  if (p >= 70) return 'cv-green';
  if (p >= 40) return 'cv-amber';
  return 'cv-red';
};
</script>

<template>
  <!-- formato novo (kit CEVICO): página inteira centrada, hero + 3 blocos -->
  <div
    class="cv-page flex flex-col h-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-[1600px] mx-auto w-full p-4 sm:p-6">
      <CevicoHero
        :pal="pal"
        title="Formulários"
        subtitle="Perguntas pré-operatórias e pesquisas que o paciente responde pelo link: as respostas chegam no card certo do CRM e viram insights de marketing."
        icon="i-lucide-clipboard-list"
      >
        <template #chips>
          <span class="cevico-hero-chip">{{
            plural(forms.length, 'formulário', 'formulários')
          }}</span>
          <span class="cevico-hero-chip">{{
            plural(totalResponses, 'resposta', 'respostas')
          }}</span>
        </template>
        <template #actions>
          <button
            class="cevico-hero-btn cevico-hero-btn-on"
            @click="openBuilder(null)"
          >
            <span class="i-lucide-plus text-sm" />Novo formulário
          </button>
        </template>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading" variant="list" />

      <template v-else>
        <!-- ── Bloco 1: Seus formulários — cartão por formulário com envio ×
             respostas × conversão e a barra de conclusão (item 73) ── -->
        <section
          class="cv-block p-6 sm:p-9 mb-10"
          :style="blockVars('formularios')"
        >
          <div class="flex items-center gap-3 mb-6 flex-wrap">
            <span class="cv-icon cv-icon-lg"
              ><span class="i-lucide-clipboard-list text-lg"
            /></span>
            <div class="min-w-0 flex-1">
              <h2
                class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12"
              >
                Seus formulários
              </h2>
              <p class="text-sm text-n-slate-10 mt-0.5">
                Toque num formulário para ver as respostas. Cada cartão mostra
                envios, respostas e conversão.
              </p>
            </div>
          </div>

          <div class="fk-forms grid grid-cols-1 gap-5">
            <!-- primeiro cartão: criar (mesmo tamanho dos outros) -->
            <button
              type="button"
              class="cv-tile-add rounded-2xl p-5 min-h-[12rem] flex flex-col items-center justify-center gap-2 text-center"
              @click="openBuilder(null)"
            >
              <span class="cv-icon cv-icon-xl"
                ><span class="i-lucide-plus text-2xl"
              /></span>
              <span class="text-base font-bold leading-snug"
                >Criar formulário</span
              >
              <span class="text-xs opacity-80 leading-snug"
                >pré-operatório, pesquisa, satisfação…</span
              >
            </button>

            <button
              v-for="f in forms"
              :key="f.id"
              type="button"
              class="cv-sub cv-sub-hover rounded-2xl p-5 text-left flex flex-col gap-4 min-w-0"
              :class="{ 'cv-sub-on': selectedFormId === f.id }"
              @click="selectForm(f.id)"
            >
              <div class="flex items-start gap-2">
                <p
                  class="text-base font-bold text-n-slate-12 leading-snug flex-1 min-w-0"
                >
                  {{ f.name }}
                </p>
                <span v-if="!f.active" class="cv-chip cv-slate">inativo</span>
                <span
                  v-else-if="selectedFormId === f.id"
                  class="cv-chip flex-shrink-0"
                >
                  <span class="i-lucide-check text-[10px]" />aberto
                </span>
              </div>

              <!-- envio × respostas × conversão: o texto aparece inteiro, o
                   número encolhe junto com o cartão -->
              <div class="fk-kpis grid gap-2">
                <div class="fk-tile cv-stat text-center min-w-0">
                  <p
                    class="fk-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap text-n-slate-12"
                  >
                    {{ f.sent_count }}
                  </p>
                  <p
                    class="text-[11px] font-semibold text-n-slate-10 mt-1 leading-tight"
                  >
                    envios
                  </p>
                </div>
                <div class="fk-tile cv-stat text-center min-w-0">
                  <p
                    class="fk-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap text-n-slate-12"
                  >
                    {{ f.responses_count }}
                  </p>
                  <p
                    class="text-[11px] font-semibold text-n-slate-10 mt-1 leading-tight"
                  >
                    respostas
                  </p>
                </div>
                <div class="fk-tile cv-stat text-center min-w-0">
                  <p
                    class="fk-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap text-n-slate-12"
                  >
                    {{ convPct(f) === null ? '—' : `${convPct(f)}%` }}
                  </p>
                  <p
                    class="text-[11px] font-semibold text-n-slate-10 mt-1 leading-tight"
                  >
                    conversão
                  </p>
                </div>
              </div>

              <!-- conclusão: de quem abre, quantos chegam ao fim -->
              <div class="mt-auto">
                <template v-if="donePct(f) !== null">
                  <div
                    class="cv-track cv-track-sm"
                    :class="retentionTone(donePct(f))"
                  >
                    <div
                      class="cv-fill"
                      :style="{ width: `${Math.max(donePct(f), 2)}%` }"
                    />
                  </div>
                  <p class="text-xs text-n-slate-10 mt-1.5 leading-snug">
                    <b class="text-n-slate-12">{{ donePct(f) }}%</b> de quem
                    abre conclui · abandono {{ abandonPct(f) }}%
                  </p>
                </template>
                <p v-else class="text-xs text-n-slate-9 leading-snug">
                  A retenção card a card começa a contar nas próximas visitas.
                </p>
              </div>
            </button>

            <p
              v-if="!forms.length"
              class="text-sm text-n-slate-10 col-span-full"
            >
              Nenhum formulário ainda. Crie o primeiro e ligue nas automações de
              coluna do CRM (Modo Programação).
            </p>
          </div>

          <!-- ações do formulário selecionado -->
          <div
            v-if="selectedForm"
            class="mt-8 pt-6 border-t border-n-weak flex flex-col gap-3"
          >
            <div class="flex items-center gap-2 flex-wrap">
              <span class="text-sm font-semibold text-n-slate-11 mr-1">{{
                selectedForm.name
              }}</span>
              <button
                class="cv-btn cv-btn-sm"
                @click="openBuilder(selectedForm)"
              >
                <span class="i-lucide-pencil text-xs" />Editar perguntas
              </button>
              <button
                class="cv-btn cv-btn-sm cv-gold"
                @click="copyShortLink(selectedForm)"
              >
                <span class="i-lucide-link text-xs" />Copiar link do paciente
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                @click="copyTestLink(selectedForm)"
              >
                <span class="i-lucide-flask-conical text-xs" />Copiar link de
                teste
              </button>
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger"
                @click="removeForm(selectedForm)"
              >
                <span class="i-lucide-trash-2 text-xs" />Excluir
              </button>
            </div>
            <p
              class="text-xs text-n-slate-10 flex items-start gap-1.5 leading-snug"
            >
              <span class="i-lucide-zap text-sm flex-shrink-0 mt-px" />
              <span
                >Envio automático: no CRM, abra o Modo Programação e ligue a
                automação "Enviar formulário" na coluna desejada.</span
              >
            </p>
          </div>
        </section>

        <!-- ── Bloco 2: Respostas do formulário selecionado ── -->
        <section
          v-if="selectedForm"
          class="cv-block p-6 sm:p-9 mb-10"
          :style="blockVars('respostas')"
        >
          <div class="flex items-center gap-3 mb-6 flex-wrap">
            <span class="cv-icon cv-icon-lg"
              ><span class="i-lucide-inbox text-lg"
            /></span>
            <div class="min-w-0 flex-1">
              <h2
                class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12"
              >
                Respostas
              </h2>
              <p class="text-sm text-n-slate-10 mt-0.5">
                {{ selectedForm.name }}
              </p>
            </div>
          </div>

          <div v-if="isLoadingSummary" class="flex justify-center py-10">
            <Spinner />
          </div>

          <template v-else-if="summary">
            <div class="fr-grid grid grid-cols-1 gap-5">
              <div
                class="fr-tile cv-sub rounded-2xl p-5 flex flex-col gap-3 min-w-0"
              >
                <p
                  class="text-xs font-semibold text-n-slate-10 flex items-center gap-2"
                >
                  <span class="cv-icon cv-icon-sm"
                    ><span class="i-lucide-inbox text-sm" /></span
                  >Respostas
                </p>
                <p
                  class="fr-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap text-n-slate-12"
                >
                  {{ summary.total }}
                </p>
              </div>
              <div
                class="fr-tile cv-sub rounded-2xl p-5 flex flex-col gap-3 min-w-0"
              >
                <p
                  class="text-xs font-semibold text-n-slate-10 flex items-center gap-2"
                >
                  <span class="cv-icon cv-icon-sm"
                    ><span class="i-lucide-clock text-sm" /></span
                  >Última resposta
                </p>
                <p
                  class="fr-value font-extrabold tabular-nums tracking-tight leading-none whitespace-nowrap text-n-slate-12"
                >
                  {{ fmtDate(summary.last_response_at) }}
                </p>
              </div>
              <!-- Insights: sem fundo colorido — cor só no ícone e na borda -->
              <div
                class="cv-sub rounded-2xl p-5 flex flex-col gap-3 min-w-0 fk-accent"
              >
                <p
                  class="text-xs font-semibold text-n-slate-10 flex items-center gap-2"
                >
                  <span class="cv-icon cv-icon-sm cv-gold"
                    ><span class="i-lucide-sparkles text-sm" /></span
                  >Insights de marketing
                </p>
                <p class="text-sm text-n-slate-11 leading-snug">
                  Dores, desejos e objeções do seu público, direto das
                  respostas.
                </p>
                <button
                  class="cv-btn mt-auto self-start"
                  :disabled="isGeneratingInsights || !summary.total"
                  @click="generateInsights"
                >
                  <span
                    :class="
                      isGeneratingInsights
                        ? 'i-lucide-loader-circle animate-spin'
                        : 'i-lucide-sparkles'
                    "
                    class="text-sm"
                  />
                  {{
                    isGeneratingInsights
                      ? 'Analisando…'
                      : summary.ai_insight
                        ? 'Atualizar'
                        : 'Gerar com IA'
                  }}
                </button>
              </div>
            </div>

            <!-- Retenção card a card: onde o paciente ABANDONA (item 73) -->
            <div
              v-if="funnelRows(selectedForm).length"
              class="cv-sub rounded-2xl p-5 sm:p-6 mt-6"
            >
              <div class="flex items-center gap-2 mb-5 flex-wrap">
                <span class="cv-icon cv-icon-sm cv-red"
                  ><span class="i-lucide-trending-down text-sm"
                /></span>
                <h3 class="text-base font-bold text-n-slate-12">
                  Retenção card a card
                </h3>
                <span class="cv-chip"
                  >{{ selectedForm.funnel_stats?.open || 0 }} aberturas</span
                >
                <span class="cv-chip"
                  >{{ selectedForm.funnel_stats?.done || 0 }} concluíram</span
                >
                <span
                  v-if="abandonPct(selectedForm) !== null"
                  class="cv-chip cv-red"
                >
                  abandono {{ abandonPct(selectedForm) }}%
                </span>
              </div>
              <div class="space-y-3">
                <div
                  v-for="(row, ri) in funnelRows(selectedForm)"
                  :key="row.id"
                  class="flex flex-col sm:flex-row sm:items-center gap-1.5 sm:gap-3"
                >
                  <p
                    class="text-xs text-n-slate-11 leading-snug sm:w-72 sm:flex-shrink-0 flex items-start gap-1.5"
                  >
                    <span class="text-n-slate-9 tabular-nums flex-shrink-0"
                      >{{ ri + 1 }}º</span
                    >
                    <span
                      v-if="row.message"
                      class="i-lucide-message-circle text-sm text-n-slate-9 flex-shrink-0 mt-px"
                      title="Card de mensagem"
                    />
                    <span class="min-w-0">{{ row.label }}</span>
                  </p>
                  <div class="flex items-center gap-3 flex-1 min-w-0">
                    <div
                      class="cv-track flex-1"
                      :class="retentionTone(row.pctReached)"
                    >
                      <div
                        class="cv-fill"
                        :style="{ width: `${Math.max(row.pctReached, 2)}%` }"
                      />
                    </div>
                    <span
                      class="text-xs font-bold tabular-nums text-n-slate-12 w-11 text-right whitespace-nowrap"
                    >
                      {{ row.pctReached }}%
                    </span>
                  </div>
                </div>
              </div>
              <p class="text-xs text-n-slate-9 mt-4 leading-snug">
                % de quem abriu o link que chegou em cada card. A queda entre um
                card e o próximo mostra onde o formulário perde gente.
              </p>
            </div>

            <!-- Insights gerados pela IA -->
            <div
              v-if="summary.ai_insight"
              class="cv-sub rounded-2xl p-5 sm:p-6 mt-6"
            >
              <div class="flex items-center gap-2 mb-4 flex-wrap">
                <span class="cv-icon cv-icon-sm cv-gold"
                  ><span class="i-lucide-sparkles text-sm"
                /></span>
                <h3 class="text-base font-bold text-n-slate-12">
                  Insights do público
                </h3>
                <span class="cv-chip">{{
                  plural(
                    summary.ai_insight.responses_analyzed,
                    'resposta',
                    'respostas'
                  )
                }}</span>
                <span v-if="summary.ai_insight.generated_at" class="cv-chip">{{
                  fmtDate(summary.ai_insight.generated_at)
                }}</span>
              </div>
              <p class="text-sm text-n-slate-11 leading-relaxed mb-6">
                {{ summary.ai_insight.resumo }}
              </p>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-5">
                <div
                  v-for="g in INSIGHT_GROUPS"
                  :key="g.key"
                  class="rounded-xl p-4 border fk-group"
                  :class="g.tone"
                >
                  <p
                    class="text-sm font-bold text-n-slate-12 mb-3 flex items-center gap-2"
                  >
                    <span class="cv-icon cv-icon-sm"
                      ><span :class="g.icon" class="text-sm" /></span
                    >{{ g.label }}
                  </p>
                  <ul class="space-y-1.5">
                    <li
                      v-for="(item, i) in summary.ai_insight[g.key] || []"
                      :key="i"
                      class="text-sm text-n-slate-11 leading-relaxed flex gap-2"
                    >
                      <span
                        class="w-1.5 h-1.5 rounded-full flex-shrink-0 mt-2 fk-dot"
                      />{{ item }}
                    </li>
                  </ul>
                </div>
              </div>
            </div>
          </template>
        </section>

        <!-- ── Bloco 3: Pergunta a pergunta ── -->
        <section
          v-if="selectedForm && summary"
          class="cv-block p-6 sm:p-9 mb-10"
          :style="blockVars('perguntas')"
        >
          <div class="flex items-center gap-3 mb-6 flex-wrap">
            <span class="cv-icon cv-icon-lg"
              ><span class="i-lucide-list-checks text-lg"
            /></span>
            <div class="min-w-0 flex-1">
              <h2
                class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12"
              >
                Pergunta a pergunta
              </h2>
              <p class="text-sm text-n-slate-10 mt-0.5">
                Como o público respondeu cada pergunta. A resposta mais comum
                leva o troféu.
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 items-stretch">
            <div
              v-for="q in summary.questions"
              :key="q.id"
              class="cv-sub rounded-2xl p-5 flex flex-col min-w-0"
            >
              <div class="flex items-start gap-3 mb-4">
                <div class="flex-1 min-w-0">
                  <p class="text-base font-bold text-n-slate-12 leading-snug">
                    {{ q.label }}
                  </p>
                  <p class="text-xs text-n-slate-10 mt-1">
                    {{ plural(q.answered, 'resposta', 'respostas') }}
                  </p>
                </div>
                <!-- média em dourado (escalas) -->
                <span
                  v-if="q.type === 'scale' && q.average !== null"
                  class="cv-chip cv-chip-lg cv-gold flex-shrink-0"
                  title="Média das notas"
                >
                  <span class="i-lucide-star text-xs" />{{ q.average }}
                </span>
              </div>

              <!-- barras: a líder em dourado (troféu), as demais no tom do bloco -->
              <div v-if="q.counts" class="space-y-3.5">
                <div
                  v-for="(count, option, idx) in q.counts"
                  :key="option"
                  :class="{ 'cv-gold': idx === 0 && q.answered > 0 }"
                >
                  <div class="flex items-start justify-between gap-3 mb-1.5">
                    <span
                      class="text-sm font-medium text-n-slate-12 leading-snug min-w-0 flex items-start gap-1.5"
                    >
                      <span
                        v-if="idx === 0 && q.answered > 0"
                        class="i-lucide-trophy text-sm flex-shrink-0 mt-px fk-trophy"
                        title="Resposta mais comum"
                      />
                      <span class="min-w-0">{{ option }}</span>
                    </span>
                    <span
                      class="text-xs font-bold tabular-nums text-n-slate-12 whitespace-nowrap flex-shrink-0"
                    >
                      {{ count }} · {{ pct(count, q.answered) }}%
                    </span>
                  </div>
                  <div class="cv-track">
                    <div
                      class="cv-fill"
                      :style="{
                        width: `${Math.max(pct(count, q.answered), 3)}%`,
                      }"
                    />
                  </div>
                </div>
                <p
                  v-if="!Object.keys(q.counts).length"
                  class="text-sm text-n-slate-9"
                >
                  Sem respostas ainda.
                </p>
              </div>

              <!-- respostas abertas: citações discretas -->
              <div v-else class="space-y-2 max-h-72 overflow-y-auto pr-1">
                <blockquote
                  v-for="(a, i) in q.answers"
                  :key="i"
                  class="text-sm text-n-slate-11 leading-relaxed pl-3 py-0.5 border-l-2 fk-quote"
                >
                  "{{ a }}"
                </blockquote>
                <p v-if="!q.answers?.length" class="text-sm text-n-slate-9">
                  Sem respostas ainda.
                </p>
              </div>
            </div>
          </div>
        </section>
      </template>
    </div>

    <!-- ══ Builder modal ══ -->
    <div
      v-if="showBuilder"
      class="fixed inset-0 bg-black/50 z-40 flex items-center justify-center p-4"
      @click.self="showBuilder = false"
    >
      <div
        class="bg-n-solid-1 rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-5"
      >
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-sm font-semibold text-n-slate-12">
            {{ draft.id ? 'Editar formulário' : 'Novo formulário' }}
          </h2>
          <button
            class="i-lucide-x text-lg text-n-slate-10 hover:text-n-slate-12"
            @click="showBuilder = false"
          />
        </div>

        <div class="space-y-3 mb-4">
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Nome (interno)</label
            >
            <input
              v-model="draft.name"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="Perguntas Pré-Operatórias"
            />
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Endereço do link (o paciente vê na barra)</label
            >
            <div class="flex items-center gap-2">
              <span class="text-xs text-n-slate-10 whitespace-nowrap font-mono"
                >…/forms/</span
              >
              <input
                v-model="draft.slug"
                class="flex-1 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12 font-mono"
                placeholder="pre-avaliacao"
              />
            </div>
            <p class="text-[11px] text-n-slate-9 mt-1">
              Só letras minúsculas, números e hífens — vira o link limpo pra
              mandar no WhatsApp (ex.:
              <span class="font-mono"
                >clinica.cevico.com.br/forms/pre-avaliacao</span
              >). Quem abre por ele se identifica com nome + WhatsApp e a
              resposta cai no card certo. Deixe em branco ao criar que o sistema
              gera um.
            </p>
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Título de abertura (o paciente vê)</label
              >
              <input
                v-model="draft.intro_title"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder="Antes da sua consulta na CEVICO"
              />
            </div>
            <div>
              <label class="text-xs font-medium text-n-slate-11 block mb-1"
                >Mensagem de agradecimento</label
              >
              <input
                v-model="draft.thank_you_text"
                class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
                placeholder="Suas respostas foram enviadas!"
              />
            </div>
          </div>
          <div>
            <label class="text-xs font-medium text-n-slate-11 block mb-1"
              >Texto de abertura</label
            >
            <input
              v-model="draft.intro_text"
              class="w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-2 text-n-slate-12"
              placeholder="Leva menos de 2 minutos..."
            />
          </div>
          <label class="flex items-center gap-2 text-xs text-n-slate-11">
            <input
              v-model="draft.active"
              type="checkbox"
              class="rounded accent-n-brand"
            />
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
              <span
                class="text-[11px] font-semibold text-n-slate-9 flex-shrink-0"
                >{{ q.type === 'message' ? '💬' : `${i + 1}.` }}</span
              >
              <input
                v-model="q.label"
                class="flex-1 border border-n-weak rounded-lg px-2.5 py-1.5 text-sm bg-n-solid-2 text-n-slate-12"
                :placeholder="
                  q.type === 'message'
                    ? 'Frase do card (ex: Você está indo muito bem! 🚀)'
                    : 'Escreva a pergunta...'
                "
              />
              <button
                class="i-lucide-chevron-up text-n-slate-10 hover:text-n-slate-12"
                title="Subir"
                @click="moveQuestion(i, -1)"
              />
              <button
                class="i-lucide-chevron-down text-n-slate-10 hover:text-n-slate-12"
                title="Descer"
                @click="moveQuestion(i, 1)"
              />
              <button
                class="i-lucide-trash-2 text-n-slate-10 hover:text-red-500"
                title="Remover"
                @click="draft.questions.splice(i, 1)"
              />
            </div>
            <div class="flex items-center gap-3 flex-wrap">
              <select
                v-model="q.type"
                class="border border-n-weak rounded-lg px-2 py-1.5 text-xs bg-n-solid-2 text-n-slate-12"
              >
                <option
                  v-for="t in QUESTION_TYPES"
                  :key="t.value"
                  :value="t.value"
                >
                  {{ t.label }}
                </option>
              </select>
              <label
                v-if="q.type !== 'message'"
                class="flex items-center gap-1.5 text-xs text-n-slate-11"
              >
                <input
                  v-model="q.required"
                  type="checkbox"
                  class="rounded accent-n-brand"
                />
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
                :class="
                  q.color === c.key
                    ? 'border-n-brand bg-n-brand/10 text-n-brand font-medium'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
                "
                :title="c.label"
                @click="q.color = c.key"
              >
                <span
                  class="w-3.5 h-3.5 rounded-full border border-black/10"
                  :style="{ background: c.css }"
                />
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
            @click="
              draft.questions.push({
                ...newQuestion(),
                type: 'message',
                required: false,
              })
            "
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

<style scoped>
/* O texto aparece INTEIRO sempre (mesma técnica do MoneyTiles): as grades
   decidem quantos cartões cabem pela largura do CONTÊINER e o número encolhe
   junto com o cartão — nunca corta rótulo nem número. */
.fk-forms {
  grid-template-columns: repeat(auto-fit, minmax(min(18rem, 100%), 1fr));
}
.fk-kpis {
  grid-template-columns: repeat(auto-fit, minmax(4.75rem, 1fr));
}
.fk-tile {
  container-type: inline-size;
}
.fk-value {
  font-size: clamp(1rem, 18cqi, 1.5rem);
}
.fr-grid {
  grid-template-columns: repeat(auto-fit, minmax(min(15rem, 100%), 1fr));
}
.fr-tile {
  container-type: inline-size;
}
.fr-value {
  font-size: clamp(1.4rem, 14cqi, 2.25rem);
}
/* cor do bloco em detalhes pontuais (o lint barra style inline): borda da
   ficha de Insights, grupos do insight, bolinha da lista, troféu e citação */
.cv-page .cv-sub.fk-accent {
  border-color: rgb(var(--cv-rgb) / 0.45);
}
.cv-page .fk-group {
  border-color: rgb(var(--cv-rgb) / 0.3);
}
.cv-page .fk-dot {
  background: var(--cv);
}
.cv-page .fk-trophy {
  color: var(--cv);
}
.cv-page .fk-quote {
  border-color: rgb(var(--cv-rgb) / 0.45);
}
</style>
