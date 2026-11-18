<script setup>
// 🪝 item 397: a aba BANCO — todas as peças organizadas em sanfonas por
// modelo (Ganchos → uma sanfona por tipo; Histórias; Ofertas; Reganchos),
// com uma barra de filtros que vale para tudo e o formulário de peça nova.
import { ref, computed, watch } from 'vue';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import CbSanfona from './CbSanfona.vue';
import CbFiltros from './CbFiltros.vue';
import CbPeca from './CbPeca.vue';
import { TIPOS, PECAS, SAUDE, filtrosPadrao, passaFiltro, filtroAtivo } from './cbMeta';

const props = defineProps({
  blocks: { type: Array, required: true },
  podeEditar: { type: Boolean, default: false },
});
const emit = defineEmits(['favoritar', 'salvo', 'apagado']);

const PAGE = 20;
const PADRAO = { ...filtrosPadrao(), saude: 'todos' };
const filtros = ref({ ...PADRAO });
const abertas = ref({ gancho: true }); // peça e tipo abertos: 'gancho', 'historia', 't:educativo'…
const limites = ref({});
const toggle = k => {
  abertas.value = { ...abertas.value, [k]: !abertas.value[k] };
};
const limite = k => limites.value[k] || PAGE;
const verMais = k => {
  limites.value = { ...limites.value, [k]: limite(k) + PAGE };
};

const filtradas = computed(() => props.blocks.filter(b => passaFiltro(b, filtros.value)));
const daPeca = k => filtradas.value.filter(b => b.kind === k);
const doTipo = k => filtradas.value.filter(b => b.kind === 'gancho' && (b.categoria || 'cevico') === k);
const tiposVisiveis = computed(() => {
  const conhecidos = new Set(TIPOS.map(t => t.key));
  const extras = [...new Set(props.blocks.filter(b => b.kind === 'gancho' && !conhecidos.has(b.categoria)).map(b => b.categoria))]
    .filter(Boolean)
    .map(k => ({ key: k, label: k, icon: 'i-lucide-tag', color: '#64748b', desc: '' }));
  return [...TIPOS, ...extras];
});

// com busca, abre sozinho o que tem resultado (e fecha o que ficou vazio)
watch(
  () => filtros.value.busca,
  q => {
    if (!q.trim()) return;
    const novo = {};
    PECAS.forEach(p => {
      novo[p.key] = daPeca(p.key).length > 0;
    });
    tiposVisiveis.value.forEach(t => {
      novo[`t:${t.key}`] = doTipo(t.key).length > 0;
    });
    abertas.value = novo;
  }
);
const abrirTudo = v => {
  const novo = {};
  PECAS.forEach(p => {
    novo[p.key] = v;
  });
  tiposVisiveis.value.forEach(t => {
    novo[`t:${t.key}`] = v;
  });
  abertas.value = novo;
};

// ── peça nova / edição ──
const nova = ref(null);
const abrirNova = (kind = 'gancho', categoria = '') => {
  nova.value = { kind, categoria: categoria || (kind === 'gancho' ? 'cevico' : ''), texto: '', exemplo: '', referencia: '', saude: 'pronto' };
};
const editar = b => {
  nova.value = { ...b };
};
const salvar = async () => {
  const p = nova.value;
  if (!p?.texto?.trim()) return;
  const payload = { kind: p.kind, categoria: p.categoria, texto: p.texto, exemplo: p.exemplo, referencia: p.referencia, saude: p.saude };
  try {
    const { data } = p.id ? await CrmAPI.updateCopyBlock(p.id, payload) : await CrmAPI.createCopyBlock(payload);
    emit('salvo', data);
    nova.value = null;
    useAlert('Peça salva no banco ✓');
  } catch (err) {
    useAlert(err?.response?.data?.message || err?.response?.data?.error || 'Não deu para salvar a peça.');
  }
};
const apagar = async b => {
  if (!window.confirm('Apagar esta peça do banco?')) return;
  try {
    await CrmAPI.deleteCopyBlock(b.id);
    emit('apagado', b.id);
  } catch {
    useAlert('Não deu para apagar.');
  }
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text -->
  <div>
    <div class="flex items-start gap-4 mb-6 flex-wrap">
      <span class="cv-icon cv-icon-lg"><span class="i-lucide-library text-xl" /></span>
      <div class="min-w-0 flex-1">
        <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight">O banco</h2>
        <p class="text-sm text-n-slate-11 mt-1">Cada modelo na sua gaveta. Filtre em cima; abra a gaveta que quiser. Use [colchetes] para as lacunas.</p>
      </div>
      <button v-if="podeEditar" class="cv-btn cv-blue" @click="abrirNova()">
        <span class="i-lucide-plus" />
        Nova peça
      </button>
    </div>

    <div class="mb-6">
      <CbFiltros v-model="filtros" :total="filtradas.length" :padrao="PADRAO" />
      <div class="flex gap-2 mt-3">
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="abrirTudo(true)">Abrir tudo</button>
        <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="abrirTudo(false)">Fechar tudo</button>
      </div>
    </div>

    <div v-if="nova" class="cv-sub p-5 mb-6 flex flex-col gap-3">
      <p class="text-sm font-semibold text-n-slate-12">{{ nova.id ? 'Editar peça' : 'Nova peça' }}</p>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
        <select v-model="nova.kind" class="cv-input" :disabled="!!nova.id">
          <option v-for="k in PECAS" :key="k.key" :value="k.key">{{ k.label }}</option>
        </select>
        <select v-if="nova.kind === 'gancho'" v-model="nova.categoria" class="cv-input">
          <option v-for="t in tiposVisiveis" :key="t.key" :value="t.key">{{ t.label }}</option>
        </select>
        <input v-else v-model="nova.categoria" class="cv-input" placeholder="Nome / tipo (ex.: Mito → Verdade)" />
        <select v-model="nova.saude" class="cv-input">
          <option v-for="(s, k) in SAUDE" :key="k" :value="k">{{ s.label }}</option>
        </select>
      </div>
      <textarea v-model="nova.texto" rows="3" class="cv-input w-full !h-auto py-2" placeholder="Texto, com [lacunas] entre colchetes" />
      <input v-model="nova.exemplo" class="cv-input w-full" placeholder="Exemplo preenchido para a CEVICO (opcional)" />
      <input v-model="nova.referencia" class="cv-input w-full" placeholder="Link do vídeo de referência (opcional)" />
      <div class="flex gap-2">
        <button class="cv-btn cv-blue" :disabled="!nova.texto?.trim()" @click="salvar">Salvar</button>
        <button class="cv-btn cv-btn-ghost" @click="nova = null">Cancelar</button>
      </div>
    </div>

    <CbSanfona
      v-for="p in PECAS"
      :key="p.key"
      :open="!!abertas[p.key]"
      :title="p.label"
      :icon="p.icon"
      :desc="p.desc"
      :count="filtroAtivo(filtros, PADRAO) ? `${daPeca(p.key).length} de ${blocks.filter(b => b.kind === p.key).length}` : daPeca(p.key).length"
      @toggle="toggle(p.key)"
    >
      <!-- ganchos: uma gaveta por tipo -->
      <template v-if="p.key === 'gancho'">
        <CbSanfona
          v-for="t in tiposVisiveis.filter(x => blocks.some(b => b.kind === 'gancho' && (b.categoria || 'cevico') === x.key) || x.key === 'cevico')"
          :key="t.key"
          size="sm"
          :open="!!abertas[`t:${t.key}`]"
          :title="t.label"
          :icon="t.icon"
          :color="t.color"
          :desc="t.desc"
          :count="doTipo(t.key).length"
          @toggle="toggle(`t:${t.key}`)"
        >
          <p v-if="!doTipo(t.key).length" class="text-sm text-n-slate-10 py-2">
            {{ t.key === 'cevico' ? 'Ainda não há ganchos da casa. Clique em "Nova peça" para criar o primeiro.' : 'Nenhum gancho deste tipo no filtro.' }}
          </p>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <CbPeca
              v-for="b in doTipo(t.key).slice(0, limite(`t:${t.key}`))"
              :key="b.id"
              :peca="b"
              modo="banco"
              :pode-editar="podeEditar"
              @favoritar="emit('favoritar', $event)"
              @editar="editar"
              @apagar="apagar"
            />
          </div>
          <div v-if="doTipo(t.key).length > limite(`t:${t.key}`)" class="flex justify-center mt-4">
            <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="verMais(`t:${t.key}`)">{{ `Ver mais (${doTipo(t.key).length - limite(`t:${t.key}`)} restantes)` }}</button>
          </div>
        </CbSanfona>
      </template>
      <template v-else>
        <p v-if="!daPeca(p.key).length" class="text-sm text-n-slate-10 py-2">Nada aqui com este filtro.</p>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
          <CbPeca
            v-for="b in daPeca(p.key).slice(0, limite(p.key))"
            :key="b.id"
            :peca="b"
            modo="banco"
            :pode-editar="podeEditar"
            @favoritar="emit('favoritar', $event)"
            @editar="editar"
            @apagar="apagar"
          />
        </div>
        <div v-if="daPeca(p.key).length > limite(p.key)" class="flex justify-center mt-4">
          <button class="cv-btn cv-btn-sm cv-btn-ghost" @click="verMais(p.key)">{{ `Ver mais (${daPeca(p.key).length - limite(p.key)} restantes)` }}</button>
        </div>
        <button v-if="podeEditar" class="cv-btn cv-btn-sm cv-btn-ghost mt-4" @click="abrirNova(p.key)">
          <span class="i-lucide-plus" />
          {{ { historia: 'Nova história', oferta: 'Nova oferta', regancho: 'Novo regancho' }[p.key] }}
        </button>
      </template>
    </CbSanfona>
  </div>
</template>
