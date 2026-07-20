<script setup>
// PÁGINAS CEVICO: o ambiente de sites da clínica — anunciar procedimentos,
// quebrar objeções e nutrir pacientes, organizado por estágio da jornada.
// Identidade da marca (azul marinho + dourado) com o nosso toque; cada
// página nasce pronta para SEO (meta título/descrição próprios, /p/slug).
import { ref, computed, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');
const currentUserId = useMapGetter('getCurrentUserID');

const isLoading = ref(true);
const pages = ref([]);
const categories = ref({});

const CATEGORY_ORDER = ['captacao', 'pre_consulta', 'pre_cirurgia', 'pos_operatorio'];
const CATEGORY_META = {
  captacao: { icon: 'i-lucide-megaphone', grad: 'linear-gradient(135deg, #0F5FA6, #1E7FBF)' },
  pre_consulta: { icon: 'i-lucide-stethoscope', grad: 'linear-gradient(135deg, #0284C7, #38BDF8)' },
  pre_cirurgia: { icon: 'i-lucide-heart-pulse', grad: 'linear-gradient(135deg, #B8860B, #D4AF37)' },
  pos_operatorio: { icon: 'i-lucide-shield-check', grad: 'linear-gradient(135deg, #047857, #10B981)' },
};

// cores dos cards (paleta da marca + dopamine)
const CARD_COLORS = ['#0F5FA6', '#D4AF37', '#0284C7', '#047857', '#7C3AED', '#DB2777', '#EA580C', '#0D9488'];

// ── Construtor v2: seções + efeitos ──
const SECTION_TYPES = [
  { key: 'texto', label: 'Texto', icon: 'i-lucide-align-left' },
  { key: 'beneficios', label: 'Benefícios', icon: 'i-lucide-badge-check' },
  { key: 'passos', label: 'Passo a passo', icon: 'i-lucide-list-ordered' },
  { key: 'faq', label: 'Perguntas (FAQ)', icon: 'i-lucide-circle-help' },
  { key: 'depoimento', label: 'Depoimento', icon: 'i-lucide-quote' },
  { key: 'visao', label: '👁️ Experiência de visão', icon: 'i-lucide-eye' },
  { key: 'hero', label: 'Faixa de destaque', icon: 'i-lucide-sparkles' },
  { key: 'cta', label: 'Chamada (CTA)', icon: 'i-lucide-megaphone' },
];
const SECTION_EFFECTS = [
  { key: 'nenhum', label: 'Sem efeito' },
  { key: 'movimento', label: 'Movimentação' },
  { key: 'foco', label: 'Desfocado → foco' },
  { key: 'liquido', label: 'Líquido' },
  { key: 'miopia', label: 'Efeito miopia' },
  { key: 'astigmatismo', label: 'Efeito astigmatismo' },
  { key: 'brilho', label: 'Brilho dourado' },
];
const ITEM_TYPES = ['beneficios', 'passos', 'faq'];
const typeMeta = key => SECTION_TYPES.find(t => t.key === key) || SECTION_TYPES[0];

const blankSection = type => ({
  type,
  effect: 'nenhum',
  title: '',
  text: '',
  items: ITEM_TYPES.includes(type) ? [{ title: '', text: '' }] : [],
});
const addSection = type => form.value.sections.push(blankSection(type));
const removeSection = i => form.value.sections.splice(i, 1);
const moveSection = (i, dir) => {
  const s = form.value.sections;
  const j = i + dir;
  if (j < 0 || j >= s.length) return;
  [s[i], s[j]] = [s[j], s[i]];
};

// ── IA no editor, em DOIS modos:
// 'briefing' → Copywriter escreve a página do zero
// 'copy'     → Construtor de Páginas monta a página com uma copy pronta
const ai = ref({ mode: 'briefing', briefing: '', copy: '', form_id: '', generating: false });
const insightForms = ref([]);
const loadInsightForms = async () => {
  try {
    const { data } = await CrmAPI.getForms();
    insightForms.value = (data || []).filter(f => f.has_insight);
  } catch {
    insightForms.value = [];
  }
};
const generateWithAI = async () => {
  const isCopyMode = ai.value.mode === 'copy';
  if (isCopyMode && !ai.value.copy.trim()) {
    useAlert('Cole a copy pronta que o Construtor deve montar.');
    return;
  }
  if (!isCopyMode && !ai.value.briefing.trim()) {
    useAlert('Escreva o briefing: assunto, objetivo e o que não pode faltar.');
    return;
  }
  ai.value.generating = true;
  try {
    const { data } = await CrmAPI.generatePage({
      category: form.value.category,
      ...(isCopyMode
        ? { copy: ai.value.copy }
        : { briefing: ai.value.briefing, form_id: ai.value.form_id || undefined }),
    });
    form.value.title = data.title || form.value.title;
    form.value.subtitle = data.subtitle || form.value.subtitle;
    form.value.emoji = data.emoji || form.value.emoji;
    form.value.meta_title = data.meta_title || '';
    form.value.meta_description = data.meta_description || '';
    form.value.cta_label = data.cta_label || form.value.cta_label;
    form.value.sections = (data.sections || []).map(s => ({ ...blankSection(s.type), ...s, items: s.items || [] }));
    useAlert('Página escrita! Revise as seções, ajuste o que quiser e publique. ✨');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui gerar a página.');
  } finally {
    ai.value.generating = false;
  }
};

const fetchPages = async () => {
  isLoading.value = true;
  try {
    const { data } = await CrmAPI.getPages();
    pages.value = data.pages || [];
    categories.value = data.categories || {};
  } catch {
    pages.value = [];
  } finally {
    isLoading.value = false;
  }
};

const pagesByCategory = computed(() => {
  const map = {};
  CATEGORY_ORDER.forEach(c => {
    map[c] = pages.value.filter(
      p => p.category === c && (!statusFilter.value || p.status === statusFilter.value)
    );
  });
  return map;
});

// ── editor ──
const showEditor = ref(false);
const editing = ref(null);
const saving = ref(false);
const form = ref({});

const blankPage = () => ({
  title: '',
  slug: '',
  category: 'captacao',
  status: 'draft',
  emoji: '👁️',
  color: '#0F5FA6',
  subtitle: '',
  body: '',
  meta_title: '',
  meta_description: '',
  seo_keywords: '',
  cta_label: 'Falar com a CEVICO no WhatsApp',
  cta_url: '',
  next_page_id: null,
  sections: [],
});

// ── gestão de projetos: ideia → em produção → publicada (17/07) ──
const STATUS_META = {
  idea: { label: '💡 IDEIA', chip: '💡 Ideias', badge: 'bg-violet-500/90 text-white' },
  draft: { label: '🛠 EM PRODUÇÃO', chip: '🛠 Em produção', badge: 'bg-black/40 text-white/90' },
  published: { label: 'NO AR', chip: '🟢 Publicadas', badge: 'bg-white/90 text-green-700' },
};
const statusFilter = ref(''); // '' = todas
const statusCount = status => pages.value.filter(p => p.status === status).length;

// ── funil: próxima página + números de conversão ──
const funnelCandidates = computed(() =>
  pages.value.filter(p => p.id !== editing.value?.id)
);
const nextPageTitle = id => pages.value.find(p => p.id === id)?.title || '';
const pageStatsTitle = page => {
  const l7 = page.last7 || {};
  return `Últimos 7 dias: ${l7.views || 0} visitas · ${l7.next || 0} seguiram o funil · ${l7.cta || 0} foram pro WhatsApp`;
};
const pageConversion = page => {
  const clicks = (page.cta_clicks_count || 0) + (page.next_clicks_count || 0);
  if (!page.views_count) return null;
  return Math.round((clicks / page.views_count) * 100);
};

const openNew = category => {
  editing.value = null;
  form.value = { ...blankPage(), category: category || 'captacao', ab_variants: [] };
  comments.value = [];
  showEditor.value = true;
};

const openEdit = page => {
  editing.value = page;
  form.value = {
    ...page,
    ab_variants: (page.ab_variants || []).map(v => ({ ...v })),
    sections: (page.sections || []).map(s => ({ ...blankSection(s.type), ...s, items: s.items || [] })),
  };
  comments.value = page.team_comments || [];
  showEditor.value = true;
};

// ── 🧪 Teste A/B: variações de título/subtítulo/botão no MESMO endereço ──
const addVariant = () => {
  form.value.ab_variants = form.value.ab_variants || [];
  const used = form.value.ab_variants.map(v => v.key);
  const key = ['b', 'c', 'd'].find(k => !used.includes(k));
  if (!key) return;
  form.value.ab_variants.push({
    key, name: `Variação ${key.toUpperCase()}`, title: '', subtitle: '', cta_label: '', active: false,
  });
};
const removeVariant = i => form.value.ab_variants.splice(i, 1);
const abTotals = computed(() => editing.value?.ab_results || {});
const abLine = key => {
  const t = abTotals.value[key];
  if (!t) return null;
  const clicks = (t.cta || 0) + (t.next || 0);
  const rate = t.view ? Math.round((clicks / t.view) * 100) : null;
  return { views: t.view || 0, clicks, rate };
};

// ── 💬 comentários do time (estúdio de copy) ──
const comments = ref([]);
const commentText = ref('');
const sendingComment = ref(false);
const sendComment = async () => {
  if (!commentText.value.trim() || !editing.value) return;
  sendingComment.value = true;
  try {
    const { data } = await CrmAPI.addPageComment(editing.value.id, commentText.value.trim());
    comments.value = data.team_comments || [];
    commentText.value = '';
  } catch {
    useAlert('Não consegui comentar.');
  } finally {
    sendingComment.value = false;
  }
};
const removeComment = async comment => {
  try {
    const { data } = await CrmAPI.deletePageComment(editing.value.id, comment.id);
    comments.value = data.team_comments || [];
  } catch {
    useAlert('Só o autor ou um admin apagam o comentário.');
  }
};
const fmtCommentAt = iso =>
  new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

const savePage = async (publish = null) => {
  if (!form.value.title?.trim()) {
    useAlert('Dê um título para a página.');
    return;
  }
  saving.value = true;
  try {
    const payload = { ...form.value };
    if (publish !== null) payload.status = publish ? 'published' : 'draft';
    if (editing.value) {
      await CrmAPI.updatePage(editing.value.id, payload);
    } else {
      await CrmAPI.createPage(payload);
    }
    showEditor.value = false;
    useAlert(publish ? 'Página publicada! 🎉' : 'Página salva.');
    fetchPages();
  } catch (error) {
    useAlert(error?.response?.data?.message || 'Não consegui salvar a página.');
  } finally {
    saving.value = false;
  }
};

const deletePage = async page => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir a página "${page.title}"? O link público para de funcionar.`)) return;
  try {
    await CrmAPI.deletePage(page.id);
    useAlert('Página excluída.');
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui excluir a página.');
  }
  fetchPages();
};

const copyLink = async page => {
  const url = page.public_url || `${window.location.origin}/p/${page.slug}`;
  try {
    await navigator.clipboard.writeText(url);
    useAlert('Link copiado!');
  } catch {
    useAlert(url);
  }
};

const openPublic = page => {
  // abre no endereço oficial (www.cevico.com.br/slug) quando configurado
  window.open(page.public_url || `/p/${page.slug}`, '_blank', 'noopener');
};

// caminho curto exibido no card (sem https://)
const publicPath = page =>
  (page.public_url || `/p/${page.slug}`).replace(/^https?:\/\//, '');

onMounted(() => {
  fetchPages();
  loadInsightForms(); // formulários com insights alimentam o copywriter
});
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-5xl mx-auto w-full p-4 sm:p-8">
      <!-- Header da marca -->
      <div
        class="rounded-2xl p-5 mb-6 text-white shadow-lg relative overflow-hidden"
        style="background: linear-gradient(160deg, #072a4c 0%, #0b3b66 55%, #0f5fa6 100%)"
      >
        <div class="absolute left-0 right-0 bottom-0 h-1" style="background: linear-gradient(90deg, #d4af37, #f4de8e, #d4af37)" />
        <div class="flex items-center gap-3 flex-wrap">
          <span class="w-10 h-10 rounded-xl flex items-center justify-center border-2" style="border-color: #d4af37; color: #f4de8e">
            <span class="i-lucide-panels-top-left text-lg" />
          </span>
          <div class="flex-1 min-w-0">
            <h1 class="text-lg font-bold">Páginas</h1>
            <p class="text-xs text-white/75">
              sites da CEVICO para cada estágio da jornada — anunciar, tirar dúvidas e nutrir pacientes · prontos para o Google (SEO)
            </p>
          </div>
          <button
            class="px-4 h-9 rounded-xl text-xs font-bold flex items-center gap-1.5 shadow-md text-[#072A4C]"
            style="background: linear-gradient(135deg, #d4af37, #f4de8e)"
            @click="openNew()"
          >
            <span class="i-lucide-plus text-sm" /> Nova página
          </button>
        </div>
      </div>

      <SkeletonScreen v-if="isLoading" variant="list" />

      <template v-else>
        <!-- gestão de projetos: filtro por etapa (ideia/produção/publicada) -->
        <div class="flex items-center h-[34px] bg-n-solid-2 border border-n-weak rounded-xl px-0.5 gap-0.5 mb-5 w-fit max-w-full overflow-x-auto">
          <button
            class="h-7 px-3 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0"
            :class="statusFilter === '' ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="statusFilter === '' ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="statusFilter = ''"
          >
            Todas ({{ pages.length }})
          </button>
          <button
            v-for="(meta, st) in STATUS_META"
            :key="st"
            class="h-7 px-3 rounded-lg text-xs font-medium whitespace-nowrap transition-colors flex-shrink-0"
            :class="statusFilter === st ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
            :style="statusFilter === st ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
            @click="statusFilter = statusFilter === st ? '' : st"
          >
            {{ meta.chip }} ({{ statusCount(st) }})
          </button>
        </div>
        <div v-for="cat in CATEGORY_ORDER" :key="cat" class="mb-7">
          <div class="flex items-center gap-2 mb-3">
            <span class="w-7 h-7 rounded-lg flex items-center justify-center text-white" :style="{ background: CATEGORY_META[cat].grad }">
              <span :class="CATEGORY_META[cat].icon" class="text-sm" />
            </span>
            <h2 class="text-sm font-bold text-n-slate-12">{{ categories[cat] || cat }}</h2>
            <span class="text-[11px] text-n-slate-9">{{ pagesByCategory[cat].length }} página(s)</span>
            <button
              class="ml-auto text-[11px] font-medium text-n-slate-10 hover:text-n-brand flex items-center gap-1"
              @click="openNew(cat)"
            >
              <span class="i-lucide-plus text-xs" /> criar aqui
            </button>
          </div>

          <div v-if="!pagesByCategory[cat].length" class="rounded-xl border border-dashed border-n-weak px-4 py-5 text-center text-[12px] text-n-slate-9">
            Nenhuma página nesta etapa ainda.
          </div>

          <!-- botões médios: cor/emoji do assunto + título -->
          <div v-else class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <div
              v-for="page in pagesByCategory[cat]"
              :key="page.id"
              class="rounded-xl border border-n-weak bg-n-solid-2 overflow-hidden hover:shadow-md hover:border-n-brand/50 transition-all cursor-pointer group"
              @click="openEdit(page)"
            >
              <div class="h-16 flex items-center justify-center text-3xl relative" :style="{ background: `linear-gradient(135deg, ${page.color || '#0F5FA6'}, ${page.color || '#0F5FA6'}CC)` }">
                <span>{{ page.emoji || '👁️' }}</span>
                <span
                  class="absolute top-1.5 right-1.5 px-1.5 py-0.5 rounded-md text-[9px] font-bold"
                  :class="STATUS_META[page.status]?.badge || 'bg-black/30 text-white/90'"
                >
                  {{ STATUS_META[page.status]?.label || page.status }}
                </span>
              </div>
              <div class="p-3">
                <p class="text-[13px] font-bold text-n-slate-12 leading-snug line-clamp-2">{{ page.title }}</p>
                <p class="text-[10px] text-n-slate-9 mt-1 truncate" :title="publicPath(page)">{{ publicPath(page) }}</p>
                <!-- números do funil: visitas · seguiram o funil · WhatsApp · conversão -->
                <p
                  v-if="page.status === 'published'"
                  class="text-[10px] text-n-slate-10 mt-0.5 whitespace-nowrap"
                  :title="pageStatsTitle(page)"
                >
                  👁 {{ page.views_count }}
                  <template v-if="page.next_page_id"> · ➡ {{ page.next_clicks_count }}</template>
                  · 💬 {{ page.cta_clicks_count }}
                  <span v-if="pageConversion(page) !== null" class="font-semibold text-emerald-600">
                    · {{ pageConversion(page) }}% clicam
                  </span>
                </p>
                <div class="flex items-center gap-1 mt-2" @click.stop>
                  <button class="px-2 h-6 rounded-md text-[10px] font-medium text-n-slate-11 hover:bg-n-alpha-1 border border-n-weak" @click="copyLink(page)">
                    copiar link
                  </button>
                  <button class="px-2 h-6 rounded-md text-[10px] font-medium text-n-slate-11 hover:bg-n-alpha-1 border border-n-weak" @click="openPublic(page)">
                    abrir ↗
                  </button>
                  <button
                    v-if="isAdmin"
                    class="ml-auto w-6 h-6 rounded-md flex items-center justify-center text-red-500 hover:bg-red-500/10"
                    @click="deletePage(page)"
                  >
                    <span class="i-lucide-trash-2 text-xs" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- ══ Editor ══ -->
    <div
      v-if="showEditor"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      @click.self="showEditor = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-xl w-full max-w-2xl max-h-[92vh] overflow-y-auto">
        <div class="h-1.5 w-full" style="background: linear-gradient(90deg, #0b3b66, #d4af37)" />
        <div class="p-5">
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
              <span class="i-lucide-panels-top-left text-base" style="color: #d4af37" />
              {{ editing ? 'Editar página' : 'Nova página' }}
            </h3>
            <button class="w-7 h-7 rounded-lg hover:bg-n-alpha-1 flex items-center justify-center text-n-slate-10" @click="showEditor = false">
              <span class="i-lucide-x text-sm" />
            </button>
          </div>

          <label class="block mb-3">
            <span class="text-[11px] font-medium text-n-slate-11">Título da página *</span>
            <input
              v-model="form.title"
              type="text"
              placeholder="Cirurgia de Catarata: como funciona, lentes e recuperação"
              class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
            />
          </label>

          <!-- categoria: botões em linha -->
          <div class="mb-3">
            <span class="text-[11px] font-medium text-n-slate-11">Etapa da jornada:</span>
            <div class="flex items-center gap-1.5 flex-wrap mt-1">
              <button
                v-for="cat in CATEGORY_ORDER"
                :key="cat"
                class="px-2.5 h-7 rounded-lg text-[11px] font-medium border transition-all"
                :class="form.category === cat ? 'text-white border-transparent shadow-sm' : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-1'"
                :style="form.category === cat ? { background: CATEGORY_META[cat].grad } : {}"
                @click="form.category = cat"
              >
                {{ (categories[cat] || cat).replace('Procedimentos — ', '') }}
              </button>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
            <label class="block">
              <span class="text-[11px] font-medium text-n-slate-11">Emoji do assunto</span>
              <input v-model="form.emoji" type="text" placeholder="👁️" class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12" />
            </label>
            <div>
              <span class="text-[11px] font-medium text-n-slate-11">Cor do card</span>
              <div class="flex items-center gap-1.5 flex-wrap mt-1.5">
                <button
                  v-for="c in CARD_COLORS"
                  :key="c"
                  class="w-7 h-7 rounded-lg border-2 transition-transform hover:scale-110"
                  :class="form.color === c ? 'border-n-slate-12' : 'border-transparent'"
                  :style="{ background: c }"
                  @click="form.color = c"
                />
              </div>
            </div>
          </div>

          <label class="block mb-3">
            <span class="text-[11px] font-medium text-n-slate-11">Subtítulo (aparece no topo da página)</span>
            <input v-model="form.subtitle" type="text" placeholder="Tudo o que você precisa saber antes de decidir, explicado com calma." class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12" />
          </label>

          <!-- 🪄 IA no editor: Copywriter escreve OU Construtor monta a copy pronta -->
          <div class="rounded-xl p-3 mb-3 border border-purple-500/30" style="background: linear-gradient(135deg, rgba(124,58,237,.08), rgba(212,175,55,.08))">
            <div class="flex items-center gap-1.5 mb-2 flex-wrap">
              <span class="i-lucide-sparkles text-xs" style="color: #7C3AED" />
              <span class="text-[11px] font-semibold text-n-slate-12 mr-1">Criar com IA:</span>
              <button
                class="px-2.5 h-7 rounded-full border text-[11px] font-medium transition-colors"
                :class="ai.mode === 'briefing' ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                :style="ai.mode === 'briefing' ? { background: 'linear-gradient(135deg, #7C3AED, #5B21B6)' } : {}"
                @click="ai.mode = 'briefing'"
              >
                ✍️ Escrever do zero (Copywriter)
              </button>
              <button
                class="px-2.5 h-7 rounded-full border text-[11px] font-medium transition-colors"
                :class="ai.mode === 'copy' ? 'text-white border-transparent' : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                :style="ai.mode === 'copy' ? { background: 'linear-gradient(135deg, #0F5FA6, #B8860B)' } : {}"
                @click="ai.mode = 'copy'"
              >
                🧱 Montar de copy pronta (Construtor)
              </button>
            </div>
            <textarea
              v-if="ai.mode === 'briefing'"
              v-model="ai.briefing"
              rows="3"
              placeholder="Briefing: assunto, objetivo da página e o que não pode faltar. Ex: página de PRK para quem tem medo de dor — quebrar a objeção, explicar a recuperação dia a dia e chamar para a avaliação."
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-2 text-[12px] text-n-slate-12"
            />
            <textarea
              v-else
              v-model="ai.copy"
              rows="6"
              placeholder="Cole aqui a copy pronta (do Copywriter, sua ou do time). O Construtor NÃO reescreve: ele distribui em seções, escolhe os efeitos e gera o SEO."
              class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-2 text-[12px] text-n-slate-12"
            />
            <div class="flex items-center gap-2 mt-2 flex-wrap">
              <select v-if="ai.mode === 'briefing'" v-model="ai.form_id" class="h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12 max-w-[260px]">
                <option value="">Sem insights de formulário</option>
                <option v-for="f in insightForms" :key="f.id" :value="f.id">Usar insights de: {{ f.name }}</option>
              </select>
              <button
                class="ml-auto px-3 h-8 rounded-lg text-[11px] font-bold text-white flex items-center gap-1.5 disabled:opacity-60"
                style="background: linear-gradient(135deg, #7C3AED, #5B21B6)"
                :disabled="ai.generating"
                @click="generateWithAI"
              >
                <span :class="ai.generating ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-sparkles'" class="text-xs" />
                {{ ai.generating ? (ai.mode === 'copy' ? 'Montando…' : 'Escrevendo…') : (ai.mode === 'copy' ? 'Montar página com IA' : 'Gerar página com IA') }}
              </button>
            </div>
            <p class="text-[10px] text-n-slate-9 mt-1.5">
              A IA preenche as seções abaixo — qualquer pessoa do time revisa e salva o rascunho; publicar é com o admin. Requer o agente ligado (Automações → Agentes de IA).
            </p>
          </div>

          <!-- ══ Construtor por SEÇÕES ══ -->
          <div class="mb-3">
            <p class="text-[11px] font-semibold text-n-slate-12 mb-1.5 flex items-center gap-1.5">
              <span class="i-lucide-layers text-xs" style="color: #d4af37" /> Seções da página
              <span class="font-normal text-n-slate-9">— empilhe, escolha o efeito de cada uma</span>
            </p>

            <div
              v-for="(sec, si) in form.sections"
              :key="si"
              class="rounded-xl border border-n-weak p-3 mb-2 bg-n-solid-2"
            >
              <div class="flex items-center gap-2 mb-2">
                <span :class="typeMeta(sec.type).icon" class="text-sm" style="color: #d4af37" />
                <span class="text-[12px] font-bold text-n-slate-12">{{ typeMeta(sec.type).label }}</span>
                <div class="flex-1" />
                <button class="i-lucide-chevron-up text-n-slate-10 hover:text-n-slate-12" title="Subir" @click="moveSection(si, -1)" />
                <button class="i-lucide-chevron-down text-n-slate-10 hover:text-n-slate-12" title="Descer" @click="moveSection(si, 1)" />
                <button class="i-lucide-trash-2 text-n-slate-10 hover:text-red-500" title="Remover" @click="removeSection(si)" />
              </div>

              <input
                v-model="sec.title"
                class="w-full h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[12px] text-n-slate-12 mb-2"
                :placeholder="sec.type === 'depoimento' ? 'Quem disse (ex: Maria S., operada de catarata)' : 'Título da seção (opcional)'"
              />
              <textarea
                v-model="sec.text"
                :rows="sec.type === 'texto' ? 4 : 2"
                class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-2 py-1.5 text-[12px] text-n-slate-12"
                :placeholder="sec.type === 'depoimento' ? 'O depoimento (use só depoimentos reais)' : 'Texto da seção (parágrafos separados por linha em branco)'"
              />

              <!-- itens (benefícios / passos / FAQ) -->
              <template v-if="ITEM_TYPES.includes(sec.type)">
                <div v-for="(item, ii) in sec.items" :key="ii" class="flex items-start gap-1.5 mt-1.5">
                  <input
                    v-model="item.title"
                    class="w-2/5 h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12"
                    :placeholder="sec.type === 'faq' ? 'Pergunta' : 'Item'"
                  />
                  <input
                    v-model="item.text"
                    class="flex-1 h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12"
                    :placeholder="sec.type === 'faq' ? 'Resposta' : 'Explicação curta'"
                  />
                  <button class="i-lucide-x text-n-slate-10 hover:text-red-500 mt-2" @click="sec.items.splice(ii, 1)" />
                </div>
                <button class="text-[10px] text-n-slate-10 hover:text-n-brand mt-1.5" @click="sec.items.push({ title: '', text: '' })">
                  + adicionar item
                </button>
              </template>

              <!-- efeito da seção: botões em linha -->
              <div class="flex items-center gap-1 flex-wrap mt-2">
                <span class="text-[10px] text-n-slate-10 mr-1">Efeito:</span>
                <button
                  v-for="fx in SECTION_EFFECTS"
                  :key="fx.key"
                  class="px-2 h-6 rounded-full border text-[10px] font-medium transition-colors"
                  :class="sec.effect === fx.key
                    ? 'border-n-brand bg-n-brand/10 text-n-brand'
                    : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'"
                  @click="sec.effect = fx.key"
                >
                  {{ fx.label }}
                </button>
              </div>
            </div>

            <!-- adicionar seção: botões em linha por tipo -->
            <div class="flex items-center gap-1.5 flex-wrap">
              <button
                v-for="t in SECTION_TYPES"
                :key="t.key"
                class="px-2.5 h-7 rounded-lg border border-dashed border-n-weak text-[11px] text-n-slate-10 hover:text-n-brand hover:border-n-brand flex items-center gap-1"
                @click="addSection(t.key)"
              >
                <span :class="t.icon" class="text-xs" /> {{ t.label }}
              </button>
            </div>
          </div>

          <!-- texto corrido (modo antigo) — ignorado quando há seções -->
          <details class="mb-3" :open="!form.sections.length">
            <summary class="text-[11px] font-medium text-n-slate-11 cursor-pointer">
              Conteúdo em texto corrido (modo antigo{{ form.sections.length ? ' — ignorado quando a página tem seções' : '' }})
            </summary>
            <textarea
              v-model="form.body"
              rows="8"
              placeholder="## O que é a cirurgia de catarata?&#10;&#10;Texto do parágrafo...&#10;&#10;- item de lista&#10;- outro item&#10;&#10;> destaque em dourado (citação)"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-2 text-[13px] text-n-slate-12 font-mono"
            />
            <span class="text-[10px] text-n-slate-9">## título · **negrito** · - lista · &gt; destaque dourado — formatação simples (markdown)</span>
          </details>

          <!-- SEO -->
          <div class="bg-n-alpha-1 rounded-xl p-3 mb-3">
            <p class="text-[11px] font-semibold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-search text-xs" style="color: #d4af37" /> Google (SEO)
            </p>
            <label class="block mb-2">
              <span class="text-[11px] font-medium text-n-slate-11">Título no Google (vazio = usa o título da página)</span>
              <input v-model="form.meta_title" type="text" placeholder="Cirurgia de Catarata em São Paulo | CEVICO" class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12" />
            </label>
            <label class="block mb-2">
              <span class="text-[11px] font-medium text-n-slate-11">Descrição no Google (1-2 frases que convidam ao clique)</span>
              <textarea v-model="form.meta_description" rows="2" class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-2 py-1.5 text-[13px] text-n-slate-12" />
            </label>
            <label class="block">
              <span class="text-[11px] font-medium text-n-slate-11">Palavras-chave (separadas por vírgula — viram filtro na Análise)</span>
              <input
                v-model="form.seo_keywords"
                type="text"
                placeholder="catarata, cirurgia de catarata, lente trifocal"
                class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
              />
            </label>
          </div>

          <!-- Próximo passo do botão: WhatsApp OU outra página (funil) -->
          <div class="bg-n-alpha-1 rounded-xl p-3 mb-3">
            <p class="text-[11px] font-semibold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-milestone text-xs" style="color: #d4af37" /> Próximo passo do botão
              <span class="text-[10px] font-normal text-n-slate-9">— todo clique é contado (mede a conversão)</span>
            </p>
            <div class="flex items-center h-[34px] bg-n-solid-2 border border-n-weak rounded-xl px-0.5 gap-0.5 w-fit mb-2">
              <button
                class="h-7 px-3 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
                :class="!form.next_page_id ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                :style="!form.next_page_id ? { background: 'linear-gradient(135deg, #059669, #4ADE80)' } : {}"
                @click="form.next_page_id = null"
              >
                💬 Convite pro WhatsApp
              </button>
              <button
                class="h-7 px-3 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
                :class="form.next_page_id ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                :style="form.next_page_id ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
                :disabled="!funnelCandidates.length"
                @click="form.next_page_id = form.next_page_id || funnelCandidates[0]?.id"
              >
                ➡️ Outra página CEVICO (funil)
              </button>
            </div>

            <div v-if="form.next_page_id" class="mb-2">
              <span class="text-[11px] font-medium text-n-slate-11">Página de destino (o visitante chega marcado com a origem)</span>
              <select
                v-model="form.next_page_id"
                class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12"
              >
                <option v-for="p in funnelCandidates" :key="p.id" :value="p.id">
                  {{ STATUS_META[p.status]?.chip || p.status }} — {{ p.title }}
                </option>
              </select>
              <p class="text-[10px] text-amber-600 mt-1" v-if="pages.find(p => p.id === form.next_page_id)?.status !== 'published'">
                ⚠ A página de destino ainda não está publicada — enquanto isso, o botão usa o WhatsApp.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Texto do botão (vazio = automático)</span>
                <input v-model="form.cta_label" type="text" class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12" />
              </label>
              <label class="block">
                <span class="text-[11px] font-medium text-n-slate-11">Link do WhatsApp da clínica</span>
                <input v-model="form.cta_url" type="text" placeholder="https://wa.me/5511..." class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12" />
              </label>
            </div>
          </div>

          <!-- 🧪 Teste A/B: variações servidas no mesmo endereço -->
          <div v-if="editing" class="bg-n-alpha-1 rounded-xl p-3 mb-3">
            <p class="text-[11px] font-semibold text-n-slate-12 mb-1 flex items-center gap-1.5">
              <span class="i-lucide-flask-conical text-xs" style="color: #d4af37" /> Teste A/B
              <span class="text-[10px] font-normal text-n-slate-9">— variações do título/subtítulo/botão servidas no MESMO endereço; visitas e cliques contam por variação</span>
            </p>

            <!-- original (A) -->
            <div class="flex items-center gap-2 flex-wrap rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1.5 mb-1.5 text-[11px]">
              <span class="font-bold text-n-slate-12">A — original</span>
              <span class="text-n-slate-10 truncate flex-1 min-w-[120px]">{{ form.title }}</span>
              <span v-if="abLine('a')" class="text-n-slate-10">
                {{ abLine('a').views }} visitas · {{ abLine('a').clicks }} cliques
                <b v-if="abLine('a').rate !== null" class="text-emerald-600">· {{ abLine('a').rate }}%</b>
              </span>
            </div>

            <div v-for="(v, vi) in form.ab_variants || []" :key="v.key" class="rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-2 mb-1.5">
              <div class="flex items-center gap-2 flex-wrap mb-1.5">
                <span class="text-[11px] font-bold text-n-slate-12 uppercase">{{ v.key }}</span>
                <input v-model="v.name" type="text" class="h-7 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12" style="width: 9rem" />
                <span v-if="abLine(v.key)" class="text-[11px] text-n-slate-10">
                  {{ abLine(v.key).views }} visitas · {{ abLine(v.key).clicks }} cliques
                  <b v-if="abLine(v.key).rate !== null" class="text-emerald-600">· {{ abLine(v.key).rate }}%</b>
                </span>
                <label class="ml-auto flex items-center gap-1.5 text-[11px] font-medium cursor-pointer" :class="v.active ? 'text-emerald-600' : 'text-n-slate-10'">
                  <input v-model="v.active" type="checkbox" class="accent-emerald-600" style="width: 14px; height: 14px" />
                  {{ v.active ? 'no ar (sorteada)' : 'pausada' }}
                </label>
                <button class="i-lucide-trash-2 text-n-slate-10 hover:text-red-500 text-sm" title="Excluir variação" @click="removeVariant(vi)" />
              </div>
              <input v-model="v.title" type="text" placeholder="Título desta variação (vazio = usa o original)" class="w-full h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12 mb-1.5" />
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                <input v-model="v.subtitle" type="text" placeholder="Subtítulo (vazio = original)" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12" />
                <input v-model="v.cta_label" type="text" placeholder="Texto do botão (vazio = original)" class="h-8 rounded-lg border border-n-weak bg-n-solid-1 px-2 text-[11px] text-n-slate-12" />
              </div>
            </div>

            <button
              v-if="(form.ab_variants || []).length < 3"
              class="px-2.5 h-7 rounded-lg border border-dashed border-n-weak text-[11px] text-n-slate-10 hover:text-n-brand hover:border-n-brand flex items-center gap-1"
              @click="addVariant"
            >
              <span class="i-lucide-plus text-xs" /> Criar variação
            </button>
            <p class="text-[10px] text-n-slate-9 mt-1.5">
              Ative a variação e salve: cada visitante é sorteado entre a original e as ativas. Os resultados aparecem aqui e na Análise de Páginas.
            </p>
          </div>

          <!-- 💬 Comentários do time (estúdio de copy) -->
          <div v-if="editing" class="bg-n-alpha-1 rounded-xl p-3 mb-3">
            <p class="text-[11px] font-semibold text-n-slate-12 mb-2 flex items-center gap-1.5">
              <span class="i-lucide-messages-square text-xs" style="color: #d4af37" /> Comentários do time
              <span class="text-[10px] font-normal text-n-slate-9">— sugestões de copy, ajustes, aprovações</span>
            </p>
            <div v-if="comments.length" class="space-y-1.5 mb-2 max-h-44 overflow-y-auto">
              <div v-for="c in comments" :key="c.id" class="rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-1.5">
                <div class="flex items-center gap-2">
                  <span class="text-[11px] font-bold text-n-slate-12">{{ c.name }}</span>
                  <span class="text-[10px] text-n-slate-9">{{ fmtCommentAt(c.at) }}</span>
                  <button
                    v-if="isAdmin || c.user_id === currentUserId"
                    class="ml-auto i-lucide-x text-n-slate-10 hover:text-red-500 text-xs"
                    title="Apagar"
                    @click="removeComment(c)"
                  />
                </div>
                <p class="text-[11px] text-n-slate-11 mt-0.5 whitespace-pre-line">{{ c.text }}</p>
              </div>
            </div>
            <div class="flex items-center gap-1.5">
              <input
                v-model="commentText"
                type="text"
                placeholder="Deixe uma sugestão pra este texto…"
                class="flex-1 min-w-0 h-8 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[11px] text-n-slate-12"
                @keyup.enter="sendComment"
              />
              <button
                class="px-2.5 h-8 rounded-lg text-[11px] font-semibold text-white disabled:opacity-50"
                style="background: linear-gradient(135deg, #0F5FA6, #1E7FBF)"
                :disabled="sendingComment || !commentText.trim()"
                @click="sendComment"
              >
                Comentar
              </button>
            </div>
          </div>

          <label v-if="editing && isAdmin" class="block mb-3">
            <span class="text-[11px] font-medium text-n-slate-11">Endereço da página (a parte final do link) — mudar quebra links já divulgados</span>
            <input v-model="form.slug" type="text" class="mt-1 w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-[13px] text-n-slate-12 font-mono" />
          </label>

          <!-- etapa do projeto (gestão: ideia → produção → publicada) -->
          <div v-if="isAdmin" class="flex items-center gap-2 mb-4 flex-wrap">
            <span class="text-[11px] font-medium text-n-slate-11">Etapa do projeto:</span>
            <div class="flex items-center h-[34px] bg-n-solid-2 border border-n-weak rounded-xl px-0.5 gap-0.5">
              <button
                v-for="(meta, st) in STATUS_META"
                :key="st"
                class="h-7 px-3 rounded-lg text-xs font-medium whitespace-nowrap transition-colors"
                :class="form.status === st ? 'text-white' : 'text-n-slate-11 hover:bg-n-alpha-1'"
                :style="form.status === st ? { background: 'linear-gradient(135deg, #0F5FA6, #7C3AED)' } : {}"
                @click="form.status = st"
              >
                {{ meta.chip }}
              </button>
            </div>
          </div>

          <div class="flex items-center justify-end gap-2">
            <button class="px-3 h-9 rounded-lg text-[12px] font-medium text-n-slate-11 hover:bg-n-alpha-1" @click="showEditor = false">
              Cancelar
            </button>
            <button
              class="px-3 h-9 rounded-lg text-[12px] font-semibold border border-n-weak text-n-slate-12 hover:bg-n-alpha-1 disabled:opacity-60"
              :disabled="saving"
              @click="savePage(isAdmin ? null : false)"
            >
              {{ isAdmin ? 'Salvar' : 'Salvar rascunho' }}
            </button>
            <button
              v-if="isAdmin"
              class="px-4 h-9 rounded-lg text-[12px] font-bold text-[#072A4C] disabled:opacity-60 shadow-sm"
              style="background: linear-gradient(135deg, #d4af37, #f4de8e)"
              :disabled="saving"
              @click="savePage(true)"
            >
              {{ saving ? 'Salvando…' : 'Publicar 🚀' }}
            </button>
            <span v-else class="text-[10px] text-n-slate-9">rascunho salvo vai para o admin publicar</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
