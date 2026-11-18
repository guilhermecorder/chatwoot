<script setup>
// 🪝 item 397 (18/11): BANCO DE GANCHOS — o ambiente de geração de
// criativos no padrão GANCHO → HISTÓRIA → OFERTA. Guilherme: "subir os
// 1.000 ganchos como templates; escolher o tipo de gancho e ele já ir
// gerando; escrever o corpo; escolher o call to action; inserir ganchos
// contextualizados ao longo da copy; e ir aumentando a base".
// 18/11 (2ª volta): "banco mais bem organizado em modelos, com filtro;
// apertar um botão Criar, escolher o tipo de gancho e ir vendo os ganchos;
// algo mais sanfonado" → três abas:
//   Criar (CbCriar: botão Criar + passos em sanfona) · Banco (CbBanco:
//   filtros + gavetas por modelo/tipo) · Criações (o que foi salvo).
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CbCriar from 'dashboard/components-next/cevico/copybank/CbCriar.vue';
import CbBanco from 'dashboard/components-next/cevico/copybank/CbBanco.vue';
import CrmAPI from 'dashboard/api/crm';

const { canEdit } = useCevicoAccess();
const podeEditar = computed(() => canEdit('marketing.criativos'));

const pal = useCevicoPalette({
  scope: 'report:banco-ganchos',
  blocks: [
    { id: 'criar', label: 'Criar', icon: 'i-lucide-wand-sparkles' },
    { id: 'banco', label: 'Banco', icon: 'i-lucide-library' },
    { id: 'criacoes', label: 'Criações', icon: 'i-lucide-file-text' },
  ],
});
const { cvVars, blockVars } = pal;

const loading = ref(true);
const blocks = ref([]);
const tab = ref('criar'); // criar | banco | criacoes
const criarRef = ref(null);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getCopyBank();
    blocks.value = data.blocks || [];
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para abrir o banco.');
  } finally {
    loading.value = false;
  }
};
const conta = k => blocks.value.filter(b => b.kind === k).length;

const favoritar = async b => {
  if (!podeEditar.value) return;
  b.favorito = !b.favorito;
  try {
    await CrmAPI.updateCopyBlock(b.id, { favorito: b.favorito });
  } catch {
    b.favorito = !b.favorito;
    useAlert('Não deu para marcar.');
  }
};
const onSalvo = data => {
  const i = blocks.value.findIndex(b => b.id === data.id);
  if (i >= 0) blocks.value[i] = data;
  else blocks.value.push(data);
};
const onApagado = id => {
  blocks.value = blocks.value.filter(b => b.id !== id);
};

// ── Criações ──
const drafts = ref([]);
const draftsLoaded = ref(false);
const loadDrafts = async () => {
  try {
    const { data } = await CrmAPI.getCopyDrafts();
    drafts.value = data.drafts || [];
    draftsLoaded.value = true;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para listar as criações.');
  }
};
const onDraftSalvo = d => drafts.value.unshift(d);
const reabrir = d => {
  tab.value = 'criar';
  criarRef.value?.carregar(d);
};
const copiar = async text => {
  try {
    await navigator.clipboard.writeText(text);
    useAlert('Copiado ✓');
  } catch {
    useAlert('Não deu para copiar — selecione o texto e copie à mão.');
  }
};
const mudarStatus = async (d, status) => {
  const antes = d.status;
  d.status = status;
  try {
    await CrmAPI.updateCopyDraft(d.id, { status });
  } catch {
    d.status = antes;
    useAlert('Não deu para mudar.');
  }
};
const apagarDraft = async d => {
  if (!window.confirm(`Apagar "${d.titulo}"?`)) return;
  try {
    await CrmAPI.deleteCopyDraft(d.id);
    drafts.value = drafts.value.filter(x => x.id !== d.id);
  } catch {
    useAlert('Não deu para apagar.');
  }
};
const fmtData = s =>
  s
    ? new Date(s).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: 'short',
      })
    : '';

const irPara = t => {
  tab.value = t;
  if (t === 'criacoes' && !draftsLoaded.value) loadDrafts();
};

onMounted(() => {
  load();
  loadDrafts();
});
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div class="flex flex-col h-full w-full bg-n-solid-1 overflow-hidden">
    <!-- a tela inteira rola (regra: toda tela rola até o fim) -->
    <div class="flex-1 overflow-y-auto p-4 sm:p-10">
      <div class="cv-page max-w-[1400px] mx-auto w-full" :style="cvVars">
        <CevicoHero
          :pal="pal"
          title="Banco de Ganchos"
          subtitle="Gancho → História → Oferta. Crie um criativo em 3 passos, com os modelos do banco e a ajuda da IA — e a base cresce a cada criação."
          icon="i-lucide-anchor"
        >
          <template #chips>
            <span class="cevico-hero-chip">
              <span class="i-lucide-anchor text-xs" />
              {{ `${conta('gancho')} ganchos` }}
            </span>
            <span class="cevico-hero-chip">
              <span class="i-lucide-book-open text-xs" />
              {{ `${conta('historia')} histórias` }}
            </span>
            <span class="cevico-hero-chip">
              <span class="i-lucide-mouse-pointer-click text-xs" />
              {{ `${conta('oferta')} ofertas` }}
            </span>
            <span class="cevico-hero-chip">
              <span class="i-lucide-repeat text-xs" />
              {{ `${conta('regancho')} reganchos` }}
            </span>
          </template>
        </CevicoHero>

        <div class="flex items-center gap-3 flex-wrap mb-8">
          <div class="cv-seg flex-wrap">
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'criar' }"
              @click="irPara('criar')"
            >
              <span class="i-lucide-wand-sparkles" />
              Criar
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'banco' }"
              @click="irPara('banco')"
            >
              <span class="i-lucide-library" />
              Banco
            </button>
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'criacoes' }"
              @click="irPara('criacoes')"
            >
              <span class="i-lucide-file-text" />
              {{ `Criações${drafts.length ? ` (${drafts.length})` : ''}` }}
            </button>
          </div>
          <CevicoViewOnlyPill v-if="!podeEditar" />
        </div>

        <p v-if="loading" class="text-sm text-n-slate-10 mb-10">
          Abrindo o banco…
        </p>

        <template v-else>
          <!-- v-show: o criativo em andamento não se perde ao trocar de aba -->
          <section
            v-show="tab === 'criar'"
            class="cv-block p-4 sm:p-9 mb-12"
            :style="blockVars('criar')"
          >
            <CbCriar
              ref="criarRef"
              :blocks="blocks"
              :pode-editar="podeEditar"
              @favoritar="favoritar"
              @draft-salvo="onDraftSalvo"
            />
          </section>

          <section
            v-if="tab === 'banco'"
            class="cv-block p-4 sm:p-9 mb-12"
            :style="blockVars('banco')"
          >
            <CbBanco
              :blocks="blocks"
              :pode-editar="podeEditar"
              @favoritar="favoritar"
              @salvo="onSalvo"
              @apagado="onApagado"
            />
          </section>

          <section
            v-if="tab === 'criacoes'"
            class="cv-block p-4 sm:p-9 mb-12"
            :style="blockVars('criacoes')"
          >
            <div class="flex items-start gap-4 mb-6 flex-wrap">
              <span class="cv-icon cv-icon-lg">
                <span class="i-lucide-file-text text-xl" />
              </span>
              <div class="min-w-0 flex-1">
                <h2
                  class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight"
                >
                  Criações
                </h2>
                <p class="text-sm text-n-slate-11 mt-1">
                  Tudo que foi criado e salvo, com o gancho, a história e a
                  oferta que entraram.
                </p>
              </div>
            </div>
            <p v-if="!draftsLoaded" class="text-sm text-n-slate-10">
              Carregando…
            </p>
            <p v-else-if="!drafts.length" class="text-sm text-n-slate-10">
              Nenhuma criação salva ainda. Crie uma na aba "Criar".
            </p>
            <div class="grid grid-cols-1 xl:grid-cols-2 gap-5">
              <div
                v-for="d in drafts"
                :key="d.id"
                class="cv-sub p-5 flex flex-col gap-3 min-w-0"
              >
                <div class="flex items-start gap-2 flex-wrap">
                  <p
                    class="text-base font-bold text-n-slate-12 flex-1 min-w-0 break-words"
                  >
                    {{ d.titulo }}
                  </p>
                  <select
                    :value="d.status"
                    class="cv-input !h-8 !w-auto text-xs"
                    :disabled="!podeEditar"
                    @change="mudarStatus(d, $event.target.value)"
                  >
                    <option value="rascunho">Rascunho</option>
                    <option value="aprovado">Aprovado</option>
                    <option value="publicado">Publicado</option>
                  </select>
                </div>
                <p class="text-xs text-n-slate-10">
                  {{
                    [fmtData(d.created_at), d.tema, d.formato, d.autor]
                      .filter(Boolean)
                      .join(' · ')
                  }}
                </p>
                <p
                  class="text-sm text-n-slate-12 whitespace-pre-line break-words line-clamp-[12]"
                >
                  {{ d.texto_final }}
                </p>
                <div class="flex flex-wrap gap-2 mt-auto">
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    @click="copiar(d.texto_final)"
                  >
                    <span class="i-lucide-copy" />
                    Copiar
                  </button>
                  <button
                    class="cv-btn cv-btn-sm cv-btn-ghost"
                    @click="reabrir(d)"
                  >
                    <span class="i-lucide-pencil" />
                    Reabrir para editar
                  </button>
                  <button
                    v-if="podeEditar"
                    class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger"
                    @click="apagarDraft(d)"
                  >
                    <span class="i-lucide-trash-2" />
                    Apagar
                  </button>
                </div>
              </div>
            </div>
          </section>
        </template>
      </div>
    </div>
  </div>
</template>
