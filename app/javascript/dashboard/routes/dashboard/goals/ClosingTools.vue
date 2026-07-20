<script setup>
// FERRAMENTAS DE FECHAMENTO (high ticket): o arsenal de quem fecha —
// script CEVICO, MAPA DE OBJEÇÕES por estágio (gerado pela IA a partir
// das conversas que CONVERTERAM) e as ferramentas importantes do time.
import { ref, onMounted } from 'vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CrmAPI from 'dashboard/api/crm';

const { isAdmin } = useAdmin();
const isLoading = ref(true);
const data = ref(null);
const script = ref('');
const editingScript = ref(false);
const savingScript = ref(false);
const generating = ref(false);

const load = async () => {
  try {
    const { data: payload } = await CrmAPI.getClosingTools();
    data.value = payload;
    script.value = payload.script || '';
  } catch {
    useAlert('Não consegui carregar as ferramentas.');
  } finally {
    isLoading.value = false;
  }
};

const saveScript = async () => {
  savingScript.value = true;
  try {
    await CrmAPI.updateClosingScript(script.value);
    editingScript.value = false;
    useAlert('Script salvo — já está na mão do time.');
  } catch {
    useAlert('Não consegui salvar o script.');
  } finally {
    savingScript.value = false;
  }
};

const generateMap = async () => {
  generating.value = true;
  try {
    const { data: res } = await CrmAPI.generateObjectionMap();
    useAlert(res.message || 'Mapa em produção!');
    setTimeout(async () => {
      await load();
      generating.value = false;
    }, 120000);
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui iniciar.');
    generating.value = false;
  }
};

const copyText = async text => {
  try {
    await navigator.clipboard.writeText(text);
    useAlert('Copiado! Cola na conversa e arrasa. ✨');
  } catch {
    useAlert(text);
  }
};

const FREQ_COLORS = { alta: '#DC2626', média: '#B45309', media: '#B45309', baixa: '#64748B' };

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full overflow-y-auto bg-n-surface-1">
    <div class="max-w-4xl mx-auto w-full p-4 sm:p-8">
      <div class="flex items-center gap-3 flex-wrap mb-5">
        <span class="w-9 h-9 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #065F46, #34D399)">
          <span class="i-lucide-swords text-white text-lg" />
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-lg font-bold text-n-slate-12">Ferramentas de Fechamento</h1>
          <p class="text-xs text-n-slate-10">o arsenal do high ticket: script, mapa de objeções e as respostas que mais converteram</p>
        </div>
      </div>

      <SkeletonScreen v-if="isLoading" variant="list" />

      <template v-else>
        <!-- Script CEVICO -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-5">
          <div class="flex items-center gap-2 flex-wrap mb-2">
            <h2 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
              <span class="i-lucide-scroll-text text-base" style="color: #B8860B" /> Script de fechamento
            </h2>
            <button
              v-if="isAdmin && !editingScript"
              class="ml-auto px-2.5 h-7 rounded-lg border border-n-weak text-[11px] text-n-slate-11 hover:bg-n-alpha-1"
              @click="editingScript = true"
            >
              Editar
            </button>
            <template v-else-if="isAdmin">
              <button class="ml-auto px-2.5 h-7 rounded-lg text-[11px] text-n-slate-10 hover:bg-n-alpha-1" @click="editingScript = false; script = data.script || ''">
                Cancelar
              </button>
              <button
                class="px-3 h-7 rounded-lg text-[11px] font-bold text-white disabled:opacity-50"
                style="background: linear-gradient(135deg, #B8860B, #D4A017)"
                :disabled="savingScript"
                @click="saveScript"
              >
                Salvar
              </button>
            </template>
          </div>
          <textarea
            v-if="editingScript"
            v-model="script"
            rows="12"
            placeholder="Cole aqui o script oficial de fechamento (etapas, frases-chave, âncoras de valor, fechamento)…"
            class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs text-n-slate-12 resize-y font-mono"
          />
          <pre v-else-if="script" class="text-xs text-n-slate-11 whitespace-pre-wrap font-sans leading-relaxed bg-n-alpha-1 rounded-xl p-3 max-h-80 overflow-y-auto">{{ script }}</pre>
          <p v-else class="text-xs text-n-slate-9">
            Nenhum script salvo ainda{{ isAdmin ? ' — clique em Editar e cole o script oficial.' : '.' }}
          </p>
        </div>

        <!-- Mapa de Objeções -->
        <div class="bg-n-solid-2 border border-n-weak rounded-2xl p-5 mb-6">
          <div class="flex items-center gap-2 flex-wrap mb-1">
            <h2 class="text-sm font-bold text-n-slate-12 flex items-center gap-2">
              <span class="i-lucide-shield-question text-base" style="color: #047857" /> Mapa de Objeções
            </h2>
            <span v-if="data.objection_map" class="text-[10px] text-n-slate-9">
              gerado {{ new Date(data.objection_map.generated_at).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' }) }}
            </span>
            <button
              v-if="isAdmin"
              class="ml-auto px-3 h-8 rounded-lg text-[11px] font-bold text-white disabled:opacity-50"
              style="background: linear-gradient(135deg, #065F46, #34D399)"
              :disabled="generating"
              :title="data.sales_agent_enabled ? '' : 'Ligue o Consultor Comercial em Automações → Agentes de IA'"
              @click="generateMap"
            >
              {{ generating ? 'A IA está lendo as conversas… (2-3 min)' : (data.objection_map ? 'Atualizar com IA' : 'Gerar com IA') }}
            </button>
          </div>
          <p class="text-[11px] text-n-slate-10 mb-4">
            a IA lê as conversas de quem AVANÇOU em cada estágio e extrai as maiores objeções + as respostas reais que converteram — clique em qualquer resposta pra copiar
          </p>

          <template v-if="data.objection_map?.stages?.length">
            <div v-for="stage in data.objection_map.stages" :key="stage.key" class="mb-4">
              <p class="text-xs font-bold text-n-slate-12 mb-2 flex items-center gap-1.5">
                <span class="i-lucide-milestone text-sm" style="color: #047857" />
                {{ stage.label }}
                <span class="text-[10px] font-normal text-n-slate-9">({{ stage.conversations }} conversas analisadas)</span>
              </p>
              <div v-for="(o, oi) in stage.objecoes" :key="oi" class="rounded-xl border border-n-weak bg-n-solid-1 p-3 mb-2">
                <div class="flex items-center gap-2 flex-wrap">
                  <p class="text-xs font-semibold text-n-slate-12 flex-1">“{{ o.objecao }}”</p>
                  <span class="text-[9px] font-bold px-1.5 py-0.5 rounded-full uppercase" :style="{ background: `${FREQ_COLORS[o.frequencia] || '#64748B'}20`, color: FREQ_COLORS[o.frequencia] || '#64748B' }">
                    {{ o.frequencia }}
                  </span>
                </div>
                <button
                  class="w-full text-left mt-2 rounded-lg px-2.5 py-2 transition-colors hover:bg-emerald-500/10"
                  style="background: rgba(16, 185, 129, 0.06); border-left: 3px solid #10b981"
                  title="Clique para copiar"
                  @click="copyText(o.melhor_resposta)"
                >
                  <p class="text-xs text-n-slate-11 leading-snug">{{ o.melhor_resposta }}</p>
                  <p class="text-[10px] text-n-slate-9 mt-1">{{ o.por_que_funciona }} · <b>clique pra copiar</b></p>
                </button>
              </div>
            </div>
          </template>
          <p v-else class="text-xs text-n-slate-9">
            Nenhum mapa gerado ainda{{ isAdmin ? ' — clique em "Gerar com IA" (precisa do Consultor Comercial ligado).' : '.' }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
