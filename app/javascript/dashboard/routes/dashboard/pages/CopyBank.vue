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
// 18/11 (tarde): "quero ter a liberdade e quero ter a referência" → aba
//   Escrever (CbEscrever): página livre ou um campo por parte de um modelo
//   de roteiro, com o modelo, os ganchos e a pesquisa ao lado.
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CbCriar from 'dashboard/components-next/cevico/copybank/CbCriar.vue';
import CbBanco from 'dashboard/components-next/cevico/copybank/CbBanco.vue';
import CbEscrever from 'dashboard/components-next/cevico/copybank/CbEscrever.vue';
import CbCriacoes from 'dashboard/components-next/cevico/copybank/CbCriacoes.vue';
import CbRanking from 'dashboard/components-next/cevico/copybank/CbRanking.vue';
import CrmAPI from 'dashboard/api/crm';

const { canEdit } = useCevicoAccess();
const podeEditar = computed(() => canEdit('marketing.criativos'));

const pal = useCevicoPalette({
  scope: 'report:banco-ganchos',
  blocks: [
    { id: 'criar', label: 'Criar', icon: 'i-lucide-wand-sparkles' },
    { id: 'escrever', label: 'Escrever', icon: 'i-lucide-pen-line' },
    { id: 'banco', label: 'Banco', icon: 'i-lucide-library' },
    { id: 'criacoes', label: 'Criações', icon: 'i-lucide-file-text' },
    { id: 'ranking', label: 'Ranking', icon: 'i-lucide-trophy' },
  ],
});
const { cvVars, blockVars } = pal;

const route = useRoute();
// 🧾 "Usar na copy" (Formulários) chega com ?form=<id>
const formInicial = computed(() => route.query.form || null);
const loading = ref(true);
const blocks = ref([]);
const empresa = ref({ clinica: true });
const tab = ref('criar'); // criar | escrever | banco | criacoes | ranking
const criarRef = ref(null);
const escreverRef = ref(null);

const load = async () => {
  loading.value = true;
  try {
    const { data } = await CrmAPI.getCopyBank();
    blocks.value = data.blocks || [];
    empresa.value = data.empresa || { clinica: true };
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
const onDraftAtualizado = d => {
  const i = drafts.value.findIndex(x => x.id === d.id);
  if (i >= 0) drafts.value[i] = d;
  else drafts.value.unshift(d);
};
// criação escrita na aba Escrever guarda partes.modelo; as da aba Criar não
const reabrir = d => {
  if (d.partes?.modelo) {
    tab.value = 'escrever';
    escreverRef.value?.carregar(d);
    return;
  }
  tab.value = 'criar';
  criarRef.value?.carregar(d);
};
const onDraftApagado = id => {
  drafts.value = drafts.value.filter(x => x.id !== id);
};

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
              :class="{ 'cv-seg-on': tab === 'escrever' }"
              @click="irPara('escrever')"
            >
              <span class="i-lucide-pen-line" />
              Escrever
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
            <button
              class="cv-seg-item"
              :class="{ 'cv-seg-on': tab === 'ranking' }"
              @click="irPara('ranking')"
            >
              <span class="i-lucide-trophy" />
              Ranking
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
              :empresa="empresa"
              :form-inicial="formInicial"
              @favoritar="favoritar"
              @draft-salvo="onDraftSalvo"
            />
          </section>

          <!-- v-show: o texto em andamento não se perde ao trocar de aba -->
          <section
            v-show="tab === 'escrever'"
            class="cv-block p-4 sm:p-9 mb-12"
            :style="blockVars('escrever')"
          >
            <CbEscrever
              ref="escreverRef"
              :blocks="blocks"
              :pode-editar="podeEditar"
              :empresa="empresa"
              @draft-salvo="onDraftSalvo"
              @draft-atualizado="onDraftAtualizado"
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
              :clinica="empresa.clinica !== false"
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
            <CbCriacoes
              :drafts="drafts"
              :loaded="draftsLoaded"
              :pode-editar="podeEditar"
              @reabrir="reabrir"
              @atualizado="onDraftAtualizado"
              @apagado="onDraftApagado"
            />
          </section>

          <section
            v-if="tab === 'ranking'"
            class="cv-block p-4 sm:p-9 mb-12"
            :style="blockVars('ranking')"
          >
            <CbRanking @ir-para="irPara" />
          </section>
        </template>
      </div>
    </div>
  </div>
</template>
