<script setup>
// 🎨 Configurações → PERSONALIZAÇÃO (28/10; nasceu como "Identidade da
// empresa" na rodada 334, só admin). Tudo que a conta pode trocar POR DENTRO
// do sistema, sem código: quem é a empresa, identidade visual (imagens,
// paleta, marca d'água), as palavras e o dicionário global, as frases das
// telas, os nomes dos ambientes, unidades, equipe e listas (coringa),
// assistente virtual, módulos e site público. Lê `crm/getCompany` e grava
// com `crm/updateCompany` — manda só o que esta tela edita. Sem nada salvo,
// a conta é a CEVICO de hoje, byte a byte.
import { ref, computed, onMounted } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { PALETTES } from 'dashboard/helper/cevicoPalettes';
import { AMBIENTES_POR_GRUPO } from 'dashboard/helper/ambientesCatalogo';
import { FRASES_DAS_TELAS } from 'dashboard/helper/frases';
import PersonalizacaoEquipe from 'dashboard/routes/dashboard/settings/personalizacao/Index.vue';

const store = useStore();
const company = useMapGetter('crm/getCompany');

const isLoading = ref(true);
const isSaving = ref(false);

const pal = useCevicoPalette({
  scope: 'settings:empresa',
  blocks: [
    { id: 'quem', label: 'Quem somos', icon: 'i-lucide-building-2' },
    { id: 'visual', label: 'Identidade visual', icon: 'i-lucide-palette' },
    { id: 'vocab', label: 'Palavras', icon: 'i-lucide-spell-check' },
    { id: 'frases', label: 'Frases das telas', icon: 'i-lucide-text-quote' },
    { id: 'nomes', label: 'Nomes dos ambientes', icon: 'i-lucide-signpost' },
    { id: 'unidades', label: 'Unidades', icon: 'i-lucide-store' },
    { id: 'equipe', label: 'Equipe e listas', icon: 'i-lucide-users' },
    { id: 'assistente', label: 'Assistente virtual', icon: 'i-lucide-bot' },
    { id: 'modulos', label: 'Módulos', icon: 'i-lucide-toggle-right' },
    { id: 'site', label: 'Site público', icon: 'i-lucide-globe' },
  ],
});
const { cvVars, blockVars } = pal;

// ── o que cada ramo significa ───────────────────────────────────────────
const SEGMENTS = [
  { key: 'clinica', label: 'Clínica', icon: 'i-lucide-stethoscope' },
  { key: 'otica', label: 'Ótica', icon: 'i-lucide-glasses' },
  { key: 'outro', label: 'Outro ramo', icon: 'i-lucide-briefcase' },
];

// mesmas palavras padrão do servidor (Cevico::Company::VOCABULARY) — viram o
// placeholder de cada linha conforme o ramo escolhido aqui na tela
const VOCAB_DEFAULTS = {
  clinica: {
    paciente: 'paciente',
    paciente_plural: 'pacientes',
    consulta: 'consulta',
    consulta_plural: 'consultas',
    medico: 'médico',
    medico_plural: 'médicos',
    cirurgia: 'cirurgia',
    cirurgia_plural: 'cirurgias',
    empresa: 'clínica',
    unidade: 'unidade',
    unidade_plural: 'unidades',
  },
  otica: {
    paciente: 'cliente',
    paciente_plural: 'clientes',
    consulta: 'atendimento',
    consulta_plural: 'atendimentos',
    medico: 'consultor',
    medico_plural: 'consultores',
    cirurgia: 'compra',
    cirurgia_plural: 'compras',
    empresa: 'ótica',
    unidade: 'loja',
    unidade_plural: 'lojas',
  },
  outro: {
    paciente: 'cliente',
    paciente_plural: 'clientes',
    consulta: 'atendimento',
    consulta_plural: 'atendimentos',
    medico: 'consultor',
    medico_plural: 'consultores',
    cirurgia: 'compra',
    cirurgia_plural: 'compras',
    empresa: 'empresa',
    unidade: 'unidade',
    unidade_plural: 'unidades',
  },
};
const VOCAB_ROWS = [
  { key: 'paciente', label: 'paciente' },
  { key: 'paciente_plural', label: 'pacientes' },
  { key: 'consulta', label: 'consulta' },
  { key: 'consulta_plural', label: 'consultas' },
  { key: 'medico', label: 'médico' },
  { key: 'medico_plural', label: 'médicos' },
  { key: 'cirurgia', label: 'cirurgia' },
  { key: 'cirurgia_plural', label: 'cirurgias' },
  { key: 'empresa', label: 'empresa' },
  { key: 'unidade', label: 'unidade' },
  { key: 'unidade_plural', label: 'unidades' },
];

const MODULES = [
  {
    key: 'cirurgias',
    label: 'Cirurgias',
    hint: 'agenda de cirurgias, hub, pós-operatório no CRM e indicadores de cirurgia',
  },
  {
    key: 'medicos',
    label: 'Médicos',
    hint: 'médico por horário na Agenda, relatório de médicos e vídeos do médico no roteiro',
  },
  {
    key: 'oftalmofacil',
    label: 'Oftalmofácil',
    hint: 'conexão com o sistema dos parceiros (pacientes que vêm de fora)',
  },
  {
    key: 'notas_clinicas',
    label: 'Notas clínicas',
    hint: 'anotações clínicas no painel do paciente',
  },
  {
    key: 'pos_operatorio',
    label: 'Pós-operatório',
    hint: 'Atendente de pós-operatório, orientações e pesquisa depois da cirurgia',
  },
];

// ── formulário ──────────────────────────────────────────────────────────
const emptyVocabulary = () =>
  Object.fromEntries(VOCAB_ROWS.map(r => [r.key, '']));

const form = ref({
  name: '',
  segment: 'clinica',
  city: '',
  tagline: '',
  about: '',
  offers: '',
  tone: '',
  vocabulary: emptyVocabulary(),
  units: [],
  assistant: { name: '', gender: 'f' },
  modules: {},
  public_host: '',
  hub: { whatsapp: '', tagline: '', cta_text: '' },
  tracking: { meta_pixel_id: '', ga4_measurement_id: '' },
  // 🎨 Personalização (28/10)
  visual: { system_name: '', palette: '', watermark: true, accent: '' },
  dictionary: { mode: 'auto', pairs: [] }, // mode: auto | on | off
  phrases: {},
  labels: {},
});

// ── 🎨 identidade visual: imagens ───────────────────────────────────────
const IMAGENS = [
  { kind: 'icon', label: 'Ícone', hint: 'barra lateral e aba do navegador (quadrado, PNG/SVG)' },
  { kind: 'hero', label: 'Imagem do cabeçalho', hint: 'no lugar do olho CEVICO, no canto dos cabeçalhos' },
  { kind: 'logo', label: 'Logo (fundo claro)', hint: 'documentos, impressões e páginas' },
  { kind: 'logo_dark', label: 'Logo (fundo escuro)', hint: 'versão para fundo escuro' },
];
const imagemEnviando = ref('');
const imagens = computed(() => company.value?.images || {});
const enviarImagem = async (kind, event) => {
  const file = event?.target?.files?.[0];
  if (!file) return;
  imagemEnviando.value = kind;
  try {
    await store.dispatch('crm/updateCompanyImage', { kind, file });
    useAlert('Imagem salva. Já aparece para quem recarregar a tela.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui enviar a imagem.');
  } finally {
    imagemEnviando.value = '';
    if (event?.target) event.target.value = '';
  }
};
const removerImagem = async kind => {
  imagemEnviando.value = kind;
  try {
    await store.dispatch('crm/updateCompanyImage', { kind, remove: true });
    useAlert('Imagem removida — volta a valer a da instalação.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui remover a imagem.');
  } finally {
    imagemEnviando.value = '';
  }
};
const paletas = PALETTES.filter(p => p.group !== 'salad');

// ── 🎨 dicionário global ────────────────────────────────────────────────
const dicionarioPadroes = computed(() => company.value?.dictionary?.defaults || []);
const dicionarioAtivoAgora = computed(() => {
  if (form.value.dictionary.mode === 'on') return true;
  if (form.value.dictionary.mode === 'off') return false;
  return form.value.segment !== 'clinica';
});
const addPar = () => form.value.dictionary.pairs.push({ de: '', para: '' });
const removePar = i => form.value.dictionary.pairs.splice(i, 1);
const usarParesDoVocabulario = () => {
  form.value.dictionary.pairs = dicionarioPadroes.value.map(p => ({ ...p }));
};

// ── 🎨 frases das telas (segmento + telas adaptadas) ────────────────────
const fraseBusca = ref('');
const todasAsFrases = computed(() => {
  const doSegmento = Object.entries(company.value?.phrase_defaults || {}).map(
    ([chave, padrao]) => ({ chave, padrao, tela: 'Agenda e painéis (segmento)' })
  );
  const vistas = new Set(doSegmento.map(f => f.chave));
  const dasTelas = FRASES_DAS_TELAS.filter(f => !vistas.has(f.chave));
  return [...doSegmento, ...dasTelas];
});
const frasesFiltradas = computed(() => {
  const q = fraseBusca.value.trim().toLowerCase();
  const lista = q
    ? todasAsFrases.value.filter(
        f =>
          f.padrao.toLowerCase().includes(q) ||
          (form.value.phrases[f.chave] || '').toLowerCase().includes(q) ||
          f.tela.toLowerCase().includes(q)
      )
    : todasAsFrases.value;
  return lista.reduce((acc, f) => {
    (acc[f.tela] ||= []).push(f);
    return acc;
  }, {});
});
const frasesPersonalizadas = computed(
  () => Object.values(form.value.phrases).filter(v => String(v || '').trim()).length
);
const limparFrases = () => {
  form.value.phrases = {};
};

// ── 🎨 nomes dos ambientes ───────────────────────────────────────────────
const nomesPersonalizados = computed(
  () => Object.values(form.value.labels).filter(v => String(v || '').trim()).length
);
const limparNomes = () => {
  form.value.labels = {};
};

// chave da unidade a partir do nome ("Loja Moema" → "loja_moema"), igual ao
// parameterize(separator: '_') do servidor
const slugify = text =>
  String(text || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 40);

const hydrate = () => {
  const c = company.value || {};
  const defaults = VOCAB_DEFAULTS[c.segment || 'clinica'];
  // na tela só fica o que foge do padrão do ramo (vazio = padrão)
  const vocabulary = emptyVocabulary();
  VOCAB_ROWS.forEach(r => {
    const word = c.vocabulary?.[r.key] || '';
    vocabulary[r.key] = word && word !== defaults[r.key] ? word : '';
  });
  form.value = {
    name: c.name || '',
    segment: c.segment || 'clinica',
    city: c.city || '',
    tagline: c.tagline || '',
    about: c.about || '',
    offers: c.offers || '',
    tone: c.tone || '',
    vocabulary,
    units: (c.units || []).map(u => ({
      key: u.key || slugify(u.label),
      label: u.label || '',
      address: u.address || '',
      phone: u.phone || '',
      keyTouched: Boolean(u.key),
    })),
    assistant: {
      name: c.assistant?.name || '',
      gender: c.assistant?.gender || 'f',
    },
    modules: Object.fromEntries(
      MODULES.map(m => [m.key, c.modules?.[m.key] !== false])
    ),
    public_host: c.public_host || '',
    hub: {
      whatsapp: c.hub?.whatsapp || '',
      tagline: c.hub?.tagline || '',
      cta_text: c.hub?.cta_text || '',
    },
    tracking: {
      meta_pixel_id: c.tracking?.meta_pixel_id || '',
      ga4_measurement_id: c.tracking?.ga4_measurement_id || '',
    },
    // 🎨 Personalização (28/10)
    visual: {
      system_name: c.visual?.system_name || '',
      palette: c.visual?.palette || '',
      watermark: c.visual?.watermark !== false,
      accent: c.visual?.accent || '',
    },
    dictionary: {
      mode: c.dictionary?.explicit ? (c.dictionary.enabled ? 'on' : 'off') : 'auto',
      // na tela só os pares PRÓPRIOS; vazio = os pares do vocabulário
      pairs: (c.dictionary?.pairs || []).some(
        p => !(c.dictionary?.defaults || []).some(d => d.de === p.de && d.para === p.para)
      )
        ? (c.dictionary?.pairs || []).map(p => ({ ...p }))
        : [],
    },
    phrases: { ...(c.phrases || {}) },
    labels: { ...(c.labels || {}) },
  };
};

onMounted(async () => {
  try {
    await store.dispatch('crm/fetchSettings');
    hydrate();
  } catch {
    useAlert('Não consegui carregar a identidade da empresa.');
  } finally {
    isLoading.value = false;
  }
});

const vocabDefaults = computed(
  () => VOCAB_DEFAULTS[form.value.segment] || VOCAB_DEFAULTS.clinica
);
const isClinic = computed(() => form.value.segment === 'clinica');
const customWords = computed(
  () => Object.values(form.value.vocabulary).filter(Boolean).length
);

// ao trocar o ramo, os módulos de clínica seguem o padrão do ramo novo
// (clínica = ligados; ótica/outro = desligados) — o admin pode mexer depois
const setSegment = key => {
  if (form.value.segment === key) return;
  form.value.segment = key;
  MODULES.forEach(m => {
    form.value.modules[m.key] = key === 'clinica';
  });
};

const resetVocabulary = () => {
  form.value.vocabulary = emptyVocabulary();
};

// ── unidades ────────────────────────────────────────────────────────────
const addUnit = () => {
  form.value.units.push({
    key: '',
    label: '',
    address: '',
    phone: '',
    keyTouched: false,
  });
};
const removeUnit = i => form.value.units.splice(i, 1);
const moveUnit = (i, dir) => {
  const j = i + dir;
  if (j < 0 || j >= form.value.units.length) return;
  const list = form.value.units;
  [list[i], list[j]] = [list[j], list[i]];
};
const onUnitLabel = unit => {
  if (!unit.keyTouched) unit.key = slugify(unit.label);
};

// ── salvar ──────────────────────────────────────────────────────────────
const payload = () => {
  const f = form.value;
  return {
    name: f.name.trim(),
    segment: f.segment,
    city: f.city.trim(),
    tagline: f.tagline.trim(),
    about: f.about.trim(),
    offers: f.offers.trim(),
    tone: f.tone.trim(),
    vocabulary: Object.fromEntries(
      Object.entries(f.vocabulary).map(([k, v]) => [k, String(v || '').trim()])
    ),
    units: f.units
      .filter(u => u.label.trim() || u.key.trim())
      .map(u => ({
        key: u.key.trim() || slugify(u.label),
        label: u.label.trim(),
        address: u.address.trim(),
        phone: u.phone.trim(),
      })),
    assistant: { name: f.assistant.name.trim(), gender: f.assistant.gender },
    modules: { ...f.modules },
    public_host: f.public_host.trim(),
    hub: {
      whatsapp: f.hub.whatsapp.trim(),
      tagline: f.hub.tagline.trim(),
      cta_text: f.hub.cta_text.trim(),
    },
    tracking: {
      meta_pixel_id: f.tracking.meta_pixel_id.trim(),
      ga4_measurement_id: f.tracking.ga4_measurement_id.trim(),
    },
    // 🎨 Personalização (28/10)
    visual: {
      system_name: f.visual.system_name.trim(),
      palette: f.visual.palette,
      watermark: f.visual.watermark,
      accent: f.visual.accent.trim(),
    },
    dictionary: {
      enabled: f.dictionary.mode === 'auto' ? '' : f.dictionary.mode === 'on',
      pairs: f.dictionary.pairs
        .map(p => ({ de: String(p.de || '').trim(), para: String(p.para || '').trim() }))
        .filter(p => p.de && p.para),
    },
    phrases: Object.fromEntries(
      Object.entries(f.phrases)
        .map(([k, v]) => [k, String(v || '').trim()])
        .filter(([, v]) => v)
    ),
    labels: Object.fromEntries(
      Object.entries(f.labels)
        .map(([k, v]) => [k, String(v || '').trim()])
        .filter(([, v]) => v)
    ),
  };
};

const save = async () => {
  if (!form.value.name.trim()) {
    useAlert('Dê um nome à empresa antes de salvar.');
    return;
  }
  isSaving.value = true;
  try {
    await store.dispatch('crm/updateCompany', payload());
    hydrate();
    useAlert(
      `Personalização da ${form.value.name} salva! Telas, menu, agentes e páginas já usam o novo.`
    );
  } catch (e) {
    useAlert(
      e?.response?.data?.error || 'Não consegui salvar a identidade da empresa.'
    );
  } finally {
    isSaving.value = false;
  }
};

const segmentLabel = computed(
  () => SEGMENTS.find(s => s.key === form.value.segment)?.label || 'Clínica'
);
const unitWord = computed(() =>
  (
    form.value.vocabulary.unidade_plural || vocabDefaults.value.unidade_plural
  ).toLowerCase()
);
</script>

<template>
  <div
    class="cv-page cv-overlay flex-1 overflow-y-auto"
    :style="cvVars"
    data-sem-dicionario
  >
    <div class="max-w-[980px] mx-auto px-4 sm:px-6 py-5 sm:py-8">
      <CevicoHero
        :pal="pal"
        title="Personalização"
        subtitle="quem é a empresa · imagens e cores · palavras e frases · nomes dos ambientes · unidades e equipe · assistente · módulos · site público — tudo por dentro do sistema"
        icon="i-lucide-palette"
      >
        <template #actions>
          <button
            class="cv-btn cv-btn-sm"
            :disabled="isSaving || isLoading"
            @click="save"
          >
            <span
              :class="
                isSaving
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-save'
              "
              class="text-xs"
            />
            {{ isSaving ? 'Salvando…' : 'Salvar tudo' }}
          </button>
        </template>
      </CevicoHero>

      <div v-if="isLoading" class="py-16 text-center text-sm text-n-slate-10">
        Carregando…
      </div>

      <template v-else>
        <!-- ══ QUEM SOMOS ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('quem')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon">
              <span class="i-lucide-building-2 text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Quem somos
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            É daqui que os agentes de IA, as páginas e as mensagens tiram o nome
            e o jeito de falar da empresa.
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="cv-sub p-3 block sm:col-span-2">
              <span class="cv-label block mb-1">Nome da empresa</span>
              <input
                v-model="form.name"
                class="cv-input w-full text-sm"
                placeholder="Ex.: Sua Ótica"
                maxlength="80"
              />
            </label>

            <div class="cv-sub p-3 sm:col-span-2">
              <span class="cv-label block mb-2">Ramo</span>
              <div class="cv-seg grid grid-cols-3 w-full">
                <button
                  v-for="s in SEGMENTS"
                  :key="s.key"
                  type="button"
                  class="cv-seg-item"
                  :class="form.segment === s.key ? 'cv-seg-on' : ''"
                  @click="setSegment(s.key)"
                >
                  <span :class="s.icon" class="text-sm" />
                  <span class="truncate">{{ s.label }}</span>
                </button>
              </div>
              <p class="text-[11px] text-n-slate-10 mt-2 leading-snug">
                O ramo muda as palavras do sistema (paciente → cliente, consulta
                → atendimento…) e, fora da clínica, desliga os módulos de
                clínica (cirurgias, médicos, pós-operatório). Nada de clínica
                some de uma clínica.
              </p>
            </div>

            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Cidade</span>
              <input
                v-model="form.city"
                class="cv-input w-full text-sm"
                placeholder="São Paulo"
              />
            </label>
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Frase curta (tagline)</span>
              <input
                v-model="form.tagline"
                class="cv-input w-full text-sm"
                placeholder="Ex.: Óculos de grau com design e preço justo"
              />
            </label>

            <label class="cv-sub p-3 block sm:col-span-2">
              <span class="cv-label block mb-1">Sobre a empresa</span>
              <textarea
                v-model="form.about"
                rows="3"
                class="cv-input w-full text-sm"
                placeholder="Quem é a empresa, há quanto tempo existe, o que a diferencia."
              />
            </label>
            <label class="cv-sub p-3 block sm:col-span-2">
              <span class="cv-label block mb-1">O que oferece</span>
              <textarea
                v-model="form.offers"
                rows="3"
                class="cv-input w-full text-sm"
                placeholder="Ex.: óculos de grau, lentes de contato, óculos de sol, exame de vista gratuito."
              />
              <span class="text-[10px] text-n-slate-9 block mt-1">
                Entra no roteiro dos agentes como "O que a empresa oferece".
              </span>
            </label>
            <label class="cv-sub p-3 block sm:col-span-2">
              <span class="cv-label block mb-1">Tom de voz</span>
              <input
                v-model="form.tone"
                class="cv-input w-full text-sm"
                placeholder="Ex.: leve, próximo e direto, como um amigo que entende de óculos"
              />
            </label>
          </div>
        </section>

        <!-- ══ IDENTIDADE VISUAL (28/10) ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('visual')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon">
              <span class="i-lucide-palette text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Identidade visual
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            As imagens e cores desta empresa dentro do sistema. Sem nada aqui,
            valem as da instalação (a marca que veste o sistema na subida).
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
            <div
              v-for="img in IMAGENS"
              :key="img.kind"
              class="cv-sub p-3 flex items-center gap-3"
            >
              <div
                class="w-16 h-16 rounded-xl border border-n-weak bg-n-alpha-1 flex items-center justify-center overflow-hidden flex-shrink-0"
                :class="img.kind === 'logo_dark' ? 'bg-slate-900' : ''"
              >
                <img
                  v-if="imagens[img.kind]"
                  :src="imagens[img.kind]"
                  alt=""
                  class="max-w-full max-h-full object-contain"
                />
                <span
                  v-else
                  class="i-lucide-image text-xl text-n-slate-9"
                />
              </div>
              <div class="min-w-0 flex-1">
                <span class="text-sm font-semibold text-n-slate-12 block">
                  {{ img.label }}
                </span>
                <span class="text-[11px] text-n-slate-10 block leading-snug">
                  {{ img.hint }}
                </span>
                <div class="flex items-center gap-2 mt-2 flex-wrap">
                  <label class="cv-btn cv-btn-ghost cv-btn-sm cursor-pointer">
                    <span
                      :class="
                        imagemEnviando === img.kind
                          ? 'i-lucide-loader-circle animate-spin'
                          : 'i-lucide-upload'
                      "
                      class="text-xs"
                    />
                    {{ imagens[img.kind] ? 'Trocar' : 'Enviar' }}
                    <input
                      type="file"
                      accept="image/png,image/jpeg,image/svg+xml,image/webp"
                      class="hidden"
                      :disabled="Boolean(imagemEnviando)"
                      @change="enviarImagem(img.kind, $event)"
                    />
                  </label>
                  <button
                    v-if="imagens[img.kind]"
                    type="button"
                    class="cv-btn cv-btn-ghost cv-btn-danger cv-btn-sm"
                    :disabled="Boolean(imagemEnviando)"
                    @click="removerImagem(img.kind)"
                  >
                    <span class="i-lucide-trash-2 text-xs" />
                    Remover
                  </button>
                </div>
              </div>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Nome do sistema</span>
              <input
                v-model="form.visual.system_name"
                class="cv-input w-full text-sm"
                placeholder="Ex.: Sistema LIFE"
                maxlength="40"
              />
              <span class="text-[10px] text-n-slate-9 block mt-1">
                Aparece na saudação do Meu Painel. Vazio = nome da empresa.
              </span>
            </label>
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Paleta padrão</span>
              <select v-model="form.visual.palette" class="cv-input w-full text-sm">
                <option value="">Cor do dia (muda sozinha)</option>
                <option v-for="p in paletas" :key="p.key" :value="p.key">
                  {{ p.emoji ? `${p.emoji} ` : '' }}{{ p.label }}
                </option>
              </select>
              <span class="text-[10px] text-n-slate-9 block mt-1">
                Vale onde ninguém escolheu uma paleta própria.
              </span>
            </label>
            <div class="cv-sub p-3 flex items-center gap-3">
              <div class="min-w-0 flex-1">
                <span class="cv-label block mb-1">Marca d'água nos cabeçalhos</span>
                <span class="text-[11px] text-n-slate-10 block leading-snug">
                  O olho CEVICO (ou a imagem do cabeçalho) no canto dos painéis.
                </span>
              </div>
              <button
                type="button"
                class="cv-switch cv-switch-lg flex-shrink-0"
                :class="form.visual.watermark ? 'cv-switch-on' : ''"
                :aria-pressed="form.visual.watermark"
                :title="form.visual.watermark ? 'Esconder' : 'Mostrar'"
                @click="form.visual.watermark = !form.visual.watermark"
              />
            </div>
          </div>
        </section>

        <!-- ══ VOCABULÁRIO ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('vocab')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-spell-check text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Palavras
            </h2>
            <span class="cv-chip ml-auto">{{ segmentLabel }}</span>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            Palavra do sistema → palavra da empresa. Em branco vale o padrão do
            ramo (mostrado em cinza). Vale nas telas, nos robôs e nos agentes de
            IA.
          </p>

          <div class="cv-sub overflow-hidden">
            <div
              class="hidden sm:grid grid-cols-[1fr_1.4fr] gap-2 px-3 py-2 border-b border-n-weak"
            >
              <span class="cv-label">Palavra do sistema</span>
              <span class="cv-label">Palavra da empresa</span>
            </div>
            <div
              v-for="row in VOCAB_ROWS"
              :key="row.key"
              class="grid grid-cols-1 sm:grid-cols-[1fr_1.4fr] gap-1 sm:gap-2 px-3 py-2 items-center border-b border-n-weak last:border-b-0"
            >
              <span class="text-sm text-n-slate-11">
                {{ row.label }}
                <span
                  v-if="form.vocabulary[row.key]"
                  class="i-lucide-arrow-right text-[10px] text-n-slate-9 mx-1"
                />
              </span>
              <input
                v-model="form.vocabulary[row.key]"
                class="cv-input w-full text-sm"
                :placeholder="vocabDefaults[row.key]"
                maxlength="40"
              />
            </div>
          </div>

          <div class="flex items-center gap-2 mt-3 flex-wrap">
            <button
              type="button"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              :disabled="!customWords"
              @click="resetVocabulary"
            >
              <span class="i-lucide-rotate-ccw text-xs" />
              Voltar ao padrão do ramo
            </button>
            <span class="text-[11px] text-n-slate-9">
              {{
                customWords
                  ? `${customWords} palavra(s) personalizada(s)`
                  : 'tudo no padrão do ramo'
              }}
            </span>
          </div>
          <!-- 🎨 dicionário global (28/10) -->
          <div class="cv-sub p-3 mt-4">
            <div class="flex items-center gap-2 flex-wrap mb-1">
              <span class="i-lucide-replace text-sm text-n-slate-11" />
              <span class="text-sm font-semibold text-n-slate-12">
                Dicionário global das telas
              </span>
              <span
                class="cv-chip ml-auto"
                :class="dicionarioAtivoAgora ? '' : 'opacity-60'"
              >
                {{ dicionarioAtivoAgora ? 'ligado' : 'desligado' }}
              </span>
            </div>
            <p class="text-[11px] text-n-slate-10 leading-snug mb-3">
              Troca as palavras da clínica em TODAS as telas do painel —
              inclusive as que ainda escrevem o texto à mão. Nunca mexe no
              conteúdo das conversas, mensagens e campos de texto. Em branco,
              usa as palavras acima.
            </p>
            <div class="cv-seg grid grid-cols-3 w-full mb-3">
              <button
                type="button"
                class="cv-seg-item"
                :class="form.dictionary.mode === 'auto' ? 'cv-seg-on' : ''"
                @click="form.dictionary.mode = 'auto'"
              >
                Automático
              </button>
              <button
                type="button"
                class="cv-seg-item"
                :class="form.dictionary.mode === 'on' ? 'cv-seg-on' : ''"
                @click="form.dictionary.mode = 'on'"
              >
                Ligado
              </button>
              <button
                type="button"
                class="cv-seg-item"
                :class="form.dictionary.mode === 'off' ? 'cv-seg-on' : ''"
                @click="form.dictionary.mode = 'off'"
              >
                Desligado
              </button>
            </div>
            <p class="text-[10px] text-n-slate-9 mb-3">
              Automático = ligado fora da clínica, desligado na clínica.
            </p>
            <div v-if="!form.dictionary.pairs.length" class="text-[11px] text-n-slate-10 mb-2">
              <template v-if="dicionarioPadroes.length">
                Pares em uso (das palavras acima):
                <span v-for="p in dicionarioPadroes" :key="p.de" class="cv-chip mr-1 mb-1">
                  {{ p.de }} → {{ p.para }}
                </span>
              </template>
              <template v-else>
                Nenhuma palavra muda com o ramo atual — defina as palavras acima ou
                adicione pares próprios.
              </template>
            </div>
            <div
              v-for="(p, i) in form.dictionary.pairs"
              :key="`par-${i}`"
              class="grid grid-cols-[1fr_auto_1fr_auto] gap-2 items-center mb-2"
            >
              <input
                v-model="p.de"
                class="cv-input w-full text-sm"
                placeholder="palavra da clínica"
                maxlength="40"
              />
              <span class="i-lucide-arrow-right text-xs text-n-slate-9" />
              <input
                v-model="p.para"
                class="cv-input w-full text-sm"
                placeholder="palavra da empresa"
                maxlength="40"
              />
              <button
                type="button"
                class="cv-btn cv-btn-ghost cv-btn-danger cv-btn-sm px-2"
                title="Remover par"
                @click="removePar(i)"
              >
                <span class="i-lucide-trash-2 text-xs" />
              </button>
            </div>
            <div class="flex items-center gap-2 flex-wrap">
              <button
                type="button"
                class="cv-btn cv-btn-ghost cv-btn-sm"
                @click="addPar"
              >
                <span class="i-lucide-plus text-xs" />
                Adicionar par
              </button>
              <button
                v-if="!form.dictionary.pairs.length && dicionarioPadroes.length"
                type="button"
                class="cv-btn cv-btn-ghost cv-btn-sm"
                @click="usarParesDoVocabulario"
              >
                <span class="i-lucide-list-plus text-xs" />
                Editar os pares em uso
              </button>
            </div>
          </div>
        </section>

        <!-- ══ FRASES DAS TELAS (28/10) ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('frases')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-text-quote text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Frases das telas
            </h2>
            <span class="cv-chip ml-auto">
              {{ frasesPersonalizadas }} de {{ todasAsFrases.length }}
            </span>
          </div>
          <p class="text-xs text-n-slate-10 mb-3">
            Títulos e rótulos inteiros ("Consultas marcadas hoje", "Agenda de
            Cirurgias"…), para acertar gênero e concordância. Em branco vale o
            padrão em cinza. Palavras soltas o dicionário acima já resolve.
          </p>
          <div class="flex items-center gap-2 mb-3 flex-wrap">
            <input
              v-model="fraseBusca"
              class="cv-input flex-1 min-w-[200px] text-sm"
              placeholder="Buscar frase, tela ou texto…"
            />
            <button
              type="button"
              class="cv-btn cv-btn-ghost cv-btn-sm"
              :disabled="!frasesPersonalizadas"
              @click="limparFrases"
            >
              <span class="i-lucide-rotate-ccw text-xs" />
              Voltar tudo ao padrão
            </button>
          </div>
          <div class="space-y-3 max-h-[520px] overflow-y-auto pr-1">
            <div
              v-for="(lista, tela) in frasesFiltradas"
              :key="tela"
              class="cv-sub overflow-hidden"
            >
              <div class="px-3 py-2 border-b border-n-weak flex items-center gap-2">
                <span class="text-xs font-semibold text-n-slate-12">{{ tela }}</span>
                <span class="text-[10px] text-n-slate-9">{{ lista.length }}</span>
              </div>
              <div
                v-for="f in lista"
                :key="f.chave"
                class="grid grid-cols-1 sm:grid-cols-[1fr_1.2fr] gap-1 sm:gap-2 px-3 py-1.5 items-center border-b border-n-weak last:border-b-0"
              >
                <span class="text-xs text-n-slate-11 truncate" :title="f.chave">
                  {{ f.padrao }}
                </span>
                <input
                  v-model="form.phrases[f.chave]"
                  class="cv-input w-full text-sm"
                  :placeholder="f.padrao"
                  maxlength="300"
                />
              </div>
            </div>
            <div
              v-if="!Object.keys(frasesFiltradas).length"
              class="cv-sub p-4 text-sm text-n-slate-10 text-center"
            >
              Nenhuma frase com esse texto.
            </div>
          </div>
        </section>

        <!-- ══ NOMES DOS AMBIENTES (28/10) ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('nomes')">
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-signpost text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Nomes dos ambientes
            </h2>
            <span class="cv-chip ml-auto">{{ nomesPersonalizados }} renomeado(s)</span>
          </div>
          <p class="text-xs text-n-slate-10 mb-3">
            Como cada ambiente se chama no menu e no título da tela (Agenda →
            "Vistorias", Espaço do Paciente → "Espaço do Cliente"…). Em branco
            vale o nome de hoje.
          </p>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
            <div
              v-for="(lista, grupo) in AMBIENTES_POR_GRUPO"
              :key="grupo"
              class="cv-sub overflow-hidden"
            >
              <div class="px-3 py-2 border-b border-n-weak">
                <span class="text-xs font-semibold text-n-slate-12">{{ grupo }}</span>
              </div>
              <div
                v-for="a in lista"
                :key="a.chave"
                class="grid grid-cols-[1fr_1.2fr] gap-2 px-3 py-1.5 items-center border-b border-n-weak last:border-b-0"
              >
                <span class="text-xs text-n-slate-11 truncate">{{ a.padrao }}</span>
                <input
                  v-model="form.labels[a.chave]"
                  class="cv-input w-full text-sm"
                  :placeholder="a.padrao"
                  maxlength="60"
                />
              </div>
            </div>
          </div>
          <button
            type="button"
            class="cv-btn cv-btn-ghost cv-btn-sm mt-3"
            :disabled="!nomesPersonalizados"
            @click="limparNomes"
          >
            <span class="i-lucide-rotate-ccw text-xs" />
            Voltar aos nomes de hoje
          </button>
        </section>

        <!-- ══ UNIDADES (LOJAS) ══ -->
        <section
          class="cv-block p-5 sm:p-6 mb-4"
          :style="blockVars('unidades')"
        >
          <div class="flex items-center gap-2 mb-1 flex-wrap">
            <span class="cv-icon">
              <span class="i-lucide-store text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Unidades ({{ unitWord }})
            </h2>
            <span class="cv-chip ml-auto">{{ form.units.length }}</span>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            As unidades aparecem na Agenda, nas Tarefas e nos acessos por pessoa
            (quem só vê uma loja). A chave é gerada sozinha a partir do nome e é
            o que o sistema guarda — mude só se souber o que está fazendo.
            <template v-if="isClinic">
              Clínica sem lista própria usa as unidades que a Agenda já conhece.
            </template>
          </p>

          <div
            v-if="!form.units.length"
            class="cv-sub p-4 text-sm text-n-slate-10 text-center"
          >
            Nenhuma unidade cadastrada ainda.
          </div>

          <div class="space-y-2">
            <div
              v-for="(unit, i) in form.units"
              :key="i"
              class="cv-sub p-3 grid grid-cols-1 sm:grid-cols-[1.2fr_0.9fr_1.4fr_0.9fr_auto] gap-2 items-end"
            >
              <label class="block">
                <span class="cv-label block mb-1">Nome</span>
                <input
                  v-model="unit.label"
                  class="cv-input w-full text-sm"
                  placeholder="Ex.: Loja Moema"
                  maxlength="60"
                  @input="onUnitLabel(unit)"
                />
              </label>
              <label class="block">
                <span class="cv-label block mb-1">Chave</span>
                <input
                  v-model="unit.key"
                  class="cv-input w-full text-xs font-mono"
                  placeholder="loja_moema"
                  maxlength="40"
                  @input="unit.keyTouched = true"
                />
              </label>
              <label class="block">
                <span class="cv-label block mb-1">Endereço</span>
                <input
                  v-model="unit.address"
                  class="cv-input w-full text-sm"
                  placeholder="Rua, número, bairro"
                  maxlength="200"
                />
              </label>
              <label class="block">
                <span class="cv-label block mb-1">Telefone</span>
                <input
                  v-model="unit.phone"
                  class="cv-input w-full text-sm"
                  placeholder="11999990000"
                  maxlength="20"
                />
              </label>
              <div class="flex items-center gap-1 justify-end">
                <button
                  type="button"
                  class="cv-btn cv-btn-ghost cv-btn-sm px-2"
                  title="Subir"
                  :disabled="i === 0"
                  @click="moveUnit(i, -1)"
                >
                  <span class="i-lucide-chevron-up text-xs" />
                </button>
                <button
                  type="button"
                  class="cv-btn cv-btn-ghost cv-btn-sm px-2"
                  title="Descer"
                  :disabled="i === form.units.length - 1"
                  @click="moveUnit(i, 1)"
                >
                  <span class="i-lucide-chevron-down text-xs" />
                </button>
                <button
                  type="button"
                  class="cv-btn cv-btn-ghost cv-btn-danger cv-btn-sm px-2"
                  title="Remover unidade"
                  @click="removeUnit(i)"
                >
                  <span class="i-lucide-trash-2 text-xs" />
                </button>
              </div>
            </div>
          </div>

          <button
            type="button"
            class="cv-btn cv-btn-ghost cv-btn-sm mt-3"
            @click="addUnit"
          >
            <span class="i-lucide-plus text-xs" />
            Adicionar unidade
          </button>
        </section>

        <!-- ══ EQUIPE E LISTAS (coringa, embutido 28/10) ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('equipe')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon">
              <span class="i-lucide-users text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Equipe, listas e meta
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            Quem atende (os "médicos" do sistema), as agendas paralelas, os
            motivos e as opções da Agenda, a meta do mês e o contexto que os
            robôs usam. Este bloco salva sozinho, com o próprio botão.
          </p>
          <PersonalizacaoEquipe embutido />
        </section>

        <!-- ══ ASSISTENTE VIRTUAL ══ -->
        <section
          class="cv-block p-5 sm:p-6 mb-4"
          :style="blockVars('assistente')"
        >
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon"><span class="i-lucide-bot text-base" /></span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Assistente virtual
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            Como os agentes de IA se apresentam ("Aqui é a Ana, assistente
            virtual da Sua Ótica"). A Integração do Agente de Ligação pode ter
            uma persona própria; vazia, vale esta.
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Nome</span>
              <input
                v-model="form.assistant.name"
                class="cv-input w-full text-sm"
                placeholder="Ex.: Ana"
                maxlength="40"
              />
            </label>
            <div class="cv-sub p-3">
              <span class="cv-label block mb-2">Gênero (o/a)</span>
              <div class="cv-seg grid grid-cols-2 w-full">
                <button
                  type="button"
                  class="cv-seg-item"
                  :class="form.assistant.gender === 'f' ? 'cv-seg-on' : ''"
                  @click="form.assistant.gender = 'f'"
                >
                  a assistente
                </button>
                <button
                  type="button"
                  class="cv-seg-item"
                  :class="form.assistant.gender === 'm' ? 'cv-seg-on' : ''"
                  @click="form.assistant.gender = 'm'"
                >
                  o assistente
                </button>
              </div>
            </div>
          </div>
        </section>

        <!-- ══ MÓDULOS ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('modulos')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon">
              <span class="i-lucide-toggle-right text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Módulos
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-4">
            Partes do sistema que só fazem sentido numa clínica. Numa ótica elas
            nascem desligadas; aqui você liga ou desliga uma a uma.
          </p>
          <div class="space-y-2">
            <div
              v-for="m in MODULES"
              :key="m.key"
              class="cv-sub p-3 flex items-center gap-3"
            >
              <div class="min-w-0 flex-1">
                <span class="text-sm font-semibold text-n-slate-12 block">
                  {{ m.label }}
                </span>
                <span class="text-[11px] text-n-slate-10 block leading-snug">
                  {{ m.hint }}
                </span>
              </div>
              <div class="flex flex-col items-end gap-1 flex-shrink-0">
                <button
                  type="button"
                  class="cv-switch cv-switch-lg"
                  :class="form.modules[m.key] ? 'cv-switch-on' : ''"
                  :aria-pressed="form.modules[m.key]"
                  :title="form.modules[m.key] ? 'Desligar' : 'Ligar'"
                  @click="form.modules[m.key] = !form.modules[m.key]"
                />
                <span class="text-[10px] text-n-slate-9">
                  {{ form.modules[m.key] ? 'Ligado' : 'Desligado' }}
                </span>
              </div>
            </div>
          </div>
        </section>

        <!-- ══ SITE PÚBLICO ══ -->
        <section class="cv-block p-5 sm:p-6 mb-4" :style="blockVars('site')">
          <div class="flex items-center gap-2 mb-1">
            <span class="cv-icon">
              <span class="i-lucide-globe text-base" />
            </span>
            <h2 class="text-base sm:text-lg font-bold text-n-slate-12">
              Site público desta empresa
            </h2>
          </div>
          <p class="text-xs text-n-slate-10 mb-3">
            O domínio onde as páginas desta empresa respondem, o WhatsApp da
            porta de entrada (hub) e o rastreio dela.
          </p>
          <p
            class="text-[11px] rounded-xl border border-amber-500/40 bg-amber-500/10 text-n-slate-11 px-3 py-2 mb-4"
          >
            ⚠️ Vazio = vale a configuração geral do sistema (Configurações →
            Domínio).
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <label class="cv-sub p-3 block sm:col-span-2">
              <span class="cv-label block mb-1">
                Domínio público (sem https://)
              </span>
              <input
                v-model="form.public_host"
                class="cv-input w-full text-sm"
                placeholder="www.suaotica.com.br"
              />
              <span class="text-[10px] text-n-slate-9 block mt-1">
                Aponte o domínio para o mesmo endereço do sistema (CNAME) e
                cadastre no EasyPanel, igual ao passo a passo de Configurações →
                Domínio.
              </span>
            </label>
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">
                WhatsApp do hub (só números, com DDI)
              </span>
              <input
                v-model="form.hub.whatsapp"
                class="cv-input w-full text-sm"
                placeholder="5511999990000"
              />
            </label>
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Frase de boas-vindas</span>
              <input
                v-model="form.hub.tagline"
                class="cv-input w-full text-sm"
                placeholder="Ex.: Enxergue melhor, do seu jeito."
                maxlength="300"
              />
            </label>
            <label class="cv-sub p-3 block sm:col-span-2">
              <span class="cv-label block mb-1">
                Mensagem do botão (o que o cliente envia ao clicar)
              </span>
              <input
                v-model="form.hub.cta_text"
                class="cv-input w-full text-sm"
                :placeholder="`Olá! Vim do site da ${form.name || 'empresa'} e quero mais informações.`"
                maxlength="300"
              />
            </label>
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">
                Pixel da Meta (só o número)
              </span>
              <input
                v-model="form.tracking.meta_pixel_id"
                class="cv-input w-full text-sm"
                placeholder="1234567890123456"
              />
            </label>
            <label class="cv-sub p-3 block">
              <span class="cv-label block mb-1">Google GA4 (código G-…)</span>
              <input
                v-model="form.tracking.ga4_measurement_id"
                class="cv-input w-full text-sm"
                placeholder="G-AB12CD34EF"
              />
            </label>
          </div>
        </section>

        <div class="flex items-center justify-end gap-3 mb-8">
          <button class="cv-btn cv-btn-lg" :disabled="isSaving" @click="save">
            <span
              :class="
                isSaving
                  ? 'i-lucide-loader-circle animate-spin'
                  : 'i-lucide-save'
              "
              class="text-sm"
            />
            {{ isSaving ? 'Salvando…' : 'Salvar personalização' }}
          </button>
        </div>
      </template>
    </div>
  </div>
</template>
