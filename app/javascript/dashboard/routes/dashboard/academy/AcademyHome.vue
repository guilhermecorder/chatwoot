<script setup>
// Academia CEVICO — educação do time interno (item 77).
// Duas áreas: TRILHAS (cards estilo streaming, agora com os temas dos
// GARGALOS da jornada do paciente) e FERRAMENTAS (o Guilherme escreve
// ferramentas de trabalho em texto e o time lê em página bonita).
import { ref, computed, onMounted } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';

const currentRole = useMapGetter('getCurrentRole');
const isAdmin = computed(() => currentRole.value === 'administrator');

const activeTab = ref('trilhas'); // trilhas | ferramentas

// ── TRILHAS ─────────────────────────────────────────────────────────
// A primeira seção ataca os GARGALOS reais do funil (item 77): cada tema
// nasce de um ponto onde o lead trava na jornada.
const TRACKS = [
  {
    section: 'Gargalos da jornada — onde o lead trava (e como destravar)',
    items: [
      {
        title: 'Lead novo que não responde',
        desc: 'Primeira resposta em minutos + follow-up que reabre a conversa sem afastar',
        icon: 'i-lucide-message-circle-question',
        gradient: 'linear-gradient(135deg, #DC2626 0%, #7f1d1d 100%)',
      },
      {
        title: 'Orçamento enviado que esfria',
        desc: 'Quebra de objeções de preço e o caminho de volta para a consulta',
        icon: 'i-lucide-snowflake',
        gradient: 'linear-gradient(135deg, #0E7490 0%, #164e63 100%)',
      },
      {
        title: 'Agendou e não veio (no-show)',
        desc: 'Confirmação de véspera, lembretes com carinho e reagendamento imediato',
        icon: 'i-lucide-calendar-x',
        gradient: 'linear-gradient(135deg, #D97706 0%, #92400e 100%)',
      },
      {
        title: 'Indicação de cirurgia sem fechamento',
        desc: 'Do "vou pensar" ao sim: acompanhamento longo com elegância',
        icon: 'i-lucide-hourglass',
        gradient: 'linear-gradient(135deg, #7C3AED 0%, #4c1d95 100%)',
      },
      {
        title: 'Pós-operatório sem indicação',
        desc: 'NPS alto virando novas indicações — o paciente feliz traz o próximo',
        icon: 'i-lucide-heart-plus',
        gradient: 'linear-gradient(135deg, #059669 0%, #064e3b 100%)',
      },
    ],
  },
  {
    section: 'Trilhas de Treinamento',
    items: [
      {
        title: 'Treinamento para Médicos',
        desc: 'Protocolos, jornada do paciente e boas práticas clínicas',
        icon: 'i-lucide-stethoscope',
        gradient: 'linear-gradient(135deg, #0F5FA6 0%, #063a68 100%)',
      },
      {
        title: 'Treinamento para Vendedores',
        desc: 'Do primeiro contato ao fechamento da cirurgia',
        icon: 'i-lucide-trending-up',
        gradient: 'linear-gradient(135deg, #BF953F 0%, #7a5c1e 100%)',
      },
      {
        title: 'Atendimento WhatsApp Pós-Cirurgia',
        desc: 'Acompanhamento, cuidados e encantamento no pós-operatório',
        icon: 'i-lucide-heart-handshake',
        gradient: 'linear-gradient(135deg, #12A594 0%, #0a5d54 100%)',
      },
      {
        title: 'Agendamento de Consultas',
        desc: 'Scripts e fluxo ideal para converter conversas em consultas',
        icon: 'i-lucide-calendar-check',
        gradient: 'linear-gradient(135deg, #6E56CF 0%, #3d2f74 100%)',
      },
      {
        title: 'Agendamento de Cirurgias',
        desc: 'Orçamento, indicação e confirmação cirúrgica sem fricção',
        icon: 'i-lucide-calendar-heart',
        gradient: 'linear-gradient(135deg, #E54666 0%, #83243c 100%)',
      },
    ],
  },
  {
    section: 'Procedimentos Mapeados',
    items: [
      {
        title: 'Cirurgia Refrativa',
        desc: 'Jornada completa: captação, orçamento e conversão',
        icon: 'i-lucide-eye',
        gradient: 'linear-gradient(135deg, #2781F6 0%, #0d3a75 100%)',
      },
      {
        title: 'Catarata',
        desc: 'Fluxo do diagnóstico ao pós-operatório',
        icon: 'i-lucide-scan-eye',
        gradient: 'linear-gradient(135deg, #0F5FA6 0%, #BF953F 130%)',
      },
      {
        title: 'Consultas e Exames',
        desc: 'Padrões de atendimento e triagem',
        icon: 'i-lucide-clipboard-list',
        gradient: 'linear-gradient(135deg, #12A594 0%, #0F5FA6 130%)',
      },
    ],
  },
  {
    section: 'Materiais de Apoio',
    items: [
      {
        title: 'Checklists Operacionais',
        desc: 'Passo a passo de cada rotina do dia a dia',
        icon: 'i-lucide-list-checks',
        gradient: 'linear-gradient(135deg, #60646C 0%, #1c2024 100%)',
      },
      {
        title: 'Scripts de Atendimento',
        desc: 'Mensagens prontas e tom de voz CEVICO',
        icon: 'i-lucide-message-square-quote',
        gradient: 'linear-gradient(135deg, #BF953F 0%, #0F5FA6 140%)',
      },
      {
        title: 'Cultura CEVICO',
        desc: 'Valores, responsabilidades e o jeito de servir do time',
        icon: 'i-lucide-gem',
        gradient: 'linear-gradient(135deg, #6E56CF 0%, #E54666 140%)',
      },
    ],
  },
];

// ── FERRAMENTAS ─────────────────────────────────────────────────────
const tools = ref([]);
const canEdit = ref(false);
const loadingTools = ref(false);

const loadTools = async () => {
  loadingTools.value = true;
  try {
    const { data } = await CrmAPI.getTeamTools();
    tools.value = data.tools || [];
    canEdit.value = data.can_edit === true;
  } catch {
    tools.value = [];
  } finally {
    loadingTools.value = false;
  }
};
onMounted(loadTools);

// agrupadas por categoria (vazia = "Geral"), na ordem de posição
const toolGroups = computed(() => {
  const groups = new Map();
  tools.value.forEach(tool => {
    const key = tool.category || 'Geral';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(tool);
  });
  return [...groups.entries()].map(([category, items]) => ({ category, items }));
});

// ── leitura em "texto bonito": marcação leve → blocos estruturados ──
// (sem v-html: o texto é quebrado em blocos e trechos, nunca injetado)
const parseInline = text => {
  const parts = [];
  const re = /\*\*(.+?)\*\*/g;
  let last = 0;
  let m = re.exec(text);
  while (m !== null) {
    if (m.index > last) parts.push({ text: text.slice(last, m.index), bold: false });
    parts.push({ text: m[1], bold: true });
    last = m.index + m[0].length;
    m = re.exec(text);
  }
  if (last < text.length) parts.push({ text: text.slice(last), bold: false });
  return parts.length ? parts : [{ text, bold: false }];
};

const parseContent = raw => {
  const blocks = [];
  (raw || '').split('\n').forEach(line => {
    const t = line.trim();
    if (!t) return;
    if (t === '---') blocks.push({ type: 'divider' });
    else if (t.startsWith('## ')) blocks.push({ type: 'h3', parts: parseInline(t.slice(3)) });
    else if (t.startsWith('# ')) blocks.push({ type: 'h2', parts: parseInline(t.slice(2)) });
    else if (t.startsWith('> ')) blocks.push({ type: 'quote', parts: parseInline(t.slice(2)) });
    else if (/^(-|\*|•)\s/.test(t)) blocks.push({ type: 'bullet', parts: parseInline(t.replace(/^(-|\*|•)\s/, '')) });
    else if (/^\d+[.)]\s/.test(t)) blocks.push({ type: 'num', num: t.match(/^(\d+)/)[1], parts: parseInline(t.replace(/^\d+[.)]\s/, '')) });
    else blocks.push({ type: 'p', parts: parseInline(t) });
  });
  return blocks;
};

// ── leitura ──
const readingTool = ref(null);
const readingBlocks = computed(() =>
  readingTool.value ? parseContent(readingTool.value.content) : []
);
const openTool = tool => {
  readingTool.value = tool;
};

// ── editor (só admin) ──
const showEditor = ref(false);
const editingId = ref(null);
const savingTool = ref(false);
const toolForm = ref({ title: '', emoji: '🧰', category: '', content: '', published: true });

const startNewTool = () => {
  editingId.value = null;
  toolForm.value = { title: '', emoji: '🧰', category: '', content: '', published: true };
  showEditor.value = true;
};
const startEditTool = tool => {
  editingId.value = tool.id;
  toolForm.value = {
    title: tool.title,
    emoji: tool.emoji,
    category: tool.category,
    content: tool.content,
    published: tool.published,
  };
  readingTool.value = null;
  showEditor.value = true;
};

const previewBlocks = computed(() => parseContent(toolForm.value.content));

const saveTool = async () => {
  if (!toolForm.value.title.trim()) {
    useAlert('Dê um título à ferramenta.');
    return;
  }
  savingTool.value = true;
  try {
    if (editingId.value) await CrmAPI.updateTeamTool(editingId.value, toolForm.value);
    else await CrmAPI.createTeamTool(toolForm.value);
    useAlert(editingId.value ? 'Ferramenta atualizada. 🧰' : 'Ferramenta criada. 🧰');
    showEditor.value = false;
    await loadTools();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui salvar.');
  } finally {
    savingTool.value = false;
  }
};

const removeTool = async tool => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Excluir a ferramenta "${tool.title}"?`)) return;
  try {
    await CrmAPI.deleteTeamTool(tool.id);
    readingTool.value = null;
    await loadTools();
  } catch {
    useAlert('Não consegui excluir.');
  }
};

const fmtDate = iso =>
  new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <!-- Hero -->
    <div
      class="px-8 pt-10 pb-6 relative overflow-hidden flex-shrink-0"
      style="background: linear-gradient(120deg, rgba(15,95,166,0.14), rgba(191,149,63,0.12) 60%, transparent)"
    >
      <p class="text-xs font-semibold tracking-widest text-n-gold uppercase mb-1">
        Educação do time
      </p>
      <h1 class="text-2xl font-bold text-n-slate-12 flex items-center gap-2">
        <span class="i-lucide-graduation-cap text-n-brand" />
        Academia CEVICO
      </h1>
      <p class="text-sm text-n-slate-10 mt-2 max-w-xl">
        Treinamentos, checklists, scripts e as ferramentas de trabalho do time —
        tudo para elevar o padrão de atendimento.
      </p>

      <!-- abas -->
      <div class="flex gap-1 mt-4">
        <button
          class="px-3.5 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'trilhas' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'trilhas' ? { background: 'linear-gradient(135deg, #0F5FA6, #3B82F6)' } : {}"
          @click="activeTab = 'trilhas'"
        >
          <span class="i-lucide-graduation-cap text-xs" />
          Trilhas
        </button>
        <button
          class="px-3.5 py-1.5 text-sm font-medium rounded-lg transition-colors flex items-center gap-1.5"
          :class="activeTab === 'ferramentas' ? 'text-white font-bold shadow-sm' : 'text-n-slate-11 hover:bg-n-alpha-1'"
          :style="activeTab === 'ferramentas' ? { background: 'linear-gradient(135deg, #B8860B, #D4A017)' } : {}"
          @click="activeTab = 'ferramentas'"
        >
          <span class="i-lucide-wrench text-xs" />
          Ferramentas
          <span v-if="tools.length" class="text-[10px] font-bold px-1.5 rounded-full bg-white/25">{{ tools.length }}</span>
        </button>
      </div>
    </div>

    <!-- ══ TRILHAS ══ -->
    <div v-if="activeTab === 'trilhas'" class="px-8 pb-10 space-y-8">
      <!-- Destaque: Sistema TACOH (link externo, ao vivo) -->
      <div>
        <h2 class="text-sm font-semibold text-n-slate-12 mb-3">Destaque</h2>
        <a
          href="https://cevico.guilhermecorder.com.br/conteudos/"
          target="_blank"
          rel="noopener noreferrer"
          class="group relative flex items-center gap-6 rounded-2xl overflow-hidden p-6 transition-transform duration-200 hover:scale-[1.01] hover:shadow-xl"
          style="background: linear-gradient(120deg, #0a1c3d 0%, #10254f 55%, #16305f 100%)"
        >
          <!-- Logo TACOH -->
          <svg viewBox="0 0 200 200" class="w-28 h-28 flex-shrink-0 drop-shadow" xmlns="http://www.w3.org/2000/svg">
            <defs>
              <linearGradient id="tacoh-gold" x1="0" y1="0" x2="1" y2="1">
                <stop offset="0%" stop-color="#E7CC8A" />
                <stop offset="50%" stop-color="#C6A15B" />
                <stop offset="100%" stop-color="#9c7a34" />
              </linearGradient>
            </defs>
            <circle cx="100" cy="100" r="78" fill="none" stroke="url(#tacoh-gold)" stroke-width="9" />
            <!-- nós com letras -->
            <g font-family="Georgia, serif" font-weight="bold" font-size="20" fill="#0a1c3d" text-anchor="middle">
              <g><circle cx="100" cy="22" r="15" fill="url(#tacoh-gold)" /><text x="100" y="29">T</text></g>
              <g><circle cx="174" cy="76" r="15" fill="url(#tacoh-gold)" /><text x="174" y="83">A</text></g>
              <g><circle cx="146" cy="163" r="15" fill="url(#tacoh-gold)" /><text x="146" y="170">C</text></g>
              <g><circle cx="54" cy="163" r="15" fill="url(#tacoh-gold)" /><text x="54" y="170">O</text></g>
              <g><circle cx="26" cy="76" r="15" fill="url(#tacoh-gold)" /><text x="26" y="83">H</text></g>
            </g>
            <!-- funil central -->
            <g font-family="Georgia, serif" font-weight="bold" fill="#E7CC8A" text-anchor="middle">
              <text x="100" y="92" font-size="15">GANCHO</text>
              <text x="100" y="108" font-size="10" fill="#C6A15B">↓</text>
              <text x="100" y="123" font-size="15">CORPO</text>
            </g>
          </svg>

          <div class="flex-1 min-w-0">
            <span class="text-[10px] font-bold uppercase tracking-widest text-n-gold">Sistema TACOH</span>
            <h3 class="text-lg font-bold text-white mt-1 leading-snug">
              Sistema Tacoh para produção de conteúdos
            </h3>
            <p class="text-sm text-white/70 mt-1">
              Método de criação de conteúdo: Gancho → Corpo → CTA. Clique para acessar o material completo.
            </p>
            <span class="inline-flex items-center gap-1 mt-3 text-sm font-semibold text-n-gold group-hover:gap-2 transition-all">
              Acessar conteúdos
              <span class="i-lucide-external-link text-xs" />
            </span>
          </div>
        </a>
      </div>

      <div v-for="section in TRACKS" :key="section.section">
        <h2 class="text-sm font-semibold text-n-slate-12 mb-3">{{ section.section }}</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <div
            v-for="item in section.items"
            :key="item.title"
            class="group relative rounded-2xl overflow-hidden cursor-pointer transition-transform duration-200 hover:scale-[1.03] hover:shadow-xl"
            style="aspect-ratio: 16/9"
            :style="{ background: item.gradient }"
          >
            <!-- brilho -->
            <div class="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300"
                 style="background: radial-gradient(600px 200px at 30% 0%, rgba(255,255,255,0.14), transparent)" />

            <!-- selo em breve -->
            <span class="absolute top-3 right-3 text-[10px] font-bold uppercase tracking-wide px-2 py-1 rounded-full bg-black/35 text-white backdrop-blur-sm">
              Em breve
            </span>

            <!-- conteúdo -->
            <div class="absolute inset-0 flex flex-col justify-end p-4">
              <span :class="item.icon" class="text-3xl text-white/90 mb-2" />
              <p class="text-sm font-bold text-white leading-tight">{{ item.title }}</p>
              <p class="text-[11px] text-white/75 mt-1 leading-snug">{{ item.desc }}</p>
            </div>
          </div>
        </div>
      </div>

      <p class="text-xs text-n-slate-9 max-w-2xl">
        Este é o espaço de cultura e educação da CEVICO. Cada card vai virar uma trilha com
        vídeos, documentos e avaliações — administrados por aqui mesmo, sem ferramentas externas.
      </p>
    </div>

    <!-- ══ FERRAMENTAS ══ -->
    <div v-else class="px-8 pb-10">
      <div class="flex items-center justify-between mb-4 flex-wrap gap-2 max-w-4xl">
        <p class="text-sm text-n-slate-11">
          Ferramentas de trabalho escritas para o time — abra e use no atendimento.
        </p>
        <button
          v-if="canEdit"
          class="h-9 px-4 rounded-lg text-sm font-bold text-white flex items-center gap-1.5"
          style="background: linear-gradient(135deg, #B8860B, #D4A017)"
          @click="startNewTool"
        >
          <span class="i-lucide-plus text-sm" />
          Nova ferramenta
        </button>
      </div>

      <div v-if="loadingTools" class="py-16 text-center text-n-slate-10 text-sm">Carregando…</div>

      <div v-else-if="!tools.length" class="max-w-4xl rounded-2xl border border-n-weak bg-n-solid-2 py-14 text-center">
        <p class="text-4xl mb-3">🧰</p>
        <p class="text-sm font-semibold text-n-slate-12 mb-1">Nenhuma ferramenta publicada ainda</p>
        <p class="text-xs text-n-slate-10 max-w-md mx-auto">
          <template v-if="canEdit">
            Crie a primeira: um script de fechamento, o método de confirmação de véspera,
            o checklist do pós-operatório — escrito uma vez, usado pelo time inteiro.
          </template>
          <template v-else>O Guilherme está preparando as primeiras ferramentas do time.</template>
        </p>
      </div>

      <div v-else class="space-y-6 max-w-4xl">
        <div v-for="group in toolGroups" :key="group.category">
          <h2 class="text-xs font-bold text-n-slate-9 uppercase tracking-wide mb-2">{{ group.category }}</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <button
              v-for="tool in group.items"
              :key="tool.id"
              class="text-left rounded-2xl border border-n-weak bg-n-solid-2 p-4 hover:border-n-gold hover:shadow-md transition-all relative"
              @click="openTool(tool)"
            >
              <span v-if="!tool.published" class="absolute top-2.5 right-2.5 text-[9px] font-bold uppercase px-1.5 py-0.5 rounded-full bg-amber-500/15 text-amber-600">rascunho</span>
              <span class="text-2xl block mb-2">{{ tool.emoji }}</span>
              <p class="text-sm font-bold text-n-slate-12 leading-snug">{{ tool.title }}</p>
              <p class="text-[10px] text-n-slate-9 mt-1.5">Atualizada em {{ fmtDate(tool.updated_at) }}</p>
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══ LEITURA (texto bonito) ══ -->
    <div
      v-if="readingTool"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="readingTool = null"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-2xl max-h-[88vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #152C61, #D4AF37)" />
        <div class="flex items-start justify-between px-6 sm:px-8 pt-6 pb-4 border-b border-n-weak flex-shrink-0">
          <div class="min-w-0">
            <p v-if="readingTool.category" class="text-[10px] font-bold uppercase tracking-widest text-n-gold mb-1">{{ readingTool.category }}</p>
            <h2 class="text-xl font-bold text-n-slate-12 leading-tight" style="font-family: Georgia, 'Times New Roman', serif">
              {{ readingTool.emoji }} {{ readingTool.title }}
            </h2>
          </div>
          <div class="flex items-center gap-1 flex-shrink-0 ml-3">
            <button
              v-if="canEdit"
              class="w-8 h-8 rounded-lg hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-10"
              title="Editar"
              @click="startEditTool(readingTool)"
            >
              <span class="i-lucide-pencil text-sm" />
            </button>
            <button
              v-if="canEdit"
              class="w-8 h-8 rounded-lg hover:bg-red-500/10 flex items-center justify-center text-n-slate-10 hover:text-red-500"
              title="Excluir"
              @click="removeTool(readingTool)"
            >
              <span class="i-lucide-trash-2 text-sm" />
            </button>
            <button class="w-8 h-8 rounded-lg hover:bg-n-alpha-2 flex items-center justify-center text-n-slate-10" @click="readingTool = null">
              <span class="i-lucide-x text-base" />
            </button>
          </div>
        </div>
        <div class="px-6 sm:px-8 py-6 overflow-y-auto">
          <div v-if="!readingBlocks.length" class="text-sm text-n-slate-10 italic">Ainda sem conteúdo.</div>
          <template v-for="(block, i) in readingBlocks" :key="i">
            <hr v-if="block.type === 'divider'" class="my-5 border-n-weak" />
            <h3
              v-else-if="block.type === 'h2'"
              class="text-lg font-bold mt-5 mb-2 first:mt-0"
              style="font-family: Georgia, 'Times New Roman', serif; color: #B8860B"
            >
              <template v-for="(part, j) in block.parts" :key="j">{{ part.text }}</template>
            </h3>
            <h4 v-else-if="block.type === 'h3'" class="text-sm font-bold text-n-slate-12 mt-4 mb-1.5">
              <template v-for="(part, j) in block.parts" :key="j">{{ part.text }}</template>
            </h4>
            <blockquote
              v-else-if="block.type === 'quote'"
              class="border-l-4 pl-4 py-1 my-3 text-sm italic text-n-slate-11"
              style="border-color: #D4AF37"
            >
              <template v-for="(part, j) in block.parts" :key="j">
                <b v-if="part.bold">{{ part.text }}</b><template v-else>{{ part.text }}</template>
              </template>
            </blockquote>
            <p v-else-if="block.type === 'bullet'" class="text-sm text-n-slate-11 leading-relaxed flex gap-2 mb-1.5">
              <span class="flex-shrink-0 mt-1.5 w-1.5 h-1.5 rounded-full" style="background: #D4AF37" />
              <span>
                <template v-for="(part, j) in block.parts" :key="j">
                  <b v-if="part.bold" class="text-n-slate-12">{{ part.text }}</b><template v-else>{{ part.text }}</template>
                </template>
              </span>
            </p>
            <p v-else-if="block.type === 'num'" class="text-sm text-n-slate-11 leading-relaxed flex gap-2 mb-1.5">
              <b class="flex-shrink-0 tabular-nums" style="color: #B8860B">{{ block.num }}.</b>
              <span>
                <template v-for="(part, j) in block.parts" :key="j">
                  <b v-if="part.bold" class="text-n-slate-12">{{ part.text }}</b><template v-else>{{ part.text }}</template>
                </template>
              </span>
            </p>
            <p v-else class="text-sm text-n-slate-11 leading-relaxed mb-3">
              <template v-for="(part, j) in block.parts" :key="j">
                <b v-if="part.bold" class="text-n-slate-12">{{ part.text }}</b><template v-else>{{ part.text }}</template>
              </template>
            </p>
          </template>
        </div>
      </div>
    </div>

    <!-- ══ EDITOR (só admin) ══ -->
    <div
      v-if="showEditor"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      @click.self="showEditor = false"
    >
      <div class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-4xl max-h-[90vh] flex flex-col overflow-hidden">
        <div class="h-1.5 w-full flex-shrink-0" style="background: linear-gradient(135deg, #B8860B, #D4A017)" />
        <div class="flex items-center justify-between px-6 py-4 border-b border-n-weak flex-shrink-0">
          <h2 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-wrench" style="color: #B8860B" />
            {{ editingId ? 'Editar ferramenta' : 'Nova ferramenta' }}
          </h2>
          <button class="text-n-slate-10 hover:text-n-slate-12 i-lucide-x text-xl" @click="showEditor = false" />
        </div>

        <div class="p-6 overflow-y-auto">
          <div class="flex items-end gap-3 flex-wrap mb-4">
            <label class="block">
              <span class="text-[11px] font-medium text-n-slate-11">Emoji</span>
              <input
                v-model="toolForm.emoji"
                type="text"
                class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-base text-center"
                style="width: 4rem; margin-bottom: 0"
              />
            </label>
            <label class="block flex-1" style="min-width: 14rem">
              <span class="text-[11px] font-medium text-n-slate-11">Título</span>
              <input
                v-model="toolForm.title"
                type="text"
                placeholder="Ex: Script de confirmação de véspera"
                class="mt-1 block w-full h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12"
                style="margin-bottom: 0"
              />
            </label>
            <label class="block">
              <span class="text-[11px] font-medium text-n-slate-11">Categoria (opcional)</span>
              <input
                v-model="toolForm.category"
                type="text"
                placeholder="Ex: Vendas"
                class="mt-1 block h-9 rounded-lg border border-n-weak bg-n-solid-2 px-2 text-sm text-n-slate-12"
                style="width: 10rem; margin-bottom: 0"
              />
            </label>
            <label class="flex items-center gap-2 text-xs text-n-slate-11 cursor-pointer h-9">
              <input v-model="toolForm.published" type="checkbox" class="rounded" />
              Publicada para o time
            </label>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            <label class="block">
              <span class="text-[11px] font-medium text-n-slate-11">
                Conteúdo — <b># título</b>, <b>## subtítulo</b>, <b>- lista</b>, <b>1. passos</b>, <b>&gt; citação</b>, <b>**negrito**</b>, <b>---</b> divisor
              </span>
              <textarea
                v-model="toolForm.content"
                rows="16"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm text-n-slate-12 font-mono"
                placeholder="# Quando usar&#10;Na véspera de toda consulta agendada.&#10;&#10;## O script&#10;> Oi [nome]! Amanhã é o seu dia na CEVICO 💙&#10;&#10;1. Enviar até as 18h&#10;2. Sem resposta em 2h → ligar&#10;- **Nunca** cancelar direto: sempre oferecer reagendamento"
              />
            </label>
            <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 overflow-y-auto" style="max-height: 24rem">
              <p class="text-[10px] font-bold uppercase tracking-widest text-n-slate-9 mb-3">Prévia — como o time vai ler</p>
              <p v-if="!previewBlocks.length" class="text-xs text-n-slate-9 italic">Escreva ao lado para ver a prévia.</p>
              <template v-for="(block, i) in previewBlocks" :key="i">
                <hr v-if="block.type === 'divider'" class="my-4 border-n-weak" />
                <h3 v-else-if="block.type === 'h2'" class="text-base font-bold mt-4 mb-1.5 first:mt-0" style="font-family: Georgia, serif; color: #B8860B">
                  <template v-for="(part, j) in block.parts" :key="j">{{ part.text }}</template>
                </h3>
                <h4 v-else-if="block.type === 'h3'" class="text-xs font-bold text-n-slate-12 mt-3 mb-1">
                  <template v-for="(part, j) in block.parts" :key="j">{{ part.text }}</template>
                </h4>
                <blockquote v-else-if="block.type === 'quote'" class="border-l-4 pl-3 py-0.5 my-2 text-xs italic text-n-slate-11" style="border-color: #D4AF37">
                  <template v-for="(part, j) in block.parts" :key="j">
                    <b v-if="part.bold">{{ part.text }}</b><template v-else>{{ part.text }}</template>
                  </template>
                </blockquote>
                <p v-else-if="block.type === 'bullet'" class="text-xs text-n-slate-11 leading-relaxed flex gap-1.5 mb-1">
                  <span class="flex-shrink-0 mt-1.5 w-1 h-1 rounded-full" style="background: #D4AF37" />
                  <span>
                    <template v-for="(part, j) in block.parts" :key="j">
                      <b v-if="part.bold" class="text-n-slate-12">{{ part.text }}</b><template v-else>{{ part.text }}</template>
                    </template>
                  </span>
                </p>
                <p v-else-if="block.type === 'num'" class="text-xs text-n-slate-11 leading-relaxed flex gap-1.5 mb-1">
                  <b class="flex-shrink-0 tabular-nums" style="color: #B8860B">{{ block.num }}.</b>
                  <span>
                    <template v-for="(part, j) in block.parts" :key="j">
                      <b v-if="part.bold" class="text-n-slate-12">{{ part.text }}</b><template v-else>{{ part.text }}</template>
                    </template>
                  </span>
                </p>
                <p v-else class="text-xs text-n-slate-11 leading-relaxed mb-2">
                  <template v-for="(part, j) in block.parts" :key="j">
                    <b v-if="part.bold" class="text-n-slate-12">{{ part.text }}</b><template v-else>{{ part.text }}</template>
                  </template>
                </p>
              </template>
            </div>
          </div>
        </div>

        <div class="px-6 py-4 border-t border-n-weak flex gap-2 flex-shrink-0">
          <button
            class="flex-1 flex items-center justify-center gap-1.5 text-sm font-semibold text-white py-2 rounded-lg disabled:opacity-50"
            style="background: linear-gradient(135deg, #B8860B, #D4A017)"
            :disabled="savingTool"
            @click="saveTool"
          >
            <span :class="savingTool ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-check'" class="text-sm" />
            {{ savingTool ? 'Salvando…' : editingId ? 'Salvar alterações' : 'Criar ferramenta' }}
          </button>
          <button class="px-4 border border-n-weak rounded-lg py-2 text-sm text-n-slate-11" @click="showEditor = false">
            Cancelar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
