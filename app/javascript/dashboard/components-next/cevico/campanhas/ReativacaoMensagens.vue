<script setup>
// 📣 item 380 (03/11): Reativação de fim de ano — as mensagens PRONTAS da
// campanha (config/cevico/reativacao_fim_de_ano.yml) por público (coluna do
// CRM, prioridade 1 → 6) e por frente (refrativa / lentes / catarata).
// Quem edita campanhas altera cada mensagem aqui mesmo (fica por cima do
// original, com "Restaurar original"); o resto do time vê e copia.
import { ref, computed, nextTick, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { hexToRgb } from 'dashboard/helper/cevicoPalettes';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import ReativacaoPlano from 'dashboard/components-next/cevico/campanhas/ReativacaoPlano.vue';
import CrmAPI from 'dashboard/api/crm';

const props = defineProps({
  canEdit: { type: Boolean, default: false },
  // página própria (menu Reativação): sem as margens negativas da aba
  espacoso: { type: Boolean, default: false },
});

const VAR = '{{nome}}';
const META_VAR = '{{1}}';
const TEXT_MAX = 1500;
const STORAGE_KEY = 'cevico:reativacao:frente';
const PRIORITY_ICONS = {
  1: 'i-lucide-flame',
  2: 'i-lucide-stethoscope',
  3: 'i-lucide-calendar-x',
  4: 'i-lucide-calendar-off',
  5: 'i-lucide-receipt',
  6: 'i-lucide-user-plus',
};

const data = ref(null);
const isLoading = ref(true);

const publicos = computed(() =>
  [...(data.value?.publicos || [])].sort(
    (a, b) => Number(a.prioridade) - Number(b.prioridade)
  )
);
const frentes = computed(() => data.value?.frentes || []);
const campanha = computed(() => data.value?.campanha || {});
const allMessages = computed(() =>
  publicos.value.flatMap(p => Object.values(p.mensagens || {}).flat())
);
const editedCount = computed(
  () => allMessages.value.filter(m => m.editado).length
);

// 🍎 paleta do kit: um bloco por público (salada de frutas por padrão)
const paletteBlocks = computed(() => [
  // 📣 item 381: o plano de envio em fatias fica no topo, com o próprio tom
  { id: 'plano', label: 'Plano de envio', icon: 'i-lucide-calendar-clock' },
  ...publicos.value.map(p => ({
    id: p.key,
    label: p.titulo,
    icon: PRIORITY_ICONS[p.prioridade] || 'i-lucide-users',
  })),
]);
const pal = useCevicoPalette({
  scope: 'report:campanhas',
  blocks: paletteBlocks,
});
const { cvVars, blockVars } = pal;

// ── filtro de frente (lembrado no navegador) ───────────────────────────
const readStoredFrente = () => {
  try {
    return window.localStorage.getItem(STORAGE_KEY) || 'todas';
  } catch {
    return 'todas';
  }
};
const frenteFilter = ref(readStoredFrente());
const setFrente = key => {
  frenteFilter.value = key;
  try {
    window.localStorage.setItem(STORAGE_KEY, key);
  } catch {
    // navegador sem armazenamento: só não lembra
  }
};
const visibleFrentes = computed(() =>
  frenteFilter.value === 'todas'
    ? frentes.value
    : frentes.value.filter(f => f.key === frenteFilter.value)
);

// cor da frente (do YAML) vestindo as peças do kit: --cv, --cv-grad…
const darken = (hex, amount) => {
  const [r, g, b] = hexToRgb(hex).split(/[ ,]+/).map(Number);
  const d = v => Math.round(v * (1 - amount));
  return `#${[d(r), d(g), d(b)]
    .map(v => v.toString(16).padStart(2, '0'))
    .join('')}`;
};
const frenteVars = frente => {
  const cor = frente?.cor || '#2563EB';
  const deep = darken(cor, 0.35);
  return {
    '--cv': cor,
    '--cv-rgb': hexToRgb(cor),
    '--cv-deep': deep,
    '--cv-deep-rgb': hexToRgb(deep),
    '--cv-grad': `linear-gradient(135deg, ${deep}, ${cor})`,
    '--cv-grad-2': `linear-gradient(135deg, ${cor}, ${cor})`,
    '--cv-grad-3': `linear-gradient(135deg, ${cor}, ${cor})`,
  };
};

// ── texto do balão: {{nome}} vira chip ─────────────────────────────────
const parts = texto =>
  String(texto || '')
    .split(/(\{\{nome\}\})/g)
    .filter(Boolean)
    .map((t, i) => ({ key: i, chip: t === VAR, text: t }));

const formatDate = iso => {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
};

// "Editado por fulano em dd/mm" (sem o que não tiver)
const editedSeal = msg => {
  const bits = ['Editado'];
  if (msg.editado_por) bits.push(`por ${msg.editado_por}`);
  const when = formatDate(msg.editado_em);
  if (when) bits.push(`em ${when}`);
  return bits.join(' ');
};

// ── edição por cartão ──────────────────────────────────────────────────
const drafts = ref({}); // id → { titulo, texto }
const savingId = ref(null);
const copiedId = ref(null);
const confirmResetId = ref(null);
const textareas = ref({});

const autoGrow = el => {
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${el.scrollHeight + 2}px`;
};
const setTextarea = (id, el) => {
  if (el) {
    textareas.value[id] = el;
    autoGrow(el);
  } else {
    delete textareas.value[id];
  }
};

const startEdit = async (msg, focusTitle = false) => {
  if (!props.canEdit) return;
  confirmResetId.value = null;
  drafts.value = {
    ...drafts.value,
    [msg.id]: { titulo: msg.titulo, texto: msg.texto },
  };
  await nextTick();
  const area = textareas.value[msg.id];
  if (area) {
    autoGrow(area);
    if (!focusTitle) area.focus();
  }
  if (focusTitle) {
    const input = document.getElementById(`reativacao-titulo-${msg.id}`);
    if (input) input.focus();
  }
};
const cancelEdit = id => {
  const next = { ...drafts.value };
  delete next[id];
  drafts.value = next;
};
const draftLength = id => (drafts.value[id]?.texto || '').trim().length;

const replaceMessage = updated => {
  publicos.value.forEach(p => {
    Object.keys(p.mensagens || {}).forEach(frente => {
      const list = p.mensagens[frente];
      const idx = list.findIndex(m => m.id === updated.id);
      if (idx >= 0) list.splice(idx, 1, updated);
    });
  });
};

const saveEdit = async msg => {
  const draft = drafts.value[msg.id];
  if (!draft) return;
  const texto = draft.texto.trim();
  if (!texto.length || texto.length > TEXT_MAX) {
    useAlert(`A mensagem precisa ter de 1 a ${TEXT_MAX} caracteres.`);
    return;
  }
  savingId.value = msg.id;
  try {
    const { data: res } = await CrmAPI.updateReactivationMessage({
      id: msg.id,
      texto,
      titulo: draft.titulo.trim() || msg.titulo_original,
    });
    replaceMessage(res.message);
    cancelEdit(msg.id);
    useAlert('Mensagem salva.');
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para salvar a mensagem.');
  } finally {
    savingId.value = null;
  }
};

const resetMessage = async msg => {
  savingId.value = msg.id;
  try {
    const { data: res } = await CrmAPI.updateReactivationMessage({
      id: msg.id,
      reset: 1,
    });
    replaceMessage(res.message);
    cancelEdit(msg.id);
    confirmResetId.value = null;
    useAlert('Mensagem restaurada ao original.');
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para restaurar.');
  } finally {
    savingId.value = null;
  }
};

// copia pelo clipboard moderno; se o navegador recusar (iframe, http,
// permissão), cai no jeito antigo (textarea + execCommand)
const legacyCopy = texto => {
  const area = document.createElement('textarea');
  area.value = texto;
  area.setAttribute('readonly', '');
  area.style.position = 'fixed';
  area.style.opacity = '0';
  document.body.appendChild(area);
  area.select();
  let ok = false;
  try {
    ok = document.execCommand('copy');
  } catch {
    ok = false;
  }
  area.remove();
  return ok;
};
const copyMessage = async msg => {
  const texto = drafts.value[msg.id]?.texto ?? msg.texto;
  let ok = false;
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(texto);
      ok = true;
    } catch {
      ok = false;
    }
  }
  if (!ok) ok = legacyCopy(texto);
  if (!ok) {
    useAlert('Não deu para copiar. Selecione o texto e copie manualmente.');
    return;
  }
  copiedId.value = msg.id;
  setTimeout(() => {
    if (copiedId.value === msg.id) copiedId.value = null;
  }, 1600);
};

const load = async () => {
  isLoading.value = true;
  try {
    const { data: res } = await CrmAPI.getReactivationMessages();
    data.value = res;
  } catch (err) {
    useAlert(
      err?.response?.data?.error || 'Não deu para carregar as mensagens.'
    );
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
</script>

<template>
  <div class="cv-page reativacao" :class="espacoso ? '' : '-m-6 p-4 sm:p-6'" :style="cvVars">
    <div class="max-w-[1600px] mx-auto w-full" :class="espacoso ? 'space-y-2' : ''">
      <CevicoHero
        :pal="pal"
        :title="campanha.titulo || 'Reativação de fim de ano'"
        :subtitle="campanha.resumo || ''"
        icon="i-lucide-message-circle"
      >
        <template #chips>
          <span class="cevico-hero-chip">
            <span class="i-lucide-users text-xs" />
            {{ publicos.length }} públicos
          </span>
          <span class="cevico-hero-chip">
            <span class="i-lucide-message-square-text text-xs" />
            {{ allMessages.length }} mensagens
          </span>
          <span class="cevico-hero-chip">
            <span class="i-lucide-pencil text-xs" />
            {{ editedCount }} editada(s)
          </span>
          <span class="cevico-hero-chip font-mono">variável {{ VAR }}</span>
        </template>
        <template #actions>
          <CevicoViewOnlyPill v-if="!canEdit" />
        </template>
      </CevicoHero>

      <!-- 📣 item 381: o plano de envio em fatias (robô de hora em hora) -->
      <div :style="blockVars('plano')">
        <ReativacaoPlano :can-edit="canEdit" />
      </div>

      <SkeletonScreen v-if="isLoading" variant="list" />

      <template v-else>
        <!-- seletor de FRENTE (lembrado no navegador) -->
        <div class="cv-seg mb-10 flex-wrap">
          <button
            class="cv-seg-item"
            :class="{ 'cv-seg-on': frenteFilter === 'todas' }"
            @click="setFrente('todas')"
          >
            <span class="i-lucide-layout-grid cv-seg-icon" />
            Todas
          </button>
          <button
            v-for="f in frentes"
            :key="f.key"
            class="cv-seg-item"
            :class="{ 'cv-seg-on': frenteFilter === f.key }"
            :style="frenteVars(f)"
            :title="f.sub"
            @click="setFrente(f.key)"
          >
            <span :class="f.icone" class="cv-seg-icon" />
            {{ f.titulo }}
          </button>
        </div>

        <!-- um bloco por público, prioridade 1 → 6 -->
        <section
          v-for="p in publicos"
          :key="p.key"
          class="cv-block p-6 sm:p-10 mb-12"
          :style="blockVars(p.key)"
        >
          <div class="flex items-start gap-4 mb-6 flex-wrap">
            <span class="cv-icon cv-icon-lg">
              <span :class="PRIORITY_ICONS[p.prioridade]" class="text-lg" />
            </span>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2 flex-wrap mb-1">
                <span class="reativacao-prio">
                  Prioridade {{ p.prioridade }}
                </span>
                <span class="cv-chip" :title="`Coluna do CRM: ${p.coluna}`">
                  <span class="i-lucide-columns-3 text-xs" />
                  {{ p.funil?.stage_name || p.coluna }}
                </span>
                <span v-if="p.funil" class="cv-chip">
                  <span class="i-lucide-users text-xs" />
                  {{ p.funil.cards }}
                  {{ p.funil.cards === 1 ? 'pessoa' : 'pessoas' }} na coluna
                  hoje
                </span>
                <span v-else class="cv-chip opacity-70">
                  coluna não encontrada no funil
                </span>
              </div>
              <h2
                class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight break-words"
              >
                {{ p.titulo }}
              </h2>
              <p class="text-sm text-n-slate-11 mt-1 leading-relaxed">
                {{ p.quem }}
              </p>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-5 mb-10">
            <div class="cv-sub p-3 text-xs text-n-slate-11 leading-relaxed">
              <p class="cv-label mb-1">Como falar</p>
              {{ p.estrategia }}
            </div>
            <div class="cv-sub p-3 text-xs text-n-slate-11 leading-relaxed">
              <p class="cv-label mb-1">Quando</p>
              {{ p.quando }}
            </div>
          </div>

          <!-- uma linha por frente: título + 3 cartões -->
          <div
            v-for="f in visibleFrentes"
            :key="f.key"
            class="mb-10 last:mb-0"
            :style="frenteVars(f)"
          >
            <div class="flex items-center gap-2 mb-5">
              <span class="cv-icon cv-icon-sm">
                <span :class="f.icone" class="text-sm" />
              </span>
              <h3 class="text-sm font-bold text-n-slate-12">{{ f.titulo }}</h3>
              <span class="text-xs text-n-slate-10 hidden sm:inline">
                · {{ f.sub }}
              </span>
            </div>

            <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
              <article
                v-for="(msg, idx) in p.mensagens[f.key] || []"
                :key="msg.id"
                class="cv-sub p-6 flex flex-col gap-4 min-w-0"
              >
                <!-- título -->
                <div class="flex items-start gap-2 min-w-0">
                  <span class="cv-chip flex-shrink-0">{{ idx + 1 }}</span>
                  <input
                    v-if="drafts[msg.id]"
                    :id="`reativacao-titulo-${msg.id}`"
                    v-model="drafts[msg.id].titulo"
                    class="cv-input w-full !h-8 text-sm font-bold"
                    maxlength="120"
                    placeholder="Título da mensagem"
                  />
                  <button
                    v-else
                    class="text-left text-sm font-bold text-n-slate-12 leading-snug min-w-0 flex-1 break-words group"
                    :class="canEdit ? 'cursor-text' : 'cursor-default'"
                    :title="canEdit ? 'Clique para editar o título' : ''"
                    @click="startEdit(msg, true)"
                  >
                    {{ msg.titulo }}
                    <span
                      v-if="canEdit"
                      class="i-lucide-pencil text-[11px] opacity-0 group-hover:opacity-60 align-middle"
                    />
                  </button>
                </div>

                <!-- balão -->
                <template v-if="drafts[msg.id]">
                  <textarea
                    :ref="el => setTextarea(msg.id, el)"
                    v-model="drafts[msg.id].texto"
                    class="cv-input w-full text-[13px] leading-relaxed resize-none"
                    rows="4"
                    :maxlength="TEXT_MAX"
                    @input="autoGrow($event.target)"
                  />
                  <p
                    class="text-[11px] tabular-nums"
                    :class="
                      draftLength(msg.id) > TEXT_MAX || !draftLength(msg.id)
                        ? 'text-red-600 font-semibold'
                        : 'text-n-slate-10'
                    "
                  >
                    {{ draftLength(msg.id) }} / {{ TEXT_MAX }} caracteres
                  </p>
                </template>
                <template v-else>
                  <div class="reativacao-bubble">
                    <!-- numa linha só de propósito: o balão é pre-wrap, qualquer quebra aqui viraria espaço no texto -->
                    <span v-for="part in parts(msg.texto)" :key="part.key" :class="part.chip ? 'reativacao-var' : ''">{{ part.text }}</span>
                  </div>
                  <p class="text-[11px] text-n-slate-10 tabular-nums">
                    {{ msg.texto.length }} caracteres
                    <span
                      v-if="msg.editado"
                      class="cv-chip ml-1 !h-5 !text-[10px]"
                      :title="
                        msg.editado_em
                          ? `Editado em ${formatDate(msg.editado_em)}`
                          : ''
                      "
                    >
                      <span class="i-lucide-pencil text-[10px]" />
                      {{ editedSeal(msg) }}
                    </span>
                  </p>
                </template>

                <!-- ações -->
                <div class="flex items-center gap-2 flex-wrap mt-auto">
                  <template v-if="drafts[msg.id]">
                    <button
                      class="cv-btn cv-btn-sm"
                      :disabled="
                        savingId === msg.id ||
                        !draftLength(msg.id) ||
                        draftLength(msg.id) > TEXT_MAX
                      "
                      @click="saveEdit(msg)"
                    >
                      <span class="i-lucide-check text-sm" />
                      {{ savingId === msg.id ? 'Salvando…' : 'Salvar' }}
                    </button>
                    <button
                      class="cv-btn cv-btn-sm cv-btn-ghost"
                      :disabled="savingId === msg.id"
                      @click="cancelEdit(msg.id)"
                    >
                      Cancelar
                    </button>
                  </template>
                  <template v-else-if="confirmResetId === msg.id">
                    <span class="text-xs text-n-slate-11">
                      Voltar ao texto original?
                    </span>
                    <button
                      class="cv-btn cv-btn-sm cv-btn-danger-on"
                      :disabled="savingId === msg.id"
                      @click="resetMessage(msg)"
                    >
                      {{ savingId === msg.id ? 'Restaurando…' : 'Sim, restaurar' }}
                    </button>
                    <button
                      class="cv-btn cv-btn-sm cv-btn-ghost"
                      @click="confirmResetId = null"
                    >
                      Não
                    </button>
                  </template>
                  <template v-else>
                    <button
                      class="cv-btn cv-btn-sm cv-btn-ghost"
                      title="Copiar o texto da mensagem"
                      @click="copyMessage(msg)"
                    >
                      <span
                        :class="
                          copiedId === msg.id
                            ? 'i-lucide-clipboard-check'
                            : 'i-lucide-copy'
                        "
                        class="text-sm"
                      />
                      {{ copiedId === msg.id ? 'Copiado!' : 'Copiar' }}
                    </button>
                    <button
                      v-if="canEdit"
                      class="cv-btn cv-btn-sm"
                      @click="startEdit(msg)"
                    >
                      <span class="i-lucide-pencil text-sm" />
                      Editar
                    </button>
                    <button
                      v-if="canEdit && msg.editado"
                      class="cv-btn cv-btn-sm cv-btn-ghost cv-btn-danger ml-auto"
                      title="Apagar a edição e voltar ao texto original"
                      @click="confirmResetId = msg.id"
                    >
                      <span class="i-lucide-rotate-ccw text-sm" />
                      Restaurar original
                    </button>
                  </template>
                </div>
              </article>
            </div>
          </div>
        </section>

        <!-- regras da casa -->
        <section
          v-if="campanha.regras?.length"
          class="cv-block cv-strip p-6 sm:p-8 mb-12"
        >
          <div class="flex items-center gap-2 mb-3">
            <span class="cv-icon cv-icon-sm">
              <span class="i-lucide-shield-check text-sm" />
            </span>
            <h3 class="text-sm font-bold text-n-slate-12">Regras da casa</h3>
          </div>
          <ul class="text-xs text-n-slate-11 leading-relaxed space-y-1.5 list-disc pl-5">
            <li v-for="(regra, i) in campanha.regras" :key="i">{{ regra }}</li>
          </ul>
          <p class="text-xs text-n-slate-10 mt-3 font-mono">
            {{ VAR }} vira {{ META_VAR }} no modelo da Meta.
          </p>
        </section>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* badge grande da prioridade: a peça do botão do kit, só que parada */
.reativacao-prio {
  display: inline-flex;
  align-items: center;
  height: 28px;
  padding: 0 12px;
  border-radius: 9999px;
  font-size: 12px;
  font-weight: 800;
  letter-spacing: 0.01em;
  color: #fff;
  background: var(--cv-grad);
  border: 1px solid rgba(255, 255, 255, 0.35);
  box-shadow:
    inset 0 1px 0 rgba(255, 255, 255, 0.4),
    0 6px 14px -6px rgb(var(--cv-deep-rgb) / 0.7);
}
/* balão com cara de WhatsApp: verde claro, cantos redondos, rabinho */
.reativacao-bubble {
  position: relative;
  padding: 10px 12px;
  border-radius: 14px;
  border-top-left-radius: 4px;
  font-size: 13px;
  line-height: 1.55;
  color: #111b21;
  background: #dcf8c6;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
  box-shadow: 0 1px 1px rgba(0, 0, 0, 0.08);
}
.dark .reativacao-bubble {
  color: #e9edef;
  background: #005c4b;
}
.reativacao-var {
  display: inline-block;
  padding: 0 6px;
  border-radius: 9999px;
  font-size: 11px;
  font-weight: 700;
  line-height: 18px;
  color: #065f46;
  background: rgba(5, 150, 105, 0.16);
  border: 1px solid rgba(5, 150, 105, 0.35);
}
.dark .reativacao-var {
  color: #a7f3d0;
  background: rgba(16, 185, 129, 0.22);
  border-color: rgba(16, 185, 129, 0.45);
}
</style>
