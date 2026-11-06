<script setup>
// 🧪 item 383 (03/11): SEGMENTAÇÃO DA BASE — o ambiente onde a base é
// separada em segmentos para TESTAR mensagens (até 5, com 100 pessoas cada,
// por exemplo) e depois ESCALAR a vencedora no ritmo escolhido (150 por hora,
// 10 a cada 5 minutos…). Guilherme: "mandar para 8 mil no mesmo dia não é o
// nosso estilo; quero selecionar a base, isolar o que já foi testado, ver a
// taxa de cada mensagem e programar os envios com respiro".
// Quatro blocos: 1 Sua base · 2 Segmento novo · 3 Seus segmentos · 4 Painel,
// e um TUTORIAL GUIADO que abre sozinho na 1ª vez e pode ser revisto sempre.
import { ref, computed, onMounted, nextTick } from 'vue';
import { useRouter, useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import { useCevicoAccess } from 'dashboard/composables/useCevicoAccess';
import CevicoHero from 'dashboard/components-next/cevico/CevicoHero.vue';
import CevicoViewOnlyPill from 'dashboard/components-next/cevico/CevicoViewOnlyPill.vue';
import CvTutorial from 'dashboard/components-next/cevico/CvTutorial.vue';
import SegmentacaoBase from 'dashboard/components-next/cevico/segmentacao/SegmentacaoBase.vue';
import SegmentoNovo from 'dashboard/components-next/cevico/segmentacao/SegmentoNovo.vue';
import SegmentoCard from 'dashboard/components-next/cevico/segmentacao/SegmentoCard.vue';
import SegmentacaoPainel from 'dashboard/components-next/cevico/segmentacao/SegmentacaoPainel.vue';
import { fmtInt } from 'dashboard/components-next/cevico/segmentacao/segmentacaoHelpers';
import CrmAPI from 'dashboard/api/crm';

const router = useRouter();
const route = useRoute();
const { canEdit } = useCevicoAccess();
const canEditCampaigns = computed(() => canEdit('crm.campanhas'));
const accountId = computed(() => route.params.accountId);

const pal = useCevicoPalette({
  scope: 'report:segmentacao',
  blocks: [
    { id: 'base', label: 'Sua base', icon: 'i-lucide-database' },
    { id: 'novo', label: 'Segmento novo', icon: 'i-lucide-scissors' },
    { id: 'lista', label: 'Seus segmentos', icon: 'i-lucide-layers' },
    { id: 'painel', label: 'Painel', icon: 'i-lucide-line-chart' },
  ],
});
const { cvVars, blockVars } = pal;

const base = ref(null);
const baseLoading = ref(true);
const segments = ref([]);
const listLoading = ref(true);
const refreshKey = ref(0);
const selectedStageIds = ref([]);
const novoRef = ref(null);
const listFilter = ref('todos'); // 'todos' | 'enviando' | 'teste' | 'escala' | 'concluido'

const loadBase = async () => {
  baseLoading.value = true;
  try {
    const { data } = await CrmAPI.getSegmentsBase();
    base.value = data;
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para carregar a base.');
  } finally {
    baseLoading.value = false;
  }
};
const loadList = async () => {
  listLoading.value = true;
  try {
    const { data } = await CrmAPI.getSegments();
    segments.value = data.segments || [];
  } catch (err) {
    useAlert(err?.response?.data?.error || 'Não deu para listar os segmentos.');
  } finally {
    listLoading.value = false;
  }
};
// ── tutorial guiado (abre sozinho na 1ª vez; "Tutorial" no topo reabre) ──
const TUTORIAL_KEY = 'cevico:tutorial:segmentacao:visto';
const tutorialOpen = ref(false);
const tutorialSeen = () => {
  try {
    return window.localStorage.getItem(TUTORIAL_KEY) === '1';
  } catch {
    return true;
  }
};
const markTutorialSeen = () => {
  try {
    window.localStorage.setItem(TUTORIAL_KEY, '1');
  } catch {
    // sem armazenamento: só não lembra
  }
};
const TUTORIAL_STEPS = [
  { icon: 'i-lucide-compass', title: 'Por que segmentar antes de disparar',
    text: 'Mandar a mesma mensagem para 8 mil pessoas no mesmo dia é jogar no escuro: não dá para saber qual texto funciona, e o WhatsApp pode bloquear o número.\nAqui a base é separada em pedaços (segmentos). Primeiro você TESTA algumas mensagens em lotes pequenos, mede, e só depois ESCALA a vencedora para o resto, no ritmo que quiser.' },
  { target: '#seg-base', icon: 'i-lucide-database', title: '1 · Sua base',
    text: 'Cada coluna do CRM mostra quem tem telefone, quem já entrou em algum segmento (já foi testado ou está reservado) e quem ainda pode receber hoje.\nQuem está num segmento nunca entra em outro: é isso que isola o que já foi testado.' },
  { target: '#seg-novo-base', icon: 'i-lucide-filter', title: '2 · De onde vem a base',
    text: 'Escolha as colunas e ajuste a peneira: dias desde que chegou, conversa recente, consulta marcada, campanha recente.\nA frase embaixo diz, por extenso, quem vai entrar.' },
  { target: '#seg-novo-tipo', icon: 'i-lucide-flask-conical', title: 'Teste × Escala, e o tamanho',
    text: 'TESTE = até 5 mensagens, sorteio equilibrado (ex.: 500 pessoas = 100 por mensagem).\nESCALA = uma mensagem só (a vencedora) para um lote grande ou a base inteira.\nSorteio é a ordem certa para testar; “mais antigos” serve para limpar a base parada.' },
  { target: '#seg-novo-mensagens', icon: 'i-lucide-message-square-text', title: 'As mensagens A, B, C…',
    text: 'Cada mensagem é um modelo aprovado pela Meta (categoria Marketing). O {{1}} vira o primeiro nome.\nOs modelos vêm da caixa padrão: crie na Meta e clique em “Buscar novos templates” na caixa se faltar algum.' },
  { target: '#seg-novo-ritmo', icon: 'i-lucide-timer', title: 'O ritmo de envio',
    text: '“150 por hora, de 60 em 60 min” = 150 às 9h, 150 às 10h…\n“120 por hora, de 5 em 5 min” = 10 pessoas a cada 5 minutos.\nJanela, dias úteis e teto por dia valem sempre. Pela caixa de origem = quem veio do Instagram recebe pela caixa do Instagram.' },
  { target: '#seg-novo-calcular', icon: 'i-lucide-calculator', title: 'Calcular e reservar',
    text: '“Calcular quem entra” mostra a peneira regra a regra e quantas pessoas vão ser reservadas.\n“Reservar segmento” só separa as pessoas — nada é enviado ainda.' },
  { target: '#seg-lista', icon: 'i-lucide-layers', title: '3 · Seus segmentos',
    text: 'Cada cartão é um segmento. “Iniciar” liga o robô (as levas saem no ritmo, dentro do horário). “Mandar a próxima leva agora” força uma leva na hora, digitando ENVIAR.\n“Pausar” para tudo; quem já recebeu fica registrado.' },
  { target: '#seg-lista', icon: 'i-lucide-trophy', title: 'Ler os resultados e escalar',
    text: '“Resultados” abre a tabela por mensagem: enviadas, entregues, lidas, respondeu, consulta marcada, cirurgia — e o gráfico de linha por dia.\nA vencedora ganha 🏆 (maior taxa de consulta; respostas desempatam; mínimo de 20 enviadas). “Escalar a vencedora” cria o lote de escala só com ela, para quem ainda não recebeu.' },
  { target: '#seg-painel', icon: 'i-lucide-line-chart', title: '4 · Painel',
    text: 'A soma de todos os segmentos: quantos estão enviando, quantas pessoas na fila, enviadas, respostas e consultas dos últimos 30 dias, dia a dia.\nPara rever este tutorial, clique em “Tutorial” no topo da página a qualquer hora.' },
];
const onTutorialFinish = () => markTutorialSeen();
const onTutorialClose = () => markTutorialSeen();

const refreshAll = async () => {
  await Promise.all([loadBase(), loadList()]);
  refreshKey.value += 1;
};
onMounted(async () => {
  await refreshAll();
  if (!tutorialSeen()) {
    await nextTick();
    tutorialOpen.value = true;
  }
});

const pickStage = id => {
  novoRef.value?.addStage(id);
  document.getElementById('seg-novo')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};
const onCreated = async () => {
  await refreshAll();
  await nextTick();
  document.getElementById('seg-lista')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};
// ação num cartão (iniciar, pausar, leva, apagar): a lista e o painel mudam; a base só
// muda quando um segmento é reservado ou apagado — e o formulário não pode ser mexido
const onChanged = async data => {
  await loadList();
  refreshKey.value += 1;
  if (data === null) await loadBase(); // apagou: as pessoas voltaram para a base
};

const FILTERS = [
  { key: 'todos', label: 'Todos' },
  { key: 'enviando', label: 'Enviando' },
  { key: 'teste', label: 'Testes' },
  { key: 'escala', label: 'Escalas' },
  { key: 'concluido', label: 'Concluídos' },
];
const visibleSegments = computed(() => {
  const f = listFilter.value;
  if (f === 'todos') return segments.value;
  if (f === 'teste' || f === 'escala') return segments.value.filter(s => s.kind === f);
  return segments.value.filter(s => s.status === f);
});
const sendingCount = computed(() => segments.value.filter(s => s.status === 'enviando').length);
const totalSent = computed(() => segments.value.reduce((a, s) => a + Number(s.sent || 0), 0));
const totalReserved = computed(() => segments.value.reduce((a, s) => a + Number(s.reserved || 0), 0));

</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-solid-1 overflow-hidden">
    <!-- Header no padrão das telas do CRM -->
    <div class="flex items-center gap-3 px-6 py-4 border-b border-n-weak flex-shrink-0 flex-wrap">
      <button class="flex items-center gap-1 text-sm text-n-slate-11 hover:text-n-slate-12" @click="router.push({ name: 'crm_board' })">
        <span class="i-lucide-arrow-left" />
        CRM
      </button>
      <span class="text-n-slate-8">/</span>
      <h1 class="text-base font-semibold text-n-slate-12 flex items-center gap-2">
        <span class="w-8 h-8 rounded-xl flex items-center justify-center" style="background: linear-gradient(135deg, #1d4ed8, #3b82f6)">
          <span class="i-lucide-layers text-white text-base" />
        </span>
        Segmentação
        <CevicoViewOnlyPill v-if="!canEditCampaigns" />
      </h1>
      <div class="flex-1" />
      <button
        id="seg-tutorial-btn"
        class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1"
        title="Rever o passo a passo guiado"
        @click="tutorialOpen = true"
      >
        <span class="i-lucide-graduation-cap" />
        Tutorial
      </button>
      <button class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1" title="Mensagens prontas e plano por coluna" @click="router.push({ name: 'crm_reativacao' })">
        <span class="i-lucide-rotate-ccw" />
        Reativação
      </button>
      <button class="text-xs px-3 py-1.5 rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-1 flex items-center gap-1" title="Campanhas, automações e ligações" @click="router.push({ name: 'crm_campaigns' })">
        <span class="i-lucide-megaphone" />
        Campanha WhatsApp
      </button>
    </div>

    <!-- a tela inteira rola (regra: toda tela rola até o fim) -->
    <div class="flex-1 overflow-y-auto p-6 sm:p-10">
      <div class="cv-page max-w-[1600px] mx-auto w-full" :style="cvVars">
        <CevicoHero
          :pal="pal"
          title="Segmentação da base"
          subtitle="Separe a base em pedaços, teste até 5 mensagens em lotes pequenos, descubra a vencedora e escale no ritmo certo."
          icon="i-lucide-layers"
        >
          <template #chips>
            <span class="cevico-hero-chip"><span class="i-lucide-layers text-xs" />{{ segments.length }} segmentos</span>
            <span class="cevico-hero-chip"><span class="i-lucide-play text-xs" />{{ sendingCount }} enviando</span>
            <span class="cevico-hero-chip"><span class="i-lucide-lock text-xs" />{{ fmtInt(totalReserved) }} na fila</span>
            <span class="cevico-hero-chip"><span class="i-lucide-send text-xs" />{{ fmtInt(totalSent) }} enviadas</span>
          </template>
        </CevicoHero>

        <section id="seg-base" class="cv-block p-6 sm:p-10 mb-12" :style="blockVars('base')">
          <SegmentacaoBase :stages="base?.stages || []" :loading="baseLoading" :selected="selectedStageIds" @pick="pickStage" />
        </section>

        <section id="seg-novo" class="cv-block p-6 sm:p-10 mb-12" :style="blockVars('novo')">
          <SegmentoNovo ref="novoRef" :base="base" :can-edit="canEditCampaigns" @created="onCreated" @update:stage-ids="selectedStageIds = $event" />
        </section>

        <section id="seg-lista" class="cv-block p-6 sm:p-10 mb-12" :style="blockVars('lista')">
          <div class="flex items-start gap-4 mb-6 flex-wrap">
            <span class="cv-icon cv-icon-lg"><span class="i-lucide-layers text-xl" /></span>
            <div class="min-w-0 flex-1">
              <h2 class="text-xl sm:text-2xl tracking-tight font-bold text-n-slate-12 leading-tight">3. Seus segmentos</h2>
              <p class="text-sm text-n-slate-11 mt-1">Inicie, pause, mande uma leva agora, leia os resultados por mensagem e escale a vencedora.</p>
            </div>
            <div class="cv-seg cv-seg-sm flex-wrap">
              <button v-for="f in FILTERS" :key="f.key" class="cv-seg-item" :class="{ 'cv-seg-on': listFilter === f.key }" @click="listFilter = f.key">{{ f.label }}</button>
            </div>
          </div>
          <p v-if="listLoading && !segments.length" class="text-sm text-n-slate-10">Carregando…</p>
          <p v-else-if="!visibleSegments.length" class="text-sm text-n-slate-10">
            {{ segments.length ? 'Nenhum segmento neste filtro.' : 'Nenhum segmento ainda. Monte o primeiro no bloco acima: ele nasce reservado, sem mandar nada.' }}
          </p>
          <div v-else class="grid grid-cols-1 xl:grid-cols-2 gap-5">
            <SegmentoCard v-for="s in visibleSegments" :key="s.id" :seg="s" :can-edit="canEditCampaigns" :account-id="accountId" @changed="onChanged" @escalado="onCreated" />
          </div>
        </section>

        <section id="seg-painel" class="cv-block p-6 sm:p-10 mb-12" :style="blockVars('painel')">
          <SegmentacaoPainel :refresh-key="refreshKey" />
        </section>
      </div>
    </div>

    <CvTutorial v-model="tutorialOpen" name="Tutorial · Segmentação" :steps="TUTORIAL_STEPS" @finish="onTutorialFinish" @close="onTutorialClose" />
  </div>
</template>
