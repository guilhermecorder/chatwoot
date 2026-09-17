<script setup>
// 🗺️ DIAGRAMA DE UM FLUXO (item 170): recebe a definição Mermaid gerada no
// servidor (Crm::FlowMap::Flow#to_mermaid) e desenha no navegador.
// O Mermaid é pesado — entra só sob demanda (import dinâmico) e só quando
// esta aba abre. Clique num nó → emite 'nodeClick' com o id (<chave>_<nó>).
// Zoom −/100%/+ e "Baixar PNG" (html-to-image). Erro de sintaxe vira um
// aviso legível — nunca quebra a tela.
import { ref, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonPiece from 'dashboard/components-next/cevico/SkeletonPiece.vue';

const props = defineProps({
  definition: { type: String, default: '' },
  flowKey: { type: String, default: 'fluxo' },
});
const emit = defineEmits(['nodeClick']);

const host = ref(null);
const isLoading = ref(true);
const error = ref('');
const zoom = ref(1);
const isExporting = ref(false);

// módulo carregado UMA vez por sessão; re-inicializa só quando o tema muda
let mermaidMod = null;
let initializedTheme = null;
let renderSeq = 0;
let themeObserver = null;

// o Chatwoot marca o tema escuro com a classe `dark` no <body> (themeHelper)
const isDark = () =>
  document.body.classList.contains('dark') ||
  document.documentElement.classList.contains('dark');

const loadMermaid = async () => {
  if (!mermaidMod) {
    const { default: mermaid } = await import('mermaid');
    mermaidMod = mermaid;
  }
  const theme = isDark() ? 'dark' : 'neutral';
  if (initializedTheme !== theme) {
    mermaidMod.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme,
      fontFamily: 'inherit',
      flowchart: { curve: 'basis', htmlLabels: false, useMaxWidth: true },
    });
    initializedTheme = theme;
  }
  return mermaidMod;
};

// id do nó no SVG: `flowchart-<chave>_<nó>-<n>` (ou data-id nas versões novas)
const nodeIdOf = g => {
  if (g.dataset?.id) return g.dataset.id;
  const m = /^flowchart-(.+)-\d+$/.exec(g.id || '');
  return m ? m[1] : null;
};

const bindClicks = () => {
  if (!host.value) return;
  host.value.querySelectorAll('g.node').forEach(g => {
    const id = nodeIdOf(g);
    if (!id) return;
    g.style.cursor = 'pointer';
    g.setAttribute('role', 'button');
    g.addEventListener('click', () => emit('nodeClick', id));
  });
};

const render = async () => {
  if (!props.definition) {
    isLoading.value = false;
    return;
  }
  renderSeq += 1;
  const seq = renderSeq;
  isLoading.value = true;
  error.value = '';
  try {
    const mermaid = await loadMermaid();
    const safeKey = String(props.flowKey).replace(/[^a-z0-9_-]/gi, '');
    const { svg } = await mermaid.render(
      `cv-flow-${safeKey}-${seq}`,
      props.definition
    );
    if (seq !== renderSeq) return; // veio outro render no meio — descarta
    if (host.value) host.value.innerHTML = svg;
    await nextTick();
    bindClicks();
  } catch (e) {
    if (seq !== renderSeq) return;
    error.value = String(e?.message || e || 'erro desconhecido');
  } finally {
    if (seq === renderSeq) isLoading.value = false;
  }
};

const zoomIn = () => {
  zoom.value = Math.min(2, Math.round((zoom.value + 0.25) * 100) / 100);
};
const zoomOut = () => {
  zoom.value = Math.max(0.5, Math.round((zoom.value - 0.25) * 100) / 100);
};
const zoomReset = () => {
  zoom.value = 1;
};

// PNG em 2× para ficar nítido no WhatsApp/impressão
const downloadPng = async () => {
  if (!host.value?.firstElementChild || isExporting.value) return;
  isExporting.value = true;
  try {
    const { toPng } = await import('html-to-image');
    const dataUrl = await toPng(host.value, {
      pixelRatio: 2,
      backgroundColor: isDark() ? '#0F172A' : '#FFFFFF',
      style: { zoom: 1 },
    });
    const a = document.createElement('a');
    a.href = dataUrl;
    a.download = `fluxo-${props.flowKey}.png`;
    a.click();
  } catch {
    useAlert('Não consegui gerar a imagem deste fluxo.');
  } finally {
    isExporting.value = false;
  }
};

watch(() => props.definition, render);

onMounted(() => {
  render();
  // tema claro/escuro trocado com a aba aberta → redesenha com o tema certo
  themeObserver = new MutationObserver(() => {
    const theme = isDark() ? 'dark' : 'neutral';
    if (mermaidMod && theme !== initializedTheme) render();
  });
  themeObserver.observe(document.body, {
    attributes: true,
    attributeFilter: ['class'],
  });
});
onBeforeUnmount(() => {
  themeObserver?.disconnect();
});
</script>

<template>
  <div class="cv-flow">
    <!-- barra: dica + zoom + PNG -->
    <div class="flex items-center gap-2 mb-2 flex-wrap">
      <span class="text-[11px] text-n-slate-9 mr-auto">
        <span class="i-lucide-mouse-pointer-click text-[10px]" />
        clique num passo para abrir a configuração
      </span>
      <div class="cv-seg cv-seg-sm" title="Zoom do diagrama">
        <button
          class="cv-seg-item"
          :disabled="zoom <= 0.5"
          title="Diminuir"
          @click="zoomOut"
        >
          <span class="i-lucide-minus text-xs" />
        </button>
        <button
          class="cv-seg-item tabular-nums"
          title="Voltar a 100%"
          @click="zoomReset"
        >
          {{ Math.round(zoom * 100) }}%
        </button>
        <button
          class="cv-seg-item"
          :disabled="zoom >= 2"
          title="Aumentar"
          @click="zoomIn"
        >
          <span class="i-lucide-plus text-xs" />
        </button>
      </div>
      <button
        class="cv-btn cv-btn-ghost cv-btn-sm"
        :disabled="isLoading || !!error || isExporting"
        title="Baixa o fluxograma como imagem PNG"
        @click="downloadPng"
      >
        <span
          :class="
            isExporting ? 'i-lucide-loader-2 animate-spin' : 'i-lucide-download'
          "
          class="text-xs"
        />
        Baixar PNG
      </button>
    </div>

    <!-- esqueleto enquanto o Mermaid carrega/desenha -->
    <div v-if="isLoading" class="space-y-2 p-2">
      <SkeletonPiece variant="pill" class="w-40 mx-auto" :order="0" />
      <SkeletonPiece variant="block" class="h-14 w-72 mx-auto" :order="1" />
      <SkeletonPiece variant="block" class="h-14 w-72 mx-auto" :order="2" />
      <SkeletonPiece variant="block" class="h-14 w-72 mx-auto" :order="3" />
      <SkeletonPiece variant="pill" class="w-24 mx-auto" :order="4" />
    </div>

    <!-- erro legível (definição inválida, Mermaid não carregou…) -->
    <div
      v-else-if="error"
      class="rounded-xl border-2 p-4 text-sm text-n-slate-11"
      style="
        border-color: rgba(212, 160, 23, 0.4);
        background: rgba(212, 160, 23, 0.08);
      "
    >
      <p class="font-semibold text-n-slate-12 mb-1">
        ⚠️ Não consegui desenhar este fluxo.
      </p>
      <p class="text-[11px] text-n-slate-9 break-words">{{ error }}</p>
    </div>

    <!-- o SVG entra aqui (fica no DOM mesmo carregando, para o innerHTML ter destino) -->
    <div
      class="cv-flow-scroll overflow-auto rounded-xl"
      :class="isLoading || error ? 'hidden' : ''"
    >
      <div ref="host" class="cv-flow-host p-2" :style="{ zoom }" />
    </div>
  </div>
</template>

<style scoped>
.cv-flow-scroll {
  max-height: 72vh;
  background: rgb(var(--cv-rgb, 15 95 166) / 0.04);
}
.cv-flow-host :deep(svg) {
  display: block;
  margin: 0 auto;
}
/* rótulos das arestas legíveis nos dois temas */
.cv-flow-host :deep(.edgeLabel) {
  font-size: 11px;
}
</style>
