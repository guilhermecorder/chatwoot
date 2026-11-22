<script setup>
// 🪝 item 397: AMBIENTE DE CRIAÇÃO — botão "Criar criativo" e os passos em
// sanfona: 1 Gancho (escolhe o TIPO em cartões, vê os ganchos daquele tipo
// com filtro, usa um) → 2 História → 3 Oferta → 4 Copy pronta. Fechado,
// cada passo mostra o resumo do que foi escolhido.
import { ref, computed, nextTick, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import CbSanfona from './CbSanfona.vue';
import CbFiltros from './CbFiltros.vue';
import CbPeca from './CbPeca.vue';
import CbFormulario from './CbFormulario.vue';
import { TIPOS, TIPO, filtrosPadrao, passaFiltro } from './cbMeta';

const props = defineProps({
  blocks: { type: Array, required: true },
  podeEditar: { type: Boolean, default: false },
  // 🏢 { nome, clinica, ramo, temas } — fora da clínica: tema livre e sem selo de saúde
  empresa: { type: Object, default: () => ({ clinica: true }) },
  formInicial: { type: [Number, String], default: null }, // veio de "Usar na copy" (Formulários)
});
const emit = defineEmits(['favoritar', 'draftSalvo']);

const TEMAS = [
  { key: 'refrativa', label: 'Refrativa' },
  { key: 'catarata', label: 'Catarata' },
  { key: 'avaliacao', label: 'Avaliação' },
  { key: 'geral', label: 'Geral' },
];
const FORMATOS = [
  { key: 'reels', label: 'Reels' },
  { key: 'carrossel', label: 'Carrossel' },
  { key: 'anuncio', label: 'Anúncio' },
  { key: 'post', label: 'Post' },
];
const PAGE = 20;

const iniciado = ref(false);
const tema = ref('refrativa');
const formato = ref('reels');
const notas = ref('');
const aberto = ref({ gancho: true });
const abrirSo = k => {
  aberto.value = { [k]: true };
  nextTick(() => document.getElementById(`cb-passo-${k}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' }));
};
const toggle = k => {
  aberto.value = { ...aberto.value, [k]: !aberto.value[k] };
};

const ofKind = k => props.blocks.filter(b => b.kind === k);
const historias = computed(() => ofKind('historia'));
const ofertas = computed(() => ofKind('oferta'));
const reganchos = computed(() => ofKind('regancho'));
const ganchos = computed(() => ofKind('gancho'));

// ── passo 1: tipo → lista filtrada ──
const tipo = ref(null); // key de TIPOS | 'favoritos' | 'usados' | 'todos'
const clinica = computed(() => props.empresa?.clinica !== false);
const filtroBase = () => ({ ...filtrosPadrao(), saude: clinica.value ? 'uteis' : 'todos' });
const filtros = ref(filtroBase());
const temaLivre = ref('');
// 🧾 o que foi puxado do formulário e vai para a IA
const contexto = ref([]);
const limite = ref(PAGE);
const ESPECIAIS = [
  { key: 'favoritos', label: 'Favoritos', icon: 'i-lucide-star', color: '#ca8a04', desc: 'Os que você marcou com ⭐' },
  { key: 'usados', label: 'Mais usados', icon: 'i-lucide-trophy', color: '#9333ea', desc: 'Os que o time mais escolhe' },
  { key: 'todos', label: 'Buscar em todos', icon: 'i-lucide-search', color: '#475569', desc: 'Todos os tipos juntos' },
];
const contaTipo = k => ganchos.value.filter(g => (g.categoria || 'cevico') === k && (!clinica.value || g.saude !== 'evitar')).length;
const tiposComGancho = computed(() => TIPOS.filter(t => contaTipo(t.key) > 0));
const tipoAtual = computed(() => TIPO[tipo.value] || ESPECIAIS.find(e => e.key === tipo.value));
const escolherTipo = k => {
  tipo.value = k;
  limite.value = PAGE;
  gerados.value = [];
  filtros.value = { ...filtroBase(), favoritos: k === 'favoritos', usados: k === 'usados' };
};
const lista = computed(() => {
  let l = ganchos.value;
  if (tipo.value && TIPO[tipo.value]) l = l.filter(g => (g.categoria || 'cevico') === tipo.value);
  l = l.filter(g => passaFiltro(g, filtros.value));
  if (filtros.value.usados) l = [...l].sort((a, b) => b.usos - a.usos);
  return l;
});

const gancho = ref({ texto: '', modelo: null });
const lacunaValores = ref({});
const lacunasAbertas = computed(() => [...new Set((gancho.value.texto.match(/\[([^[\]]{1,60})\]/g) || []).map(s => s.slice(1, -1)))]);
const aplicarLacuna = nome => {
  const v = String(lacunaValores.value[nome] || '').trim();
  if (!v) return;
  gancho.value.texto = gancho.value.texto.split(`[${nome}]`).join(v);
  delete lacunaValores.value[nome];
};
const marcarUso = b => {
  if (!b?.id) return;
  b.usos += 1;
  CrmAPI.useCopyBlock(b.id).catch(() => {});
};
const usarGancho = (modelo, texto) => {
  gancho.value = { texto: texto || modelo.texto, modelo };
  lacunaValores.value = {};
  marcarUso(modelo);
  nextTick(() => document.getElementById('cb-seu-gancho')?.scrollIntoView({ behavior: 'smooth', block: 'center' }));
};

// IA: 8 ganchos do tipo escolhido, já preenchidos para o tema
// o que toda chamada da IA leva: tema, formato, observações e o contexto do formulário
const baseIA = () => ({ tema: tema.value, tema_livre: clinica.value ? '' : temaLivre.value, formato: formato.value, notas: notas.value, contexto: contexto.value });
const gerando = ref('');
const gerados = ref([]);
const gerarGanchos = async () => {
  gerando.value = 'ganchos';
  try {
    const categoria = TIPO[tipo.value] ? tipo.value : null;
    const ids = categoria ? [] : lista.value.slice(0, 8).map(g => g.id);
    const { data } = await CrmAPI.generateCopyHooks({ ...baseIA(), categoria, ids });
    gerados.value = data.ganchos || [];
    if (!gerados.value.length) useAlert('A IA não devolveu ganchos. Tente de novo.');
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não consegui gerar agora.');
  } finally {
    gerando.value = '';
  }
};

// ── passo 2: história ──
const historia = ref('');
const historiaModelo = ref(null);
const historiaEl = ref(null);
const usarHistoria = h => {
  if (historia.value.trim() && historiaModelo.value?.id !== h.id && !window.confirm('Trocar o texto da história por esta estrutura?')) return;
  historiaModelo.value = h;
  historia.value = h.texto;
  marcarUso(h);
};
const inserirRegancho = r => {
  const el = historiaEl.value;
  const txt = historia.value;
  const pos = el && typeof el.selectionStart === 'number' ? el.selectionStart : txt.length;
  const antes = txt.slice(0, pos).replace(/\s*$/, '');
  const depois = txt.slice(pos).replace(/^\s*/, '');
  const meio = `${antes ? '\n\n' : ''}${r.texto}${depois ? '\n\n' : ''}`;
  historia.value = antes + meio + depois;
  marcarUso(r);
  nextTick(() => {
    if (!el) return;
    const p = (antes + meio).length;
    el.focus();
    el.setSelectionRange(p, p);
  });
};

// ── passo 3: oferta ──
const oferta = ref('');
const usarOferta = o => {
  oferta.value = o.texto;
  marcarUso(o);
};

// ── passo 4: copy pronta ──
const iaReganchos = ref(true);
const escreverCopy = async () => {
  if (!gancho.value.texto.trim()) {
    useAlert('Escolha um gancho primeiro (passo 1).');
    abrirSo('gancho');
    return;
  }
  gerando.value = 'copy';
  try {
    const sorteio = [...reganchos.value].sort(() => Math.random() - 0.5).slice(0, 6).map(r => r.texto);
    const { data } = await CrmAPI.generateCopyText({
      ...baseIA(),
      gancho: gancho.value.texto,
      historia_modelo: historiaModelo.value ? `${historiaModelo.value.categoria}: ${historiaModelo.value.texto}` : '',
      historia: historia.value,
      oferta: oferta.value,
      reganchos: iaReganchos.value ? sorteio : [],
    });
    gancho.value.texto = data.gancho || gancho.value.texto;
    historia.value = data.historia || historia.value;
    oferta.value = data.oferta || oferta.value;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não consegui escrever agora.');
  } finally {
    gerando.value = '';
  }
};
const textoFinal = computed(() => [gancho.value.texto, historia.value, oferta.value].map(s => s.trim()).filter(Boolean).join('\n\n'));
const faltaLacuna = computed(() => /\[[^[\]]{1,60}\]/.test(textoFinal.value));
const copiar = async () => {
  try {
    await navigator.clipboard.writeText(textoFinal.value);
    useAlert('Copiado ✓');
  } catch {
    useAlert('Não deu para copiar — selecione o texto e copie à mão.');
  }
};
const salvando = ref(false);
const salvar = async () => {
  if (!textoFinal.value) return;
  const sugestao = gancho.value.texto.trim().slice(0, 70);
  const titulo = window.prompt('Nome da criação:', sugestao);
  if (titulo === null) return;
  salvando.value = true;
  try {
    const { data } = await CrmAPI.createCopyDraft({
      titulo: titulo.trim() || sugestao || 'Criação',
      tema: tema.value,
      formato: formato.value,
      texto_final: textoFinal.value,
      partes: {
        gancho: { block_id: gancho.value.modelo?.id || null, tipo: gancho.value.modelo?.categoria || null, modelo: gancho.value.modelo?.texto || null, texto: gancho.value.texto },
        historia: { block_id: historiaModelo.value?.id || null, estrutura: historiaModelo.value?.categoria || null, texto: historia.value },
        oferta: { texto: oferta.value },
      },
    });
    emit('draftSalvo', data);
    useAlert('Salvo em Criações ✓');
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para salvar.');
  } finally {
    salvando.value = false;
  }
};

const zerar = () => {
  gancho.value = { texto: '', modelo: null };
  historia.value = '';
  historiaModelo.value = null;
  oferta.value = '';
  gerados.value = [];
  tipo.value = null;
  aberto.value = { gancho: true };
};
const criar = () => {
  if (iniciado.value && textoFinal.value && !window.confirm('Começar um criativo novo? O atual será descartado (salve antes, se quiser).')) return;
  zerar();
  iniciado.value = true;
};
// "Reabrir no Montar" (vem da aba Criações)
const carregar = d => {
  zerar();
  iniciado.value = true;
  gancho.value = { texto: d.partes?.gancho?.texto || '', modelo: null };
  historia.value = d.partes?.historia?.texto || '';
  oferta.value = d.partes?.oferta?.texto || '';
  tema.value = d.tema || tema.value;
  formato.value = d.formato || formato.value;
  aberto.value = { previa: true };
};
// do formulário: abrir um tipo de gancho / usar o gancho do ângulo
const verTipo = k => {
  escolherTipo(k);
  abrirSo('gancho');
};
const usarGanchoAngulo = texto => {
  gancho.value = { texto, modelo: null };
  abrirSo('gancho');
};
// veio de Formulários ("Usar na copy"): já abre o criativo com o público
watch(
  () => props.formInicial,
  v => {
    if (!v) return;
    iniciado.value = true;
    aberto.value = { publico: true };
  },
  { immediate: true }
);
defineExpose({ carregar });

const resumo = s => String(s || '').replace(/\s+/g, ' ').trim();

// 👁 "ver tudo": abre o detalhe (exemplo, vídeo, original) de todas as linhas
const verTudo = ref(false);
// 🪟 painel "Seu criativo" (ao lado, no computador)
const painel = computed(() => [
  { key: 'gancho', n: 1, label: 'Gancho', color: '#2563eb', texto: resumo(gancho.value.texto) },
  { key: 'historia', n: 2, label: 'História', color: '#7c3aed', texto: resumo(historia.value) },
  { key: 'oferta', n: 3, label: 'Oferta', color: '#059669', texto: resumo(oferta.value) },
]);
const palavras = computed(() => textoFinal.value.split(/\s+/).filter(Boolean).length);
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div>
    <!-- antes de começar: o botão Criar -->
    <div v-if="!iniciado" class="cv-sub p-6 sm:p-10 flex flex-col items-center text-center gap-5">
      <span class="w-16 h-16 rounded-[20px] flex items-center justify-center text-white" style="background: linear-gradient(135deg, #1d4ed8, #3b82f6)">
        <span class="i-lucide-wand-sparkles text-3xl" />
      </span>
      <div>
        <h2 class="text-2xl sm:text-3xl tracking-tight font-bold text-n-slate-12">Ambiente de criação</h2>
        <p class="text-sm sm:text-base text-n-slate-11 mt-2 max-w-xl">Um criativo em 3 passos: escolha o tipo de gancho e o gancho, escreva a história, escolha a oferta. A IA ajuda em cada um.</p>
      </div>
      <div class="flex flex-wrap justify-center gap-2 text-sm text-n-slate-11">
        <span class="cv-chip">1 · Gancho</span>
        <span class="i-lucide-arrow-right self-center" />
        <span class="cv-chip">2 · História</span>
        <span class="i-lucide-arrow-right self-center" />
        <span class="cv-chip">3 · Oferta</span>
      </div>
      <button class="cv-btn cv-blue !h-12 !px-8 !text-base" @click="criar">
        <span class="i-lucide-plus" />
        Criar criativo
      </button>
    </div>

    <template v-else>
      <!-- barra do criativo em andamento -->
      <div class="cv-sub p-4 sm:p-5 mb-5 flex flex-col gap-4">
        <div class="flex items-center gap-3 flex-wrap">
          <p class="text-sm font-semibold text-n-slate-12 flex-1">Criativo em andamento</p>
          <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="criar">
            <span class="i-lucide-plus" />
            Novo criativo
          </button>
        </div>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Sobre o quê</p>
            <div v-if="clinica" class="flex flex-wrap gap-2">
              <button v-for="t in TEMAS" :key="t.key" class="cv-chip" :class="{ 'cv-chip-on': tema === t.key }" @click="tema = t.key">{{ t.label }}</button>
            </div>
            <input v-else v-model="temaLivre" class="cv-input w-full" :placeholder="`ex.: o principal produto da ${empresa?.nome || 'empresa'}`" />
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Formato</p>
            <div class="flex flex-wrap gap-2">
              <button v-for="f in FORMATOS" :key="f.key" class="cv-chip" :class="{ 'cv-chip-on': formato === f.key }" @click="formato = f.key">{{ f.label }}</button>
            </div>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Observações para a IA</p>
            <input v-model="notas" class="cv-input w-full" placeholder="ex.: público 40+, vista cansada" />
          </div>
        </div>
      </div>

      <div class="xl:grid xl:grid-cols-[minmax(0,1fr)_280px] xl:gap-6 xl:items-start">
      <div class="min-w-0">
      <!-- 0 · O QUE O PÚBLICO DISSE (formulário) -->
      <div id="cb-passo-publico" class="scroll-mt-4">
        <CbSanfona
          :open="!!aberto.publico"
          title="O que o público disse"
          icon="i-lucide-clipboard-list"
          color="#0891b2"
          desc="Opcional: puxe o que importa de um formulário para guiar a copy"
          :summary="contexto.length ? `${contexto.length} itens do formulário vão para a copy` : ''"
          :done="contexto.length > 0 && !aberto.publico"
          @toggle="toggle('publico')"
        >
          <CbFormulario v-model="contexto" :pode-editar="podeEditar" :form-inicial="formInicial" @ver-tipo="verTipo" @usar-gancho="usarGanchoAngulo" />
        </CbSanfona>
      </div>

      <!-- 1 · GANCHO -->
      <div id="cb-passo-gancho" class="scroll-mt-4">
        <CbSanfona
          :open="!!aberto.gancho"
          title="1 · Gancho"
          icon="i-lucide-anchor"
          color="#2563eb"
          desc="Escolha o tipo de gancho e depois o gancho"
          :summary="gancho.texto ? resumo(gancho.texto) : ''"
          :done="!!gancho.texto && !aberto.gancho"
          @toggle="toggle('gancho')"
        >
          <!-- o gancho escolhido -->
          <div v-if="gancho.texto || gancho.modelo" id="cb-seu-gancho" class="rounded-2xl border-2 border-[#2563eb66] p-4 sm:p-5 mb-6">
            <p class="text-sm font-semibold text-n-slate-12 mb-2">
              Seu gancho
              <span v-if="gancho.modelo" class="font-normal text-n-slate-10">{{ ` · modelo ${TIPO[gancho.modelo.categoria]?.label || gancho.modelo.categoria}` }}</span>
            </p>
            <textarea v-model="gancho.texto" rows="2" class="cv-input w-full !h-auto py-2 text-base" />
            <div v-if="lacunasAbertas.length" class="mt-3">
              <p class="text-xs text-n-slate-10 mb-2">Preencha as lacunas (Enter aplica):</p>
              <div class="flex flex-wrap gap-3">
                <div v-for="l in lacunasAbertas" :key="l" class="flex items-center gap-2">
                  <span class="text-xs px-1 rounded bg-[#2563eb1f] text-[#2563eb] font-medium whitespace-nowrap">{{ `[${l}]` }}</span>
                  <input v-model="lacunaValores[l]" class="cv-input !h-8 w-44" placeholder="preencher…" @keydown.enter.prevent="aplicarLacuna(l)" @blur="aplicarLacuna(l)" />
                </div>
              </div>
            </div>
            <div class="flex flex-wrap gap-2 mt-4">
              <button class="cv-btn cv-blue" :disabled="!gancho.texto.trim()" @click="abrirSo('historia')">
                Pronto, ir para a História
                <span class="i-lucide-arrow-right" />
              </button>
              <button class="cv-btn cv-btn-ghost" @click="gancho = { texto: '', modelo: null }">Trocar gancho</button>
            </div>
          </div>

          <!-- escolher o TIPO -->
          <template v-if="!tipo">
            <p class="text-sm font-semibold text-n-slate-12 mb-3">Que tipo de gancho?</p>
            <div class="grid grid-cols-2 md:grid-cols-3 xl:grid-cols-4 gap-3">
              <button
                v-for="t in [...tiposComGancho, ...ESPECIAIS]"
                :key="t.key"
                class="cv-sub p-4 text-left flex flex-col gap-2 hover:-translate-y-0.5 transition-transform min-w-0"
                @click="escolherTipo(t.key)"
              >
                <span class="w-9 h-9 rounded-[11px] flex items-center justify-center text-white" :style="{ background: `linear-gradient(135deg, ${t.color}, ${t.color}cc)` }">
                  <span :class="t.icon" class="text-lg" />
                </span>
                <span class="font-bold text-n-slate-12 leading-tight">{{ t.label }}</span>
                <span class="text-xs text-n-slate-10 leading-snug">{{ t.desc }}</span>
                <span v-if="TIPO[t.key]" class="text-xs font-semibold" :style="{ color: t.color }">{{ `${contaTipo(t.key)} ganchos` }}</span>
              </button>
            </div>
          </template>

          <!-- ganchos do tipo escolhido -->
          <template v-else>
            <div class="flex items-center gap-3 flex-wrap mb-4">
              <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="tipo = null">
                <span class="i-lucide-arrow-left" />
                Tipos
              </button>
              <span class="flex items-center gap-2 font-bold text-n-slate-12 text-lg">
                <span :class="tipoAtual?.icon" :style="{ color: tipoAtual?.color }" />
                {{ tipoAtual?.label }}
              </span>
              <span class="flex-1" />
              <button class="cv-btn cv-blue" :disabled="gerando !== ''" @click="gerarGanchos">
                <span class="i-lucide-sparkles" />
                {{ gerando === 'ganchos' ? 'Gerando…' : 'Gerar 8 com IA' }}
              </button>
            </div>
            <div class="mb-5">
              <CbFiltros v-model="filtros" :total="lista.length" sem-fonte :clinica="clinica" :padrao="filtroBase()" />
            </div>
            <div class="flex items-center gap-3 mb-3">
              <p class="text-xs text-n-slate-10 flex-1">Clique numa frase para ver o exemplo e o vídeo.</p>
              <button class="cv-btn cv-btn-sm cv-btn-ghost" :class="{ 'cv-chip-on': verTudo }" @click="verTudo = !verTudo">
                <span class="i-lucide-rows-3" />
                {{ verTudo ? 'Só as frases' : 'Ver tudo' }}
              </button>
            </div>

            <div v-if="gerados.length" class="mb-6">
              <p class="text-sm font-semibold text-n-slate-12 mb-3">{{ `✨ Gerados para ${TEMAS.find(t => t.key === tema)?.label}` }}</p>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div v-for="(g, i) in gerados" :key="i" class="cv-sub p-4 flex flex-col gap-2">
                  <p class="text-base font-semibold text-n-slate-12 leading-snug">{{ g.texto }}</p>
                  <p class="text-xs text-n-slate-10">{{ `Modelo: ${g.modelo.texto}` }}</p>
                  <div class="flex flex-wrap gap-2 mt-auto">
                    <button class="cv-btn cv-btn-sm cv-blue" @click="usarGancho(g.modelo, g.texto)">Usar este</button>
                    <a v-if="g.modelo.referencia" :href="g.modelo.referencia" target="_blank" rel="noopener noreferrer" class="cv-btn cv-btn-sm cv-btn-ghost">
                      <span class="i-lucide-play" />
                      Vídeo
                    </a>
                  </div>
                </div>
              </div>
            </div>

            <p v-if="!lista.length" class="text-sm text-n-slate-10">Nenhum gancho com este filtro.</p>
            <div v-if="lista.length" class="rounded-2xl border border-n-weak divide-y divide-n-weak overflow-hidden">
              <CbPeca
                v-for="g in lista.slice(0, limite)"
                :key="g.id"
                :peca="g"
                :aberta="verTudo"
                :pode-editar="podeEditar"
                :clinica="clinica"
                :mostrar-tipo="!TIPO[tipo]"
                @usar="usarGancho"
                @usar-exemplo="p => usarGancho(p, p.exemplo)"
                @favoritar="emit('favoritar', $event)"
              />
            </div>
            <div v-if="lista.length > limite" class="flex justify-center mt-5">
              <button class="cv-btn cv-btn-ghost" @click="limite += PAGE">{{ `Ver mais (${lista.length - limite} restantes)` }}</button>
            </div>
          </template>
        </CbSanfona>
      </div>

      <!-- 2 · HISTÓRIA -->
      <div id="cb-passo-historia" class="scroll-mt-4">
        <CbSanfona
          :open="!!aberto.historia"
          title="2 · História"
          icon="i-lucide-book-open"
          color="#7c3aed"
          desc="O corpo da copy: escolha uma estrutura e escreva"
          :summary="historia ? resumo(historia) : ''"
          :done="!!historia.trim() && !aberto.historia"
          @toggle="toggle('historia')"
        >
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">Estrutura</p>
          <div class="flex flex-wrap gap-2 mb-4">
            <button v-for="h in historias" :key="h.id" class="cv-chip" :class="{ 'cv-chip-on': historiaModelo?.id === h.id }" @click="usarHistoria(h)">{{ h.categoria }}</button>
          </div>
          <textarea ref="historiaEl" v-model="historia" rows="9" class="cv-input w-full !h-auto py-3 leading-relaxed" placeholder="O corpo da copy…" />
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mt-5 mb-1">Reganchos</p>
          <p class="text-xs text-n-slate-10 mb-2">Ponha o cursor no texto e clique: a frase entra ali, para segurar a pessoa até o fim.</p>
          <div class="flex flex-wrap gap-2">
            <button v-for="r in reganchos" :key="r.id" class="cv-chip" @click="inserirRegancho(r)">{{ r.texto }}</button>
          </div>
          <button class="cv-btn cv-blue mt-5" @click="abrirSo('oferta')">
            Ir para a Oferta
            <span class="i-lucide-arrow-right" />
          </button>
        </CbSanfona>
      </div>

      <!-- 3 · OFERTA -->
      <div id="cb-passo-oferta" class="scroll-mt-4">
        <CbSanfona
          :open="!!aberto.oferta"
          title="3 · Oferta"
          icon="i-lucide-mouse-pointer-click"
          color="#059669"
          desc="O convite final (call to action)"
          :summary="oferta ? resumo(oferta) : ''"
          :done="!!oferta.trim() && !aberto.oferta"
          @toggle="toggle('oferta')"
        >
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3 mb-4">
            <button
              v-for="o in ofertas"
              :key="o.id"
              class="cv-sub p-3 text-left text-sm text-n-slate-12 hover:opacity-80"
              :class="{ 'ring-2 ring-[#2563eb]': oferta === o.texto }"
              @click="usarOferta(o)"
            >
              {{ o.texto }}
            </button>
          </div>
          <textarea v-model="oferta" rows="2" class="cv-input w-full !h-auto py-2" placeholder="Ou escreva a sua oferta." />
          <button class="cv-btn cv-blue mt-5" @click="abrirSo('previa')">
            Ver a copy pronta
            <span class="i-lucide-arrow-right" />
          </button>
        </CbSanfona>
      </div>

      <!-- 4 · COPY PRONTA -->
      <div id="cb-passo-previa" class="scroll-mt-4">
        <CbSanfona
          :open="!!aberto.previa"
          title="4 · Copy pronta"
          icon="i-lucide-file-text"
          color="#152c61"
          desc="Revise, peça ajuda à IA, copie ou salve"
          @toggle="toggle('previa')"
        >
          <label class="flex items-center gap-2 text-sm text-n-slate-11 mb-4 cursor-pointer select-none">
            <input v-model="iaReganchos" type="checkbox" />
            A IA pode espalhar reganchos ao longo da história
          </label>
          <div class="flex flex-wrap gap-3 mb-5">
            <button class="cv-btn cv-blue" :disabled="gerando !== ''" @click="escreverCopy">
              <span class="i-lucide-sparkles" />
              {{ gerando === 'copy' ? 'Escrevendo…' : 'Escrever com IA' }}
            </button>
            <button class="cv-btn" :disabled="!textoFinal || salvando" @click="salvar">
              <span class="i-lucide-save" />
              Salvar em Criações
            </button>
            <button class="cv-btn cv-btn-ghost" :disabled="!textoFinal" @click="copiar">
              <span class="i-lucide-copy" />
              Copiar
            </button>
          </div>
          <div v-if="contexto.length" class="mb-4">
            <p class="text-xs text-n-slate-10 mb-2">{{ `A IA vai usar ${contexto.length} itens do formulário:` }}</p>
            <div class="flex flex-wrap gap-2">
              <button v-for="c in contexto" :key="c" class="cv-chip cv-chip-on max-w-full" title="Tirar" @click="contexto = contexto.filter(x => x !== c)">
                <span class="truncate">{{ c }}</span>
                <span class="i-lucide-x text-xs" />
              </button>
            </div>
          </div>
          <div v-if="faltaLacuna" class="cv-strip p-3 mb-4 text-sm">Ainda tem [lacuna] sem preencher na copy.</div>
          <div class="rounded-2xl bg-n-alpha-1 p-5 sm:p-7">
            <p v-if="!textoFinal" class="text-sm text-n-slate-10">Escolha o gancho, escreva a história e a oferta — a copy aparece aqui.</p>
            <template v-else>
              <p class="text-lg font-bold text-n-slate-12 whitespace-pre-line break-words">{{ gancho.texto }}</p>
              <p v-if="historia" class="text-[15px] text-n-slate-12 whitespace-pre-line leading-relaxed mt-4 break-words">{{ historia }}</p>
              <p v-if="oferta" class="text-[15px] font-semibold text-[#2563eb] whitespace-pre-line mt-4 break-words">{{ oferta }}</p>
            </template>
          </div>
        </CbSanfona>
      </div>
      </div>

      <!-- 🪟 SEU CRIATIVO: o que já foi escolhido, sempre à vista (computador) -->
      <aside class="hidden xl:block sticky top-4">
        <div class="cv-sub p-4">
          <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-1">Seu criativo</p>
          <div class="divide-y divide-n-weak">
            <button v-for="p in painel" :key="p.key" type="button" class="w-full flex items-start gap-3 text-left py-3 min-w-0" @click="abrirSo(p.key)">
              <span
                class="w-7 h-7 rounded-full flex-shrink-0 flex items-center justify-center text-sm font-bold"
                :class="p.texto ? 'text-white' : 'bg-n-alpha-2 text-n-slate-10'"
                :style="p.texto ? { background: p.color } : {}"
              >
                <span v-if="p.texto" class="i-lucide-check" />
                <template v-else>{{ p.n }}</template>
              </span>
              <span class="min-w-0 flex-1">
                <span class="block text-sm font-bold text-n-slate-12">{{ p.label }}</span>
                <span v-if="p.texto" class="block text-sm text-n-slate-11 line-clamp-3 break-words">{{ p.texto }}</span>
                <span v-else class="block text-sm text-n-slate-10">Falta escolher</span>
              </span>
            </button>
          </div>
          <div class="flex items-end gap-3 pt-3 border-t border-n-weak">
            <div class="flex-1">
              <p class="text-2xl font-bold text-n-slate-12 leading-none">{{ palavras }}</p>
              <p class="text-xs text-n-slate-10 mt-1">palavras</p>
            </div>
            <button class="cv-btn cv-btn-sm cv-blue" :disabled="!textoFinal" @click="abrirSo('previa')">Ver a copy</button>
          </div>
        </div>
      </aside>
      </div>
    </template>
  </div>
</template>
