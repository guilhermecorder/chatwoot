<script setup>
// 📊 SUA ÓTICA — ANÁLISE DA LOJA (02/11/2026). A página de análise do SavWin
// (gerada no Mac por OTICA/analise/savwin.py) aparece aqui dentro do sistema,
// só para quem está logado na conta da ótica. O HTML vem pela API (com o
// login) e entra num iframe SANDBOX via srcdoc: o CSS/JS da página funcionam
// sem encostar no painel. Cada envio é uma versão; a mais nova é a que abre.
// "Enviar nova versão" (upload do index.html) é só de administrador.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import CrmAPI from 'dashboard/api/crm';
import { fmtDateTime, INPUT, LABEL } from './oticaFormat';

const { isAdmin } = useCevicoAccess();

const pal = useCevicoPalette({
  scope: 'otica:analise',
  blocks: [{ id: 'pagina', label: 'Página', icon: 'i-lucide-chart-column' }],
});
const pageStyle = computed(() => pal.cvVars.value);

const isLoading = ref(true);
const loadError = ref('');
const reports = ref([]);
const latestId = ref(null);
const currentId = ref(null);
const html = ref('');
const htmlLoading = ref(false);
const showHistory = ref(false);

const current = computed(() =>
  reports.value.find(r => r.id === currentId.value)
);
const isLatest = computed(
  () => !currentId.value || currentId.value === latestId.value
);

const fmtSize = bytes => {
  if (!bytes) return '';
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1).replace('.', ',')} MB`;
};
const who = r => r?.created_by?.name || 'sistema';

// o painel está no escuro? (o Chatwoot marca `dark` no <body>) — a página
// respeita data-theme (claro/escuro)
const dashboardDark = () =>
  document.body.classList.contains('dark') ||
  document.documentElement.classList.contains('dark');
const themed = raw => {
  const theme = dashboardDark() ? 'dark' : 'light';
  return raw.replace(/<html([^>]*)>/i, (m, attrs) =>
    /data-theme=/.test(attrs) ? m : `<html${attrs} data-theme="${theme}">`
  );
};

const loadHtml = async id => {
  htmlLoading.value = true;
  try {
    const { data } = await CrmAPI.getOticaReportHtml(id);
    html.value = themed(String(data || ''));
    currentId.value = id;
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui abrir essa versão.');
  } finally {
    htmlLoading.value = false;
  }
};

const load = async () => {
  loadError.value = '';
  try {
    const { data: payload } = await CrmAPI.getOticaReports();
    reports.value = payload.reports || [];
    latestId.value = payload.latest_id || null;
    if (latestId.value) await loadHtml(latestId.value);
    else html.value = '';
  } catch (e) {
    loadError.value =
      e?.response?.data?.error || 'Não consegui carregar a análise.';
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);

// o tema do painel muda sem recarregar: re-aplica na página
let themeObserver;
onMounted(() => {
  themeObserver = new MutationObserver(() => {
    if (html.value)
      html.value = themed(html.value.replace(/ data-theme="(dark|light)"/, ''));
  });
  const opts = { attributes: true, attributeFilter: ['class'] };
  themeObserver.observe(document.body, opts);
  themeObserver.observe(document.documentElement, opts);
});
onBeforeUnmount(() => themeObserver?.disconnect());

// ── enviar nova versão (só admin) ──
const fileInput = ref(null);
const uploadOpen = ref(false);
const uploadFile = ref(null);
const uploadTitle = ref('');
const uploadNote = ref('');
const uploading = ref(false);

const pickFile = ev => {
  const f = ev.target.files?.[0];
  uploadFile.value = f || null;
};
const openUpload = () => {
  uploadOpen.value = true;
  uploadFile.value = null;
  uploadTitle.value = '';
  uploadNote.value = '';
};
const submitUpload = async () => {
  if (!uploadFile.value) {
    useAlert('Escolha o arquivo index.html gerado pela análise.');
    return;
  }
  uploading.value = true;
  try {
    const fd = new FormData();
    fd.append('file', uploadFile.value, uploadFile.value.name);
    if (uploadTitle.value.trim()) fd.append('title', uploadTitle.value.trim());
    if (uploadNote.value.trim()) fd.append('note', uploadNote.value.trim());
    await CrmAPI.uploadOticaReport(fd);
    useAlert('Nova versão da análise no ar.');
    uploadOpen.value = false;
    await load();
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui enviar o arquivo.');
  } finally {
    uploading.value = false;
  }
};

// abrir numa aba só dela (sem cabeçalho do sistema): o HTML já está aqui
const openFull = () => {
  if (!html.value) return;
  const blob = new Blob([html.value], { type: 'text/html;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  window.open(url, '_blank', 'noopener');
  setTimeout(() => URL.revokeObjectURL(url), 60000);
};
</script>

<template>
  <div
    class="cv-page flex flex-col h-full w-full overflow-y-auto bg-n-surface-1"
    :style="pageStyle"
  >
    <div class="max-w-7xl mx-auto w-full p-4 sm:p-8">
      <CevicoHero
        :pal="pal"
        title="Análise da loja"
        subtitle="Os números do SavWin lidos e explicados: vendas, clientes, produtos, estoque, equipe e as decisões. Só quem entra no sistema vê esta página."
        icon="i-lucide-chart-column"
        :palette="false"
      >
        <template #chips>
          <span v-if="current" class="cv-glass-chip">
            <span class="i-lucide-calendar-check text-xs" />
            versão de {{ fmtDateTime(current.created_at) }}
          </span>
          <span v-if="current" class="cv-glass-chip">
            <span class="i-lucide-user text-xs" />
            enviada por {{ who(current) }}
          </span>
          <span v-if="reports.length > 1" class="cv-glass-chip">
            <span class="i-lucide-history text-xs" />
            {{ reports.length }} versões
          </span>
        </template>
      </CevicoHero>

      <SkeletonScreen v-if="isLoading" variant="dashboard" />

      <template v-else>
        <div
          v-if="loadError"
          class="cv-block cv-strip cv-red px-4 py-3.5 mb-8 flex items-center gap-3"
        >
          <p class="text-xs text-n-slate-11 flex-1">{{ loadError }}</p>
          <button class="cv-btn cv-btn-sm" @click="load">Tentar de novo</button>
        </div>

        <!-- barra: versão · histórico · tela cheia · enviar -->
        <div class="flex items-center gap-2 flex-wrap mb-4">
          <span
            v-if="current && !isLatest"
            class="inline-flex items-center gap-1 text-[11px] font-bold px-2.5 py-1 rounded-full bg-n-amber-3 text-n-amber-11"
          >
            <span class="i-lucide-history" />
            versão antiga
            <button class="underline ml-1" @click="loadHtml(latestId)">
              voltar à mais nova
            </button>
          </span>
          <button
            v-if="reports.length > 1"
            class="cv-btn cv-btn-sm"
            @click="showHistory = !showHistory"
          >
            <span class="i-lucide-history text-xs" />
            {{ showHistory ? 'Esconder histórico' : 'Histórico' }}
          </button>
          <button
            v-if="html"
            class="cv-btn cv-btn-sm"
            title="Abre a página numa aba só dela"
            @click="openFull"
          >
            <span class="i-lucide-maximize-2 text-xs" /> Tela cheia
          </button>
          <button
            v-if="isAdmin"
            class="cv-btn cv-btn-sm cv-btn-primary ml-auto"
            @click="openUpload"
          >
            <span class="i-lucide-upload text-xs" /> Enviar nova versão
          </button>
        </div>

        <!-- envio (só admin) -->
        <section
          v-if="isAdmin && uploadOpen"
          class="cv-ag-block p-5 sm:p-7 mb-6"
        >
          <h2 class="cv-ag-block-title">Enviar nova versão</h2>
          <span class="cv-ag-block-sub">
            o arquivo index.html que o savwin.py gera no Mac (ou mande direto de
            lá com --enviar)
          </span>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-3 mt-4">
            <label class="flex flex-col gap-1">
              <span :class="LABEL">Arquivo (index.html)</span>
              <input
                ref="fileInput"
                type="file"
                accept=".html,.htm,text/html"
                :class="INPUT"
                @change="pickFile"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span :class="LABEL">Título (opcional)</span>
              <input
                v-model="uploadTitle"
                type="text"
                :class="INPUT"
                placeholder="Análise da loja"
                maxlength="120"
              />
            </label>
            <label class="flex flex-col gap-1">
              <span :class="LABEL">Observação (opcional)</span>
              <input
                v-model="uploadNote"
                type="text"
                :class="INPUT"
                placeholder="ex.: leitura do SavWin de 22/10"
                maxlength="300"
              />
            </label>
          </div>
          <div class="flex items-center gap-2 mt-4">
            <button
              class="cv-btn cv-btn-primary"
              :disabled="uploading || !uploadFile"
              @click="submitUpload"
            >
              <span class="i-lucide-upload text-xs" />
              {{ uploading ? 'Enviando…' : 'Enviar' }}
            </button>
            <button
              class="cv-btn"
              :disabled="uploading"
              @click="uploadOpen = false"
            >
              Cancelar
            </button>
            <span v-if="uploadFile" class="text-[11px] text-n-slate-10">
              {{ uploadFile.name }} · {{ fmtSize(uploadFile.size) }}
            </span>
          </div>
        </section>

        <!-- histórico de versões -->
        <section
          v-if="showHistory && reports.length"
          class="cv-ag-block p-5 sm:p-7 mb-6"
        >
          <h2 class="cv-ag-block-title">Histórico</h2>
          <span class="cv-ag-block-sub"
            >cada envio é uma versão; a mais nova é a que abre</span
          >
          <div class="flex flex-col gap-2 mt-4">
            <button
              v-for="r in reports"
              :key="r.id"
              class="cv-sub p-3 flex items-center gap-3 text-left"
              :class="r.id === currentId ? 'ring-2 ring-n-brand' : ''"
              @click="loadHtml(r.id)"
            >
              <span
                class="w-7 h-7 rounded-lg grid place-items-center text-white flex-shrink-0"
                :class="r.id === latestId ? 'bg-n-teal-9' : 'bg-n-slate-8'"
              >
                <span class="i-lucide-file-chart-column text-xs" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block text-[13px] font-bold text-n-slate-12">
                  {{ r.title }}
                  <span
                    v-if="r.id === latestId"
                    class="text-[10px] font-bold text-n-teal-11 ml-1"
                    >mais nova</span
                  >
                </span>
                <span class="block text-[11px] text-n-slate-11">
                  {{ fmtDateTime(r.created_at) }} · {{ who(r) }} ·
                  {{ fmtSize(r.size_bytes) }}
                  <template v-if="r.note"> · {{ r.note }}</template>
                </span>
              </span>
            </button>
          </div>
        </section>

        <!-- a página -->
        <section class="cv-ag-block p-2 sm:p-3 mb-8">
          <div
            v-if="!html && !htmlLoading"
            class="cv-sub p-8 text-center text-n-slate-10 text-sm flex flex-col items-center gap-3"
          >
            <span class="i-lucide-chart-column text-3xl" />
            <p>Nenhuma análise foi enviada ainda.</p>
            <p v-if="isAdmin" class="text-xs">
              Gere a página no Mac (<code
                >python3 OTICA/analise/savwin.py --enviar</code
              >) ou envie o index.html pelo botão acima.
            </p>
            <p v-else class="text-xs">
              Peça a um administrador para enviar a primeira versão.
            </p>
          </div>
          <div v-else class="relative">
            <div
              v-if="htmlLoading"
              class="absolute inset-0 grid place-items-center bg-n-alpha-1 rounded-xl z-10 text-xs text-n-slate-11"
            >
              Abrindo a página…
            </div>
            <iframe
              v-if="html"
              :srcdoc="html"
              sandbox="allow-scripts allow-popups allow-forms"
              referrerpolicy="no-referrer"
              title="Análise da loja"
              class="w-full rounded-xl border border-n-weak bg-white h-[calc(100vh-15rem)] min-h-[32rem]"
            />
          </div>
        </section>
      </template>
    </div>
  </div>
</template>
