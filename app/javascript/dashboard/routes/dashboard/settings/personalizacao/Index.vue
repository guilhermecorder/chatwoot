<script setup>
// 🧩 Configurações → Personalização (sistema coringa)
// O admin adapta o sistema ao SEU negócio sem tocar em código:
// profissionais, unidades, listas da agenda, meta do mês e o contexto
// do negócio dos robôs. Salvo POR CONTA (crm_settings) por cima do
// pacote do segmento — apagar tudo volta ao padrão do segmento.
import { ref, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';
import { SEGMENTO, termoCap, frase } from 'dashboard/helper/segmento';

const store = useStore();
const crmSettings = useMapGetter('crm/getSettings');

const professionals = ref([]);
const units = ref([]);
const problemas = ref([]);
const procedimentos = ref([]);
const vendasMes = ref(null);
const businessContext = ref('');
const isLoading = ref(true);
const isSaving = ref(false);

// sem ajuste salvo, a tela abre com os valores do SEGMENTO — o admin
// edita a partir deles
const hydrate = () => {
  const seg = crmSettings.value?.segment || {};
  const pack = SEGMENTO || {};
  professionals.value = (seg.professionals?.length ? seg.professionals : pack.profissionais || [])
    .map(p => ({ nome: p.nome || '', apelido: p.apelido || '', cor: p.cor || '#0F5FA6', grafias: p.grafias || '' }));
  units.value = (seg.units?.length ? seg.units : pack.unidades || [])
    .map(u => ({ key: u.key || '', nome: u.nome || '', cor: u.cor || '#2563EB', endereco: u.endereco || '' }));
  problemas.value = [...(seg.problemas?.length ? seg.problemas : pack.problemas || [])];
  procedimentos.value = [...(seg.procedimentos?.length ? seg.procedimentos : pack.procedimentos || [])];
  vendasMes.value = seg.metas?.vendas_mes || pack.metas?.vendas_mes || null;
  businessContext.value = crmSettings.value?.ai?.business_context || '';
};

onMounted(async () => {
  try {
    await store.dispatch('crm/fetchSettings');
    hydrate();
  } catch {
    useAlert('Não consegui carregar a personalização.');
  } finally {
    isLoading.value = false;
  }
});

const addProfessional = () =>
  professionals.value.push({ nome: '', apelido: '', cor: '#7C3AED', grafias: '' });
const removeProfessional = i => professionals.value.splice(i, 1);

// key da unidade: gerada do nome na criação e NUNCA mais muda (é gravada
// nos agendamentos — mudar a key órfã o histórico)
const slugify = nome =>
  (nome || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 30);
const addUnit = () => units.value.push({ key: '', nome: '', cor: '#EA580C', endereco: '' });
const removeUnit = i => units.value.splice(i, 1);

const addItem = list => list.push('');
const removeItem = (list, i) => list.splice(i, 1);

const save = async () => {
  isSaving.value = true;
  try {
    await CrmAPI.updateSegment({
      professionals: professionals.value.filter(p => p.nome?.trim()),
      units: units.value
        .filter(u => u.nome?.trim())
        .map(u => ({ ...u, key: u.key?.trim() || slugify(u.nome) })),
      problemas: problemas.value.map(p => p.trim()).filter(Boolean),
      procedimentos: procedimentos.value.map(p => p.trim()).filter(Boolean),
      metas: { vendas_mes: Number(vendasMes.value) || null },
    });
    await CrmAPI.updateAi({ business_context: businessContext.value });
    await store.dispatch('crm/fetchSettings');
    hydrate();
    useAlert('Personalização salva! As telas passam a usar os novos valores.');
  } catch {
    useAlert('Erro ao salvar a personalização.');
  } finally {
    isSaving.value = false;
  }
};

// volta TUDO ao padrão do segmento (apaga os ajustes da conta)
const restoreDefaults = async () => {
  if (!window.confirm('Voltar tudo ao padrão do segmento? Os ajustes desta conta serão apagados.')) return;
  isSaving.value = true;
  try {
    await CrmAPI.updateSegment({ professionals: [], units: [], problemas: [], procedimentos: [], metas: {} });
    await store.dispatch('crm/fetchSettings');
    hydrate();
    useAlert('Padrões do segmento restaurados.');
  } catch {
    useAlert('Erro ao restaurar os padrões.');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-4xl w-full mx-auto p-6 space-y-6">
      <div>
        <h1 class="text-xl font-bold text-n-slate-12">🧩 Personalização</h1>
        <p class="text-sm text-n-slate-10 mt-1">
          Adapte o sistema ao seu negócio: {{ termoCap('profissionais') }}, unidades, listas da Agenda,
          meta do mês e o contexto que os robôs de IA usam. Sem ajuste salvo, valem os padrões do
          segmento (<b>{{ SEGMENTO.nome || 'Clínica oftalmológica' }}</b>).
        </p>
      </div>

      <div v-if="isLoading" class="flex justify-center py-16"><Spinner /></div>

      <template v-else>
        <!-- ═ Profissionais ═ -->
        <section class="bg-n-solid-2 border border-n-weak rounded-xl p-4 space-y-3">
          <h2 class="text-sm font-bold text-n-slate-12">{{ termoCap('profissionais') }}</h2>
          <p class="text-[11px] text-n-slate-9">
            São eles que aparecem na Agenda, nos filtros e nos dashboards. "Grafias" é opcional:
            um padrão tolerante a apelidos (ex.: <code>gustavo|bittar</code> reconhece "Gustavo",
            "Dr. Gustavo Bittar"...). Vazio = só o nome exato.
          </p>
          <div v-for="(p, i) in professionals" :key="`prof-${i}`" class="flex flex-wrap items-center gap-2">
            <input v-model="p.nome" placeholder="Nome completo" class="flex-1 min-w-40 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12">
            <input v-model="p.apelido" placeholder="Apelido curto" class="w-32 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12">
            <input v-model="p.cor" type="color" class="w-10 h-9 rounded-lg border border-n-weak bg-n-solid-1 cursor-pointer" title="Cor do profissional">
            <input v-model="p.grafias" placeholder="grafias (opcional)" class="w-40 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12">
            <button class="text-red-500 hover:text-red-600 i-lucide-trash-2 text-base" title="Remover" @click="removeProfessional(i)" />
          </div>
          <button class="text-xs font-semibold text-n-brand hover:underline" @click="addProfessional">
            + Adicionar {{ termoCap('profissional').toLowerCase() }}
          </button>
        </section>

        <!-- ═ Unidades ═ -->
        <section class="bg-n-solid-2 border border-n-weak rounded-xl p-4 space-y-3">
          <h2 class="text-sm font-bold text-n-slate-12">Unidades</h2>
          <p class="text-[11px] text-n-slate-9">
            Agendas paralelas (matriz, filial, loja...). ⚠️ O código interno nasce do nome e
            <b>não muda mais</b> — ele é gravado junto com cada agendamento; renomeie só o nome exibido.
          </p>
          <div v-for="(u, i) in units" :key="`unit-${i}`" class="flex flex-wrap items-center gap-2">
            <input v-model="u.nome" placeholder="Nome exibido" class="flex-1 min-w-36 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12">
            <span class="text-[10px] text-n-slate-9 font-mono px-2 py-1 bg-n-alpha-1 rounded" :title="'código interno (fixo)'">{{ u.key || slugify(u.nome) || '—' }}</span>
            <input v-model="u.cor" type="color" class="w-10 h-9 rounded-lg border border-n-weak bg-n-solid-1 cursor-pointer" title="Cor da unidade">
            <input v-model="u.endereco" placeholder="Endereço (opcional)" class="flex-1 min-w-40 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12">
            <button class="text-red-500 hover:text-red-600 i-lucide-trash-2 text-base" title="Remover" @click="removeUnit(i)" />
          </div>
          <button class="text-xs font-semibold text-n-brand hover:underline" @click="addUnit">+ Adicionar unidade</button>
        </section>

        <!-- ═ Listas da Agenda ═ -->
        <div class="grid sm:grid-cols-2 gap-4">
          <section class="bg-n-solid-2 border border-n-weak rounded-xl p-4 space-y-2">
            <h2 class="text-sm font-bold text-n-slate-12">Motivos do {{ termoCap('atendimento').toLowerCase() }}</h2>
            <p class="text-[11px] text-n-slate-9">Opções do campo "problema/motivo" na Agenda.</p>
            <div v-for="(p, i) in problemas" :key="`prob-${i}`" class="flex items-center gap-2">
              <input v-model="problemas[i]" class="flex-1 border border-n-weak rounded-lg px-3 py-1.5 text-sm bg-n-solid-1 text-n-slate-12">
              <button class="text-red-500 hover:text-red-600 i-lucide-x text-sm" @click="removeItem(problemas, i)" />
            </div>
            <button class="text-xs font-semibold text-n-brand hover:underline" @click="addItem(problemas)">+ Adicionar</button>
          </section>

          <section class="bg-n-solid-2 border border-n-weak rounded-xl p-4 space-y-2">
            <h2 class="text-sm font-bold text-n-slate-12">{{ frase('indicacao_impressao', 'Cirurgia indicada') }} — opções</h2>
            <p class="text-[11px] text-n-slate-9">O que pode ser indicado/vendido na conferência do dia.</p>
            <div v-for="(p, i) in procedimentos" :key="`proc-${i}`" class="flex items-center gap-2">
              <input v-model="procedimentos[i]" class="flex-1 border border-n-weak rounded-lg px-3 py-1.5 text-sm bg-n-solid-1 text-n-slate-12">
              <button class="text-red-500 hover:text-red-600 i-lucide-x text-sm" @click="removeItem(procedimentos, i)" />
            </div>
            <button class="text-xs font-semibold text-n-brand hover:underline" @click="addItem(procedimentos)">+ Adicionar</button>
          </section>
        </div>

        <!-- ═ Meta + contexto do negócio ═ -->
        <section class="bg-n-solid-2 border border-n-weak rounded-xl p-4 space-y-3">
          <h2 class="text-sm font-bold text-n-slate-12">Meta e contexto do negócio</h2>
          <label class="block text-xs font-medium text-n-slate-11">
            🎯 Meta do mês ({{ termoCap('vendas').toLowerCase() }})
            <input v-model.number="vendasMes" type="number" min="1" class="mt-1 w-32 border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12 block">
          </label>
          <label class="block text-xs font-medium text-n-slate-11">
            🤖 Contexto do negócio (usado pelos robôs de IA)
            <textarea
              v-model="businessContext"
              rows="5"
              placeholder="Descreva o que a empresa vende, diferenciais, política de preços e tom de voz. Os robôs usam isso para responder e analisar no tom certo."
              class="mt-1 w-full border border-n-weak rounded-lg px-3 py-2 text-sm bg-n-solid-1 text-n-slate-12"
            />
          </label>
        </section>

        <div class="flex items-center gap-3 pb-8">
          <button
            class="px-4 py-2 rounded-lg text-sm font-semibold text-white bg-n-brand hover:opacity-90 disabled:opacity-50 flex items-center gap-2"
            :disabled="isSaving"
            @click="save"
          >
            <Spinner v-if="isSaving" class="!w-4 !h-4" /> Salvar personalização
          </button>
          <button
            class="px-4 py-2 rounded-lg text-sm font-medium border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 disabled:opacity-50"
            :disabled="isSaving"
            @click="restoreDefaults"
          >
            Restaurar padrão do segmento
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
