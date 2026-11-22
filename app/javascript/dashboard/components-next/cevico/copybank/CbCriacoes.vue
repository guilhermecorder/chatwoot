<script setup>
// 📄 18/11/2026: aba CRIAÇÕES do Banco de Ganchos em linha fina (Guilherme:
// "um lugar com as criações… mais minimalista, conduzir o olho"). Fechada, a
// linha mostra só o nome, o código e quantos anúncios estão ligados; aberta,
// o texto, as ações e os ANÚNCIOS DA META ligados à criação — é por essa
// ligação que o Ranking sabe qual gancho deu resultado.
// Ligação: pelo código (CRI-<id>) no nome do anúncio na Meta, ou à mão aqui.
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import { TIPO } from './cbMeta';

const props = defineProps({
  drafts: { type: Array, required: true },
  loaded: { type: Boolean, default: false },
  podeEditar: { type: Boolean, default: false },
});
const emit = defineEmits(['reabrir', 'atualizado', 'apagado']);

const STATUS = {
  rascunho: { label: 'Rascunho', color: '#94a3b8' },
  aprovado: { label: 'Aprovado', color: '#2563eb' },
  publicado: { label: 'Publicado', color: '#059669' },
};

const busca = ref('');
const aberta = ref(null);
const lista = computed(() => {
  const q = busca.value.trim().toLowerCase();
  if (!q) return props.drafts;
  return props.drafts.filter(d =>
    `${d.titulo} ${d.codigo} ${d.texto_final}`.toLowerCase().includes(q)
  );
});
const fmtData = s =>
  s
    ? new Date(s).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' })
    : '';
const tipoDe = d => TIPO[d.partes?.gancho?.tipo]?.label || '';

const copiar = async (texto, aviso = 'Copiado ✓') => {
  try {
    await navigator.clipboard.writeText(texto);
    useAlert(aviso);
  } catch {
    useAlert('Não deu para copiar. Selecione o texto e copie à mão.');
  }
};
const mudarStatus = async (d, status) => {
  try {
    const { data } = await CrmAPI.updateCopyDraft(d.id, { status });
    emit('atualizado', data);
  } catch {
    useAlert('Não deu para mudar.');
  }
};
const apagar = async d => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Apagar "${d.titulo}"?`)) return;
  try {
    await CrmAPI.deleteCopyDraft(d.id);
    emit('apagado', d.id);
  } catch {
    useAlert('Não deu para apagar.');
  }
};

// ── ligar anúncios da Meta ──
const ligando = ref(null); // id da criação com a busca de anúncios aberta
const buscaAd = ref('');
const ads = ref([]);
const buscandoAds = ref(false);
const buscarAds = async () => {
  buscandoAds.value = true;
  try {
    const { data } = await CrmAPI.getCopyAds(buscaAd.value);
    ads.value = data.ads || [];
  } catch {
    ads.value = [];
    useAlert('Não deu para listar os anúncios.');
  } finally {
    buscandoAds.value = false;
  }
};
const abrirLigar = d => {
  ligando.value = ligando.value === d.id ? null : d.id;
  buscaAd.value = '';
  if (ligando.value) buscarAds();
};
const manuais = d => (d.partes?.ad_ids || []).map(String);
const salvarAds = async (d, ids) => {
  try {
    const { data } = await CrmAPI.linkCopyDraftAds(d.id, ids);
    emit('atualizado', data);
  } catch {
    useAlert('Não deu para ligar o anúncio.');
  }
};
const ligar = (d, ad) => salvarAds(d, [...new Set([...manuais(d), ad.ad_id])]);
const desligar = (d, adId) =>
  salvarAds(
    d,
    manuais(d).filter(x => x !== String(adId))
  );
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div>
    <div class="flex items-center gap-3 flex-wrap mb-5">
      <span class="cv-icon cv-icon-lg">
        <span class="i-lucide-file-text text-xl" />
      </span>
      <h2
        class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight"
      >
        Criações
      </h2>
      <span
        class="text-sm font-bold px-2.5 py-0.5 rounded-full bg-n-alpha-2 text-n-slate-12"
      >
        {{ drafts.length }}
      </span>
      <span class="flex-1" />
      <div class="relative w-full sm:w-72">
        <span
          class="i-lucide-search absolute left-3 top-1/2 -translate-y-1/2 text-n-slate-10"
        />
        <input v-model="busca" class="cv-input w-full !pl-9" placeholder="Buscar" />
      </div>
    </div>

    <p v-if="!loaded" class="text-sm text-n-slate-10">Carregando…</p>
    <p v-else-if="!drafts.length" class="text-sm text-n-slate-10">
      Nenhuma criação salva ainda. Crie uma na aba "Criar" ou "Escrever".
    </p>
    <p v-else-if="!lista.length" class="text-sm text-n-slate-10">
      Nada com essa palavra.
    </p>

    <div
      v-if="lista.length"
      class="rounded-2xl border border-n-weak divide-y divide-n-weak overflow-hidden"
    >
      <div v-for="d in lista" :key="d.id" class="min-w-0">
        <div
          class="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-n-alpha-1 transition-colors"
          @click="aberta = aberta === d.id ? null : d.id"
        >
          <span
            class="w-2.5 h-2.5 rounded-full flex-shrink-0"
            :style="{ background: STATUS[d.status]?.color }"
            :title="STATUS[d.status]?.label"
          />
          <p
            class="flex-1 min-w-0 text-[15px] font-semibold text-n-slate-12 truncate"
          >
            {{ d.titulo }}
          </p>
          <span
            v-if="d.anuncios?.length"
            class="text-xs font-bold px-2 py-0.5 rounded-full bg-[#05966922] text-[#059669] flex-shrink-0 whitespace-nowrap"
          >
            {{ `${d.anuncios.length} anúncio${d.anuncios.length > 1 ? 's' : ''}` }}
          </span>
          <span
            class="text-xs font-mono font-semibold px-2 py-0.5 rounded-md bg-n-alpha-2 text-n-slate-11 flex-shrink-0"
          >
            {{ d.codigo }}
          </span>
          <span
            class="text-xs text-n-slate-10 flex-shrink-0 hidden sm:inline whitespace-nowrap"
          >
            {{ fmtData(d.created_at) }}
          </span>
          <span
            class="i-lucide-chevron-down text-n-slate-10 flex-shrink-0 transition-transform duration-200"
            :class="{ 'rotate-180': aberta === d.id }"
          />
        </div>

        <div v-if="aberta === d.id" class="px-4 pb-5 grid grid-cols-1 xl:grid-cols-5 gap-5">
          <!-- o texto -->
          <div class="xl:col-span-3 min-w-0">
            <p class="text-xs text-n-slate-10 mb-2">
              {{
                [STATUS[d.status]?.label, tipoDe(d), d.tema, d.autor]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </p>
            <p
              class="text-sm text-n-slate-12 whitespace-pre-line break-words rounded-xl bg-n-alpha-1 p-4"
            >
              {{ d.texto_final }}
            </p>
            <div class="flex flex-wrap items-center gap-2 mt-3">
              <button class="cv-btn cv-btn-sm cv-blue" @click="copiar(d.texto_final)">
                <span class="i-lucide-copy" />
                Copiar
              </button>
              <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="emit('reabrir', d)">
                <span class="i-lucide-pencil" />
                Editar
              </button>
              <select
                :value="d.status"
                class="cv-input !h-8 !w-auto text-xs"
                :disabled="!podeEditar"
                @change="mudarStatus(d, $event.target.value)"
              >
                <option v-for="(s, k) in STATUS" :key="k" :value="k">
                  {{ s.label }}
                </option>
              </select>
              <button
                v-if="podeEditar"
                class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger"
                @click="apagar(d)"
              >
                <span class="i-lucide-trash-2" />
              </button>
            </div>
          </div>

          <!-- os anúncios da Meta -->
          <div class="xl:col-span-2 min-w-0">
            <p class="text-xs font-semibold uppercase tracking-wide text-n-slate-10 mb-2">
              Anúncios na Meta
            </p>
            <p v-if="!d.anuncios?.length" class="text-sm text-n-slate-10 mb-3">
              Nenhum anúncio ligado.
            </p>
            <div
              v-for="a in d.anuncios"
              :key="a.ad_id"
              class="flex items-center gap-2 py-1.5 min-w-0"
            >
              <span class="i-lucide-megaphone text-[#059669] flex-shrink-0" />
              <span class="text-sm text-n-slate-12 flex-1 min-w-0 truncate">
                {{ a.nome || a.ad_id }}
              </span>
              <button
                v-if="podeEditar && manuais(d).includes(String(a.ad_id))"
                class="text-n-slate-10 hover:text-n-slate-12 flex-shrink-0"
                title="Desligar"
                @click="desligar(d, a.ad_id)"
              >
                <span class="i-lucide-x" />
              </button>
              <span v-else class="text-[11px] text-n-slate-10 flex-shrink-0">
                pelo código
              </span>
            </div>

            <div class="flex flex-wrap gap-2 mt-3">
              <button
                class="cv-btn cv-btn-sm cv-btn-ghost"
                @click="copiar(d.codigo, `${d.codigo} copiado ✓`)"
              >
                <span class="i-lucide-copy" />
                {{ `Copiar ${d.codigo}` }}
              </button>
              <button
                v-if="podeEditar"
                class="cv-btn cv-btn-sm cv-btn-ghost"
                :class="{ 'cv-chip-on': ligando === d.id }"
                @click="abrirLigar(d)"
              >
                <span class="i-lucide-link" />
                Ligar anúncio
              </button>
            </div>
            <p class="text-xs text-n-slate-10 mt-2">
              Com o código no nome do anúncio, ele se liga sozinho.
            </p>

            <div v-if="ligando === d.id" class="mt-3">
              <input
                v-model="buscaAd"
                class="cv-input w-full mb-2"
                placeholder="Buscar anúncio ou campanha"
                @keydown.enter.prevent="buscarAds"
                @input="buscarAds"
              />
              <p v-if="buscandoAds" class="text-sm text-n-slate-10">Buscando…</p>
              <p v-else-if="!ads.length" class="text-sm text-n-slate-10">
                Nenhum anúncio encontrado. Atualize a Central de Criativos.
              </p>
              <div
                class="rounded-xl border border-n-weak divide-y divide-n-weak max-h-64 overflow-y-auto"
              >
                <button
                  v-for="ad in ads"
                  :key="ad.ad_id"
                  type="button"
                  class="w-full text-left px-3 py-2 hover:bg-n-alpha-1 min-w-0 flex items-center gap-2"
                  :disabled="d.anuncios?.some(x => String(x.ad_id) === String(ad.ad_id))"
                  @click="ligar(d, ad)"
                >
                  <span class="min-w-0 flex-1">
                    <span class="block text-sm font-medium text-n-slate-12 truncate">
                      {{ ad.nome || ad.ad_id }}
                    </span>
                    <span class="block text-xs text-n-slate-10 truncate">
                      {{ ad.campanha }}
                    </span>
                  </span>
                  <span
                    v-if="d.anuncios?.some(x => String(x.ad_id) === String(ad.ad_id))"
                    class="i-lucide-check text-[#059669] flex-shrink-0"
                  />
                  <span v-else class="i-lucide-plus text-n-slate-10 flex-shrink-0" />
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
