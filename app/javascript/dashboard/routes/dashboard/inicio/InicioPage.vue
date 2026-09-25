<script setup>
import { useAlert } from 'dashboard/composables';
// Meu Painel (tela inicial) — visível para admin E atendentes.
// Boas-vindas, avisos do Radar, indicadores por período (régua padrão:
// hoje/ontem/últimos 7/mês/ano/personalizado) e a saúde da agenda —
// com atalhos para agir rápido.
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import SkeletonPiece from 'dashboard/components-next/cevico/SkeletonPiece.vue';
import EmojiFx from 'dashboard/components-next/cevico/EmojiFx.vue';
import TileAura from 'dashboard/components-next/radar/TileAura.vue';
import PatientSpaceIcon from 'dashboard/routes/dashboard/patient/PatientSpaceIcon.vue';
import ConversationChatModal from 'dashboard/routes/dashboard/crm/components/ConversationChatModal.vue';
import CustomPanelGrid from 'dashboard/components-next/cevico/CustomPanelGrid.vue';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import AgendaDashboardCore from 'dashboard/components-next/cevico/AgendaDashboardCore.vue';
import CrmAPI from 'dashboard/api/crm';
import PatientNoteForm from 'dashboard/components-next/cevico/PatientNoteForm.vue';
import { useCevicoGoals } from 'dashboard/composables/useCevicoGoals';
import { paletteByKey } from 'dashboard/helper/cevicoBuilderCatalog';
import { ALL_THEMES } from 'dashboard/helper/cevicoThemes';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CevicoPalettePicker from 'dashboard/components-next/cevico/CevicoPalettePicker.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import draggable from 'vuedraggable';
import {
  evaluateFormula,
  variablesIn,
  formatKpi,
} from 'dashboard/helper/cevicoFormula';
import {
  DOCTORS,
  resolveWindows,
  resolveBlocked,
  resolveBlockedDays,
  resolveSurgeryWindows,
  blockKey,
  scanAgenda,
} from 'dashboard/helper/cevicoAgenda';

const router = useRouter();
const store = useStore();
const { accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const allTasks = useMapGetter('tasks/getTasks');
const crmSettings = useMapGetter('crm/getSettings');
const teamAgents = useMapGetter('agents/getAgents');
const { isAdmin } = useAdmin();

const isLoading = ref(true);
const data = ref(null);

// ── Período ─────────────────────────────────────────────────
// Régua PADRÃO dos dashboards (PeriodRuler): Hoje/Ontem/Últimos 7 dias/
// Este mês/Este ano + Personalizado (De/Até). O v-model traz sempre
// { preset, from, to } — nos presets o backend resolve as datas sozinho.
const pad2 = n => String(n).padStart(2, '0');
const hojeStr = (() => {
  const d = new Date();
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
})();
const period = ref({ preset: 'today', from: hojeStr, to: hojeStr });

// ── Painéis por pessoa: mesmo layout, indicadores e cores da função ──
const BASE_PANELS = [
  {
    key: 'agendamento',
    label: 'Agendamento',
    who: '',
    icon: 'i-lucide-calendar-check',
    desc: 'do lead ao agendamento',
    grad: 'linear-gradient(135deg, #0F5FA6 0%, #7C3AED 100%)',
  },
  {
    key: 'conducao',
    label: 'Condução',
    who: '',
    icon: 'i-lucide-route',
    desc: 'do agendamento à indicação',
    grad: 'linear-gradient(135deg, #0F766E 0%, #2DD4BF 100%)',
  },
  {
    key: 'cirurgia',
    label: 'Cirurgias',
    who: '',
    icon: 'i-lucide-heart-pulse',
    desc: 'fechamento e pós-operatório',
    grad: 'linear-gradient(135deg, #9D174D 0%, #F472B6 100%)',
  },
  {
    key: 'medico',
    label: 'Médicos',
    who: '',
    icon: 'i-lucide-stethoscope',
    desc: 'a agenda de cada médico',
    grad: 'linear-gradient(135deg, #0369A1 0%, #38BDF8 100%)',
  },
  {
    key: 'gestor',
    label: 'Gestor',
    who: '',
    icon: 'i-lucide-line-chart',
    desc: 'indicadores-chave do processo inteiro',
    grad: 'linear-gradient(135deg, #111827 0%, #475569 60%, #94A3B8 100%)',
  },
];

// RESPONSÁVEL por painel (Configurações → Painéis): o 1º nome aparece na
// pílula — "Cirurgias · Elizangela". Sem responsável = só o tema.
const panelOwners = computed(() => crmSettings.value?.panel_owners || {});
const ownerFirstName = key =>
  (panelOwners.value[key]?.name || '').split(' ')[0] || '';

// painéis do CONSTRUTOR salvos pela conta viram pílulas junto dos fixos
// (key 'custom:<id>' — o backend do home já entende esse formato)
const allPanels = computed(() => [
  ...BASE_PANELS.map(p => ({ ...p, who: ownerFirstName(p.key) || p.who })),
  // 🧑‍🤝‍🧑 painéis POR PESSOA (rodada 160): versão de um painel-base com
  // layout próprio — mesma cor/ícone do base, nome escolhido pelo admin
  ...(crmSettings.value?.panel_variants || []).map(v => {
    const base = BASE_PANELS.find(b => b.key === v.base) || BASE_PANELS[0];
    return {
      key: `variant:${v.id}`,
      label: v.name,
      who: '',
      icon: base.icon,
      desc: base.desc,
      grad: base.grad,
      base: base.key,
      variant: true,
      variantDef: v,
    };
  }),
  ...(crmSettings.value?.custom_panels || []).map(p => ({
    key: `custom:${p.id}`,
    label: p.name,
    who: '',
    icon: 'i-lucide-magnet',
    desc: 'painel do Construtor',
    grad: paletteByKey(p.palette).grads[0],
    custom: true,
    panelDef: p,
  })),
]);

// painel ATRIBUÍDO pelo admin: o agente fica travado nele
const assignedPanel = computed(() => {
  if (isAdmin.value) return null;
  const map = crmSettings.value?.panel_assignments || {};
  return map[String(currentUser.value?.id)] || null;
});
const visiblePanels = computed(() => {
  if (!assignedPanel.value) return allPanels.value;
  const only = allPanels.value.filter(p => p.key === assignedPanel.value);
  // atribuição órfã (painel custom excluído) libera todos de novo
  return only.length ? only : allPanels.value;
});

// ── Admin: quem vê qual painel (engrenagem ao lado das pílulas) ──
const showAssignModal = ref(false);
const assignDraft = ref({});
const isSavingAssign = ref(false);
const openAssignModal = () => {
  assignDraft.value = { ...(crmSettings.value?.panel_assignments || {}) };
  if (!teamAgents.value.length) store.dispatch('agents/get');
  showAssignModal.value = true;
};
const saveAssignments = async () => {
  if (isSavingAssign.value) return;
  isSavingAssign.value = true;
  try {
    const clean = Object.fromEntries(
      Object.entries(assignDraft.value).filter(([, v]) => v)
    );
    await CrmAPI.updatePanelAssignments(clean);
    await store.dispatch('crm/fetchSettings');
    showAssignModal.value = false;
  } finally {
    isSavingAssign.value = false;
  }
};
// escolha manual NESTE aparelho manda; sem ela, o painel PRINCIPAL da
// conta (settings.main_panel) assume quando as configurações chegarem
const storedPanel = localStorage.getItem('cevico_meu_painel');
const selectedPanel = ref(storedPanel || 'agendamento');
watch(assignedPanel, key => {
  if (
    key &&
    selectedPanel.value !== key &&
    allPanels.value.some(p => p.key === key)
  ) {
    selectedPanel.value = key;
    fetchData();
  }
});
const selectedDoctor = ref(
  localStorage.getItem('cevico_meu_painel_medico') || ''
);
const currentPanel = computed(
  () =>
    allPanels.value.find(p => p.key === selectedPanel.value) || BASE_PANELS[0]
);
// chave-BASE do painel escolhido: a variante por pessoa herda tudo do base
// (cards, metas, cores semânticas, blocos) — só o layout é dela
const panelBase = computed(
  () =>
    currentPanel.value.base ||
    (currentPanel.value.custom ? 'custom' : selectedPanel.value)
);

// settings chegaram: (1) aplica o painel principal UMA vez — só se a
// pessoa nunca escolheu manualmente; (2) painel custom excluído cai
// para o padrão de fábrica
let mainPanelApplied = false;
watch(crmSettings, settings => {
  if (!settings || !Object.keys(settings).length) return;
  if (!mainPanelApplied) {
    mainPanelApplied = true;
    const main = settings.main_panel;
    if (
      !storedPanel &&
      !assignedPanel.value &&
      main &&
      main !== selectedPanel.value &&
      allPanels.value.some(p => p.key === main)
    ) {
      selectedPanel.value = main;
      fetchData();
    }
  }
  if (
    (selectedPanel.value.startsWith('custom:') ||
      selectedPanel.value.startsWith('variant:')) &&
    !allPanels.value.some(p => p.key === selectedPanel.value)
  ) {
    selectedPanel.value = 'agendamento';
    fetchData();
  }
});

// ⚡ item 237: o cesto vai em PARALELO com o home (antes esperava o home
// voltar) e uma resposta atrasada de "este ano" não atropela o período que a
// pessoa escolheu depois (contador de sequência)
let homeSeq = 0;
const fetchData = async () => {
  const seq = ++homeSeq;
  fetchKpiBag();
  try {
    const { preset, from, to } = period.value;
    const { data: payload } = await CrmAPI.getHome({
      preset,
      panel: selectedPanel.value,
      doctor:
        panelBase.value === 'medico'
          ? selectedDoctor.value || undefined
          : undefined,
      // só o Personalizado manda De/Até; nos presets o backend resolve
      ...(preset === 'custom' ? { from, to } : {}),
    });
    if (seq !== homeSeq) return;
    data.value = payload;
  } catch {
    if (seq !== homeSeq) return;
    data.value = data.value || {};
  } finally {
    if (seq === homeSeq) isLoading.value = false;
  }
};

// cesto de indicadores (item 141): série + período anterior — alimenta os
// gráficos dos popups e os cards do "+"; carrega em paralelo, sem travar
const kpiBag = ref(null);
let kpiSeq = 0;
const fetchKpiBag = async () => {
  const seq = ++kpiSeq;
  try {
    const { preset, from, to } = period.value;
    const { data: bag } = await CrmAPI.getKpiBag({
      preset,
      ...(preset === 'custom' ? { from, to } : {}),
    });
    if (seq !== kpiSeq) return;
    kpiBag.value = bag;
  } catch {
    kpiBag.value = kpiBag.value || null;
  }
};

// régua nova: qualquer mudança (preset ou De/Até) recarrega o painel
watch(period, fetchData);

const setPanel = key => {
  selectedPanel.value = key;
  localStorage.setItem('cevico_meu_painel', key); // cada pessoa fica no seu painel
  fetchData();
};

const setDoctor = name => {
  selectedDoctor.value = name;
  localStorage.setItem('cevico_meu_painel_medico', name);
  fetchData();
};

// indicadores de cada painel (mesmo formato de tiles, cores próprias)
const pd = computed(() => data.value?.panel_data || {});
const rawPanelTiles = computed(() => {
  // painel do Construtor tem grade própria (CustomPanelGrid) — sem tiles fixas
  if (currentPanel.value.custom) return [];
  const d = pd.value;
  if (panelBase.value === 'conducao') {
    return [
      {
        label: 'Consultas no período',
        icon: 'i-lucide-calendar-days',
        value: d.consultations ?? 0,
        gk: 'consultations',
        chartKey: 'appointments_due',
        sub: 'agenda das unidades',
        units: d.by_unit,
        details: [
          { label: 'Compareceram', value: `${d.attended ?? 0}` },
          { label: 'Faltaram', value: `${d.missed ?? 0}` },
          { label: 'Comparecimento', value: `${d.show_rate ?? 0}%` },
        ],
        about:
          'Consultas marcadas na Agenda com data dentro do período (canceladas ficam fora). O gráfico mostra quantas caíram em cada dia/semana/mês.',
      },
      {
        label: 'Compareceram',
        icon: 'i-lucide-user-check',
        value: d.attended ?? 0,
        gk: 'attended',
        chartKey: 'appointments_attended',
        sub: 'conferência do dia (Agenda)',
        details: [
          { label: 'Faltaram', value: `${d.missed ?? 0}` },
          { label: 'Taxa de comparecimento', value: `${d.show_rate ?? 0}%` },
        ],
        about:
          'Marcadas como "Compareceu" na conferência do dia da Agenda — a base da taxa de comparecimento e do funil de indicações.',
      },
      {
        label: 'Comparecimento',
        icon: 'i-lucide-percent',
        value: `${d.show_rate ?? 0}%`,
        gk: 'show_rate',
        pct: true,
        sub: `${d.missed ?? 0} falta(s) no período`,
        units: d.by_unit,
        components: ['appointments_attended', 'appointments_missed'],
        compare: [
          { label: 'compareceram', value: d.attended ?? 0 },
          { label: 'faltaram', value: d.missed ?? 0 },
        ],
        details: [
          {
            label: 'Compareceram ÷ (compareceram + faltaram)',
            value: `${d.attended ?? 0} ÷ ${(d.attended ?? 0) + (d.missed ?? 0)} = ${d.show_rate ?? 0}%`,
          },
        ],
        about:
          'Quem confirmou consulta e veio. Referência de clínica boa: acima de 80%. É o indicador de quem cuida da confirmação (lembrete, reconfirmação, remarcação).',
      },
      {
        label: 'Indicações de cirurgia',
        icon: 'i-lucide-stethoscope',
        value: d.indications ?? 0,
        gk: 'indications',
        chartKey: 'indications',
        sub: 'saíram da consulta indicados',
        details: [
          {
            label: 'Indicados ÷ compareceram',
            value: `${d.indications ?? 0} de ${d.attended ?? 0}`,
          },
        ],
        about:
          'Consultas do período em que o médico registrou indicação de cirurgia (botão 🎯 na Agenda ou conduta no Espaço do Paciente). Começa aqui o funil de fechamento.',
      },
    ];
  }
  if (panelBase.value === 'cirurgia') {
    return [
      {
        label: 'Indicações de cirurgia',
        icon: 'i-lucide-stethoscope',
        value: d.indications ?? 0,
        gk: 'indications',
        chartKey: 'indications',
        sub: 'pacientes indicados no período',
        details: [
          {
            label: 'Viraram cirurgia agendada',
            value: `${d.surgeries_booked ?? 0} · ${d.closing_rate ?? 0}%`,
          },
        ],
        about:
          'Pacientes que saíram da consulta com indicação de cirurgia no período — é a matéria-prima do fechamento.',
      },
      {
        label: 'Cirurgias agendadas',
        icon: 'i-lucide-calendar-plus',
        value: d.surgeries_booked ?? 0,
        gk: 'surgeries_booked',
        chartKey: 'surgeries_booked',
        sub: 'fechadas no período',
        details: [
          { label: 'Realizadas', value: `${d.surgeries_done ?? 0}` },
          { label: 'Não vieram', value: `${d.surgeries_missed ?? 0}` },
        ],
        about:
          'Cirurgias registradas na Agenda de Cirurgias no período (o fechamento de fato). O gráfico mostra o ritmo de fechamento ao longo do período.',
      },
      {
        label: 'Taxa de fechamento',
        icon: 'i-lucide-percent',
        value: `${d.closing_rate ?? 0}%`,
        gk: 'closing_rate',
        pct: true,
        sub: 'agendadas ÷ indicações',
        components: ['indications', 'surgeries_booked'],
        compare: [
          { label: 'indicações', value: d.indications ?? 0 },
          { label: 'agendadas', value: d.surgeries_booked ?? 0 },
          { label: 'realizadas', value: d.surgeries_done ?? 0 },
        ],
        details: [
          {
            label: 'Agendadas ÷ indicações',
            value: `${d.surgeries_booked ?? 0} ÷ ${d.indications ?? 0} = ${d.closing_rate ?? 0}%`,
          },
        ],
        about:
          'De cada 100 pacientes indicados, quantos fecharam cirurgia. É o indicador do trabalho de fechamento (orçamento ancorado, quebra de objeção, ligação em 48h).',
      },
      {
        label: 'Cirurgias realizadas',
        icon: 'i-lucide-heart-pulse',
        value: d.surgeries_done ?? 0,
        gk: 'surgeries_done',
        chartKey: 'surgeries_done',
        sub: `${d.surgeries_missed ?? 0} não vieram`,
        compare: [
          { label: 'realizadas', value: d.surgeries_done ?? 0 },
          { label: 'não vieram', value: d.surgeries_missed ?? 0 },
        ],
        about:
          'Cirurgias marcadas como realizadas na Agenda de Cirurgias. "Não vieram" = agendou e não apareceu; "veio e não fez" entra separado no Dashboard da Agenda.',
      },
    ];
  }
  if (panelBase.value === 'medico') {
    const docNote =
      'O número é do médico escolhido; o gráfico mostra a clínica inteira no período (a série por médico fica no Dashboard dos Médicos).';
    return [
      {
        label: 'Consultas no período',
        icon: 'i-lucide-calendar-days',
        value: d.consultations ?? 0,
        gk: 'consultations',
        chartKey: 'appointments_due',
        sub: `${d.missed ?? 0} falta(s) · ${d.show_rate ?? 0}% comparecimento`,
        details: [
          { label: 'Faltas', value: `${d.missed ?? 0}` },
          { label: 'Comparecimento', value: `${d.show_rate ?? 0}%` },
        ],
        about: `Consultas deste médico com data no período. ${docNote}`,
      },
      {
        label: 'Com indicação de cirurgia',
        icon: 'i-lucide-stethoscope',
        value: d.indications ?? 0,
        gk: 'indications',
        chartKey: 'indications',
        sub: `${d.indication_rate ?? 0}% de quem compareceu`,
        compare: [
          { label: 'com indicação', value: d.indications ?? 0 },
          { label: 'sem indicação', value: d.no_indication ?? 0 },
        ],
        about: `Consultas em que o médico indicou cirurgia. ${docNote}`,
      },
      {
        label: 'Sem indicação',
        icon: 'i-lucide-user-minus',
        value: d.no_indication ?? 0,
        sub: `${d.no_indication_rate ?? 0}% de quem compareceu`,
        compare: [
          { label: 'com indicação', value: d.indications ?? 0 },
          { label: 'sem indicação', value: d.no_indication ?? 0 },
        ],
        about:
          'Consultas que não resultaram em indicação — não é perda: vira plano de cuidado, retorno e indicação futura (catarata inicial hoje é cirurgia daqui a um ano).',
      },
      {
        label: 'Conversão em cirurgia',
        icon: 'i-lucide-percent',
        value: `${d.conversion_rate ?? 0}%`,
        gk: 'conversion_rate',
        pct: true,
        sub: `${d.conversions ?? 0} viraram cirurgia · NPS ${d.nps_avg ?? '—'}`,
        compare: [
          { label: 'indicados', value: d.indications ?? 0 },
          { label: 'viraram cirurgia', value: d.conversions ?? 0 },
        ],
        details: [
          {
            label: 'NPS médio dos pacientes deste médico',
            value: `${d.nps_avg ?? '—'}`,
          },
        ],
        about:
          'Dos pacientes que este médico atendeu no período, quantos chegaram à cirurgia (pelo telefone do contato no CRM).',
      },
    ];
  }
  if (panelBase.value === 'gestor') {
    const inboxesG = d.leads_by_inbox || [];
    return [
      {
        label: 'Novos contatos (leads)',
        icon: 'i-lucide-user-plus',
        value: d.new_leads ?? 0,
        gk: 'new_leads',
        chartKey: 'new_leads',
        sub: leadsInboxSub.value,
        compareInboxes: inboxesG.map(i => ({
          label: shortInboxName(i.name),
          value: i.count,
        })),
        details: inboxesG.map(i => ({
          label: i.name,
          value: `${i.count} lead(s) · ${i.booked} agendaram · ${i.rate}%`,
        })),
        about:
          'Contatos novos do período pelas caixas de captação. A conversão por caixa mostra qual porta de entrada traz lead que decide.',
      },
      {
        label: 'Taxa de agendamento',
        icon: 'i-lucide-percent',
        value: `${d.booking_conversion ?? 0}%`,
        gk: 'booking_conversion',
        pct: true,
        sub: `${d.appointments_created ?? 0} dos ${d.new_leads ?? 0} leads do período`,
        components: ['new_leads', 'appointments_created'],
        compare: [
          { label: 'leads', value: d.new_leads ?? 0 },
          {
            label: 'entraram em Agendamento',
            value: d.appointments_created ?? 0,
          },
        ],
        about:
          'Taxa oficial (item 233): pacientes que MUDARAM DE COLUNA para "Agendamento de Consulta" no CRM no período ÷ leads do período. Só a mudança de coluna conta — exame, pós-operatório, teleconsulta e Oftalmofácil ficam fora.',
      },
      {
        label: 'Comparecimento',
        icon: 'i-lucide-user-check',
        value: `${d.show_rate ?? 0}%`,
        gk: 'show_rate',
        pct: true,
        chartKey: 'appointments_attended',
        sub: `${d.indications ?? 0} indicação(ões) de cirurgia`,
        units: d.by_unit,
        details: [
          {
            label: 'Indicações de cirurgia no período',
            value: `${d.indications ?? 0}`,
          },
        ],
        about:
          'Quem confirmou consulta e veio (conferência do dia). O gráfico mostra as presenças ao longo do período; referência boa: acima de 80%.',
      },
      {
        label: 'Fechamento de cirurgias',
        icon: 'i-lucide-heart-pulse',
        value: `${d.closing_rate ?? 0}%`,
        gk: 'closing_rate',
        pct: true,
        chartKey: 'surgeries_done',
        sub: `${d.surgeries_booked ?? 0} agendada(s) · ${d.surgeries_done ?? 0} realizada(s)`,
        components: ['indications', 'surgeries_booked'],
        compare: [
          { label: 'indicações', value: d.indications ?? 0 },
          { label: 'agendadas', value: d.surgeries_booked ?? 0 },
          { label: 'realizadas', value: d.surgeries_done ?? 0 },
        ],
        about:
          'Agendadas ÷ indicações: a eficiência do fechamento. O gráfico mostra as cirurgias realizadas ao longo do período.',
      },
    ];
  }
  // agendamento (padrão) — macro no card, detalhe no popup (item 140)
  const inboxes = d.leads_by_inbox || [];
  const dt = d.decision_time;
  const ch = d.booking_cohorts || {};
  return [
    {
      label: 'Novos contatos (leads)',
      icon: 'i-lucide-user-plus',
      value: d.new_leads ?? 0,
      gk: 'new_leads',
      chartKey: 'new_leads',
      sub: leadsInboxSub.value,
      details: inboxes.map(i => ({
        label: `${i.name}`,
        value: `${i.count} lead(s) · ${i.booked} agendaram · ${i.rate}%`,
      })),
      compareInboxes: inboxes.map(i => ({
        label: shortInboxName(i.name),
        value: i.count,
      })),
      about:
        'Contatos novos do período que chegaram pelas caixas de captação (Google, Instagram…). A conversão de cada caixa é: dos que chegaram por ela, quantos já avançaram até "Agendamento de Consulta" no CRM.',
    },
    {
      // 🌟 % de agendamento em EVIDÊNCIA (item 143): o indicador da linha
      // compacta da Saúde da Agenda promovido pra fileira principal
      label: '% de agendamento',
      icon: 'i-lucide-percent',
      id: 'booking_rate_30',
      value:
        bookingRate30.value === null
          ? '—'
          : `${String(bookingRate30.value).replace('.', ',')}%`,
      judged: true,
      chip: booking30Chip.value,
      grad: booking30Chip.value.grad,
      sub: `${data.value?.appointments_30d ?? 0} entraram em Agendamento ÷ ${data.value?.new_contacts_30d ?? 0} leads · 30 dias`,
      compare: [
        { label: 'leads (30d)', value: data.value?.new_contacts_30d ?? 0 },
        { label: 'entraram em Agendamento (30d)', value: data.value?.appointments_30d ?? 0 },
      ],
      details: [
        {
          label: 'Entradas em Agendamento de Consulta ÷ leads',
          value: `${data.value?.appointments_30d ?? 0} ÷ ${data.value?.new_contacts_30d ?? 0} = ${bookingRate30.value ?? '—'}%`,
        },
        { label: 'Referência', value: '15% muito bom · 10% bom · 5% fraco' },
      ],
      about:
        'Dos contatos que chegaram nos últimos 30 dias pelas caixas de captação, quantos mudaram de coluna para "Agendamento de Consulta" no CRM (taxa oficial: só a mudança de coluna conta — exame, pós-op, tele e Oftalmofácil ficam fora). É fixo em 30 dias (não segue a régua) pra taxa ser sempre madura e comparável com a referência.',
    },
    {
      label: 'Marcadas na Agenda',
      icon: 'i-lucide-calendar-check',
      value: d.appointments_booked ?? 0,
      gk: 'appointments_booked',
      chartKey: 'appointments_booked',
      sub: 'consultas novas no período (sem exame, tele, cancelada ou Oftalmofácil)',
      details: [
        {
          label: '⚡ Chegaram e agendaram no mesmo período',
          value: `${d.appointments_same_day ?? 0}`,
        },
        ...(dt
          ? [
              {
                label: '🤔 Tempo médio de decisão (chegar → agendar)',
                value: `${String(dt.avg_days).replace('.', ',')} dia(s) · ${dt.count} consulta(s)`,
              },
              { label: 'Decidiram no mesmo dia', value: `${dt.same_day}` },
              { label: 'Em 1 dia', value: `${dt.next_day}` },
              { label: 'Em 2 a 7 dias', value: `${dt.within_week}` },
              { label: 'Demoraram 8 dias ou mais', value: `${dt.later}` },
            ]
          : []),
      ],
      about:
        'Consultas registradas na Agenda no período (consulta marcada para o passado = preenchimento de histórico, fica fora). O tempo de decisão mede quantos dias o paciente levou entre chegar e marcar — mostra se o funil converte por impulso ou por insistência.',
    },
    {
      label: 'Agendamentos hoje',
      icon: 'i-lucide-calendar-plus',
      value: d.booked_today ?? 0,
      chip: bookingDayVerdict.value,
      judged: true,
      grad: bookingDayVerdict.value.grad,
      pct: true,
      compare: [
        {
          label: `hoje (${ch.today?.booked ?? 0}/${ch.today?.leads ?? 0})`,
          value: ch.today?.rate ?? 0,
        },
        {
          label: `ontem (${ch.yesterday?.booked ?? 0}/${ch.yesterday?.leads ?? 0})`,
          value: ch.yesterday?.rate ?? 0,
        },
        { label: 'período', value: d.booking_conversion ?? 0 },
      ],
      sub: `hoje ${ch.today?.rate ?? 0}% · ontem ${ch.yesterday?.rate ?? 0}% agendaram`,
      details: [
        {
          label: 'Chegaram HOJE e já agendaram',
          value: `${ch.today?.booked ?? 0} de ${ch.today?.leads ?? 0} · ${ch.today?.rate ?? 0}%`,
        },
        {
          label: 'Chegaram ONTEM e agendaram',
          value: `${ch.yesterday?.booked ?? 0} de ${ch.yesterday?.leads ?? 0} · ${ch.yesterday?.rate ?? 0}%`,
        },
        {
          label: 'Taxa do período (leads do período → Agendamento)',
          value: `${d.appointments_created ?? 0} de ${d.new_leads ?? 0} · ${d.booking_conversion ?? 0}%`,
        },
      ],
      about:
        'O número grande é quantas consultas foram registradas HOJE, julgado contra a fatia diária da meta do mês (Painel de Metas ÷ dias do mês). As taxas abaixo dizem quem decidiu: a de hoje ainda amadurece; a de ontem é a taxa justa pra avaliar o atendimento.',
    },
    {
      label: 'Cirurgias fechadas',
      icon: 'i-lucide-heart-pulse',
      value: d.surgeries_closed ?? 0,
      gk: 'surgeries_closed',
      chartKey: 'auto',
      chartMatch: /cirurgia agendada/i,
      sub: 'coluna Cirurgia Agendada (CRM)',
      about:
        'Leads do período que chegaram à coluna "Cirurgia Agendada" no CRM — o fechamento que nasceu dos contatos deste período.',
    },
  ];
});

// ── CARDS DO "+" (item 141): indicador pronto ou FÓRMULA sobre o cesto ──
const bagMetrics = computed(() => kpiBag.value?.metrics || {});
const bagTotals = computed(() =>
  Object.fromEntries(
    Object.entries(bagMetrics.value).map(([k, m]) => [k, m.value])
  )
);
const bagPrev = computed(() =>
  Object.fromEntries(
    Object.entries(bagMetrics.value).map(([k, m]) => [k, m.prev])
  )
);
const bagAt = i =>
  Object.fromEntries(
    Object.entries(bagMetrics.value).map(([k, m]) => [k, m.series?.[i] ?? 0])
  );
// variação vs período anterior (texto curto pro card)
const deltaLine = (value, prev, format, bag = null) => {
  if (
    value === null ||
    value === undefined ||
    prev === null ||
    prev === undefined
  )
    return '';
  if (!prev) return `anterior: ${formatKpi(prev, format)}`;
  const pct = ((value - prev) / Math.abs(prev)) * 100;
  const arrow = pct >= 0 ? '▲' : '▼';
  return `${arrow} ${Math.abs(pct).toFixed(0)}% vs ${(bag || kpiBag.value)?.previous_label || 'período anterior'} (${formatKpi(prev, format)})`;
};
const customKpiDefs = computed(() =>
  (crmSettings.value?.custom_kpis || []).filter(
    k => k.panel === 'all' || k.panel === panelBase.value
  )
);
const customTiles = computed(() =>
  customKpiDefs.value.map(def => {
    const value = evaluateFormula(def.expr, bagTotals.value);
    const prev = evaluateFormula(def.expr, bagPrev.value);
    const series = (kpiBag.value?.points || []).map(
      (_, i) => evaluateFormula(def.expr, bagAt(i)) ?? 0
    );
    const isReady = Object.keys(bagMetrics.value).includes(def.expr.trim());
    return {
      label: def.label,
      icon: def.icon || 'i-lucide-sparkles',
      value: formatKpi(value, def.format),
      rawValue: value,
      prevValue: prev,
      format: def.format,
      kpi: true,
      def,
      grad: def.color || null,
      // a variação virou a pílula ▲/▼ do card (varredura 12/09); aqui fica o valor anterior
      sub:
        prev === null || prev === undefined
          ? ''
          : `anterior: ${formatKpi(prev, def.format)} · ${kpiBag.value?.previous_label || 'período anterior'}`,
      series,
      details: [
        { label: 'Neste período', value: formatKpi(value, def.format) },
        {
          label: `Período anterior (${kpiBag.value?.previous_label || '—'})`,
          value: formatKpi(prev, def.format),
        },
        // fórmula traduzida pros nomes do cesto — ninguém precisa ler
        // "appointments_booked / new_leads" (item 152)
        {
          label: isReady ? 'Indicador' : 'Fórmula',
          value: isReady
            ? bagMetrics.value[def.expr.trim()]?.label
            : prettyFormula(def.expr),
        },
      ],
      about:
        def.note ||
        (isReady
          ? 'Indicador pronto do cesto do sistema, no período da régua.'
          : 'Calculado pela fórmula acima sobre os indicadores do período; a série do gráfico aplica a fórmula balde a balde.'),
    };
  })
);

const chartFormat = tile => v =>
  formatKpi(v, tile?.format || (tile?.pct ? 'percent' : 'number'));

// ── varredura 12/09: cada card conta a HISTÓRIA do número ──
// o indicador do cesto que alimenta o gráfico deste card (chartKey)
const bagMetricFor = tile => {
  if (!tile?.chartKey || !kpiBag.value?.metrics) return null;
  const key =
    tile.chartKey === 'auto'
      ? bagMetricByLabelOf(kpiBag.value, tile.chartMatch)
      : tile.chartKey;
  return key ? bagMetrics.value[key] || null : null;
};
// ▲/▼ vs período anterior: card de fórmula usa o próprio valor; card fixo
// usa o indicador do cesto (só contagens — taxa não tem série comparável).
// No painel Médicos o número é do médico e a série é da clínica: sem tendência.
const tileTrend = tile => {
  if (panelBase.value === 'medico') return null;
  let value = null;
  let prev = null;
  let format = tile.format || 'number';
  if (tile.def) {
    value = tile.rawValue;
    prev = tile.prevValue;
  } else if (tile.chartKey && !tile.pct && !tile.compare) {
    const m = bagMetricFor(tile);
    if (!m) return null;
    value = m.value;
    prev = m.prev;
    format = m.unit === 'brl' ? 'currency' : 'number';
  } else {
    return null;
  }
  if (value === null || value === undefined || !prev) return null;
  const pct = ((value - prev) / Math.abs(prev)) * 100;
  const up = pct >= 0;
  return {
    up,
    text: `${up ? '▲' : '▼'} ${Math.abs(pct).toFixed(0)}%`,
    title: `vs ${kpiBag.value?.previous_label || 'período anterior'}: ${formatKpi(prev, format)}`,
  };
};
// sparkline do card (série do período): linha + área, em coordenadas 100×24
const tileSpark = tile => {
  if (panelBase.value === 'medico') return null;
  const series = tile.def ? tile.series : bagMetricFor(tile)?.series;
  if (!series || series.length < 3 || !series.some(v => Number(v) > 0))
    return null;
  const n = series.length;
  const max = Math.max(1, ...series.map(v => Number(v) || 0));
  const pts = series.map((v, i) => [
    (i / (n - 1)) * 100,
    22 - ((Number(v) || 0) / max) * 20,
  ]);
  const line = pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ');
  return { line, area: `0,24 ${line} 100,24` };
};
// primeira cor de um gradiente CSS (o gráfico do popup na cor do card)
const hexFromGrad = grad =>
  (String(grad || '').match(/#[0-9a-f]{6}/gi) || [])[0] || null;

// ── 📊 GRÁFICO DO POPUP v2 (item 144): mini-régua própria, período anterior
// sobreposto balde a balde, linha de meta, ações da empresa 📌 e a
// DECOMPOSIÇÃO das taxas (as séries que formam a conta) ──
// leitores genéricos sobre QUALQUER cesto (o da página ou o do recorte)
const bagTotalsOf = bag =>
  Object.fromEntries(
    Object.entries(bag?.metrics || {}).map(([k, m]) => [k, m.value])
  );
const bagPrevTotalsOf = bag =>
  Object.fromEntries(
    Object.entries(bag?.metrics || {}).map(([k, m]) => [k, m.prev])
  );
const bagAtOf = (bag, i) =>
  Object.fromEntries(
    Object.entries(bag?.metrics || {}).map(([k, m]) => [k, m.series?.[i] ?? 0])
  );
const bagPrevAtOf = (bag, i) =>
  Object.fromEntries(
    Object.entries(bag?.metrics || {}).map(([k, m]) => [
      k,
      m.prev_series?.[i] ?? 0,
    ])
  );
const bagMetricByLabelOf = (bag, re) =>
  Object.keys(bag?.metrics || {}).find(k =>
    re.test(bag.metrics[k].label || '')
  );

// recorte escolhido DENTRO do popup (null = segue a régua da página)
const kpiModalPreset = ref(null);
const kpiModalGranularity = ref(null);
const kpiModalBag = ref(null);
const isLoadingModalBag = ref(false);
const fetchKpiModalBag = async () => {
  if (!kpiModalPreset.value && !kpiModalGranularity.value) {
    kpiModalBag.value = null;
    return;
  }
  isLoadingModalBag.value = true;
  try {
    const { preset, from, to } = period.value;
    const params = kpiModalPreset.value
      ? { preset: kpiModalPreset.value }
      : { preset, ...(preset === 'custom' ? { from, to } : {}) };
    if (kpiModalGranularity.value)
      params.granularity = kpiModalGranularity.value;
    const { data: bag } = await CrmAPI.getKpiBag(params);
    kpiModalBag.value = bag;
  } catch {
    kpiModalBag.value = null;
  } finally {
    isLoadingModalBag.value = false;
  }
};
const setModalPreset = p => {
  kpiModalPreset.value = p;
  fetchKpiModalBag();
};
const setModalGranularity = g => {
  kpiModalGranularity.value = g;
  fetchKpiModalBag();
};
const MODAL_PRESETS = [
  [null, 'Régua de cima'],
  ['last7', '7 dias'],
  ['month', 'Este mês'],
  ['year', 'Este ano'],
];
const MODAL_GRAINS = [
  [null, 'Auto'],
  ['day', 'Dia'],
  ['week', 'Semana'],
  ['month', 'Mês'],
];
// o cesto que vale pro popup: o do recorte escolhido, senão o da página
const modalBag = computed(() => kpiModalBag.value || kpiBag.value);

// meta do balde: fatia da meta MENSAL oficial pela granularidade do cesto
const goalPerBucket = tile => {
  if (!tile?.gk || tile.pct) return null;
  const target = officialTargetFor(tile.gk);
  if (!target) return null;
  const now = new Date();
  const daysInMonth = new Date(
    now.getFullYear(),
    now.getMonth() + 1,
    0
  ).getDate();
  const daily = target / daysInMonth;
  const g = modalBag.value?.granularity;
  if (g === 'week') return Math.round(daily * 7 * 10) / 10;
  if (g === 'month') return target;
  return Math.round(daily * 10) / 10;
};
// 📌 ações da empresa (PRO MAX) que caem nos baldes do gráfico
const modalMarkers = computed(() => {
  const bag = modalBag.value;
  const actions = crmSettings.value?.company_actions || [];
  if (!bag?.points?.length || !actions.length) return [];
  const keys = bag.points.map(p => p.key);
  const idxFor = date => {
    if (bag.granularity === 'month')
      return keys.findIndex(k => k.slice(0, 7) === date.slice(0, 7));
    if (bag.granularity === 'week') {
      for (let i = keys.length - 1; i >= 0; i -= 1)
        if (keys[i] <= date) return i;
      return -1;
    }
    return keys.indexOf(date);
  };
  return actions
    .map(a => ({ index: idxFor(a.date), title: a.title }))
    .filter(m => m.index >= 0);
});
// o gráfico do popup, calculado sobre o cesto ativo
const modalChart = computed(() => {
  const tile = kpiModal.value;
  const bag = modalBag.value;
  if (!tile) return null;
  if (tile.compare?.length && !tile.def && !tile.chartKey) {
    return {
      values: tile.compare.map(c => c.value),
      labels: tile.compare.map(c => c.label),
      compare: true,
    };
  }
  if (!bag) return null;
  const labels = (bag.points || []).map(p => p.label);
  if (tile.def) {
    const values = (bag.points || []).map(
      (_, i) => evaluateFormula(tile.def.expr, bagAtOf(bag, i)) ?? 0
    );
    const prevValues = (bag.prev_points || []).map(
      (_, i) => evaluateFormula(tile.def.expr, bagPrevAtOf(bag, i)) ?? 0
    );
    return {
      values,
      labels,
      prevValues: prevValues.length ? prevValues : null,
      total: evaluateFormula(tile.def.expr, bagTotalsOf(bag)),
      prev: evaluateFormula(tile.def.expr, bagPrevTotalsOf(bag)),
      goal: null,
      isFormula: true,
    };
  }
  const key =
    tile.chartKey === 'auto'
      ? bagMetricByLabelOf(bag, tile.chartMatch)
      : tile.chartKey;
  const m = key && bag.metrics?.[key];
  if (!m) {
    if (tile.compare?.length)
      return {
        values: tile.compare.map(c => c.value),
        labels: tile.compare.map(c => c.label),
        compare: true,
      };
    return null;
  }
  return {
    values: m.series || [],
    labels,
    prevValues: m.prev_series?.length ? m.prev_series : null,
    prev: m.prev,
    unit: m.unit,
    total: m.value,
    label: m.label,
    goal: goalPerBucket(tile),
  };
});
// decomposição: as séries que FORMAM a taxa (numerador/denominador) —
// cards de fórmula usam as variáveis da conta; fixos usam components[]
const modalComponents = computed(() => {
  const tile = kpiModal.value;
  const bag = modalBag.value;
  if (!tile || !bag?.metrics) return [];
  const keys = tile.def ? variablesIn(tile.def.expr) : tile.components || [];
  return keys
    .slice(0, 3)
    .filter(k => bag.metrics[k])
    .map(k => {
      const m = bag.metrics[k];
      return {
        key: k,
        label: m.label,
        values: m.series || [],
        prevValues: m.prev_series?.length ? m.prev_series : null,
        total: m.value,
        unit: m.unit,
      };
    });
});
const componentFormat = comp => v =>
  formatKpi(v, comp.unit === 'brl' ? 'currency' : 'number');
// rótulo curto do recorte ativo (cabeçalho do gráfico)
const modalRangeLabel = computed(() => {
  const found = MODAL_PRESETS.find(p => p[0] === kpiModalPreset.value);
  return found && found[0] ? found[1] : 'período da régua';
});

// ── varredura 12/09: tendência no cabeçalho, cor do gráfico e leitura em 1 frase ──
const modalDelta = computed(() => {
  const c = modalChart.value;
  if (!c || c.compare || c.prev === undefined || c.prev === null || !c.prev)
    return null;
  const total = c.total ?? 0;
  const pct = ((total - c.prev) / Math.abs(c.prev)) * 100;
  const fmt =
    kpiModal.value?.format ||
    (c.unit === 'brl'
      ? 'currency'
      : kpiModal.value?.pct
        ? 'percent'
        : 'number');
  return {
    up: pct >= 0,
    text: `${pct >= 0 ? '▲' : '▼'} ${Math.abs(pct).toFixed(0)}%`,
    sub: `vs ${modalBag.value?.previous_label || 'período anterior'} · ${formatKpi(c.prev, fmt)}`,
  };
});
const modalChartColor = computed(
  () =>
    (kpiModal.value && hexFromGrad(tileVisual(kpiModal.value).grad)) ||
    '#0F5FA6'
);
const BUCKET_WORD = {
  day: ['dia', 'dias'],
  week: ['semana', 'semanas'],
  month: ['mês', 'meses'],
};
const modalInsight = computed(() => {
  const c = modalChart.value;
  if (!c || c.compare || isLoadingModalBag.value) return '';
  const vals = (c.values || []).map(v => Number(v) || 0);
  if (!vals.length || !vals.some(v => v > 0)) return '';
  const fmt = chartFormat(kpiModal.value);
  const [one, many] =
    BUCKET_WORD[modalBag.value?.granularity] || BUCKET_WORD.day;
  const maxV = Math.max(...vals);
  const maxI = vals.indexOf(maxV);
  const avg =
    Math.round((vals.reduce((a, b) => a + b, 0) / vals.length) * 10) / 10;
  const parts = [
    `pico ${c.labels?.[maxI] ? `em ${c.labels[maxI]}` : ''}: ${fmt(maxV)}`.replace(
      'pico : ',
      'pico: '
    ),
    `média ${fmt(avg)} por ${one}`,
  ];
  if (!c.isFormula && c.total !== undefined && c.total !== null)
    parts.push(`total ${fmt(c.total)}`);
  // "sem movimento" só faz sentido pra contagem (taxa zerada não é ausência)
  const zeros = vals.filter(v => v === 0).length;
  if (!c.isFormula && zeros && vals.length > 3)
    parts.push(`${zeros} ${zeros > 1 ? many : one} sem movimento`);
  return parts.join(' · ');
});

// ── CONSTRUTOR DO "+" (admin): indicador pronto ou fórmula, cor, painel ──
const kpiBuilder = ref(null); // def em edição (novo ou existente)
const kpiBuilderMode = ref('ready'); // 'ready' | 'formula'
const isSavingKpi = ref(false);
const kpiHexColor = ref('');
const newKpiDef = () => ({
  id: '',
  label: '',
  expr: '',
  format: 'number',
  color: '',
  icon: 'i-lucide-sparkles',
  panel: currentPanel.value.custom ? 'all' : panelBase.value,
  note: '',
});
const openKpiBuilder = def => {
  kpiBuilder.value = def ? { ...def } : newKpiDef();
  kpiBuilderMode.value =
    def && !Object.keys(bagMetrics.value).includes(def.expr?.trim())
      ? 'formula'
      : 'ready';
  kpiHexColor.value = '';
  kpiModal.value = null;
};
const kpiCatalog = computed(() =>
  Object.entries(bagMetrics.value).map(([key, m]) => ({
    key,
    label: m.label,
    value: formatKpi(m.value, m.unit === 'brl' ? 'currency' : 'number'),
  }))
);
// ── 📚 INDICADORES JÁ FORMULADOS (item 143): taxas e contas importantes
// prontas pra virar card com 1 clique, separadas por categoria ──
const READY_FORMULAS = [
  {
    cat: '🎯 Taxas do funil',
    items: [
      {
        label: 'Taxa de agendamento',
        expr: 'appointments_created / new_leads * 100',
        format: 'percent',
        icon: 'i-lucide-percent',
        note: 'entradas em Agendamento de Consulta (mudança de coluna no CRM) ÷ leads · referência: 15% muito bom · 10% bom · 5% fraco',
      },
      {
        label: 'Comparecimento',
        expr: 'appointments_attended / (appointments_attended + appointments_missed) * 100',
        format: 'percent',
        icon: 'i-lucide-user-check',
        note: 'quem confirmou e veio · referência de clínica boa: acima de 80%',
      },
      {
        label: 'Taxa de indicação',
        expr: 'indications / appointments_attended * 100',
        format: 'percent',
        icon: 'i-lucide-stethoscope',
        note: 'de quem compareceu, quantos saíram da consulta indicados pra cirurgia',
      },
      {
        label: 'Fechamento de cirurgias',
        expr: 'surgeries_booked / indications * 100',
        format: 'percent',
        icon: 'i-lucide-heart-pulse',
        note: 'dos indicados, quantos fecharam cirurgia — o trabalho de fechamento',
      },
      {
        label: 'Lead → cirurgia',
        expr: 'surgeries_booked / new_leads * 100',
        format: 'percent',
        icon: 'i-lucide-trending-up',
        note: 'o funil inteiro numa taxa só: de cada 100 leads, quantos viram cirurgia',
      },
    ],
  },
  {
    cat: '💰 Financeiro',
    items: [
      {
        label: 'Ticket médio por cirurgia',
        expr: 'revenue / surgeries_done',
        format: 'currency',
        icon: 'i-lucide-badge-dollar-sign',
        note: 'faturamento fechado ÷ cirurgias realizadas no período',
      },
      {
        label: 'Faturamento por lead',
        expr: 'revenue / new_leads',
        format: 'currency',
        icon: 'i-lucide-coins',
        note: 'quanto cada contato que chega vale em faturamento — norteia quanto pagar por lead',
      },
      {
        label: 'Faturamento por consulta',
        expr: 'revenue / appointments_attended',
        format: 'currency',
        icon: 'i-lucide-wallet',
        note: 'faturamento fechado ÷ consultas com presença',
      },
    ],
  },
  {
    cat: '📅 Agenda',
    items: [
      {
        label: 'Faltas em consultas (%)',
        expr: 'appointments_missed / (appointments_attended + appointments_missed) * 100',
        format: 'percent',
        icon: 'i-lucide-user-minus',
        note: 'o inverso do comparecimento: acima de 20% é hora de reforçar a confirmação',
      },
      {
        label: 'Realização de cirurgias',
        expr: 'surgeries_done / surgeries_booked * 100',
        format: 'percent',
        icon: 'i-lucide-check-circle-2',
        note: 'das cirurgias agendadas, quantas aconteceram de fato',
      },
      {
        label: 'Cirurgias perdidas (%)',
        expr: 'surgeries_missed / (surgeries_done + surgeries_missed) * 100',
        format: 'percent',
        icon: 'i-lucide-alert-triangle',
        note: 'agendou e não veio — cada uma vale um resgate imediato',
      },
    ],
  },
  // 🏥 por unidade (pedido 02/09): cada casa com o próprio card — os
  // números-base Consultas/Presenças/Faltas de cada unidade também estão
  // na lista de indicadores prontos logo abaixo
  {
    cat: '🏥 Por unidade',
    items: [
      {
        label: 'Comparecimento · Av. Paulista',
        expr: 'appointments_attended_paulista / (appointments_attended_paulista + appointments_missed_paulista) * 100',
        format: 'percent',
        icon: 'i-lucide-building-2',
        note: 'só a casa da Paulista — coloque ao lado do Tatuapé e compare no mesmo olhar',
      },
      {
        label: 'Comparecimento · Tatuapé',
        expr: 'appointments_attended_tatuape / (appointments_attended_tatuape + appointments_missed_tatuape) * 100',
        format: 'percent',
        icon: 'i-lucide-building',
        note: 'só a casa do Tatuapé — coloque ao lado da Paulista e compare no mesmo olhar',
      },
    ],
  },
];
// valor ao vivo de cada fórmula pronta (mesmo cesto/período da régua)
const readyFormulaSections = computed(() =>
  READY_FORMULAS.map(sec => ({
    cat: sec.cat,
    items: sec.items.map(f => ({
      ...f,
      value: formatKpi(evaluateFormula(f.expr, bagTotals.value), f.format),
    })),
  }))
);
const applyReadyFormula = f => {
  kpiBuilder.value.expr = f.expr;
  kpiBuilder.value.format = f.format;
  kpiBuilder.value.icon = f.icon;
  if (!kpiBuilder.value.label) kpiBuilder.value.label = f.label;
  if (!kpiBuilder.value.note) kpiBuilder.value.note = f.note;
};
// números-base do cesto agrupados por categoria (item 143)
const KPI_CAT = key => {
  if (key.startsWith('stage_')) return '🧭 Funil (entrou na coluna)';
  if (key === 'revenue') return '💰 Financeiro';
  if (key.startsWith('surgeries_')) return '🔪 Cirurgias';
  if (key.startsWith('appointments_') || key === 'indications')
    return '📅 Consultas';
  return '👥 Chegada';
};
const kpiCatalogSections = computed(() => {
  const order = [
    '👥 Chegada',
    '📅 Consultas',
    '🔪 Cirurgias',
    '🧭 Funil (entrou na coluna)',
    '💰 Financeiro',
  ];
  const bySec = {};
  kpiCatalog.value.forEach(m => {
    const cat = KPI_CAT(m.key);
    (bySec[cat] ||= []).push(m);
  });
  return order
    .filter(cat => bySec[cat]?.length)
    .map(cat => ({ cat, items: bySec[cat] }));
});
const kpiPreview = computed(() => {
  if (!kpiBuilder.value) return { ok: false, text: '—' };
  const unknown = variablesIn(kpiBuilder.value.expr).filter(
    v => !(v in bagTotals.value)
  );
  if (unknown.length)
    return { ok: false, text: `não conheço: ${unknown.join(', ')}` };
  const v = evaluateFormula(kpiBuilder.value.expr, bagTotals.value);
  if (v === null)
    return {
      ok: false,
      text: kpiBuilder.value.expr
        ? 'fórmula inválida (ou divisão por zero)'
        : 'prévia aparece aqui',
    };
  const prev = evaluateFormula(kpiBuilder.value.expr, bagPrev.value);
  return {
    ok: true,
    text: formatKpi(v, kpiBuilder.value.format),
    delta: deltaLine(v, prev, kpiBuilder.value.format),
  };
});
const insertKpiVar = key => {
  const cur = kpiBuilder.value.expr || '';
  kpiBuilder.value.expr =
    cur && !/[\s(+\-*/]$/.test(cur) ? `${cur} ${key}` : `${cur}${key}`;
};
const kpiColorOptions = computed(() => [
  ...panelFamily.value.map((g, i) => ({
    key: `fam${i}`,
    grad: g,
    title: `família do painel · ${i + 1}`,
  })),
  ...ALL_THEMES.map(t => ({ key: t.key, grad: t.primary, title: t.label })),
  {
    key: 'ok',
    grad: 'linear-gradient(135deg, #065F46, #10B981)',
    title: 'verde',
  },
  {
    key: 'gold',
    grad: 'linear-gradient(135deg, #B8860B, #D4A017)',
    title: 'ouro',
  },
  {
    key: 'red',
    grad: 'linear-gradient(135deg, #991B1B, #EF4444)',
    title: 'vermelho',
  },
]);
const applyHexColor = () => {
  const hex = (kpiHexColor.value || '').trim();
  if (/^#[0-9a-fA-F]{6}$/.test(hex))
    kpiBuilder.value.color = `linear-gradient(135deg, ${hex}, ${hex}CC)`;
};
const saveKpiBuilder = async () => {
  const def = kpiBuilder.value;
  if (!def?.label?.trim() || !kpiPreview.value.ok) return;
  isSavingKpi.value = true;
  try {
    const list = [...(crmSettings.value?.custom_kpis || [])];
    const idx = def.id ? list.findIndex(k => k.id === def.id) : -1;
    if (idx >= 0) list[idx] = def;
    else list.push({ ...def, id: `k${Date.now().toString(36)}` });
    await CrmAPI.updateCustomKpis(list);
    await store.dispatch('crm/fetchSettings');
    kpiBuilder.value = null;
  } finally {
    isSavingKpi.value = false;
  }
};
const deleteKpi = async def => {
  const list = (crmSettings.value?.custom_kpis || []).filter(
    k => k.id !== def.id
  );
  isSavingKpi.value = true;
  try {
    await CrmAPI.updateCustomKpis(list);
    await store.dispatch('crm/fetchSettings');
    kpiBuilder.value = null;
    kpiModal.value = null;
  } finally {
    isSavingKpi.value = false;
  }
};

// família de cores do painel em cima dos tiles (item 140): cada card pega
// um degrau da família; o card JULGADO (chip de veredito) mantém a cor
// semântica; painéis do Construtor seguem sua paleta própria
// ── PALETA DO PAINEL (item 140): uma FAMÍLIA de cor por ambiente, em
// degraus (escuro → claro); a cor SEMÂNTICA (verde/âmbar/vermelho) fica
// reservada pro card que está sendo JULGADO — o olho vai direto nele.
// O admin pode trocar a família por um tema (Configurações → Painéis).
// os BLOCOS do Meu Painel (item 143): nome, ícone e a posição padrão de
// cada um — as paletas por bloco (abaixo) e o modo edição leem daqui
// rodada 161: barrinhas do modo edição com ícone lucide (sem emoji)
const BLOCK_LABELS = {
  whatsapp: 'Status do WhatsApp',
  briefing: 'Briefing do gestor',
  radar: 'Radar de Oportunidades',
  tarefas: 'Tarefas esperando você',
  mentor: 'Feedback da semana',
  indicadores: 'Indicadores do período',
  desempenho: 'Meu desempenho',
  agenda_dashboard: 'Dashboard da Agenda',
  saude_agenda: 'Saúde da Agenda',
  metas_strip: 'Metas · Rotinas · Ferramentas',
  atalhos: 'Acesso rápido',
  termometro: 'Termômetro do momento',
};
const BLOCK_ICONS = {
  whatsapp: 'i-lucide-phone',
  briefing: 'i-lucide-gauge',
  radar: 'i-lucide-radar',
  tarefas: 'i-lucide-list-checks',
  mentor: 'i-lucide-graduation-cap',
  indicadores: 'i-lucide-layout-grid',
  desempenho: 'i-lucide-target',
  agenda_dashboard: 'i-lucide-calendar-days',
  saude_agenda: 'i-lucide-activity',
  metas_strip: 'i-lucide-flag',
  atalhos: 'i-lucide-rocket',
  termometro: 'i-lucide-thermometer',
};
const TASKS_FIRST_PANELS = ['agendamento', 'conducao', 'cirurgia'];
const TOP_BLOCKS_DEFAULT = [
  'whatsapp',
  'briefing',
  'radar',
  'tarefas',
  'mentor',
];
const MAIN_BLOCKS_DEFAULT = [
  'indicadores',
  'desempenho',
  'agenda_dashboard',
  'saude_agenda',
  'metas_strip',
  'atalhos',
  'termometro',
];
// 🍎🍊 PALETAS (rodadas 162/163): as 7 cores dos iMac G3 (uma por dia da
// semana) + as 10 frutas da Apple + a salada de frutas. O motor mora no
// composable useCevicoPalette (compartilhado com os Relatórios): por painel,
// o admin escolhe o painel inteiro (cor do dia / fixa / salada) e cada bloco
// por cima; salvo em crm settings panel_palettes[painel].
// Tema legado de Configurações → Painéis (item 140) vira uma paleta: vale
// quando o admin ainda não escolheu nada aqui.
const themePalette = computed(() => {
  const themeKey = crmSettings.value?.panel_themes?.[panelBase.value];
  const theme = themeKey && ALL_THEMES.find(t => t.key === themeKey);
  if (!theme) return null;
  return {
    key: `tema:${theme.key}`,
    label: theme.label,
    emoji: theme.emoji || '',
    dot: hexFromGrad(theme.accent) || hexFromGrad(theme.pill) || '#152C61',
    hero: theme.primary,
    family: [theme.primary, theme.pill, theme.action, theme.accent],
  };
});
// 🌈 nota "Seu painel, as suas cores" — aparece UMA vez por PESSOA (22/09):
// a dispensa fica em ui_settings (servidor), então some em todo aparelho;
// o localStorage é só reforço para o caso de a gravação falhar.
const { uiSettings, updateUISettings } = useUISettings();
const DOPAMINE_NOTE_KEY = 'cevico_note_dopamine_colors_v1';
const dopamineDismissedLocally = () => {
  try {
    return !!localStorage.getItem(DOPAMINE_NOTE_KEY);
  } catch {
    return false;
  }
};
const showDopamineNote = computed(() => {
  const dismissed = uiSettings.value?.cevico_notes_dismissed || {};
  return !dismissed.dopamine_colors_v1 && !dopamineDismissedLocally();
});
const dismissDopamineNote = () => {
  try {
    localStorage.setItem(DOPAMINE_NOTE_KEY, '1');
  } catch {
    /* sem armazenamento: o servidor resolve */
  }
  updateUISettings({
    cevico_notes_dismissed: {
      ...(uiSettings.value?.cevico_notes_dismissed || {}),
      dopamine_colors_v1: true,
    },
  });
};
const pal = useCevicoPalette({
  scope: selectedPanel,
  // a variante por pessoa herda a paleta do painel-base
  fallbackScope: computed(() =>
    currentPanel.value.variant ? panelBase.value : null
  ),
  blocks: [...TOP_BLOCKS_DEFAULT, ...MAIN_BLOCKS_DEFAULT].map(id => ({
    id,
    label: BLOCK_LABELS[id],
    icon: BLOCK_ICONS[id],
  })),
  themePalette,
});
const {
  dayFlavor,
  flavorPreview,
  cycleFlavor,
  pagePalette,
  blockPalette,
  blockVars,
  blockFamily,
  cvVars,
  tileGradAt,
  openPalettePicker,
  paletteLabel,
} = pal;
// família dos CARDS da fileira (= bloco "indicadores"); a cor escolhida por
// card (item 143) e o alerta de meta continuam por cima
const panelFamily = computed(() => blockPalette('indicadores').family);

// 🔍 POPUP do card de KPI (item 140): o card mostra só o macro; o detalhe
// (linhas completas + "como é calculado") abre aqui
const kpiModal = ref(null);
const openKpi = tile => {
  kpiModal.value = tile;
  // cada abertura começa no período da régua, sem recorte próprio (item 144)
  kpiModalPreset.value = null;
  kpiModalGranularity.value = null;
  kpiModalBag.value = null;
};

// ── UX do popup (item 152): Esc fecha, a rolagem fica presa no popup
// (a página atrás não anda junto) e a transição respeita reduzir-movimento
const closeKpiModal = () => {
  kpiModal.value = null;
};
watch(kpiModal, open => {
  document.body.style.overflow = open ? 'hidden' : '';
});
const onKpiModalKey = e => {
  if (e.key === 'Escape' && kpiModal.value) closeKpiModal();
};
// gráfico sem nenhum movimento no recorte = mensagem gentil no lugar do vazio
const modalChartIsEmpty = computed(() => {
  const c = modalChart.value;
  if (!c || isLoadingModalBag.value) return false;
  return (c.values || []).every(v => !v) && !(c.prevValues || []).some(v => v);
});
// fórmula em PORTUGUÊS: troca as chaves técnicas pelos nomes do cesto
// (appointments_booked / new_leads → Consultas agendadas ÷ Novos contatos)
const prettyFormula = expr => {
  let out = ` ${String(expr || '')} `;
  Object.entries(bagMetrics.value)
    .sort((a, b) => b[0].length - a[0].length)
    .forEach(([k, m]) => {
      if (m?.label) out = out.split(k).join(m.label);
    });
  return out
    .replaceAll('*', '×')
    .replaceAll('/', '÷')
    .replace(/\s+/g, ' ')
    .trim();
};

// ids ESTÁVEIS por card (item 142): indicador de meta (gk) ou o nome em
// slug; cards do "+" usam o id salvo — é por eles que ordem/ocultos valem
const slugId = label =>
  String(label || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .slice(0, 40);
const allPanelTiles = computed(() => {
  const fixed = rawPanelTiles.value.map((t, i) => ({
    ...t,
    id: t.id || t.gk || slugId(t.label),
    grad: t.judged
      ? t.grad
      : currentPanel.value?.custom
        ? t.grad
        : tileGradAt(i),
  }));
  const custom = customTiles.value.map((t, i) => ({
    ...t,
    id: `kpi:${t.def.id}`,
    grad: t.grad || tileGradAt(fixed.length + i),
  }));
  return [...fixed, ...custom];
});

// ── MODO EDIÇÃO (admin, itens 142/143): botão no topo liga o modo — cards
// arrastam/ocultam/mudam de cor e os BLOCOS recolhem em barrinhas pra
// reordenar sem rolagem infinita; a barra grudada segura os controles ──
const organizeMode = ref(false);
const toggleEditMode = () => {
  organizeMode.value = !organizeMode.value;
  // saiu da edição: busca o que a pausa do auto-refresh segurou
  if (!organizeMode.value) refreshAll();
};
// variante por pessoa sem layout próprio ainda NASCE com o layout do base
const kpiLayout = computed(
  () =>
    crmSettings.value?.kpi_layout?.[selectedPanel.value] ||
    (currentPanel.value.variant
      ? crmSettings.value?.kpi_layout?.[panelBase.value]
      : null) || { order: [], hidden: [], colors: {} }
);
// ordem padrão = a do sistema; a ordem salva reorganiza; card novo entra no
// fim; a COR escolhida pelo admin (item 143) veste o card por cima da família
const panelTiles = computed(() => {
  const order = kpiLayout.value.order || [];
  const hidden = new Set(kpiLayout.value.hidden || []);
  const colors = kpiLayout.value.colors || {};
  const all = allPanelTiles.value;
  const rank = t => {
    const i = order.indexOf(t.id);
    return i === -1 ? 1000 + all.indexOf(t) : i;
  };
  return all
    .filter(t => !hidden.has(t.id))
    .sort((a, b) => rank(a) - rank(b))
    .map(t => (colors[t.id] ? { ...t, customGrad: colors[t.id] } : t));
});
const hiddenTiles = computed(() => {
  const hidden = new Set(kpiLayout.value.hidden || []);
  return allPanelTiles.value.filter(t => hidden.has(t.id));
});
// lista viva do arrasto (vuedraggable precisa de v-model próprio)
const dragTiles = ref([]);
// o watcher nasce DENTRO do onMounted: registrar watch(panelTiles) no setup
// avaliaria os tiles antes de várias consts lá de baixo existirem (TDZ) e
// envenenaria os computeds com undefined
onMounted(() => {
  dragTiles.value = [...panelTiles.value];
  watch(panelTiles, v => {
    dragTiles.value = [...v];
  });
});
const isSavingLayout = ref(false);
const saveKpiLayout = async patch => {
  const all = { ...(crmSettings.value?.kpi_layout || {}) };
  const cur = all[selectedPanel.value] || { order: [], hidden: [], colors: {} };
  all[selectedPanel.value] = {
    order: patch.order ?? cur.order ?? [],
    hidden: patch.hidden ?? cur.hidden ?? [],
    colors: patch.colors ?? cur.colors ?? {},
  };
  isSavingLayout.value = true;
  try {
    await CrmAPI.updateKpiLayout(all);
    await store.dispatch('crm/fetchSettings');
  } finally {
    isSavingLayout.value = false;
  }
};
const onKpiReorder = () =>
  saveKpiLayout({ order: dragTiles.value.map(t => t.id) });
const hideTile = tile =>
  saveKpiLayout({
    hidden: [...new Set([...(kpiLayout.value.hidden || []), tile.id])],
  });
const restoreTile = tile =>
  saveKpiLayout({
    hidden: (kpiLayout.value.hidden || []).filter(id => id !== tile.id),
  });
const resetKpiLayout = () => {
  saveKpiLayout({ order: [], hidden: [], colors: {} });
  resetBlockLayout();
};

// ── 🎨 COR DE QUALQUER CARD (item 143): no modo organizar, o pincel do
// card abre a palheta (família do painel, temas CEVICO, semânticas ou hex);
// a escolha vale pra todo mundo que vê o painel ──
const colorPicker = ref(null); // tile em edição de cor
const tileHexColor = ref('');
const openColorPicker = tile => {
  colorPicker.value = tile;
  tileHexColor.value = '';
};
const setTileColor = grad => {
  const colors = { ...(kpiLayout.value.colors || {}) };
  if (grad) colors[colorPicker.value.id] = grad;
  else delete colors[colorPicker.value.id];
  saveKpiLayout({ colors });
  colorPicker.value = null;
};
const applyTileHexColor = () => {
  const hex = (tileHexColor.value || '').trim();
  if (/^#[0-9a-fA-F]{6}$/.test(hex))
    setTileColor(`linear-gradient(135deg, ${hex}, ${hex}CC)`);
};

// ── ⠿ ORGANIZAR OS BLOCOS (item 143): TODOS os blocos do Meu Painel se
// movem com o mesmo arrasto magnético dos cards — duas áreas (avisos em
// cima do seletor de painel, conteúdo embaixo) e dá pra cruzar entre elas ──
const blockLayout = computed(
  () =>
    crmSettings.value?.block_layout?.[selectedPanel.value] ||
    (currentPanel.value.variant
      ? crmSettings.value?.block_layout?.[panelBase.value]
      : null) ||
    {}
);
// ordem salva + blocos novos (que ainda não estavam salvos) no lugar padrão;
// cada área só aceita os SEUS blocos (sem cruzar — o conteúdo de cada bloco
// só existe na área dele, então cruzar deixaria a barrinha vazia)
const orderedBlocks = computed(() => {
  const savedTop = (blockLayout.value.top || []).filter(id =>
    TOP_BLOCKS_DEFAULT.includes(id)
  );
  const savedMain = (blockLayout.value.main || []).filter(id =>
    MAIN_BLOCKS_DEFAULT.includes(id)
  );
  const placed = new Set([...savedTop, ...savedMain]);
  let top = [...savedTop, ...TOP_BLOCKS_DEFAULT.filter(id => !placed.has(id))];
  // item 211 (pedido 23/09): nos painéis Agendamento, Condução e Cirurgias a
  // caixa de tarefas e notas fica ACIMA DE TUDO, logo abaixo do banner
  if (TASKS_FIRST_PANELS.includes(panelBase.value))
    top = ['tarefas', ...top.filter(id => id !== 'tarefas')];
  return {
    top,
    main: [...savedMain, ...MAIN_BLOCKS_DEFAULT.filter(id => !placed.has(id))],
  };
});
const dragTopBlocks = ref([]);
const dragMainBlocks = ref([]);
// mesmo cuidado do dragTiles: o watch nasce dentro do onMounted (TDZ)
onMounted(() => {
  dragTopBlocks.value = [...orderedBlocks.value.top];
  dragMainBlocks.value = [...orderedBlocks.value.main];
  watch(orderedBlocks, v => {
    dragTopBlocks.value = [...v.top];
    dragMainBlocks.value = [...v.main];
  });
});
const saveBlockLayout = async () => {
  const all = { ...(crmSettings.value?.block_layout || {}) };
  all[selectedPanel.value] = {
    top: [...dragTopBlocks.value],
    main: [...dragMainBlocks.value],
  };
  isSavingLayout.value = true;
  try {
    await CrmAPI.updateBlockLayout(all);
    await store.dispatch('crm/fetchSettings');
  } finally {
    isSavingLayout.value = false;
  }
};
const resetBlockLayout = async () => {
  const all = { ...(crmSettings.value?.block_layout || {}) };
  if (!all[selectedPanel.value]) return;
  delete all[selectedPanel.value];
  try {
    await CrmAPI.updateBlockLayout(all);
    await store.dispatch('crm/fetchSettings');
  } catch {
    // sem drama: o padrão volta no próximo carregamento
  }
};
const layoutTouched = computed(() =>
  Boolean(
    (kpiLayout.value.order || []).length ||
      (kpiLayout.value.hidden || []).length ||
      Object.keys(kpiLayout.value.colors || {}).length ||
      (blockLayout.value.top || []).length ||
      (blockLayout.value.main || []).length
  )
);

// ── CARDS VIVOS: metas, recordes e cores por desempenho ──
// Meta é MENSAL (config do admin na mira 🎯); o backend manda o fator do
// período. Status: 🔴 <40% do esperado · 🟠 40-70% · cores do painel
// 70-100% · 🟢 meta batida · 🏆 recorde = aura de átomos orbitando.
const goalsInfo = computed(
  () => data.value?.goals || { targets: {}, factor: 1, records: {} }
);

// 🎯 METAS OFICIAIS (Painel de Metas) como FALLBACK dos alvos da mira —
// a régua de cores (abaixo/dentro/acima da meta) vale em TODOS os painéis
// (Agendamento, Condução, Cirurgias, Médicos, Gestor), mesmo sem mira própria
// configurada. Pedido 18/07 (item 79).
const officialGoals = useCevicoGoals();
onMounted(() => officialGoals.load());
const OFFICIAL_GK = {
  new_leads: 'new_leads',
  appointments_booked: 'appointments_booked',
  consultations: 'appointments_booked',
  attended: 'consultations_attended',
  surgeries_booked: 'surgeries_booked',
  surgeries_done: 'surgeries_done',
  surgeries_closed: 'surgeries_booked',
};
const officialTargetFor = gk => {
  const key = OFFICIAL_GK[gk];
  if (!key) return 0;
  return Number(officialGoals.infoFor(key)?.target || 0);
};

// paleta de "bom e mau resultado" POR PAINEL (o mau alerta, o meta celebra)
const STATUS_GRADS = {
  agendamento: {
    bad: 'linear-gradient(135deg, #7F1D1D, #B91C1C)',
    warn: 'linear-gradient(135deg, #92400E, #D97706)',
    meta: 'linear-gradient(135deg, #065F46, #10B981)',
  },
  conducao: {
    bad: 'linear-gradient(135deg, #7F1D1D, #B91C1C)',
    warn: 'linear-gradient(135deg, #92400E, #D97706)',
    meta: 'linear-gradient(135deg, #0F766E, #2DD4BF)',
  },
  cirurgia: {
    bad: 'linear-gradient(135deg, #831843, #4C0519)',
    warn: 'linear-gradient(135deg, #9A3412, #EA580C)',
    meta: 'linear-gradient(135deg, #047857, #34D399)',
  },
  medico: {
    bad: 'linear-gradient(135deg, #7F1D1D, #991B1B)',
    warn: 'linear-gradient(135deg, #A16207, #EAB308)',
    meta: 'linear-gradient(135deg, #065F46, #14B8A6)',
  },
  gestor: {
    bad: 'linear-gradient(135deg, #450A0A, #991B1B)',
    warn: 'linear-gradient(135deg, #78350F, #F59E0B)',
    meta: 'linear-gradient(135deg, #064E3B, #10B981)',
  },
};

const tileState = tile => {
  const g = goalsInfo.value;
  const value = parseFloat(String(tile.value)) || 0;
  // mira 🎯 do painel manda; sem ela, vale a meta OFICIAL do mês
  const target = Number(g.targets?.[tile.gk]) || officialTargetFor(tile.gk);
  const rec = g.records?.[tile.gk];
  let status = 'none';
  let ratio = null;
  let expected = null;
  if (tile.gk && target > 0) {
    expected = tile.pct ? target : target * (g.factor || 1);
    ratio = expected > 0 ? value / expected : null;
    if (ratio >= 1) status = 'meta';
    else if (ratio >= 0.7) status = 'ok';
    else if (ratio >= 0.4) status = 'warn';
    else status = 'bad';
  }
  // pedido 22/07: até MEIO-DIA as cores ficam neutras — de manhã o dia mal
  // começou e o "vermelho de ritmo" só assusta. Meta batida/recorde são
  // fatos (não julgamento de ritmo) e continuam aparecendo.
  if (['bad', 'warn'].includes(status) && new Date().getHours() < 12)
    status = 'neutral';
  return {
    status,
    ratio,
    expected,
    isRecord: !!rec?.is_record,
    best: rec?.best || 0,
  };
};

const tileVisual = tile => {
  const st = tileState(tile);
  const grads = STATUS_GRADS[panelBase.value] || STATUS_GRADS.agendamento;
  return {
    ...st,
    // sem status de meta mandando, um chip "Muito bom" pinta o card de
    // verde (pedido 22/07 — o dourado confundia com "neutro"); a cor
    // ESCOLHIDA pelo admin (item 143) vence o chip e a família, mas o
    // alerta de meta (vermelho/âmbar/verde-meta) continua por cima
    grad: ['bad', 'warn', 'meta'].includes(st.status)
      ? grads[st.status]
      : tile.customGrad || tile.chip?.grad || tile.grad,
    aura: st.isRecord,
    auraIntensity: Math.max(0.5, Math.min(1.2, st.ratio ?? 0.7)),
    pulse: st.status === 'meta' || st.isRecord,
  };
};

// ── modal de METAS (admin, mira 🎯 ao lado das pílulas) ──
const showGoalsModal = ref(false);
const goalsDraft = ref({});
const isSavingGoals = ref(false);
const GOAL_FIELDS = {
  agendamento: [
    { gk: 'new_leads', label: 'Novos contatos no mês' },
    { gk: 'appointments_booked', label: 'Marcadas na Agenda no mês' },
    { gk: 'booking_conversion', label: 'Taxa de agendamento (%)', pct: true },
    { gk: 'surgeries_closed', label: 'Cirurgias fechadas no mês' },
  ],
  conducao: [
    { gk: 'consultations', label: 'Consultas no mês' },
    { gk: 'attended', label: 'Comparecimentos no mês' },
    { gk: 'show_rate', label: 'Comparecimento (%)', pct: true },
    { gk: 'indications', label: 'Indicações no mês' },
  ],
  cirurgia: [
    { gk: 'indications', label: 'Indicações no mês' },
    { gk: 'surgeries_booked', label: 'Cirurgias agendadas no mês' },
    { gk: 'closing_rate', label: 'Taxa de fechamento (%)', pct: true },
    { gk: 'surgeries_done', label: 'Cirurgias realizadas no mês' },
  ],
  medico: [
    { gk: 'consultations', label: 'Consultas no mês' },
    { gk: 'indications', label: 'Indicações no mês' },
    { gk: 'conversion_rate', label: 'Conversão em cirurgia (%)', pct: true },
  ],
  gestor: [
    { gk: 'new_leads', label: 'Novos contatos no mês' },
    { gk: 'booking_conversion', label: 'Taxa de agendamento (%)', pct: true },
    { gk: 'show_rate', label: 'Comparecimento (%)', pct: true },
    { gk: 'closing_rate', label: 'Fechamento de cirurgias (%)', pct: true },
  ],
};
const openGoalsModal = () => {
  const all = crmSettings.value?.panel_goals || {};
  goalsDraft.value = JSON.parse(JSON.stringify(all));
  if (!goalsDraft.value[panelBase.value])
    goalsDraft.value[panelBase.value] = {};
  showGoalsModal.value = true;
};
const saveGoals = async () => {
  if (isSavingGoals.value) return;
  isSavingGoals.value = true;
  try {
    const clean = {};
    Object.entries(goalsDraft.value).forEach(([panel, goals]) => {
      const g = Object.fromEntries(
        Object.entries(goals || {}).filter(([, v]) => Number(v) > 0)
      );
      if (Object.keys(g).length) clean[panel] = g;
    });
    await CrmAPI.updatePanelGoals(clean);
    await store.dispatch('crm/fetchSettings');
    showGoalsModal.value = false;
    fetchData();
  } finally {
    isSavingGoals.value = false;
  }
};

// ── GESTOR: "posso viajar?" — o indicador próprio de decisão ──
// agrega metas em vermelho, radar, sem resposta e pendências num
// semáforo único com os motivos prontos para agir
const gestorSignals = computed(() => {
  if (panelBase.value !== 'gestor' || !data.value) return [];
  const sigs = [];
  (panelTiles.value || []).forEach(tile => {
    const st = tileState(tile);
    if (st.status === 'bad')
      sigs.push({
        level: 'red',
        icon: 'i-lucide-trending-down',
        text: `${tile.label}: muito abaixo da meta (${tile.value})`,
      });
    else if (st.status === 'warn')
      sigs.push({
        level: 'amber',
        icon: 'i-lucide-alert-triangle',
        text: `${tile.label}: abaixo do ritmo da meta (${tile.value})`,
      });
  });
  const alerts = radarAlerts.value.length;
  if (alerts)
    sigs.push({
      level: 'red',
      icon: 'i-lucide-radar',
      text: `${alerts} paciente(s) quente(s) sem atendimento (Radar)`,
    });
  const waiting = data.value.unanswered ?? 0;
  if (waiting > 8)
    sigs.push({
      level: 'amber',
      icon: 'i-lucide-message-circle',
      text: `${waiting} conversas abertas aguardando resposta`,
    });
  const unconfirmed = data.value.panel_data?.unconfirmed ?? 0;
  if (unconfirmed > 0)
    sigs.push({
      level: 'amber',
      icon: 'i-lucide-clipboard-alert',
      text: `${unconfirmed} consulta(s) sem conferência na Agenda`,
    });
  const bugs = data.value.my_tasks?.count ?? 0;
  if (bugs > 0)
    sigs.push({
      level: 'info',
      icon: 'i-lucide-list-todo',
      text: `${bugs} tarefa(s) esperando você no board`,
    });
  return sigs;
});
const gestorVerdict = computed(() => {
  const sigs = gestorSignals.value;
  if (sigs.some(x => x.level === 'red')) {
    return {
      key: 'red',
      title: 'Ação imediata ⚠️',
      sub: 'Tem coisa precisando de você agora — os motivos estão aqui embaixo.',
      grad: 'linear-gradient(135deg, #7F1D1D, #DC2626)',
    };
  }
  if (sigs.some(x => x.level === 'amber')) {
    return {
      key: 'amber',
      title: 'Atenção hoje 🟠',
      sub: 'Nada crítico, mas vale um olho antes de desligar.',
      grad: 'linear-gradient(135deg, #92400E, #F59E0B)',
    };
  }
  return {
    key: 'green',
    title: 'Tudo bem — pode viajar ✈️',
    sub: 'Metas no ritmo, ninguém esperando, nada travado. A operação está rodando.',
    grad: 'linear-gradient(135deg, #065F46, #10B981)',
  };
});

// linha de destaque abaixo dos tiles — muda com o painel
const panelHighlight = computed(() => {
  const d = pd.value;
  if (panelBase.value === 'conducao') {
    return {
      icon: 'i-lucide-clipboard-alert',
      color: '#D97706',
      value: d.unconfirmed ?? 0,
      label: 'Consultas sem conferência',
      sub: 'já passaram e ninguém marcou Compareceu/Faltou — confira na Agenda',
    };
  }
  if (panelBase.value === 'cirurgia') {
    return {
      icon: 'i-lucide-hourglass',
      color: '#BE185D',
      value: d.awaiting_closing ?? 0,
      label: 'Indicados aguardando fechamento',
      sub: `indicações do período ainda sem cirurgia marcada · ${d.upcoming_surgeries ?? 0} cirurgia(s) futura(s) na agenda`,
    };
  }
  if (panelBase.value === 'medico') {
    return {
      icon: 'i-lucide-slice',
      color: '#0369A1',
      value: d.surgeries ?? 0,
      label: 'Cirurgias no período',
      sub: d.doctor
        ? `realizadas/agendadas por ${d.doctor}`
        : 'todos os médicos',
    };
  }
  if (panelBase.value === 'gestor') {
    const nps = d.nps || {};
    return {
      icon: 'i-lucide-smile',
      color: '#0D9488',
      value:
        nps.satisfaction === null || nps.satisfaction === undefined
          ? '—'
          : `${nps.satisfaction}%`,
      label: 'Satisfação (NPS)',
      sub: nps.total
        ? `${nps.promoters} promotores (9-10) · ${nps.passives} notas 7-8 · ${nps.detractors} detratores (1-4)`
        : 'sem respostas ainda — ative o agente de NPS nas Automações',
    };
  }
  return {
    icon: 'i-lucide-stethoscope',
    color: '#EA580C',
    value: d.surgery_indications ?? 0,
    label: 'Indicações de cirurgia',
    sub: 'leads do período que chegaram à coluna "Indicação de Cirurgia"',
  };
});

// ── Saudação ────────────────────────────────────────────────
const firstName = computed(() => {
  const name =
    currentUser.value?.available_name || currentUser.value?.name || '';
  // só letras: vírgula, emoji ou símbolo no cadastro viravam "Guilherme,!"
  // no cabeçalho (bug real de produção, 12/09)
  const first =
    name
      .replace(/[^\p{L}\p{M}\s'-]/gu, ' ')
      .trim()
      .split(/\s+/)[0] || '';
  return first ? first.charAt(0).toUpperCase() + first.slice(1) : '';
});
const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
});
const todayLabel = computed(() => {
  const label = new Date().toLocaleDateString('pt-BR', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  });
  return label.charAt(0).toUpperCase() + label.slice(1);
});

// ── Tarefas esperando VOCÊ + notas dos pacientes (item 211) ──────
const myTasks = computed(() => data.value?.my_tasks?.items || []);
const myTasksCount = computed(() => data.value?.my_tasks?.count || 0);
const patientNotes = computed(() => data.value?.patient_notes || []);
// a caixa fica sempre à mostra nos painéis em que é a primeira coisa
const tasksBoxAlways = computed(() =>
  TASKS_FIRST_PANELS.includes(panelBase.value)
);
const showNoteForm = ref(false);
const onPanelNoteSaved = () => {
  showNoteForm.value = false;
  fetchData();
};
const deletePanelNote = async note => {
  try {
    await CrmAPI.deletePatientNote(note.id);
    if (data.value?.patient_notes)
      data.value.patient_notes = data.value.patient_notes.filter(
        n => n.id !== note.id
      );
  } catch (error) {
    useAlert(error?.response?.data?.error || 'Não consegui apagar a nota.');
  }
};
const openPatientFromNote = note => {
  if (!note.contact?.id) return;
  router.push({
    name: 'patient_space',
    params: { accountId: accountId.value, contactId: note.contact.id },
  });
};
const fmtNoteAt = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
const TASK_DOT = {
  urgent: '#dc2626',
  high: '#d97706',
  medium: 'var(--cv)',
  low: '#94a3b8',
};
const TASK_PRIORITY_LABEL = {
  low: 'baixa',
  medium: 'média',
  high: 'ALTA',
  urgent: 'URGENTE',
};
const goToTasks = () =>
  router.push({ name: 'tasks_board', params: { accountId: accountId.value } });
// atalho pro Dashboard da Agenda em TODOS os painéis (item 86 — equipe vê)
const goToAgendaDashboard = () =>
  router.push({
    name: 'agenda_dashboard_reports',
    params: { accountId: accountId.value },
  });
const fmtTaskDue = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : null;

// ── Radar de Oportunidades ──────────────────────────────────
// pausa manual pela atendente (fica registrado quem desligou e quando)
const radarStatus = ref(null);
const togglingRadar = ref(false);
const loadRadarStatus = async () => {
  try {
    const { data: ping } = await CrmAPI.radarPing();
    radarStatus.value = ping.radar;
  } catch {
    radarStatus.value = null;
  }
};
const toggleRadarManual = async () => {
  const turningOff = radarStatus.value?.enabled;
  // eslint-disable-next-line no-alert
  if (
    turningOff &&
    !window.confirm(
      'Desativar o Radar de Oportunidades? Fica registrado que foi você.'
    )
  )
    return;
  togglingRadar.value = true;
  try {
    const { data: res } = await CrmAPI.toggleRadar();
    radarStatus.value = res.radar;
  } finally {
    togglingRadar.value = false;
  }
};
const radarLastActionLabel = computed(() => {
  const a = radarStatus.value?.last_action;
  if (!a) return '';
  const when = new Date(a.at).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
  return `${a.action} por ${a.user} às ${when}`;
});

const radarAlerts = computed(
  () => data.value?.opportunity_alerts?.alerts || []
);

// ── Radar em CARROSSEL pulsante (item 63 — 19/07): um card por vez com
// tudo; os de trás só espiam (nome + tempo). "Atender agora" = 3 ✅
// pipocam do toque, -1 na contagem, o próximo assume — até zerar.
const radarQueue = ref([]);
watch(
  radarAlerts,
  list => {
    radarQueue.value = [...(list || [])];
  },
  { immediate: true }
);
const radarFront = computed(() => radarQueue.value[0] || null);
const radarPeek = computed(() => radarQueue.value.slice(1, 4));
const radarFx = ref(null);
// balão da conversa DIRETO do card (o mesmo do CRM): a atendente resolve
// dali mesmo, sem precisar ir até Conversas
const radarChat = ref(null);
const openChatBalloon = alert => {
  radarChat.value = {
    contact_id: alert.contact_id,
    name: alert.contact_name,
    phone_number: alert.phone,
    labels: [],
    last_conversation_id: alert.conversation_id,
    last_conversation: {
      inbox_id: alert.inbox_id,
      inbox_name: alert.inbox_name,
      channel_type: alert.channel_type,
      status: alert.conversation_status || 'open',
    },
  };
};
// mexeu na conversa pelo balão = aviso atendido: -1 na fila e registra no
// servidor (a eficácia do Radar continua contando normalmente)
const onRadarChatReplied = () => {
  const convId = radarChat.value?.last_conversation_id;
  if (!convId || !radarQueue.value.some(a => a.conversation_id === convId))
    return;
  radarQueue.value = radarQueue.value.filter(a => a.conversation_id !== convId);
  CrmAPI.radarAttend(convId).catch(() => {});
};
const onRadarChatResolved = ({ status }) => {
  if (status === 'resolved') onRadarChatReplied();
};
const attendNow = (alert, event) => {
  if (radarFx.value && event) {
    radarFx.value.burstAt(event.clientX, event.clientY, ['✅'], 3);
  }
  radarQueue.value = radarQueue.value.filter(a => a !== alert);
  // persiste o -1 no servidor (vale p/ todos; se o paciente continuar sem
  // resposta, a próxima auditoria do Radar recoloca o aviso sozinha)
  CrmAPI.radarAttend(alert.conversation_id).catch(() => {});
  // pequena pausa para o prêmio ser sentido antes de abrir o balão
  setTimeout(() => openChatBalloon(alert), 320);
};
const rotateRadar = () => {
  if (radarQueue.value.length < 2) return;
  const [first, ...rest] = radarQueue.value;
  radarQueue.value = [...rest, first];
};
const radarLastRun = computed(() => {
  const iso = data.value?.opportunity_alerts?.last_run_at;
  return iso
    ? new Date(iso).toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
      })
    : null;
});
// item 83 — eficácia: consultas agendadas DEPOIS do aviso atendido (30d)
const radarEfficacy = computed(
  () => data.value?.opportunity_alerts?.efficacy || null
);
const waitingLabel = alert => {
  if (!alert.waiting_since) return '';
  const min = Math.round(
    (Date.now() - new Date(alert.waiting_since).getTime()) / 60000
  );
  if (min < 60) return `${min} min sem resposta`;
  return `${Math.floor(min / 60)}h${String(min % 60).padStart(2, '0')} sem resposta`;
};
// atalhos no formato do card do CRM (iniciais + Espaço do Paciente)
// 🔧 rodada 192: avisos que não vêm do Radar de IA têm rótulo próprio —
// ligação perdida (167), "não vou" da jornada (168) e as ações do Atendente
// Pós-agendamento ao vivo (remarcou / cancelou na Agenda)
const ALERT_KIND_META = {
  missed_call: {
    icon: 'i-lucide-phone-missed',
    label: 'Ligação perdida',
    color: '#dc2626',
  },
  journey_reply: {
    icon: 'i-lucide-calendar-x',
    label: 'Respondeu "não vou"',
    color: '#d97706',
  },
  agente_remarcou: {
    icon: 'i-lucide-calendar-clock',
    label: 'Agente remarcou a consulta',
    color: '#0f5fa6',
  },
  agente_cancelou: {
    icon: 'i-lucide-calendar-off',
    label: 'Agente cancelou a consulta',
    color: '#b91c1c',
  },
  // item 217: paciente respondeu NÃO ao lembrete da véspera (consulta segue na Agenda)
  nao_confirmou: {
    icon: 'i-lucide-message-circle-x',
    label: 'Respondeu NÃO ao lembrete da consulta',
    color: '#db2777',
  },
};
const alertKindMeta = alert => ALERT_KIND_META[alert?.kind] || null;
const isAgentAlert = alert =>
  String(alert?.kind || '').startsWith('agente_') ||
  alert?.kind === 'nao_confirmou';
const openAgendaFromAlert = alert =>
  router.push({
    name: 'agenda_board',
    params: { accountId: accountId.value },
    query: alert?.task_id ? { task: alert.task_id } : {},
  });
const alertInitials = alert =>
  (alert.contact_name || '?')
    .split(' ')
    .map(w => w[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
const openPatientSpace = alert =>
  router.push(`/app/accounts/${accountId.value}/patient/${alert.contact_id}`);

// ── 🎯 Metas / Rotinas / Ferramentas (Painel de Metas alimenta) ──
const goalsData = ref(null);
const loadGoalsStrip = async () => {
  try {
    const { data: payload } = await CrmAPI.getGoalPlans();
    goalsData.value = payload;
  } catch {
    goalsData.value = null;
  }
};
const goalTargets = computed(() => goalsData.value?.plan?.targets || {});
const goalCurrent = computed(() => {
  const h = (goalsData.value?.history || []).find(
    x => x.month === goalsData.value?.month
  );
  return h?.values || {};
});
// só indicadores COM meta definida (até 3, os de maior alvo)
const goalRows = computed(() =>
  Object.entries(goalTargets.value)
    .filter(([, v]) => Number(v) > 0)
    .slice(0, 4)
    .map(([key, target]) => {
      const current = goalCurrent.value[key] || 0;
      return {
        key,
        label: goalsData.value?.indicators?.[key] || key,
        current,
        target: Number(target),
        pct: Math.min(100, Math.round((current / Number(target)) * 100)),
      };
    })
);
const teamRoutines = computed(() => goalsData.value?.routines || []);
const importantTools = computed(() => goalsData.value?.tools || []);
const goToGoals = () => router.push(`/app/accounts/${accountId.value}/goals`);
const goToTools = () => router.push(`/app/accounts/${accountId.value}/tools`);
const openTool = tool =>
  tool.url && window.open(tool.url, '_blank', 'noopener');
// abre a gaveta global de feedback de bugs (BugReportDrawer no Dashboard.vue)
const reportBug = () =>
  window.dispatchEvent(new CustomEvent('cevico:report-bug'));

// ── Mentor do Time: feedback semanal individual ──
// Cada pessoa vê o seu; admin navega pelo time (pílulas com os nomes).
const weeklyFeedback = computed(() => data.value?.weekly_feedback || null);
const myFeedback = computed(() => weeklyFeedback.value?.mine || null);
const teamFeedbacks = computed(() => weeklyFeedback.value?.team || []);
const feedbackViewUserId = ref(null);
const visibleFeedback = computed(() => {
  if (feedbackViewUserId.value) {
    return (
      teamFeedbacks.value.find(f => f.user_id === feedbackViewUserId.value) ||
      myFeedback.value
    );
  }
  return myFeedback.value || teamFeedbacks.value[0] || null;
});
const fbWeekLabel = fb => {
  if (!fb?.week_start) return '';
  const d = new Date(`${fb.week_start}T12:00:00`);
  const end = new Date(d);
  end.setDate(d.getDate() + 6);
  const f = x =>
    x.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
  return `semana de ${f(d)} a ${f(end)}`;
};

// Meta de tempo de atendimento: agora mora no Dashboard dos Agentes
// (Relatórios) — pedido 20/08. O widget do Construtor continua valendo.

// ── Indicadores do período ──────────────────────────────────
// ── Início do funil detalhado (item 138) ──
// card 1: total + quebra por caixa de captação
const shortInboxName = n =>
  (n || '')
    .replace(/caixa/i, '')
    .replace(/\(teste\)/i, '')
    .trim()
    .split(' ')[0] || n;
const leadsInboxSub = computed(() => {
  const list = data.value?.leads_by_inbox || [];
  if (!list.length) return 'caixas Google + Instagram';
  return list.map(i => `${shortInboxName(i.name)} ${i.count}`).join(' · ');
});
// conversão POR CAIXA: dos que chegaram por ela, % que avançou a Agendamento
const leadsInboxConversion = computed(() => {
  const list = (data.value?.leads_by_inbox || []).filter(i => i.count > 0);
  if (!list.length) return '';
  return `agendaram: ${list.map(i => `${shortInboxName(i.name)} ${i.rate}%`).join(' · ')}`;
});
// card 2: tempo de DECISÃO (dias entre chegar e agendar)
const decisionSub = computed(() => {
  const t = data.value?.decision_time;
  if (!t) return '';
  return `🤔 decisão média ${String(t.avg_days).replace('.', ',')}d · ${t.same_day} no dia · ${t.next_day} em 1d · ${t.within_week} em 2-7d · ${t.later} em 8d+`;
});
// card 3: o DIA julgado contra a fatia diária da meta oficial do mês
const cohortLine = (key, label) => {
  const c = data.value?.booking_cohorts?.[key];
  if (!c) return '';
  return `${label}: ${c.booked} de ${c.leads} agendaram (${c.rate}%)`;
};
const bookingDayVerdict = computed(() => {
  const booked = data.value?.booked_today ?? 0;
  const target = officialGoals.goalFor('appointments_booked')?.target || 0;
  if (!target)
    return {
      label: 'defina a meta no Painel de Metas',
      grad: 'linear-gradient(135deg, #B8860B, #D4A017)',
    };
  const now = new Date();
  const daily =
    target / new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
  const ratio = daily > 0 ? booked / daily : 1;
  if (ratio >= 1)
    return {
      label: 'Muito bom 🚀',
      grad: 'linear-gradient(135deg, #065F46, #10B981)',
    };
  if (ratio >= 0.6)
    return {
      label: 'Bom 👍',
      grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)',
    };
  if (ratio >= 0.3)
    return {
      label: 'Regular',
      grad: 'linear-gradient(135deg, #B8860B, #D4A017)',
    };
  return { label: 'Fraco', grad: 'linear-gradient(135deg, #B91C1C, #EF4444)' };
});

// ── 🎯 Meu desempenho (item 138): a pessoa + o Atendimento IA ──
const perf = computed(() => data.value?.my_performance || null);
const perfCols = computed(() => {
  if (!perf.value) return [];
  // painel do GESTOR (item 140): a equipe inteira que trabalhou no período
  if (panelBase.value === 'gestor' && perf.value.team?.length) {
    return perf.value.team.map(r => ({
      key: `u${r.id}`,
      title: r.is_ai ? `🤖 ${r.name} (Atendimento IA)` : r.name,
      row: r,
    }));
  }
  const cols = [{ key: 'me', title: 'Você', row: perf.value.me }];
  if (perf.value.ai)
    cols.push({ key: 'ai', title: '🤖 Atendimento IA', row: perf.value.ai });
  return cols.filter(c => c.row);
});
const perfFmtMin = m => {
  if (m === null || m === undefined) return '—';
  if (m >= 60)
    return `${Math.floor(m / 60)}h${String(Math.round(m % 60)).padStart(2, '0')}`;
  return `${String(m).replace('.', ',')}min`;
};
const perfBrl = v =>
  (v || 0).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
// você × você: setinha vs o período anterior (invert = menor é melhor)
const perfDelta = (curr, prevVal, invert = false) => {
  if (
    prevVal === null ||
    prevVal === undefined ||
    curr === null ||
    curr === undefined
  )
    return null;
  if (curr === prevVal) return null;
  const up = curr > prevVal;
  const good = invert ? !up : up;
  return {
    arrow: up ? '▲' : '▼',
    color: good ? '#059669' : '#DC2626',
    prev: prevVal,
  };
};
// item 139: cada pessoa tem SUAS métricas (o admin propõe em Configurações
// → Painéis); row.metrics traz as chaves escolhidas (ou o padrão)
const perfTilesFor = col => {
  const r = col.row;
  const prev = col.key === 'me' ? perf.value?.previous || {} : {};
  const goal = perf.value?.goal_minutes || 15;
  const clinic = perf.value?.clinic || {};
  const mk = key => {
    switch (key) {
      case 'touched':
        return {
          key,
          display: r.conversations_touched ?? 0,
          label: 'conversas em que atuou',
          delta: perfDelta(r.conversations_touched, prev.conversations_touched),
        };
      case 'assigned':
        return {
          key,
          display: r.conversations_assigned ?? 0,
          label: 'conversas atribuídas',
        };
      case 'messages':
        return {
          key,
          display: r.messages_sent ?? 0,
          label: 'mensagens enviadas',
          delta: perfDelta(r.messages_sent, prev.messages_sent),
        };
      case 'reply_commercial': {
        const v = r.commercial?.avg_minutes ?? null;
        return {
          key,
          display: perfFmtMin(v),
          label: `resposta média (08–17h) · ${r.commercial?.within_rate ?? 0}% na meta`,
          color: v === null ? '' : v <= goal ? '#059669' : '#DC2626',
          delta: perfDelta(v, prev.avg_reply_min, true),
        };
      }
      case 'first_response':
        return {
          key,
          display: perfFmtMin(r.avg_first_response_min),
          label: '1ª resposta (média)',
        };
      case 'resolved':
        return {
          key,
          display: r.conversations_resolved ?? 0,
          label: 'resolvidas',
          delta: perfDelta(
            r.conversations_resolved,
            prev.conversations_resolved
          ),
        };
      case 'appointments':
        return {
          key,
          display: r.appointments_created ?? 0,
          label: 'consultas agendadas',
          delta: perfDelta(r.appointments_created, prev.appointments_created),
        };
      case 'surgeries_created':
        return {
          key,
          display: r.surgeries_created ?? 0,
          label: 'cirurgias agendadas',
        };
      case 'surgeries_closed':
        return {
          key,
          display: r.surgeries?.count ?? 0,
          label: `cirurgias fechadas · ${perfBrl(r.surgeries?.revenue)}`,
        };
      case 'attendance':
        return {
          key,
          display: `${clinic.rate ?? 0}%`,
          label: `comparecimento (clínica) · ${clinic.attended ?? 0} vieram · ${clinic.missed ?? 0} faltaram`,
          color:
            (clinic.rate ?? 0) >= 80
              ? '#059669'
              : (clinic.rate ?? 0) >= 60
                ? '#D4A017'
                : '#DC2626',
        };
      case 'days_worked':
        return {
          key,
          display: r.workday?.days_active ?? 0,
          label: 'dias trabalhados',
        };
      case 'calls_answered':
        return {
          key,
          display: r.calls_answered ?? 0,
          label: 'ligações atendidas',
        };
      case 'calls_talk':
        return {
          key,
          display: `${r.calls_talk_minutes ?? 0} min`,
          label: 'ao telefone',
        };
      default:
        return null;
    }
  };
  return (r.metrics || []).map(mk).filter(Boolean);
};

// ── Saúde da agenda (janelas × consultas, calculada aqui) ───
const consultaTasks = computed(() =>
  allTasks.value.filter(
    t => (t.task_type === 'consulta' || t.unit) && t.due_at && !t.canceled_at
  )
);
const scan = opts =>
  scanAgenda({
    windows: resolveWindows(crmSettings.value),
    tasks: consultaTasks.value,
    blockedSet: new Set(
      resolveBlocked(crmSettings.value).map(b =>
        blockKey(b.date, b.time, b.unit)
      )
    ),
    blockedDays: new Set(resolveBlockedDays(crmSettings.value)),
    ...opts,
  });

// ── Saúde da Agenda de CIRURGIAS (janelas da sala cirúrgica) ──
const surgeryTasks = computed(() =>
  allTasks.value.filter(
    t => t.task_type === 'cirurgia' && t.due_at && !t.canceled_at
  )
);
const scanSurgery = opts =>
  scanAgenda({
    windows: resolveSurgeryWindows(crmSettings.value),
    tasks: surgeryTasks.value,
    blockedSet: new Set(),
    blockedDays: new Set(resolveBlockedDays(crmSettings.value)),
    ...opts,
  });
const surgFillNext7 = computed(() =>
  scanSurgery({ from: new Date(), days: 7, futureOnly: true })
);
const surgUsageLast7 = computed(() => {
  const from = new Date();
  from.setDate(from.getDate() - 7);
  return scanSurgery({ from, days: 7, pastOnly: true });
});
// bloco de cirurgias SEMPRE lado a lado com o de consultas (pedido
// 2026-07-15) — meta do mês e próxima cirurgia valem mesmo sem janelas
// da sala configuradas (as barras mostram "—" até configurar)
const showSurgeryHealth = computed(() => true);

// 🎯 META DO MÊS: 100 cirurgias — barra de progresso no retângulo
const SURGERY_GOAL = 100;
// a meta OFICIAL do Painel de Metas manda quando existe (varredura 12/09);
// sem ela, a referência histórica de 100
const surgeryGoalTarget = computed(
  () => officialTargetFor('surgeries_done') || SURGERY_GOAL
);
const surgeriesDoneMonth = computed(() => {
  const now = new Date();
  return surgeryTasks.value.filter(t => {
    const d = new Date(t.due_at);
    return (
      d.getFullYear() === now.getFullYear() &&
      d.getMonth() === now.getMonth() &&
      (t.attendance === 'attended' || t.status === 'done')
    );
  }).length;
});
const goalPct = computed(() =>
  Math.min(
    Math.round((surgeriesDoneMonth.value / surgeryGoalTarget.value) * 100),
    100
  )
);
const nextSurgery = computed(
  () =>
    surgeryTasks.value
      .filter(t => new Date(t.due_at) > new Date() && !t.attendance)
      .sort((a, b) => new Date(a.due_at) - new Date(b.due_at))[0] || null
);

const nextFreeSlots = computed(
  () =>
    scan({ from: new Date(), days: 14, freeLimit: 4, futureOnly: true })
      .freeSlots
);
const fillNext7 = computed(() =>
  scan({ from: new Date(), days: 7, futureOnly: true })
);
const usageLast7 = computed(() => {
  const from = new Date();
  from.setDate(from.getDate() - 7);
  return scan({ from, days: 7, pastOnly: true });
});
const attendance = computed(() => {
  const now = Date.now();
  const cutoff = now - 30 * 24 * 3600 * 1000;
  const past = consultaTasks.value.filter(t => {
    const d = new Date(t.due_at).getTime();
    return d < now && d > cutoff;
  });
  if (!past.length) return null;
  return Math.round(
    (past.filter(t => t.status === 'done').length / past.length) * 100
  );
});
// % de agendamento 30d (consultas ÷ novos contatos) com referência fixa
const bookingRate30 = computed(() => {
  const contacts = data.value?.new_contacts_30d || 0;
  if (!contacts) return null;
  return (
    Math.round(((data.value?.appointments_30d || 0) / contacts) * 1000) / 10
  );
});
const booking30Verdict = computed(() => {
  const r = bookingRate30.value;
  if (r === null) return null;
  if (r >= 15) return { label: 'Muito bom 🚀', color: '#10B981' };
  if (r >= 10) return { label: 'Bom 👍', color: '#3B82F6' };
  if (r >= 5) return { label: 'Regular', color: '#D4A017' };
  return { label: 'Fraco — hora de agir', color: '#EF4444' };
});
// o mesmo veredito em formato de CHIP do card julgado (item 143): a cor
// semântica pinta o card "% de agendamento" da fileira
const booking30Chip = computed(() => {
  const r = bookingRate30.value;
  if (r === null)
    return {
      label: 'sem dados de 30 dias',
      grad: 'linear-gradient(135deg, #334155, #64748B)',
    };
  if (r >= 15)
    return {
      label: 'Muito bom 🚀',
      grad: 'linear-gradient(135deg, #065F46, #10B981)',
    };
  if (r >= 10)
    return {
      label: 'Bom 👍',
      grad: 'linear-gradient(135deg, #1D4ED8, #3B82F6)',
    };
  if (r >= 5)
    return {
      label: 'Regular',
      grad: 'linear-gradient(135deg, #B8860B, #D4A017)',
    };
  return {
    label: 'Fraco — hora de agir',
    grad: 'linear-gradient(135deg, #B91C1C, #EF4444)',
  };
});

const slotLabel = f =>
  `${f.day.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' })} ${f.slot}`;
const slotDoctorShort = f =>
  DOCTORS.find(d => d.name === f.win.doctor)?.short || '';
const slotColor = f =>
  DOCTORS.find(d => d.name === f.win.doctor)?.color || '#64748B';

const nextAppointment = computed(
  () => (data.value?.next_appointments || [])[0] || null
);
const apptTime = iso =>
  new Date(iso).toLocaleString('pt-BR', {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });

// ── Atalhos ─────────────────────────────────────────────────
const shortcuts = [
  {
    label: 'CRM',
    icon: 'i-lucide-rocket',
    route: 'crm_board',
    color: '#0F5FA6',
  },
  {
    label: 'Conversas',
    icon: 'i-lucide-message-circle',
    route: 'home',
    color: '#7C3AED',
  },
  {
    label: 'Agenda',
    icon: 'i-lucide-calendar-days',
    route: 'agenda_board',
    color: '#EA580C',
  },
  {
    label: 'Tarefas',
    icon: 'i-lucide-list-checks',
    route: 'tasks_board',
    color: '#D4A017',
  },
];
const go = route =>
  router.push({ name: route, params: { accountId: accountId.value } });

// ── 🧑‍🤝‍🧑 PAINÉIS POR PESSOA (rodada 160) ──
// O admin cria uma versão de um painel-base para uma ou mais pessoas:
// mesmos números e metas do base, layout PRÓPRIO (blocos, cards, cores)
// organizado no Modo edição com o arrasto magnético. Quem está na lista
// abre o Meu Painel já nele (atribuição sincronizada no servidor).
const showVariantModal = ref(false);
const variantDraft = ref({
  id: '',
  name: '',
  base: 'agendamento',
  user_ids: [],
});
const isSavingVariant = ref(false);
const variantDeleteArmed = ref(false);
const openVariantModal = (existing = null) => {
  if (!teamAgents.value.length) store.dispatch('agents/get');
  variantDeleteArmed.value = false;
  variantDraft.value = existing
    ? {
        id: existing.id,
        name: existing.name,
        base: existing.base,
        user_ids: [...(existing.user_ids || [])],
      }
    : {
        id: '',
        name: '',
        base: BASE_PANELS.some(b => b.key === panelBase.value)
          ? panelBase.value
          : 'agendamento',
        user_ids: [],
      };
  showVariantModal.value = true;
};
const variantBaseLabel = key =>
  BASE_PANELS.find(b => b.key === key)?.label || key;
// nome sugerido = primeiros nomes de quem vai ver ("Natália · Elizangela")
const suggestedVariantName = () =>
  variantDraft.value.user_ids
    .map(
      id => (teamAgents.value.find(a => a.id === id)?.name || '').split(' ')[0]
    )
    .filter(Boolean)
    .join(' · ');
const toggleVariantUser = id => {
  const list = variantDraft.value.user_ids;
  const i = list.indexOf(id);
  if (i === -1) list.push(id);
  else list.splice(i, 1);
};
const saveVariant = async () => {
  if (isSavingVariant.value) return;
  const d = variantDraft.value;
  const name =
    d.name.trim() ||
    suggestedVariantName() ||
    `${variantBaseLabel(d.base)} · pessoa`;
  const others = (crmSettings.value?.panel_variants || []).filter(
    v => v.id !== d.id
  );
  isSavingVariant.value = true;
  try {
    const { data: saved } = await CrmAPI.updatePanelVariants([
      ...others,
      { id: d.id || '', name, base: d.base, user_ids: d.user_ids },
    ]);
    await store.dispatch('crm/fetchSettings');
    showVariantModal.value = false;
    // abre o painel recém-criado (o id nasce no servidor)
    const list = saved?.panel_variants || [];
    const mine = d.id
      ? list.find(v => v.id === d.id)
      : list.find(v => !others.some(o => o.id === v.id));
    if (mine) setPanel(`variant:${mine.id}`);
  } catch {
    useAlert('Não deu pra salvar o painel. Tente de novo.');
  } finally {
    isSavingVariant.value = false;
  }
};
const deleteVariant = async () => {
  const d = variantDraft.value;
  if (!d.id || isSavingVariant.value) return;
  const list = (crmSettings.value?.panel_variants || []).filter(
    v => v.id !== d.id
  );
  isSavingVariant.value = true;
  try {
    await CrmAPI.updatePanelVariants(list);
    await store.dispatch('crm/fetchSettings');
    showVariantModal.value = false;
    if (selectedPanel.value === `variant:${d.id}`) setPanel(d.base);
  } catch {
    useAlert('Não deu pra excluir o painel. Tente de novo.');
  } finally {
    isSavingVariant.value = false;
    variantDeleteArmed.value = false;
  }
};

// ── cabeçalho (varredura 12/09) ──
// o olho CEVICO (public/brand-assets) como marca d'água — binding dinâmico
// de propósito: src fixo com barra inicial vira import de módulo no Vite
const HERO_EYE = '/brand-assets/cevico-eye.svg';
// o que este painel acompanha, em uma frase
const HERO_LEADS = {
  agendamento:
    'Do lead ao agendamento: quem chegou, quem marcou e o que ainda espera resposta.',
  conducao:
    'Do agendamento à indicação: consultas do período, comparecimento e indicações de cirurgia.',
  cirurgia:
    'Fechamento e pós-operatório: indicações, cirurgias agendadas e realizadas.',
  medico:
    'A agenda de cada médico: consultas, indicações e conversão em cirurgia.',
  gestor:
    'O processo inteiro num olhar: chegada, agendamento, comparecimento e fechamento.',
};
const heroLead = computed(() => {
  const p = currentPanel.value || {};
  if (p.custom)
    return 'Painel montado no Construtor — os seus indicadores, do seu jeito.';
  // variante por pessoa herda a frase do painel-base
  return (
    HERO_LEADS[p.base || p.key] ||
    `Boas-vindas ao CEVICO S.I — ${p.desc || ''}.`
  );
});
// 🌡️ o PULSO do momento no cabeçalho: responde "como está agora?" antes de
// qualquer rolagem — conversas abertas, quem espera resposta, consultas de
// hoje e, quando existe, a fila do Radar
const heroPulse = computed(() => {
  const d = data.value;
  if (!d) return [];
  const waiting = d.unanswered ?? 0;
  const hot = radarQueue.value.length;
  const items = [
    {
      key: 'open',
      icon: 'i-lucide-inbox',
      value: d.open_conversations ?? 0,
      label: 'conversas abertas',
      route: 'home',
      title: 'Abrir as conversas',
    },
    {
      key: 'waiting',
      icon: 'i-lucide-clock-alert',
      value: waiting,
      label: 'aguardando resposta',
      route: 'home',
      alert: waiting > 0,
      title: 'Conversas em que o paciente falou por último',
    },
    {
      key: 'today',
      icon: 'i-lucide-calendar-check',
      value: d.appointments_today ?? 0,
      label: 'consultas hoje',
      route: 'agenda_board',
      title: 'Abrir a Agenda',
    },
  ];
  if (hot)
    items.push({
      key: 'radar',
      icon: 'i-lucide-radar',
      value: hot,
      label: hot === 1 ? 'paciente quente' : 'pacientes quentes',
      route: 'crm_board',
      alert: true,
      title: 'Radar de Oportunidades: pacientes quentes sem atendimento',
    });
  return items;
});

// mantém o painel VIVO: atualiza sozinho a cada 2 min e sempre que a
// pessoa volta para a aba (sem precisar recarregar a página)
let refreshTimer = null;
const refreshAll = () => {
  // no MODO EDIÇÃO a atualização automática pausa: um refresh no meio do
  // arrasto trocava as listas do vuedraggable e quebrava o movimento
  if (organizeMode.value) return;
  store.dispatch('tasks/fetch').catch(() => {});
  // item 237: mês/ano/personalizado mudam devagar e custam caro — a
  // atualização automática só refaz os períodos curtos (o servidor guarda
  // os longos por 10 min de qualquer forma)
  if (['month', 'last_month', 'year', 'custom'].includes(period.value?.preset)) return;
  fetchData();
};
const onVisible = () => {
  if (document.visibilityState === 'visible') refreshAll();
};

// ── ✓ dar CHECK num aviso: a janelinha some da tela e só volta quando
// houver NOVIDADE (a assinatura muda: outra semana de feedback, outros
// pacientes no Radar, outras tarefas). Por pessoa, neste aparelho. ──
const dismissStorageKey = computed(
  () => `cevico_avisos_checados_${currentUser.value?.id || 0}`
);
const dismissedAvisos = ref({});
const loadDismissedAvisos = () => {
  try {
    dismissedAvisos.value = JSON.parse(
      localStorage.getItem(dismissStorageKey.value) || '{}'
    );
  } catch {
    dismissedAvisos.value = {};
  }
};
const checkAviso = signature => {
  if (!signature) return;
  const entries = Object.entries({
    ...dismissedAvisos.value,
    [signature]: Date.now(),
  })
    .sort((a, b) => b[1] - a[1])
    .slice(0, 40); // guarda só os últimos, não cresce pra sempre
  dismissedAvisos.value = Object.fromEntries(entries);
  localStorage.setItem(
    dismissStorageKey.value,
    JSON.stringify(dismissedAvisos.value)
  );
};
const avisoChecado = signature => Boolean(dismissedAvisos.value[signature]);
// assinaturas de conteúdo de cada janelinha
const fbSignature = computed(() =>
  visibleFeedback.value
    ? `fb:${myFeedback.value?.week_start || visibleFeedback.value.week_start}`
    : ''
);
// item 88 v2 (pedido 20/07): números de WhatsApp MINI e discreto no
// painel do gestor, mostrando o STATUS DA CONTA na Meta (qualidade +
// limite de envio), não um "funcionando" genérico
const whatsappStatus = computed(() => data.value?.whatsapp_status || null);
const waProblem = computed(() =>
  (whatsappStatus.value || []).some(
    w =>
      w.reauthorization_required ||
      ['RED', 'FLAGGED'].includes(w.quality) ||
      w.name_status === 'DECLINED'
  )
);
const WA_QUALITY = {
  GREEN: { dot: '#10B981', label: 'conta saudável' },
  YELLOW: { dot: '#F59E0B', label: 'qualidade em atenção' },
  RED: { dot: '#EF4444', label: 'qualidade baixa — risco de restrição' },
  FLAGGED: { dot: '#EF4444', label: 'conta sinalizada pela Meta' },
};
const waQuality = w =>
  WA_QUALITY[(w.quality || '').toUpperCase()] || {
    dot: '#94A3B8',
    label: 'status indisponível',
  };
const WA_TIERS = {
  TIER_50: '50/dia',
  TIER_250: '250/dia',
  TIER_1K: '1 mil/dia',
  TIER_10K: '10 mil/dia',
  TIER_100K: '100 mil/dia',
  TIER_UNLIMITED: 'sem limite',
};
const waTier = tier => WA_TIERS[tier] || null;

// ── 📊 Briefing do Gestor Autônomo (só admin — null para o time) ──
// O agente lê o funil todo dia contra a média de 12 semanas e deixa aqui
// o resumo do dia + os desvios encontrados (chips) + as tarefas abertas.
const managerBrief = computed(() => data.value?.manager_brief || null);
// até 4 frases — briefing é café, não relatório
const managerBriefText = computed(() => {
  const text = (managerBrief.value?.brief || '').trim();
  if (!text) return '';
  const sentences = text.match(/[^.!?]+[.!?]*/g) || [text];
  return sentences.slice(0, 4).join('').trim();
});
const managerFindings = computed(() => managerBrief.value?.findings || []);
// chip do desvio: "Taxa de comparecimento −38%"
const managerFindingLabel = f =>
  `${f.label || f.indicator} ${Number(f.deviation_pct) < 0 ? '−' : '+'}${Math.abs(Math.round(f.deviation_pct || 0))}%`;
const managerLastRunTime = computed(() => {
  const iso = managerBrief.value?.last_run_at;
  if (!iso) return '';
  return new Date(iso).toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
});

const radarSignature = computed(
  () =>
    `radar:${radarAlerts.value
      .map(a => a.conversation_id)
      .sort((a, b) => a - b)
      .join(',')}`
);
const tasksSignature = computed(
  () =>
    `tasks:${myTasks.value
      .map(t => t.id)
      .sort((a, b) => a - b)
      .join(',')}`
);

onMounted(() => {
  loadDismissedAvisos();
  store.dispatch('crm/fetchSettings').catch(() => {});
  loadRadarStatus();
  loadGoalsStrip();
  refreshAll();
  refreshTimer = setInterval(refreshAll, 120000);
  document.addEventListener('visibilitychange', onVisible);
});

onMounted(() => window.addEventListener('keydown', onKpiModalKey));
onUnmounted(() => {
  clearInterval(refreshTimer);
  document.removeEventListener('visibilitychange', onVisible);
  window.removeEventListener('keydown', onKpiModalKey);
  document.body.style.overflow = '';
});
</script>

<template>
  <div
    class="cv-page h-full w-full overflow-y-auto bg-n-surface-1"
    :style="cvVars"
  >
    <div class="max-w-5xl mx-auto p-4 sm:p-8">
      <!-- Boas-vindas (varredura de design 12/09): cabeçalho moderno — chips
           de vidro com o dia e o painel, saudação grande, lead do painel, o
           PULSO do momento em vidros clicáveis e o olho CEVICO como marca
           d'água. A cor continua sendo a do painel escolhido. -->
      <div
        class="cevico-hero rounded-3xl p-6 sm:p-8 text-white shadow-lg mb-6 relative overflow-hidden transition-all"
        :style="{ background: pagePalette.hero }"
      >
        <span class="cevico-hero-glow cevico-hero-glow-a" aria-hidden="true" />
        <span class="cevico-hero-glow cevico-hero-glow-b" aria-hidden="true" />
        <img
          :src="HERO_EYE"
          alt=""
          aria-hidden="true"
          class="cevico-hero-eye"
        />
        <div class="relative z-10 flex flex-col gap-4" style="color: #fff">
          <div class="flex items-start justify-between gap-3 flex-wrap">
            <div class="flex items-center gap-1.5 flex-wrap">
              <span class="cevico-hero-chip"><span class="i-lucide-calendar-days text-xs" />{{
                  todayLabel
                }}</span>
              <!-- 🍎🍊 a paleta do painel: cor do dia (iMac G3), uma fruta ou a
                   salada — o admin escolhe aqui; quem não é admin passeia
                   pelas cores do dia só nesta tela -->
              <button
                class="cevico-hero-chip cevico-hero-chip-btn"
                :title="
                  isAdmin
                    ? 'Paleta do painel: cor do dia, iMac G3, frutas da Apple ou salada de frutas — e a cor de cada bloco'
                    : 'Cada dia da semana tem a sua cor, inspirada nos iMac G3 (1998–99). Clique para experimentar as outras — só nesta tela.'
                "
                @click="openPalettePicker('panel')"
              >
                <span
                  class="w-2 h-2 rounded-full flex-shrink-0"
                  :style="{
                    background: pagePalette.swatch || pagePalette.dot,
                    boxShadow: '0 0 0 2px rgba(255,255,255,0.6)',
                  }"
                />
                {{ paletteLabel(pagePalette)
                }}<span
                  v-if="flavorPreview !== null && pagePalette === dayFlavor"
                  class="opacity-75 font-normal"
                >
                  · prévia</span>
                <span
                  v-if="isAdmin"
                  class="i-lucide-palette text-[10px] opacity-80"
                />
              </button>
              <span class="cevico-hero-chip" :title="currentPanel.desc">
                <span :class="currentPanel.icon" class="text-xs" />
                Painel de {{ currentPanel.label
                }}<template v-if="currentPanel.who">
                  · {{ currentPanel.who }}</template>
              </span>
              <!-- 🧑‍🤝‍🧑 painel por pessoa: o admin edita nome/pessoas daqui -->
              <button
                v-if="isAdmin && currentPanel.variant"
                class="cevico-hero-chip cevico-hero-chip-btn"
                title="Editar este painel por pessoa: nome, painel-base e quem vê"
                @click="openVariantModal(currentPanel.variantDef)"
              >
                <span class="i-lucide-pencil text-xs" />
                Editar painel
              </button>
            </div>
            <div class="flex items-center gap-1.5 flex-shrink-0">
              <!-- ✏️ MODO EDIÇÃO (item 143): o botão vive AQUI no topo, num
                   lugar fixo — liga o modo que reordena blocos, muda cor e
                   oculta cards; a barra grudada logo abaixo segura os controles -->
              <button
                v-if="isAdmin && !currentPanel.custom"
                class="cevico-hero-btn"
                :class="organizeMode ? 'cevico-hero-btn-on' : ''"
                :title="
                  organizeMode
                    ? 'Concluir a edição do painel'
                    : 'Personalizar este painel: arrastar blocos e cards, trocar cores, ocultar'
                "
                @click="toggleEditMode"
              >
                <span
                  :class="
                    organizeMode ? 'i-lucide-check' : 'i-lucide-pencil-ruler'
                  "
                  class="text-xs"
                />
                {{ organizeMode ? 'Concluir edição' : 'Modo edição' }}
              </button>
              <!-- 🐞 Reportar problema — padrão no painel de TODOS (pedido 17/07) -->
              <button
                class="cevico-hero-btn"
                title="Algo não funcionou? Vira um card no board do Guilherme e você recebe o aviso quando resolver."
                @click="reportBug"
              >
                <span class="i-lucide-bug text-xs" />
                Reportar problema
              </button>
            </div>
          </div>
          <div>
            <h1
              class="text-3xl sm:text-[40px] font-bold leading-none tracking-tight"
              style="color: #fff"
            >
              {{ greeting
              }}<template v-if="firstName">, {{ firstName }}</template>! 👋
            </h1>
            <p
              class="text-sm sm:text-[15px] mt-2.5 max-w-2xl leading-relaxed"
              style="color: rgba(255, 255, 255, 0.86)"
            >
              {{ heroLead }}
            </p>
          </div>
          <!-- 🌡️ o pulso do momento: números vivos em vidro, cada um leva
               pro lugar certo (conversas, agenda, radar) -->
          <div
            v-if="heroPulse.length"
            class="flex items-stretch gap-2 flex-wrap"
          >
            <button
              v-for="p in heroPulse"
              :key="p.key"
              class="cevico-hero-glass flex items-center gap-2.5 text-left"
              :class="p.alert ? 'cevico-hero-glass-alert' : ''"
              :title="p.title"
              @click="go(p.route)"
            >
              <span
                class="w-8 h-8 rounded-xl flex items-center justify-center flex-shrink-0"
                style="background: rgba(255, 255, 255, 0.16)"
              >
                <span :class="p.icon" class="text-base" />
              </span>
              <span class="flex flex-col leading-none">
                <span class="text-lg font-bold tabular-nums">{{
                  p.value
                }}</span>
                <span
                  class="text-[11px] mt-1"
                  style="color: rgba(255, 255, 255, 0.82)"
                  >{{ p.label }}</span>
              </span>
            </button>
          </div>
        </div>
      </div>

      <!-- ✏️ BARRA DO MODO EDIÇÃO (item 143): gruda no topo enquanto o modo
           está ativo — dicas, cards ocultos, voltar ao padrão e Concluir
           sempre à mão, em qualquer ponto da rolagem -->
      <div
        v-if="organizeMode"
        class="cv-editbar sticky top-0 z-40 px-4 py-3 mb-6"
      >
        <div class="flex items-center gap-2 flex-wrap">
          <span class="cv-icon cv-icon-sm"><span class="i-lucide-pencil-ruler text-xs"/></span>
          <b class="text-xs text-n-slate-12">Modo edição</b>
          <span class="text-[11px] text-n-slate-10">⠿ arraste as barrinhas e os cards · 🖌 troca a cor · ✕ oculta</span>
          <button
            class="cv-btn cv-btn-ghost cv-btn-sm"
            title="Cores do painel: cor do dia, uma paleta fixa (iMac G3 ou frutas da Apple) ou salada de frutas — e a paleta de cada bloco"
            @click="openPalettePicker('panel')"
          >
            <span class="i-lucide-palette text-xs" />
            Paleta
          </button>
          <span
            v-if="isSavingLayout"
            class="i-lucide-loader-circle animate-spin text-sm text-n-slate-10"
          />
          <span v-else class="text-[10px] text-n-slate-9">salva sozinho</span>
          <span class="flex-1" />
          <button
            v-if="layoutTouched"
            class="cv-btn cv-btn-ghost cv-btn-sm"
            title="Ordem dos blocos, cards, cores e ocultos voltam ao padrão do sistema neste painel"
            @click="resetKpiLayout"
          >
            voltar ao padrão
          </button>
          <button class="cv-btn cv-btn-sm" @click="toggleEditMode">
            <span class="i-lucide-check text-xs" />
            Concluir
          </button>
        </div>
        <div
          v-if="hiddenTiles.length"
          class="flex items-center gap-1.5 flex-wrap mt-2 text-[11px]"
        >
          <span class="text-n-slate-9">cards ocultos:</span>
          <button
            v-for="t in hiddenTiles"
            :key="t.id"
            class="cv-chip"
            title="Mostrar de novo"
            @click="restoreTile(t)"
          >
            <span class="i-lucide-plus text-[10px]" />{{ t.label }}
          </button>
        </div>
      </div>

      <!-- SKELETON Homem de Ferro (item 89): o painel se monta por partes -->
      <div v-if="isLoading" class="space-y-6">
        <SkeletonPiece variant="block" class="h-28" :order="0" />
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <SkeletonPiece variant="block" class="h-36" :order="1" />
          <SkeletonPiece variant="block" class="h-36" :order="2" />
          <SkeletonPiece variant="block" class="h-36" :order="3" />
        </div>
        <div class="flex items-center gap-2 flex-wrap">
          <SkeletonPiece
            v-for="i in 5"
            :key="`pp${i}`"
            variant="pill"
            :order="3 + i"
          />
        </div>
        <div class="flex items-center gap-2 flex-wrap">
          <SkeletonPiece
            v-for="i in 6"
            :key="`per${i}`"
            variant="pill"
            class="!h-7 !w-20"
            :order="8 + i"
          />
        </div>
        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <SkeletonPiece
            v-for="i in 4"
            :key="`t${i}`"
            variant="tile"
            class="!h-36"
            :order="14 + i"
          />
        </div>
        <SkeletonPiece variant="block" class="h-64" :order="19" />
      </div>

      <template v-else>
        <!-- 🌈 Novidade: cada pessoa pode escolher as cores do seu painel (nota
             dispensável; some ao clicar e não volta neste navegador) -->
        <div v-if="showDopamineNote" class="cv-block cv-notice-dopamine mb-10">
          <div class="p-6 sm:p-8 flex items-start gap-4">
            <span
              class="cv-notice-dopamine-orb flex-shrink-0"
              aria-hidden="true"
              >🌈</span>
            <div class="min-w-0 flex-1">
              <h2
                class="text-xl sm:text-2xl font-bold text-n-slate-12 tracking-tight leading-tight"
              >
                Seu painel, as suas cores
              </h2>
              <p class="text-sm text-n-slate-11 mt-2 leading-relaxed max-w-2xl">
                Novidade fofa: agora cada pessoa escolhe a paleta do próprio
                painel. Toque na bolinha colorida ali em cima, no cabeçalho, e
                experimente as cores dos iMac G3, as frutas da Apple ou a salada
                de frutas. É só seu, ninguém mais vê — e dá pra trocar quantas
                vezes quiser. Cor boa é dopamina de graça. 💜🍊🍋
              </p>
              <div class="flex items-center gap-2 flex-wrap mt-4">
                <button
                  class="cv-btn cv-btn-sm"
                  @click="openPalettePicker('panel')"
                >
                  <span class="i-lucide-palette text-xs" />
                  Escolher minhas cores
                </button>
                <button
                  class="cv-btn cv-btn-sm cv-btn-ghost"
                  @click="dismissDopamineNote"
                >
                  Entendi, valeu!
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- 🎉 Seus reports de bug resolvidos (notificação p/ quem reportou) -->
        <div
          v-if="data?.bug_reports?.resolved?.length"
          class="cv-block cv-green mb-6"
        >
          <div class="p-4 sm:p-5">
            <div class="flex items-center gap-2 mb-2">
              <span class="cv-icon"><span class="i-lucide-party-popper text-base"/></span>
              <h2 class="text-sm font-bold text-n-slate-12">
                {{
                  data.bug_reports.resolved.length === 1
                    ? 'Um problema que você reportou foi resolvido!'
                    : `${data.bug_reports.resolved.length} problemas que você reportou foram resolvidos!`
                }}
              </h2>
            </div>
            <div class="space-y-1.5">
              <p
                v-for="r in data.bug_reports.resolved"
                :key="r.id"
                class="cv-sub text-xs text-n-slate-11 px-3 py-2"
              >
                ✅ {{ r.title }}
                <span class="text-n-slate-9">— resolvido
                  {{ new Date(r.completed_at).toLocaleDateString('pt-BR') }}.
                  Obrigado por avisar! 💙</span>
              </p>
            </div>
          </div>
        </div>

        <!-- ⠿ BLOCOS MÓVEIS (item 143) — área de AVISOS (acima do seletor
             de painel): no modo organizar, cada bloco ganha a barrinha de
             arrasto e pode trocar de lugar — inclusive cruzar pra área de
             conteúdo lá embaixo (mesmo grupo do vuedraggable) -->
        <draggable
          v-model="dragTopBlocks"
          :item-key="id => id"
          handle=".cevico-block-handle"
          :animation="220"
          :disabled="!organizeMode"
          ghost-class="opacity-30"
          @end="saveBlockLayout"
        >
          <template #item="{ element: blockId }">
            <section :style="blockVars(blockId)">
              <div
                v-if="organizeMode"
                class="cevico-block-handle cv-handle cursor-grab active:cursor-grabbing flex items-center gap-2.5 px-4 py-2.5 mb-2 text-xs font-semibold"
              >
                <span class="i-lucide-grip-vertical text-sm opacity-60" />
                <span class="cv-icon cv-icon-sm"><span :class="BLOCK_ICONS[blockId]"
class="text-xs"/></span>
                {{ BLOCK_LABELS[blockId] }}
                <button
                  v-if="isAdmin"
                  class="cv-chip"
                  :title="`Paleta deste bloco (hoje: ${paletteLabel(blockPalette(blockId))}) — clique para trocar`"
                  @pointerdown.stop
                  @mousedown.stop
                  @click.stop="openPalettePicker(blockId)"
                >
                  <span
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :style="{
                      background:
                        blockPalette(blockId).swatch ||
                        blockPalette(blockId).dot,
                      boxShadow: '0 0 0 1.5px rgba(255,255,255,0.8)',
                    }"
                  />
                  <span class="i-lucide-palette text-[10px]" />
                  {{ blockPalette(blockId).label }}
                </button>
                <span
                  class="text-n-slate-9 font-normal ml-auto hidden sm:inline"
                  >⠿ arraste pra mudar a ordem</span>
              </div>

              <!-- no modo edição os blocos RECOLHEM em barrinhas: arrasto curto,
                 sem rolagem infinita no meio do movimento -->
              <template v-if="!organizeMode">
                <template v-if="blockId === 'whatsapp'">
                  <!-- 💬 Números de WhatsApp (item 88 v2 — pedido 20/07): faixa MINI
             e discreta com o STATUS DA CONTA na Meta; fica vermelha só
             quando existe problema de verdade -->
                  <div
                    v-if="whatsappStatus"
                    class="cv-block cv-strip flex items-center gap-x-3 gap-y-1 flex-wrap mb-6 px-3.5 py-2 text-[11px]"
                    :class="waProblem ? 'cv-red' : ''"
                    title="Status das contas de WhatsApp na Meta (atualiza a cada 10 min) — detalhes em Relatórios → Saúde do WhatsApp"
                  >
                    <span class="cv-icon cv-icon-sm"><span class="i-lucide-phone text-xs"/></span>
                    <span
                      v-for="w in whatsappStatus"
                      :key="w.id"
                      class="inline-flex items-center gap-1.5 text-n-slate-11 min-w-0"
                    >
                      <span
                        class="w-2 h-2 rounded-full flex-shrink-0"
                        :style="{
                          background: w.reauthorization_required
                            ? '#EF4444'
                            : waQuality(w).dot,
                        }"
                      />
                      <b class="text-n-slate-12 truncate">{{
                        w.verified_name || w.name
                      }}</b>
                      <span
                        v-if="w.reauthorization_required"
                        class="text-red-500 font-bold whitespace-nowrap"
                        >precisa reautorizar</span>
                      <template v-else>
                        <span class="text-n-slate-9 whitespace-nowrap">{{
                          waQuality(w).label
                        }}</span>
                        <span
                          v-if="waTier(w.limit_tier)"
                          class="text-n-slate-9 whitespace-nowrap"
                          >· limite {{ waTier(w.limit_tier) }}</span>
                        <span
                          v-if="w.failed_24h"
                          class="text-amber-600 whitespace-nowrap"
                          >· {{ w.failed_24h }} falha(s) 24h</span>
                      </template>
                    </span>
                  </div>
                </template>

                <template v-else-if="blockId === 'briefing'">
                  <!-- 📊 Briefing do Gestor Autônomo (só admin): o resumo do dia +
             os desvios do funil vs a média de 12 semanas. Sem briefing
             escrito, o card fica discreto e mostra só os desvios. -->
                  <div
                    v-if="
                      managerBrief &&
                      (managerBriefText || managerFindings.length)
                    "
                    class="cv-block mb-6"
                  >
                    <div class="p-4 sm:p-5">
                      <div class="flex items-center gap-2 mb-2 flex-wrap">
                        <span class="cv-icon">
                          <span class="i-lucide-gauge text-base" />
                        </span>
                        <h2 class="text-sm font-bold text-n-slate-12">
                          Briefing do Gestor
                        </h2>
                        <span class="text-[11px] text-n-slate-9 ml-auto">funil de hoje vs a média de 12 semanas</span>
                      </div>

                      <p
                        v-if="managerBriefText"
                        class="text-sm text-n-slate-11 leading-relaxed mb-2"
                      >
                        {{ managerBriefText }}
                      </p>

                      <div
                        v-if="managerFindings.length"
                        class="flex flex-wrap gap-1.5 mb-2"
                      >
                        <span
                          v-for="(f, fi) in managerFindings"
                          :key="fi"
                          class="cv-chip cv-red"
                          :title="f.window ? `janela: ${f.window}` : ''"
                        >
                          {{ managerFindingLabel(f) }}
                        </span>
                      </div>

                      <p class="text-[11px] text-n-slate-9">
                        abriu {{ managerBrief.tasks_opened || 0 }} tarefa(s)
                        hoje<template v-if="managerLastRunTime">
                          · {{ managerLastRunTime }}
                        </template>
                      </p>
                    </div>
                  </div>
                </template>

                <template v-else-if="blockId === 'radar'">
                  <!-- 💚 Avisos do Radar de Oportunidades — cartão BRANCO (contraste
             nos dois temas) + verde dopamine + botão que emana energia
             (pedido 17/07: convite, não bronca) -->
                  <div
                    v-if="radarQueue.length && !avisoChecado(radarSignature)"
                    class="cv-block mb-6"
                  >
                    <div class="p-4 sm:p-5">
                      <div class="flex items-center gap-2 mb-3 flex-wrap">
                        <span class="cv-icon">
                          <span class="i-lucide-radar text-base" />
                        </span>
                        <h2 class="text-sm font-bold text-n-slate-12">
                          {{
                            radarQueue.length === 1
                              ? '1 paciente quente sem atendimento'
                              : `${radarQueue.length} pacientes quentes sem atendimento`
                          }}
                        </h2>
                        <!-- 📈 eficácia (item 83): o Radar gerando consulta de verdade -->
                        <span
                          v-if="radarEfficacy"
                          class="cv-chip cv-green"
                          :title="`Dos ${radarEfficacy.attended_30d} avisos atendidos nos últimos 30 dias, ${radarEfficacy.converted_30d} paciente(s) agendaram consulta depois do aviso`"
                        >
                          <span class="i-lucide-trending-up text-xs" />{{
                            radarEfficacy.converted_30d
                          }}
                          consulta(s) geradas · {{ radarEfficacy.rate }}%
                        </span>
                        <span
                          v-if="radarLastRun"
                          class="text-[11px] ml-auto text-n-slate-9"
                          >auditoria às {{ radarLastRun }}</span>
                        <button
                          v-if="radarStatus && isAdmin"
                          class="cv-btn cv-btn-ghost cv-btn-sm"
                          :title="radarLastActionLabel"
                          :disabled="togglingRadar"
                          @click="toggleRadarManual"
                        >
                          <span
                            :class="
                              radarStatus.enabled
                                ? 'i-lucide-pause'
                                : 'i-lucide-play'
                            "
                            class="text-xs"
                          />
                          {{
                            radarStatus.enabled
                              ? 'Pausar radar'
                              : 'Reativar radar'
                          }}
                        </button>
                        <button
                          class="cv-btn cv-btn-ghost cv-iconbtn flex-shrink-0"
                          title="Dar check: esconder este aviso (volta quando o Radar tiver novidade)"
                          @click="checkAviso(radarSignature)"
                        >
                          <span class="i-lucide-check text-sm" />
                        </button>
                      </div>
                      <!-- CARROSSEL pulsante (item 63): a pilha espia atrás (nome +
                 tempo) e o card da frente mostra tudo — CRM, etiquetas,
                 contexto e o botão convidativo -->
                      <div
                        class="relative max-w-2xl mx-auto"
                        :style="{
                          paddingTop: `${radarPeek.length * 14 + 2}px`,
                        }"
                      >
                        <!-- pilha de trás -->
                        <div
                          v-for="(p, i) in radarPeek"
                          :key="`peek-${p.conversation_id}`"
                          class="absolute left-1/2 -translate-x-1/2 rounded-xl border flex items-center gap-2 px-3 h-8 cursor-pointer"
                          :style="{
                            top: `${(radarPeek.length - 1 - i) * 14}px`,
                            width: `calc(100% - ${(i + 1) * 36}px)`,
                            zIndex: 3 - i,
                            background: '#fbfdfc',
                            borderColor: '#dbe7e1',
                            opacity: String(0.85 - i * 0.18),
                          }"
                          :title="`Trazer ${p.contact_name} para a frente`"
                          @click="rotateRadar"
                        >
                          <span
                            class="text-[11px] font-semibold truncate"
                            style="color: #334155"
                            >{{ p.contact_name }}</span>
                          <span
                            class="text-[10px] ml-auto flex-shrink-0"
                            style="color: #047857"
                            >{{ waitingLabel(p) }}</span>
                        </div>

                        <!-- card da FRENTE (pulsa como Tarefas 100%) -->
                        <div
                          v-if="radarFront"
                          :key="`front-${radarFront.conversation_id}`"
                          class="cevico-radar-front relative z-10 rounded-xl p-3 cursor-pointer flex flex-col gap-2 bg-white"
                          @click="openChatBalloon(radarFront)"
                        >
                          <div class="flex items-center gap-2">
                            <div
                              class="w-7 h-7 rounded-full flex items-center justify-center text-white text-[10px] font-semibold flex-shrink-0"
                              style="
                                background: linear-gradient(
                                  135deg,
                                  #059669,
                                  #4ade80
                                );
                              "
                            >
                              {{ alertInitials(radarFront) }}
                            </div>
                            <div class="flex-1 min-w-0">
                              <p
                                class="text-sm font-semibold truncate leading-tight"
                                style="color: #0f172a"
                              >
                                {{ radarFront.contact_name }}
                              </p>
                              <p
                                v-if="radarFront.phone"
                                class="text-xs truncate"
                                style="color: #64748b"
                              >
                                {{ radarFront.phone }}
                              </p>
                            </div>
                            <span
                              class="inline-flex items-center gap-1 text-[11px] font-semibold rounded-full px-2 py-0.5 flex-shrink-0"
                              style="
                                background: rgba(16, 185, 129, 0.12);
                                color: #047857;
                                border: 1px solid rgba(16, 185, 129, 0.3);
                              "
                            >
                              <span class="i-lucide-clock text-[11px]" />
                              {{ waitingLabel(radarFront) }}
                            </span>
                          </div>
                          <div
                            v-if="
                              alertKindMeta(radarFront) ||
                              radarFront.stage_name ||
                              radarFront.user_name
                            "
                            class="flex flex-wrap gap-1"
                          >
                            <span
                              v-if="alertKindMeta(radarFront)"
                              class="inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded font-semibold text-white"
                              :style="{
                                background: alertKindMeta(radarFront).color,
                              }"
                            >
                              <span
                                :class="alertKindMeta(radarFront).icon"
                                class="text-[11px]"
                              />
                              {{ alertKindMeta(radarFront).label }}
                            </span>
                            <span
                              v-if="radarFront.stage_name"
                              class="inline-flex items-center gap-1 text-xs px-1.5 py-0.5 rounded"
                              style="background: #eef2f7; color: #475569"
                            >
                              <span
                                class="w-1.5 h-1.5 rounded-full flex-shrink-0"
                                style="background: #059669"
                              />
                              {{ radarFront.stage_name }}
                            </span>
                            <span
                              v-if="radarFront.user_name"
                              class="text-xs px-1.5 py-0.5 rounded font-medium"
                              style="
                                background: rgba(212, 160, 23, 0.14);
                                color: #92600a;
                              "
                              >📌 para {{ radarFront.user_name }}</span>
                          </div>
                          <div
                            class="rounded-r-lg px-2 py-1.5"
                            style="
                              background: #f8fafc;
                              border-left: 2px solid #10b981;
                            "
                          >
                            <p
                              class="text-xs leading-snug"
                              style="color: #475569"
                            >
                              {{ radarFront.motivo }}
                            </p>
                          </div>
                          <p class="text-xs" style="color: #475569">
                            💡 <b style="color: #0f172a">O que fazer:</b>
                            {{ radarFront.acao }}
                          </p>
                          <div
                            class="flex items-center justify-between gap-1 mt-auto"
                          >
                            <div class="flex items-center gap-1">
                              <button
                                v-if="radarFront.contact_id"
                                class="flex items-center justify-center w-8 h-8 rounded-lg transition-transform hover:scale-110"
                                title="Espaço do Paciente"
                                @click.stop="openPatientSpace(radarFront)"
                              >
                                <PatientSpaceIcon :size="24" />
                              </button>
                              <button
                                class="flex items-center justify-center w-8 h-8 rounded-lg transition-transform hover:scale-110"
                                style="
                                  color: #2563eb;
                                  background: rgba(37, 99, 235, 0.1);
                                "
                                title="Abrir conversa"
                                @click.stop="openChatBalloon(radarFront)"
                              >
                                <span
                                  class="i-lucide-message-circle-more text-lg"
                                />
                              </button>
                            </div>
                            <div class="flex items-center gap-1.5">
                              <button
                                v-if="radarQueue.length > 1"
                                class="text-[11px] font-medium px-2.5 py-1.5 rounded-full border transition-colors hover:bg-slate-50"
                                style="border-color: #e2e8f0; color: #64748b"
                                title="Deixar para depois — vai para o fim da fila"
                                @click.stop="rotateRadar"
                              >
                                pular ↷
                              </button>
                              <button
                                v-if="isAgentAlert(radarFront)"
                                class="text-[11px] font-semibold px-2.5 py-1.5 rounded-full border transition-colors hover:bg-slate-50"
                                style="border-color: #bfdbfe; color: #1d4ed8"
                                title="Conferir a consulta na Agenda"
                                @click.stop="openAgendaFromAlert(radarFront)"
                              >
                                📅 Agenda
                              </button>
                              <button
                                class="cevico-energy-btn text-xs font-bold text-white px-3.5 py-1.5 rounded-lg"
                                @click.stop="attendNow(radarFront, $event)"
                              >
                                {{
                                  isAgentAlert(radarFront)
                                    ? 'Ver conversa →'
                                    : 'Atender agora →'
                                }}
                              </button>
                            </div>
                          </div>
                        </div>

                        <p
                          v-if="radarQueue.length > 4"
                          class="text-center text-[11px] mt-1.5 text-n-slate-9"
                        >
                          +{{ radarQueue.length - 4 }} na fila
                        </p>
                      </div>
                    </div>
                  </div>
                </template>

                <template v-else-if="blockId === 'tarefas'">
                  <!-- 📋 Tarefas esperando você + 📝 notas dos pacientes (item 211):
                       duas colunas, listas roláveis — cabe muito mais de 10 -->
                  <div
                    v-if="
                      tasksBoxAlways ||
                      ((myTasks.length || patientNotes.length) &&
                        !avisoChecado(tasksSignature))
                    "
                    class="cv-block mb-6"
                  >
                    <div class="p-4 sm:p-5">
                      <div class="flex items-center gap-2 mb-3 flex-wrap min-h-[30px]">
                        <span class="cv-icon cv-icon-sm">
                          <span class="i-lucide-list-checks text-sm" />
                        </span>
                        <h2 class="text-sm font-bold text-n-slate-12 leading-none">
                          Tarefas e notas
                        </h2>
                        <span class="cv-chip tabular-nums" :class="myTasksCount ? '' : 'cv-slate'">
                          {{ myTasksCount }} {{ myTasksCount === 1 ? 'tarefa' : 'tarefas' }}
                        </span>
                        <span class="cv-chip cv-slate tabular-nums">
                          {{ patientNotes.length }} {{ patientNotes.length === 1 ? 'nota' : 'notas' }}
                        </span>
                        <button
                          class="cv-btn cv-btn-ghost cv-btn-sm ml-auto"
                          title="Escrever um recado sobre um paciente"
                          @click="showNoteForm = !showNoteForm"
                        >
                          <span class="i-lucide-sticky-note text-xs" />
                          Nova nota
                        </button>
                        <button class="cv-btn cv-btn-sm" @click="goToTasks">
                          Abrir Tarefas
                          <span class="i-lucide-arrow-right text-xs" />
                        </button>
                        <button
                          v-if="!tasksBoxAlways"
                          class="cv-btn cv-btn-ghost cv-iconbtn flex-shrink-0"
                          title="Dar check: esconder este aviso (volta quando houver tarefa nova)"
                          @click="checkAviso(tasksSignature)"
                        >
                          <span class="i-lucide-check text-sm" />
                        </button>
                      </div>

                      <div v-if="showNoteForm" class="cv-sub p-3.5 mb-3">
                        <PatientNoteForm compact @saved="onPanelNoteSaved" @cancel="showNoteForm = false" />
                      </div>

                      <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
                        <!-- TAREFAS: uma linha por tarefa, lista rolável -->
                        <div class="min-w-0">
                          <p class="cv-label mb-1.5 flex items-center gap-1.5">
                            <span class="i-lucide-circle-dot text-[11px]" /> esperando você
                          </p>
                          <p v-if="!myTasks.length" class="text-xs text-n-slate-9 py-3 text-center cv-sub">
                            Nada esperando você agora. ✨
                          </p>
                          <div v-else class="space-y-1 max-h-[22rem] overflow-y-auto pr-1">
                            <button
                              v-for="task in myTasks"
                              :key="task.id"
                              class="cv-sub cv-sub-hover w-full flex items-center gap-2 px-3 py-1.5 text-left min-w-0"
                              @click="goToTasks"
                            >
                              <span
                                class="w-2 h-2 rounded-full flex-shrink-0"
                                :style="{ background: TASK_DOT[task.priority] || TASK_DOT.medium }"
                                :title="TASK_PRIORITY_LABEL[task.priority] || task.priority"
                              />
                              <span class="text-[13px] font-medium text-n-slate-12 truncate min-w-0 flex-1">
                                {{ task.title }}
                              </span>
                              <span
                                v-if="task.comments_count"
                                class="text-[10px] text-n-slate-9 inline-flex items-center gap-0.5 flex-shrink-0"
                                ><span class="i-lucide-message-circle text-[10px]" />{{ task.comments_count }}</span>
                              <span
                                v-if="task.creator_name"
                                class="text-[10px] text-n-slate-9 flex-shrink-0 hidden sm:inline"
                                >de {{ task.creator_name.split(' ')[0] }}</span>
                              <span
                                v-if="task.due_at"
                                class="cv-chip !h-5 !px-1.5 text-[10px] flex-shrink-0 tabular-nums"
                                :class="new Date(task.due_at) < new Date() ? 'cv-red' : ''"
                                ><span class="i-lucide-alarm-clock text-[10px]" />{{ fmtTaskDue(task.due_at) }}</span>
                            </button>
                          </div>
                          <p v-if="myTasksCount > myTasks.length" class="text-[10px] text-n-slate-9 mt-1.5 text-right">
                            mostrando {{ myTasks.length }} de {{ myTasksCount }} — as outras estão em Tarefas
                          </p>
                        </div>

                        <!-- NOTAS DOS PACIENTES: as mais recentes da clínica -->
                        <div class="min-w-0">
                          <p class="cv-label mb-1.5 flex items-center gap-1.5">
                            <span class="i-lucide-sticky-note text-[11px]" /> notas dos pacientes
                          </p>
                          <p v-if="!patientNotes.length" class="text-xs text-n-slate-9 py-3 text-center cv-sub">
                            Nenhuma nota ainda — escreva a primeira em "Nova nota".
                          </p>
                          <div v-else class="space-y-1.5 max-h-[22rem] overflow-y-auto pr-1">
                            <div
                              v-for="note in patientNotes"
                              :key="note.id"
                              class="cv-sub px-3 py-2 min-w-0"
                            >
                              <div class="flex items-center gap-2 min-w-0">
                                <button
                                  class="text-[13px] font-semibold text-n-slate-12 truncate hover:underline text-left"
                                  title="Abrir o Espaço do Paciente"
                                  @click="openPatientFromNote(note)"
                                >
                                  {{ note.contact?.name || 'Paciente' }}
                                </button>
                                <span class="text-[10px] text-n-slate-9 ml-auto whitespace-nowrap tabular-nums">{{ fmtNoteAt(note.created_at) }}</span>
                                <button
                                  v-if="note.mine || isAdmin"
                                  class="text-n-slate-9 hover:text-red-500 flex-shrink-0"
                                  title="Apagar a nota"
                                  @click="deletePanelNote(note)"
                                >
                                  <span class="i-lucide-trash-2 text-[11px]" />
                                </button>
                              </div>
                              <p class="text-xs text-n-slate-11 leading-snug break-words line-clamp-2">{{ note.content }}</p>
                              <p class="text-[10px] text-n-slate-9">por {{ note.author_name?.split(' ')[0] || 'equipe' }}</p>
                            </div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </template>

                <template v-else-if="blockId === 'mentor'">
                  <!-- 🧭 Mentor do Time: feedback da semana (individual; admin vê o time) -->
                  <div
                    v-if="visibleFeedback && !avisoChecado(fbSignature)"
                    class="cv-block mb-6"
                  >
                    <div class="p-4 sm:p-5">
                      <div class="flex items-center gap-2 mb-3 flex-wrap">
                        <span class="cv-icon">
                          <span class="i-lucide-graduation-cap text-base" />
                        </span>
                        <h2 class="text-sm font-bold text-n-slate-12">
                          {{
                            visibleFeedback.user_id === currentUser.id
                              ? 'Seu feedback da semana'
                              : `Feedback de ${visibleFeedback.user_name}`
                          }}
                        </h2>
                        <span class="text-[11px] text-n-slate-9 ml-auto">{{
                          fbWeekLabel(visibleFeedback)
                        }}</span>
                        <button
                          class="cv-btn cv-btn-ghost cv-iconbtn flex-shrink-0"
                          title="Dar check: li meu feedback, pode esconder (volta na próxima semana)"
                          @click="checkAviso(fbSignature)"
                        >
                          <span class="i-lucide-check text-sm" />
                        </button>
                      </div>

                      <!-- admin: navega pelo time -->
                      <div
                        v-if="isAdmin && teamFeedbacks.length > 1"
                        class="cv-seg cv-seg-sm flex-wrap mb-3"
                      >
                        <button
                          v-for="fb in teamFeedbacks"
                          :key="fb.user_id"
                          class="cv-seg-item"
                          :class="
                            visibleFeedback.user_id === fb.user_id
                              ? 'cv-seg-on'
                              : ''
                          "
                          @click="feedbackViewUserId = fb.user_id"
                        >
                          {{ fb.user_name.split(' ')[0] }}
                        </button>
                      </div>

                      <p class="text-sm text-n-slate-11 leading-relaxed mb-3">
                        {{ visibleFeedback.feedback.resumo }}
                      </p>

                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2.5 mb-3">
                        <div class="cv-sub cv-green p-3">
                          <p class="cv-label mb-1 flex items-center gap-1">
                            <span class="i-lucide-thumbs-up text-xs" />Ponto
                            forte
                          </p>
                          <p class="text-xs text-n-slate-11 leading-snug">
                            {{ visibleFeedback.feedback.ponto_forte }}
                          </p>
                        </div>
                        <div class="cv-sub cv-amber p-3">
                          <p class="cv-label mb-1 flex items-center gap-1">
                            <span class="i-lucide-wrench text-xs" />O ponto a
                            corrigir
                          </p>
                          <p class="text-xs text-n-slate-11 leading-snug">
                            {{ visibleFeedback.feedback.ponto_fraco }}
                          </p>
                        </div>
                      </div>

                      <div
                        v-if="visibleFeedback.feedback.solucoes?.length"
                        class="space-y-1.5 mb-3"
                      >
                        <p class="cv-label">Soluções simples desta semana</p>
                        <div
                          v-for="(sol, si) in visibleFeedback.feedback.solucoes"
                          :key="si"
                          class="cv-sub flex items-start gap-2 px-3 py-2"
                        >
                          <span
                            class="cv-icon text-[10px] font-bold mt-0.5"
                            style="
                              width: 20px;
                              height: 20px;
                              border-radius: 9999px;
                            "
                          >
                            {{ si + 1 }}
                          </span>
                          <div class="min-w-0">
                            <p class="text-xs font-semibold text-n-slate-12">
                              {{ sol.titulo }}
                            </p>
                            <p class="text-xs text-n-slate-10 leading-snug">
                              {{ sol.como_fazer }}
                            </p>
                          </div>
                        </div>
                      </div>

                      <p
                        v-if="visibleFeedback.feedback.incentivo"
                        class="text-xs italic"
                        style="color: var(--cv-deep)"
                      >
                        {{ visibleFeedback.feedback.incentivo }}
                      </p>
                    </div>
                  </div>
                </template>
              </template>
            </section>
          </template>
        </draggable>

        <!-- Seletor de painel (cada pessoa no seu) -->
        <div class="flex items-center gap-2 flex-wrap mb-3">
          <div class="cv-seg overflow-x-auto">
            <button
              v-for="p in visiblePanels"
              :key="p.key"
              class="cv-seg-item"
              :class="selectedPanel === p.key ? 'cv-seg-on' : ''"
              @click="setPanel(p.key)"
            >
              <span :class="p.icon" class="text-sm" />
              {{ p.label }}<template v-if="p.who"> · {{ p.who }}</template>
            </button>
            <button
              v-if="isAdmin"
              class="cv-seg-item cv-seg-icon"
              title="Definir qual painel cada pessoa vê"
              @click="openAssignModal"
            >
              <span class="i-lucide-settings-2 text-sm" />
            </button>
            <button
              v-if="isAdmin"
              class="cv-seg-item cv-seg-icon"
              title="Metas do painel (os cards mudam de cor contra a meta)"
              @click="openGoalsModal"
            >
              <span class="i-lucide-target text-sm" />
            </button>
            <!-- 🧑‍🤝‍🧑 painel por pessoa (rodada 160): versão de um painel-base
                 com layout próprio, para uma ou mais pessoas do time -->
            <button
              v-if="isAdmin"
              class="cv-seg-item"
              title="Criar um painel para uma pessoa: escolhe o painel-base e quem vê; depois organiza blocos e cards no Modo edição"
              @click="openVariantModal()"
            >
              <span class="i-lucide-user-plus text-sm" />
              Painel por pessoa
            </button>
          </div>
          <!-- atalho pro Dashboard da Agenda em TODOS os painéis (item 86) -->
          <button
            class="cv-btn"
            title="Dashboard da Agenda — comparecimento, ocupação, cirurgias"
            @click="goToAgendaDashboard"
          >
            <span class="i-lucide-calendar-range text-sm" />
            Dashboard da Agenda
          </button>
          <!-- pílulas de médico (só no painel Médicos) -->
          <div v-if="panelBase === 'medico'" class="cv-seg overflow-x-auto">
            <button
              class="cv-seg-item"
              :class="!selectedDoctor ? 'cv-seg-on' : ''"
              @click="setDoctor('')"
            >
              Todos
            </button>
            <button
              v-for="doc in DOCTORS"
              :key="doc.name"
              class="cv-seg-item"
              :class="selectedDoctor === doc.name ? 'cv-seg-on' : ''"
              :style="
                selectedDoctor === doc.name ? { background: doc.color } : {}
              "
              @click="setDoctor(doc.name)"
            >
              {{ doc.short || doc.name }}
            </button>
          </div>
        </div>

        <!-- Régua de período PADRÃO (presets + Personalizado De/Até) -->
        <div class="mb-4 max-w-full">
          <PeriodRuler v-model="period" glass class="max-w-full" />
        </div>

        <!-- ✈️ GESTOR: o indicador de decisão — posso viajar ou é ação imediata? -->
        <div
          v-if="panelBase === 'gestor' && data"
          class="cv-modal-head rounded-3xl shadow-lg mb-4 !p-5"
          :style="{ background: gestorVerdict.grad }"
        >
          <div>
            <div class="flex items-center gap-3 flex-wrap">
              <div class="flex-1 min-w-[220px]">
                <p class="text-lg font-bold">{{ gestorVerdict.title }}</p>
                <p class="text-xs text-white/80 mt-0.5">
                  {{ gestorVerdict.sub }}
                </p>
              </div>
              <span class="cv-glass-chip">
                {{
                  gestorSignals.length
                    ? `${gestorSignals.length} aviso(s)`
                    : 'nenhum aviso'
                }}
              </span>
            </div>
            <!-- central de avisos: os motivos, prontos para agir -->
            <div v-if="gestorSignals.length" class="mt-3 space-y-1.5">
              <div
                v-for="(sig, si) in gestorSignals"
                :key="si"
                class="cv-glass flex items-center gap-2 px-3 py-2 text-xs"
              >
                <span :class="sig.icon" class="text-sm shrink-0" />
                <span class="flex-1">{{ sig.text }}</span>
                <span
                  class="w-2 h-2 rounded-full shrink-0"
                  :style="{
                    background:
                      sig.level === 'red'
                        ? '#FCA5A5'
                        : sig.level === 'amber'
                          ? '#FDE68A'
                          : '#BAE6FD',
                  }"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Painel do CONSTRUTOR (custom:<id>): a grade montada pelo gestor
             substitui as tiles fixas; o resto da página continua igual -->
        <CustomPanelGrid
          v-if="currentPanel.custom"
          :widgets="currentPanel.panelDef.widgets"
          :palette="currentPanel.panelDef.palette"
          :home="data"
          :goals="goalsData"
          class="mb-6"
        />

        <!-- ⠿ BLOCOS MÓVEIS (item 143) — área de CONTEÚDO: os blocos abaixo
             do seletor se movem com o mesmo arrasto magnético dos cards -->
        <draggable
          v-model="dragMainBlocks"
          :item-key="id => id"
          handle=".cevico-block-handle"
          :animation="220"
          :disabled="!organizeMode"
          ghost-class="opacity-30"
          @end="saveBlockLayout"
        >
          <template #item="{ element: blockId }">
            <section :style="blockVars(blockId)">
              <div
                v-if="organizeMode"
                class="cevico-block-handle cv-handle cursor-grab active:cursor-grabbing flex items-center gap-2.5 px-4 py-2.5 mb-2 text-xs font-semibold"
              >
                <span class="i-lucide-grip-vertical text-sm opacity-60" />
                <span class="cv-icon cv-icon-sm"><span :class="BLOCK_ICONS[blockId]"
class="text-xs"/></span>
                {{ BLOCK_LABELS[blockId] }}
                <button
                  v-if="isAdmin"
                  class="cv-chip"
                  :title="`Paleta deste bloco (hoje: ${paletteLabel(blockPalette(blockId))}) — clique para trocar`"
                  @pointerdown.stop
                  @mousedown.stop
                  @click.stop="openPalettePicker(blockId)"
                >
                  <span
                    class="w-2 h-2 rounded-full flex-shrink-0"
                    :style="{
                      background:
                        blockPalette(blockId).swatch ||
                        blockPalette(blockId).dot,
                      boxShadow: '0 0 0 1.5px rgba(255,255,255,0.8)',
                    }"
                  />
                  <span class="i-lucide-palette text-[10px]" />
                  {{ blockPalette(blockId).label }}
                </button>
                <span
                  v-if="blockId === 'indicadores'"
                  class="text-n-slate-9 font-normal ml-auto hidden sm:inline"
                  >os cards ficam abertos pra editar cor e ordem</span>
                <span
                  v-else
                  class="text-n-slate-9 font-normal ml-auto hidden sm:inline"
                  >⠿ arraste pra mudar a ordem</span>
              </div>

              <!-- no modo edição só a FILEIRA fica aberta (é nela que se mexe
                 nos cards); os demais blocos recolhem em barrinhas -->
              <template v-if="!organizeMode || blockId === 'indicadores'">
                <template v-if="blockId === 'indicadores'">
                  <template v-if="!currentPanel.custom">
                    <!-- Indicadores do período — mudam com o painel escolhido -->
                    <draggable
                      v-model="dragTiles"
                      item-key="id"
                      :animation="220"
                      :disabled="!organizeMode"
                      ghost-class="opacity-30"
                      class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-4"
                      @end="onKpiReorder"
                    >
                      <template #item="{ element: tile }">
                        <div
                          class="cv-tile relative rounded-2xl p-4 sm:p-5 text-white shadow-lg transition-all duration-700"
                          :class="[
                            tileVisual(tile).pulse ? 'cevico-meta-pulse' : '',
                            tileVisual(tile).isRecord
                              ? 'ring-2 ring-amber-300/80'
                              : '',
                            organizeMode
                              ? 'cursor-grab active:cursor-grabbing ring-2 ring-dashed ring-white/60'
                              : '',
                          ]"
                          :style="{ background: tileVisual(tile).grad }"
                        >
                          <!-- 🏆 recorde: átomos orbitando o card em sentido horário -->
                          <TileAura
                            v-if="tileVisual(tile).aura"
                            :intensity="tileVisual(tile).auraIntensity"
                            gold
                          />
                          <div class="relative">
                            <div
                              class="flex items-center gap-1.5 mb-1.5 text-white/85"
                            >
                              <span
                                :class="tile.icon"
                                class="text-sm flex-shrink-0"
                              />
                              <p
                                class="text-xs font-medium flex-1 min-w-0 truncate"
                              >
                                {{ tile.label }}
                              </p>
                              <button
                                v-if="organizeMode"
                                class="w-6 h-6 rounded-md flex items-center justify-center bg-white/15 hover:bg-white/35 transition-colors"
                                title="Trocar a cor deste card"
                                @click.stop="openColorPicker(tile)"
                              >
                                <span class="i-lucide-paintbrush text-[11px]" />
                              </button>
                              <button
                                v-if="organizeMode"
                                class="w-6 h-6 rounded-md flex items-center justify-center bg-white/15 hover:bg-red-500/80 transition-colors"
                                title="Ocultar este card (dá pra restaurar depois)"
                                @click.stop="hideTile(tile)"
                              >
                                <span class="i-lucide-x text-[11px]" />
                              </button>
                              <button
                                v-else-if="tile.details?.length || tile.about"
                                class="w-6 h-6 rounded-md flex items-center justify-center bg-white/15 hover:bg-white/30 transition-colors"
                                title="Ver detalhes deste indicador"
                                @click.stop="openKpi(tile)"
                              >
                                <span class="i-lucide-maximize-2 text-[11px]" />
                              </button>
                            </div>
                            <!-- número grande + selos + TENDÊNCIA vs período anterior
                   (varredura 12/09: os selos saíram da linha do nome, que
                   vivia truncado — "Novos c… 🏆 RECORDE") -->
                            <div
                              class="flex items-end justify-between gap-2 flex-wrap"
                            >
                              <p
                                class="text-3xl font-bold tabular-nums tracking-tight leading-none"
                              >
                                {{ tile.value }}
                              </p>
                              <div
                                class="flex items-center gap-1 flex-wrap justify-end"
                              >
                                <span
                                  v-if="tileVisual(tile).isRecord"
                                  class="text-[9px] font-black px-1.5 py-0.5 rounded-full bg-amber-300 text-amber-900"
                                  title="Melhor resultado já registrado neste tipo de período"
                                  >🏆 RECORDE</span>
                                <span
                                  v-else-if="tileVisual(tile).status === 'meta'"
                                  class="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-white/25"
                                  title="Meta batida"
                                  >✓ META</span>
                                <span
                                  v-else-if="tileVisual(tile).status === 'bad'"
                                  class="text-[9px] font-bold px-1.5 py-0.5 rounded-full bg-black/25"
                                  title="Muito abaixo do ritmo da meta"
                                  >⚠️</span>
                                <span
                                  v-if="tileTrend(tile)"
                                  class="text-[10px] font-bold px-1.5 py-0.5 rounded-full tabular-nums"
                                  :class="
                                    tileTrend(tile).up
                                      ? 'bg-white/25'
                                      : 'bg-black/20'
                                  "
                                  :title="tileTrend(tile).title"
                                  >{{ tileTrend(tile).text }}</span>
                              </div>
                            </div>
                            <span
                              v-if="tile.chip"
                              class="inline-block mt-1 text-[10px] px-2 py-0.5 rounded-full font-semibold bg-white/20"
                              >{{ tile.chip.label }}</span>
                            <template v-if="tile.sub">
                              <!-- linhas curtas propositais: nada de frase quebrando no meio -->
                              <p
                                class="text-[11px] text-white/75 truncate mt-1"
                              >
                                {{ tile.sub }}
                              </p>
                              <p
                                v-if="tile.sub2"
                                class="text-[11px] text-white/80 truncate"
                              >
                                {{ tile.sub2 }}
                              </p>
                              <p
                                v-if="tile.sub3"
                                class="text-[11px] text-white/80 truncate"
                              >
                                {{ tile.sub3 }}
                              </p>
                            </template>
                            <!-- ✨ sparkline: a forma do período num relance (mesma série do
                   gráfico do popup; some quando não há série ou movimento) -->
                            <svg
                              v-if="tileSpark(tile)"
                              class="w-full mt-2"
                              viewBox="0 0 100 24"
                              preserveAspectRatio="none"
                              style="height: 24px"
                              aria-hidden="true"
                            >
                              <polygon
                                :points="tileSpark(tile).area"
                                fill="rgba(255,255,255,0.18)"
                              />
                              <polyline
                                :points="tileSpark(tile).line"
                                fill="none"
                                stroke="rgba(255,255,255,0.85)"
                                stroke-width="1.6"
                                stroke-linejoin="round"
                                stroke-linecap="round"
                                vector-effect="non-scaling-stroke"
                              />
                            </svg>
                            <!-- medidor da meta (aparece quando o admin definiu meta) -->
                            <div
                              v-if="tileVisual(tile).ratio !== null"
                              class="mt-2"
                            >
                              <div
                                class="h-1.5 rounded-full bg-black/20 overflow-hidden"
                              >
                                <div
                                  class="h-full rounded-full bg-white/85 transition-all duration-700"
                                  :style="{
                                    width:
                                      Math.min(
                                        100,
                                        Math.round(tileVisual(tile).ratio * 100)
                                      ) + '%',
                                  }"
                                />
                              </div>
                              <p class="text-[9px] text-white/70 mt-0.5">
                                {{ Math.round(tileVisual(tile).ratio * 100) }}%
                                do ritmo da meta
                                <template v-if="!tile.pct">
                                  · esperado
                                  {{ Math.ceil(tileVisual(tile).expected) }}
                                </template>
                              </p>
                            </div>
                          </div>
                        </div>
                      </template>

                      <!-- ➕ card novo (admin, item 141) — o modo edição agora liga no
               botão "Modo edição" do topo (item 143) -->
                      <template #footer>
                        <div
                          v-if="isAdmin && !currentPanel.custom"
                          class="cv-tile-add flex flex-col items-stretch justify-center p-3 min-h-[120px]"
                        >
                          <button
                            class="flex-1 rounded-xl transition-colors flex flex-col items-center justify-center gap-0.5 py-2"
                            title="Criar um card de indicador: indicador pronto, fórmula (ex.: agendamentos / leads) e cor"
                            @click="openKpiBuilder(null)"
                          >
                            <span class="i-lucide-plus text-2xl" />
                            <span class="text-xs font-medium">Novo indicador</span>
                          </button>
                        </div>
                      </template>
                    </draggable>

                    <!-- Linha de destaque do painel -->
                    <div
                      class="cv-block cv-strip px-4 py-3 mb-6 flex items-center gap-3"
                    >
                      <span class="cv-icon cv-icon-lg">
                        <span :class="panelHighlight.icon" class="text-lg" />
                      </span>
                      <div class="flex-1">
                        <p class="text-xs font-medium text-n-slate-11">
                          {{ panelHighlight.label }}
                        </p>
                        <p class="text-[10px] text-n-slate-9">
                          {{ panelHighlight.sub }}
                        </p>
                      </div>
                      <p class="text-2xl font-bold text-n-slate-12">
                        {{ panelHighlight.value }}
                      </p>
                    </div>
                  </template>
                </template>

                <template v-else-if="blockId === 'desempenho'">
                  <!-- 🎯 MEU DESEMPENHO (item 138): auto-avaliação — a pessoa e o
             Atendimento IA como referência; sem ranking de colegas (o
             ranking do time vive no Dashboard dos Agentes, do gestor) -->
                  <div v-if="perfCols.length" class="cv-block p-5 sm:p-6 mb-6">
                    <div class="flex items-center gap-2 mb-4 flex-wrap">
                      <span class="cv-icon">
                        <span class="i-lucide-target text-base" />
                      </span>
                      <h2 class="text-sm font-bold text-n-slate-12">
                        {{
                          panelBase === 'gestor'
                            ? 'Desempenho da equipe'
                            : 'Meu desempenho'
                        }}
                      </h2>
                      <span class="cv-chip">velocidades no horário comercial · 08h–17h</span>
                      <span
                        v-if="perf?.previous?.label"
                        class="text-[10px] text-n-slate-9 ml-auto"
                        >setinhas comparam com {{ perf.previous.label }}</span>
                    </div>

                    <div
                      class="grid grid-cols-1 gap-3"
                      :class="
                        perfCols.length > 2
                          ? 'lg:grid-cols-3'
                          : 'lg:grid-cols-2'
                      "
                    >
                      <div
                        v-for="col in perfCols"
                        :key="col.key"
                        class="cv-sub p-4"
                        :class="col.key === 'me' ? 'cv-sub-on' : ''"
                      >
                        <div class="flex items-center gap-2 mb-3">
                          <p class="text-sm font-bold text-n-slate-12 flex-1">
                            {{ col.title }}
                          </p>
                          <span class="text-[10px] text-n-slate-10">{{ col.row.messages_sent }} mensagens</span>
                        </div>

                        <div
                          class="grid grid-cols-2 sm:grid-cols-3 gap-2 text-center"
                        >
                          <div
                            v-for="t in perfTilesFor(col)"
                            :key="t.key"
                            class="cv-stat"
                          >
                            <p
                              class="text-base font-bold"
                              :class="t.color ? '' : 'text-n-slate-12'"
                              :style="t.color ? { color: t.color } : {}"
                            >
                              {{ t.display }}
                              <span
                                v-if="t.delta"
                                class="text-[10px] font-bold"
                                :title="'antes: ' + t.delta.prev"
                                :style="{ color: t.delta.color }"
                                >{{ t.delta.arrow }}</span>
                            </p>
                            <p class="text-[10px] text-n-slate-10">
                              {{ t.label }}
                            </p>
                          </div>
                        </div>

                        <!-- Radar + jornada -->
                        <div
                          class="flex items-center gap-x-4 gap-y-1 flex-wrap mt-3 text-xs text-n-slate-11"
                        >
                          <span class="inline-flex items-center gap-1.5">
                            <span
                              class="i-lucide-radar text-sm"
                              style="color: var(--cv)"
                            />
                            {{ col.row.radar_responded }} aviso(s) do Radar
                            <template
                              v-if="col.row.radar_avg_response_min !== null"
                            >
                              · respondeu em
                              <b class="text-n-slate-12">{{
                                perfFmtMin(col.row.radar_avg_response_min)
                              }}</b></template>
                          </span>
                          <span
                            v-if="col.row.workday"
                            class="inline-flex items-center gap-1.5"
                          >
                            <span
                              class="i-lucide-sunrise text-sm"
                              style="color: var(--cv)"
                            />
                            1ª msg
                            <b class="text-n-slate-12">{{
                              col.row.workday.avg_first_msg
                            }}</b>
                            · última
                            <b class="text-n-slate-12">{{
                              col.row.workday.avg_last_msg
                            }}</b>
                          </span>
                        </div>
                        <div
                          v-if="
                            col.row.workday?.top_gaps?.length ||
                            col.row.off_hours?.count
                          "
                          class="flex items-center gap-1.5 flex-wrap mt-2"
                        >
                          <span
                            v-for="(g, gi) in (
                              col.row.workday?.top_gaps || []
                            ).slice(0, 2)"
                            :key="gi"
                            class="cv-chip"
                            title="Maior pausa entre uma mensagem e outra no período"
                          >
                            pausa {{ g.day }} · {{ g.from }}→{{ g.to }} ·
                            <b>{{ perfFmtMin(g.minutes) }}</b>
                          </span>
                          <span
                            v-if="col.row.off_hours?.count"
                            class="cv-chip cv-slate"
                            :title="
                              'Dias com mensagens fora de seg–sex 08h–17h: ' +
                              (col.row.off_hours.days || []).join(' · ')
                            "
                          >
                            <span class="i-lucide-moon text-[10px]" />{{
                              col.row.off_hours.count
                            }}
                            dia(s) fora do horário<template
                              v-if="col.row.off_hours.days?.length"
                              >:
                              {{
                                col.row.off_hours.days.slice(0, 3).join(' · ')
                              }}</template>
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                </template>

                <template v-else-if="blockId === 'agenda_dashboard'">
                  <!-- 📅 Dashboard da Agenda EMBUTIDO (pedido 20/08): o dashboard
             inteiro faz parte do Meu Painel em TODAS as predefinições,
             seguindo o período da régua; a Saúde da Agenda vem logo abaixo -->
                  <div class="cv-block p-5 sm:p-6 mb-6">
                    <div
                      class="flex items-center justify-between mb-4 flex-wrap gap-2"
                    >
                      <div class="flex items-center gap-2">
                        <span class="cv-icon">
                          <span class="i-lucide-calendar-days text-base" />
                        </span>
                        <h2 class="text-sm font-bold text-n-slate-12">
                          Dashboard da Agenda
                        </h2>
                        <span class="text-[10px] text-n-slate-9">segue o período escolhido acima</span>
                      </div>
                      <button
                        class="cv-btn cv-btn-ghost cv-btn-sm"
                        title="Abrir o relatório completo em Relatórios"
                        @click="goToAgendaDashboard"
                      >
                        <span class="i-lucide-expand text-sm" />
                        Relatório completo
                      </button>
                    </div>
                    <AgendaDashboardCore
                      :period="period"
                      glass
                      :family="blockFamily('agenda_dashboard')"
                    />
                  </div>
                </template>

                <template v-else-if="blockId === 'saude_agenda'">
                  <!-- Saúde da Agenda -->
                  <div class="cv-block p-5 sm:p-6 mb-6">
                    <div
                      class="flex items-center justify-between mb-4 flex-wrap gap-2"
                    >
                      <div class="flex items-center gap-2">
                        <span class="cv-icon">
                          <span class="i-lucide-activity text-base" />
                        </span>
                        <h2 class="text-sm font-bold text-n-slate-12">
                          Saúde da Agenda
                        </h2>
                      </div>
                      <!-- atalho pulsante para a Agenda (cor do ambiente) -->
                      <button
                        class="cv-btn cv-btn-pulse"
                        @click="go('agenda_board')"
                      >
                        <span class="i-lucide-calendar-days text-sm" />
                        Ir para agenda
                        <span class="i-lucide-arrow-right text-xs" />
                      </button>
                    </div>

                    <!-- DOIS retângulos simétricos: Consultas × Cirurgias -->
                    <div
                      class="grid grid-cols-1 gap-4"
                      :class="showSurgeryHealth ? 'lg:grid-cols-2' : ''"
                    >
                      <!-- 🩺 Agenda de CONSULTAS -->
                      <div class="cv-sub p-4 flex flex-col gap-4">
                        <p
                          class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5"
                        >
                          <span
                            class="i-lucide-stethoscope text-sm"
                            style="color: var(--cv)"
                          />
                          Agenda de Consultas
                        </p>
                        <div>
                          <div
                            class="flex items-center justify-between text-xs mb-1.5"
                          >
                            <span class="text-n-slate-11">Agenda cheia
                              <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                            <span class="font-bold text-base text-n-slate-12">{{ fillNext7.pct }}%</span>
                          </div>
                          <div class="cv-track">
                            <div
                              class="cv-fill"
                              :style="{
                                width: Math.max(fillNext7.pct, 2) + '%',
                              }"
                            />
                          </div>
                          <p class="text-[10px] text-n-slate-9 mt-1">
                            {{ fillNext7.filled }} de
                            {{ fillNext7.total }} blocos
                          </p>
                        </div>
                        <div>
                          <div
                            class="flex items-center justify-between text-xs mb-1.5"
                          >
                            <span class="text-n-slate-11">Aproveitamento
                              <span class="text-n-slate-9">(últimos 7 dias)</span></span>
                            <span class="font-bold text-base text-n-slate-12">{{ usageLast7.pct }}%</span>
                          </div>
                          <div class="cv-track">
                            <div
                              class="cv-fill"
                              :style="{
                                width: Math.max(usageLast7.pct, 2) + '%',
                              }"
                            />
                          </div>
                          <p class="text-[10px] text-n-slate-9 mt-1">
                            blocos que viraram consulta
                          </p>
                        </div>
                        <div>
                          <div
                            class="flex items-center justify-between text-xs mb-1.5"
                          >
                            <span class="text-n-slate-11">Comparecimento
                              <span class="text-n-slate-9">(30 dias)</span></span>
                            <span class="font-bold text-base text-n-slate-12">{{
                              attendance === null ? '—' : attendance + '%'
                            }}</span>
                          </div>
                          <div class="cv-track">
                            <div
                              class="cv-fill"
                              :style="{
                                width: Math.max(attendance || 0, 2) + '%',
                              }"
                            />
                          </div>
                          <p class="text-[10px] text-n-slate-9 mt-1">
                            consultas concluídas ÷ realizadas
                          </p>
                        </div>
                        <!-- vagas livres, junto da agenda de consultas -->
                        <div
                          class="mt-auto pt-1"
                          style="
                            border-top: 1px solid rgb(var(--cv-rgb) / 0.18);
                          "
                        >
                          <p class="cv-label mb-1.5 mt-2">
                            Vagas livres mais próximas
                          </p>
                          <div
                            v-if="nextFreeSlots.length"
                            class="flex flex-wrap gap-1.5"
                          >
                            <button
                              v-for="(f, i) in nextFreeSlots"
                              :key="i"
                              class="cv-chip cv-chip-lg"
                              @click="go('agenda_board')"
                            >
                              <span
                                class="w-2 h-2 rounded-full flex-shrink-0"
                                :style="{ background: slotColor(f) }"
                              />
                              {{ slotLabel(f) }} · {{ slotDoctorShort(f) }}
                            </button>
                          </div>
                          <p v-else class="text-xs text-n-slate-10">
                            Sem vagas nos próximos 14 dias.
                          </p>
                          <p
                            v-if="nextAppointment"
                            class="text-[11px] text-n-slate-10 flex items-center gap-1.5 mt-2"
                          >
                            <span class="i-lucide-clock text-xs" />
                            Próxima consulta:
                            <b class="text-n-slate-12">{{
                              nextAppointment.title
                            }}</b>
                            — {{ apptTime(nextAppointment.due_at) }}
                          </p>
                        </div>
                      </div>

                      <!-- 🔪 Agenda de CIRURGIAS (simétrica) -->
                      <div
                        v-if="showSurgeryHealth"
                        class="cv-sub p-4 flex flex-col gap-4"
                      >
                        <p
                          class="text-xs font-bold text-n-slate-12 flex items-center gap-1.5"
                        >
                          <span
                            class="i-lucide-slice text-sm"
                            style="color: var(--cv)"
                          />
                          Agenda de Cirurgias
                          <span class="text-[10px] font-normal text-n-slate-9">sala cirúrgica (IOP, Ocular Surgery...)</span>
                        </p>
                        <div>
                          <div
                            class="flex items-center justify-between text-xs mb-1.5"
                          >
                            <span class="text-n-slate-11">Sala cheia
                              <span class="text-n-slate-9">(próx. 7 dias)</span></span>
                            <span class="font-bold text-base text-n-slate-12">{{
                              surgFillNext7.total
                                ? surgFillNext7.pct + '%'
                                : '—'
                            }}</span>
                          </div>
                          <div class="cv-track">
                            <div
                              class="cv-fill"
                              :style="{
                                width: Math.max(surgFillNext7.pct, 2) + '%',
                              }"
                            />
                          </div>
                          <p class="text-[10px] text-n-slate-9 mt-1">
                            {{
                              surgFillNext7.total
                                ? `${surgFillNext7.filled} de ${surgFillNext7.total} blocos`
                                : 'sem janelas da sala nos próximos dias'
                            }}
                          </p>
                        </div>
                        <div>
                          <div
                            class="flex items-center justify-between text-xs mb-1.5"
                          >
                            <span class="text-n-slate-11">Aproveitamento
                              <span class="text-n-slate-9">(últimos 7 dias)</span></span>
                            <span class="font-bold text-base text-n-slate-12">{{
                              surgUsageLast7.total
                                ? surgUsageLast7.pct + '%'
                                : '—'
                            }}</span>
                          </div>
                          <div class="cv-track">
                            <div
                              class="cv-fill"
                              :style="{
                                width: Math.max(surgUsageLast7.pct, 2) + '%',
                              }"
                            />
                          </div>
                          <p class="text-[10px] text-n-slate-9 mt-1">
                            blocos da sala que viraram cirurgia
                          </p>
                        </div>
                        <!-- 🎯 META: 100 cirurgias -->
                        <div>
                          <div
                            class="flex items-center justify-between text-xs mb-1.5"
                          >
                            <span
                              class="text-n-slate-11 inline-flex items-center gap-1"
                              ><span
                                class="i-lucide-target text-xs"
                                style="color: var(--cv)"
                              />Meta do mês
                              <span class="text-n-slate-9">({{ surgeryGoalTarget }} cirurgias)</span></span>
                            <span class="font-bold text-base text-n-slate-12">{{ surgeriesDoneMonth }} de
                              {{ surgeryGoalTarget }}</span>
                          </div>
                          <div class="cv-track">
                            <div
                              class="cv-fill"
                              :class="goalPct >= 100 ? 'cv-green' : ''"
                              :style="{ width: Math.max(goalPct, 2) + '%' }"
                            />
                          </div>
                          <p class="text-[10px] text-n-slate-9 mt-1">
                            {{ goalPct }}% da meta · cirurgias realizadas no mês
                          </p>
                        </div>
                        <div
                          class="mt-auto pt-1"
                          style="
                            border-top: 1px solid rgb(var(--cv-rgb) / 0.18);
                          "
                        >
                          <p
                            v-if="nextSurgery"
                            class="text-[11px] text-n-slate-10 flex items-center gap-1.5 mt-2"
                          >
                            <span class="i-lucide-clock text-xs" />
                            Próxima cirurgia:
                            <b class="text-n-slate-12">{{
                              nextSurgery.title.replace(/^Consulta:\s*/i, '')
                            }}</b>
                            — {{ apptTime(nextSurgery.due_at) }}
                          </p>
                          <p v-else class="text-[11px] text-n-slate-10 mt-2">
                            Nenhuma cirurgia futura na agenda.
                          </p>
                        </div>
                      </div>
                    </div>

                    <!-- o "% de agendamento" que morava aqui foi PROMOVIDO pra fileira
               de indicadores do painel Agendamento (item 143) -->
                  </div>
                </template>

                <template v-else-if="blockId === 'metas_strip'">
                  <!-- 🎯 Metas · Rotinas · Ferramentas (alimentado pelo Painel de Metas) -->
                  <div
                    v-if="goalsData"
                    class="grid grid-cols-1 md:grid-cols-3 gap-3 mb-6"
                  >
                    <!-- METAS do mês -->
                    <button
                      class="cv-block cv-block-hover p-4 text-left"
                      @click="goToGoals"
                    >
                      <div class="flex items-center gap-2 mb-2">
                        <span class="cv-icon cv-icon-sm">
                          <span class="i-lucide-target text-xs" />
                        </span>
                        <p class="text-xs font-bold text-n-slate-12 flex-1">
                          Metas do mês
                        </p>
                        <span
                          class="i-lucide-chevron-right text-sm text-n-slate-9"
                        />
                      </div>
                      <template v-if="goalRows.length">
                        <div v-for="g in goalRows" :key="g.key" class="mb-1.5">
                          <div
                            class="flex items-center justify-between text-[10px] mb-0.5"
                          >
                            <span class="text-n-slate-10 truncate">{{
                              g.label
                            }}</span>
                            <b class="text-n-slate-12">{{ g.current }}/{{ g.target }}</b>
                          </div>
                          <div class="cv-track cv-track-sm">
                            <div
                              class="cv-fill"
                              :class="g.pct >= 100 ? 'cv-green' : ''"
                              :style="{ width: `${Math.max(g.pct, 2)}%` }"
                            />
                          </div>
                        </div>
                      </template>
                      <p v-else class="text-[11px] text-n-slate-9">
                        {{
                          isAdmin
                            ? 'Defina a meta do mês no Painel de Metas →'
                            : 'A meta do mês aparece aqui quando o gestor definir.'
                        }}
                      </p>
                    </button>

                    <!-- ROTINAS -->
                    <div class="cv-block p-4">
                      <div class="flex items-center gap-2 mb-2">
                        <span class="cv-icon cv-icon-sm">
                          <span class="i-lucide-repeat text-xs" />
                        </span>
                        <p class="text-xs font-bold text-n-slate-12">Rotinas</p>
                      </div>
                      <template v-if="teamRoutines.length">
                        <p
                          v-for="(r, ri) in teamRoutines.slice(0, 5)"
                          :key="ri"
                          class="text-[11px] text-n-slate-11 leading-relaxed flex items-start gap-1.5 mb-0.5"
                        >
                          <span
                            class="i-lucide-check-circle-2 text-[11px] mt-0.5 flex-shrink-0"
                            style="color: var(--cv)"
                          />
                          {{ r }}
                        </p>
                      </template>
                      <p v-else class="text-[11px] text-n-slate-9">
                        {{
                          isAdmin
                            ? 'Cadastre as rotinas do time no Painel de Metas.'
                            : 'As rotinas combinadas aparecem aqui.'
                        }}
                      </p>
                    </div>

                    <!-- FERRAMENTAS importantes -->
                    <div class="cv-block p-4">
                      <div class="flex items-center gap-2 mb-2">
                        <span class="cv-icon cv-icon-sm">
                          <span class="i-lucide-wrench text-xs" />
                        </span>
                        <p class="text-xs font-bold text-n-slate-12">
                          Ferramentas
                        </p>
                      </div>
                      <button
                        class="cv-sub cv-sub-hover w-full flex items-center gap-1.5 text-[11px] font-semibold text-n-slate-12 px-2.5 py-1.5 mb-1"
                        @click="goToTools"
                      >
                        <span
                          class="i-lucide-swords text-[11px]"
                          style="color: var(--cv)"
                        />
                        Fechamento: script + mapa de objeções
                        <span
                          class="i-lucide-chevron-right text-[11px] ml-auto text-n-slate-9"
                        />
                      </button>
                      <button
                        v-for="(t, ti) in importantTools.slice(0, 4)"
                        :key="ti"
                        class="cv-sub cv-sub-hover w-full flex items-center gap-1.5 text-[11px] text-n-slate-11 px-2.5 py-1.5 mb-1"
                        @click="openTool(t)"
                      >
                        <span
                          class="i-lucide-external-link text-[11px] text-n-slate-9"
                        />
                        <span class="truncate">{{ t.label }}</span>
                      </button>
                    </div>
                  </div>
                </template>

                <template v-else-if="blockId === 'atalhos'">
                  <!-- Acesso rápido (compacto, largura toda) -->
                  <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
                    <button
                      v-for="(s, si) in shortcuts"
                      :key="s.route"
                      class="cv-block cv-block-hover flex items-center gap-2.5 px-4 py-3 text-left"
                      @click="go(s.route)"
                    >
                      <span
                        class="cv-icon cv-icon-lg"
                        :style="{ background: blockFamily('atalhos')[si % 4] }"
                      >
                        <span :class="s.icon" class="text-lg" />
                      </span>
                      <span class="text-sm font-semibold text-n-slate-12">{{
                        s.label
                      }}</span>
                    </button>
                  </div>
                </template>

                <template v-else-if="blockId === 'termometro'">
                  <!-- Termômetro do momento -->
                  <div
                    class="cv-block cv-strip flex flex-wrap items-center gap-2 px-3 py-2 mb-4"
                  >
                    <span class="cv-icon cv-icon-sm"><span class="i-lucide-thermometer text-xs"/></span>
                    <span class="cv-chip"><span class="i-lucide-inbox text-xs" />{{
                        data.open_conversations ?? 0
                      }}
                      conversas abertas agora</span>
                    <span
                      class="cv-chip"
                      :class="(data.unanswered ?? 0) > 0 ? 'cv-amber' : ''"
                    >
                      <span class="i-lucide-clock-alert text-xs" />{{
                        data.unanswered ?? 0
                      }}
                      aguardando resposta
                    </span>
                    <span class="cv-chip"><span class="i-lucide-calendar-check text-xs" />{{
                        data.appointments_today ?? 0
                      }}
                      consultas hoje</span>
                  </div>
                </template>
              </template>
            </section>
          </template>
        </draggable>
      </template>

      <!-- Admin: quem vê qual painel -->
      <div
        v-if="showAssignModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="showAssignModal = false"
      >
        <div class="cv-modal w-full max-w-md max-h-[85vh] flex flex-col">
          <div class="cv-modal-head flex items-center gap-3">
            <span
              class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"
              ><span class="i-lucide-settings-2 text-base"/></span>
            <div class="flex-1 min-w-0">
              <h2 class="text-base font-bold leading-tight">
                Painel de cada pessoa
              </h2>
              <p class="text-[11px] opacity-85 mt-0.5">
                quem abre o Meu Painel em qual versão
              </p>
            </div>
            <button
              class="cv-glass-btn cv-iconbtn"
              aria-label="Fechar"
              @click="showAssignModal = false"
            >
              <span class="i-lucide-x text-base" />
            </button>
          </div>
          <div class="flex-1 overflow-y-auto p-5 space-y-2">
            <p class="text-xs text-n-slate-10 mb-2">
              A pessoa abre o Meu Painel já na versão da função dela (e só vê
              essa). "Livre" = pode alternar entre todos os painéis.
            </p>
            <div
              v-for="agent in teamAgents"
              :key="agent.id"
              class="flex items-center gap-2"
            >
              <span class="text-sm text-n-slate-12 flex-1 truncate">{{
                agent.name
              }}</span>
              <select
                v-model="assignDraft[String(agent.id)]"
                class="cv-input !h-8 text-xs text-n-slate-12"
              >
                <option value="">Livre (todos)</option>
                <!-- lista também os painéis do Construtor (custom:<id>) -->
                <option v-for="p in allPanels" :key="p.key" :value="p.key">
                  {{ p.label }}<template v-if="p.who"> · {{ p.who }}</template>
                </option>
              </select>
            </div>
          </div>
          <div class="cv-modal-foot flex gap-2">
            <button
              class="cv-btn cv-btn-lg flex-1"
              :disabled="isSavingAssign"
              @click="saveAssignments"
            >
              {{ isSavingAssign ? 'Salvando…' : 'Salvar' }}
            </button>
            <button
              class="cv-btn cv-btn-ghost cv-btn-lg"
              @click="showAssignModal = false"
            >
              Cancelar
            </button>
          </div>
        </div>
      </div>

      <!-- 🧑‍🤝‍🧑 Painel por pessoa (admin, rodada 160) -->
      <div
        v-if="showVariantModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
        @click.self="showVariantModal = false"
      >
        <div class="cv-modal w-full max-w-md max-h-[85vh] flex flex-col">
          <div class="cv-modal-head flex items-center gap-3">
            <span
              class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"
              ><span class="i-lucide-user-plus text-base"/></span>
            <div class="flex-1 min-w-0">
              <h2 class="text-base font-bold leading-tight">
                {{
                  variantDraft.id
                    ? 'Editar painel por pessoa'
                    : 'Painel por pessoa'
                }}
              </h2>
              <p class="text-[11px] opacity-85 mt-0.5">
                uma versão do painel-base com layout próprio
              </p>
            </div>
            <button
              class="cv-glass-btn cv-iconbtn"
              aria-label="Fechar"
              @click="showVariantModal = false"
            >
              <span class="i-lucide-x text-base" />
            </button>
          </div>
          <div class="flex-1 overflow-y-auto p-5 space-y-4">
            <p class="text-xs text-n-slate-10 leading-relaxed">
              Uma versão do painel-base só para quem você escolher: os mesmos
              números e metas, com blocos, cards e cores organizados do jeito
              dela — no <b>Modo edição</b>, com o arrasto magnético. A pessoa
              abre o Meu Painel já neste painel.
            </p>
            <div>
              <p class="cv-label mb-1.5">Painel-base</p>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="b in BASE_PANELS"
                  :key="b.key"
                  class="cv-btn cv-btn-sm"
                  :class="variantDraft.base === b.key ? '' : 'cv-btn-ghost'"
                  @click="variantDraft.base = b.key"
                >
                  <span :class="b.icon" class="text-sm" />
                  {{ b.label }}
                </button>
              </div>
            </div>
            <div>
              <p class="cv-label mb-1.5">Quem vê este painel</p>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="agent in teamAgents"
                  :key="agent.id"
                  class="cv-btn cv-btn-sm"
                  :class="
                    variantDraft.user_ids.includes(agent.id)
                      ? ''
                      : 'cv-btn-ghost'
                  "
                  @click="toggleVariantUser(agent.id)"
                >
                  {{ agent.name }}
                </button>
                <span
                  v-if="!teamAgents.length"
                  class="text-[11px] text-n-slate-9"
                  >carregando o time…</span>
              </div>
              <p class="text-[10px] text-n-slate-9 mt-1.5">
                Quem está na lista fica travado neste painel (dá pra mudar
                depois em "Painel de cada pessoa").
              </p>
            </div>
            <div>
              <p class="cv-label mb-1">Nome do painel</p>
              <input
                v-model="variantDraft.name"
                type="text"
                maxlength="40"
                :placeholder="suggestedVariantName() || 'ex.: Natália'"
                class="cv-input w-full text-n-slate-12"
              />
            </div>
          </div>
          <div class="cv-modal-foot flex gap-2">
            <button
              class="cv-btn cv-btn-lg flex-1"
              :disabled="isSavingVariant"
              @click="saveVariant"
            >
              {{
                isSavingVariant
                  ? 'Salvando…'
                  : variantDraft.id
                    ? 'Salvar'
                    : 'Criar painel'
              }}
            </button>
            <button
              v-if="variantDraft.id"
              class="cv-btn cv-btn-ghost cv-btn-lg cv-btn-danger"
              :class="variantDeleteArmed ? 'cv-btn-danger-on' : ''"
              :disabled="isSavingVariant"
              @click="
                variantDeleteArmed
                  ? deleteVariant()
                  : (variantDeleteArmed = true)
              "
            >
              {{ variantDeleteArmed ? 'Confirmar exclusão' : 'Excluir' }}
            </button>
            <button
              class="cv-btn cv-btn-ghost cv-btn-lg"
              @click="showVariantModal = false"
            >
              Cancelar
            </button>
          </div>
        </div>
      </div>

      <!-- 🎯 Modal de METAS por painel (admin) -->
      <div
        v-if="showGoalsModal"
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
        @click.self="showGoalsModal = false"
      >
        <div class="cv-modal w-full max-w-md flex flex-col">
          <div class="cv-modal-head flex items-center gap-3">
            <span
              class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"
              ><span class="i-lucide-target text-base"/></span>
            <div class="flex-1 min-w-0">
              <h3 class="text-base font-bold leading-tight">
                Metas — {{ currentPanel.label }}
              </h3>
              <p class="text-[11px] opacity-85 mt-0.5">
                metas mensais; os cards mudam de cor pelo ritmo
              </p>
            </div>
            <button
              class="cv-glass-btn cv-iconbtn"
              aria-label="Fechar"
              @click="showGoalsModal = false"
            >
              <span class="i-lucide-x text-base" />
            </button>
          </div>
          <div class="p-5">
            <p class="text-[11px] text-n-slate-10 mb-4">
              Metas MENSAIS (as taxas % são diretas). Os cards mudam de cor pelo
              ritmo: 🔴 muito abaixo · 🟠 abaixo · cores normais no ritmo · 🟢
              meta batida · 🏆 recorde com átomos.
            </p>
            <div class="space-y-3 mb-4">
              <label
                v-for="field in GOAL_FIELDS[panelBase] || []"
                :key="field.gk"
                class="flex items-center gap-3"
              >
                <span class="text-xs text-n-slate-11 flex-1">{{
                  field.label
                }}</span>
                <input
                  v-model.number="goalsDraft[panelBase][field.gk]"
                  type="number"
                  min="0"
                  :step="field.pct ? 0.5 : 1"
                  class="cv-input w-24 text-n-slate-12 text-right"
                  placeholder="—"
                />
              </label>
            </div>
            <p class="text-[10px] text-n-slate-9 mb-3">
              Deixar vazio (ou 0) = sem meta para aquele card.
            </p>
          </div>
          <div class="cv-modal-foot flex justify-end gap-2">
            <button
              class="cv-btn cv-btn-ghost cv-btn-lg"
              @click="showGoalsModal = false"
            >
              Cancelar
            </button>
            <button
              class="cv-btn cv-btn-lg"
              :disabled="isSavingGoals"
              @click="saveGoals"
            >
              {{ isSavingGoals ? 'Salvando…' : 'Salvar metas' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Balão da conversa direto do card do Radar (o mesmo do CRM) -->
    <ConversationChatModal
      v-if="radarChat"
      :contact="radarChat"
      @close="radarChat = null"
      @replied="onRadarChatReplied"
      @resolved="onRadarChatResolved"
    />

    <EmojiFx ref="radarFx" />
  </div>
  <!-- 🔍 Popup de detalhes do card de KPI (itens 140/144; UX 152: transição
       suave, Esc fecha, rolagem própria — nunca maior que a tela) -->
  <Teleport to="body">
    <Transition name="cevico-kpi-pop">
      <div
        v-if="kpiModal"
        class="cv-page cv-overlay fixed inset-0 z-[70] flex items-center justify-center bg-black/50 backdrop-blur-[2px] p-4"
        :style="cvVars"
        role="dialog"
        aria-modal="true"
        @click.self="closeKpiModal"
      >
        <div
          class="cevico-kpi-panel cv-modal w-full max-w-lg max-h-[88vh] flex flex-col"
        >
          <div
            class="cv-modal-head !p-5 !pb-4"
            :style="{ background: tileVisual(kpiModal).grad }"
          >
            <div class="flex items-center gap-2 text-white/85">
              <span :class="kpiModal.icon" class="text-base" />
              <p class="text-sm font-medium flex-1">{{ kpiModal.label }}</p>
              <button
                class="cv-glass-btn cv-iconbtn"
                aria-label="Fechar (Esc)"
                title="Fechar (Esc)"
                @click="closeKpiModal"
              >
                <span class="i-lucide-x text-base" />
              </button>
            </div>
            <div class="flex items-end gap-3 flex-wrap mt-2">
              <p
                class="text-4xl font-bold tabular-nums tracking-tight leading-none"
              >
                {{ kpiModal.value }}
              </p>
              <!-- a tendência já no cabeçalho: a história antes do gráfico (varredura 12/09) -->
              <div v-if="modalDelta" class="flex flex-col leading-tight pb-0.5">
                <span
                  class="text-sm font-bold"
                  :class="modalDelta.up ? 'text-emerald-200' : 'text-red-200'"
                  >{{ modalDelta.text }}</span>
                <span class="text-[10px] text-white/75">{{
                  modalDelta.sub
                }}</span>
              </div>
            </div>
            <span v-if="kpiModal.chip" class="cv-glass-chip mt-1.5">{{
              kpiModal.chip.label
            }}</span>
            <p v-if="kpiModal.sub" class="text-xs text-white/80 mt-1">
              {{ kpiModal.sub }}
            </p>
          </div>
          <div class="p-5 space-y-3 overflow-y-auto overscroll-contain">
            <!-- 📊 gráfico do período v2 (item 144; UX 152: legenda visual,
               estado vazio gentil, carregamento suave, régua com rótulos) -->
            <div v-if="modalChart" class="cv-sub px-3 py-2">
              <div
                class="flex items-center justify-between gap-2 text-[10px] text-n-slate-10 mb-1"
              >
                <span class="truncate">{{
                  modalChart.compare
                    ? 'comparativo'
                    : `${modalChart.label || kpiModal.label} · ${modalBag?.granularity === 'month' ? 'por mês' : modalBag?.granularity === 'week' ? 'por semana' : 'por dia'}`
                }}</span>
                <span
                  v-if="isLoadingModalBag"
                  class="i-lucide-loader-circle animate-spin text-xs flex-shrink-0"
                />
              </div>
              <div
                class="transition-opacity duration-200"
                :class="isLoadingModalBag ? 'opacity-40' : ''"
              >
                <MiniBars
                  :values="modalChart.values"
                  :labels="modalChart.labels"
                  :color="modalChartColor"
                  :height="128"
                  :prev-values="modalChart.prevValues || null"
                  :goal="modalChart.goal ?? null"
                  :markers="modalChart.compare ? [] : modalMarkers"
                  :reference="
                    !modalChart.compare &&
                    !modalChart.prevValues &&
                    modalChart.prev
                      ? modalChart.prev / Math.max(1, modalChart.values.length)
                      : null
                  "
                  :format="chartFormat(kpiModal)"
                />
              </div>
              <!-- recorte sem nenhum movimento: fala com a pessoa em vez do vazio -->
              <p
                v-if="modalChartIsEmpty"
                class="cv-row text-[11px] text-n-slate-10 text-center mt-1 px-2 py-1.5"
              >
                Sem movimento neste recorte — experimente <b>Este mês</b> ou
                <b>Este ano</b> aqui embaixo.
              </p>
              <!-- legenda VISUAL: cada elemento do gráfico explicado com a
                 própria forma (tracinho, estrela, pino) -->
              <div
                v-if="!modalChart.compare"
                class="flex items-center gap-x-3 gap-y-0.5 flex-wrap text-[10px] text-n-slate-10 mt-0.5"
              >
                <span
                  v-if="
                    modalChart.prevValues ||
                    (modalChart.prev !== undefined && modalChart.prev !== null)
                  "
                  class="flex items-center gap-1"
                >
                  <span
                    class="inline-block w-4 border-t-2 border-dashed"
                    style="border-color: #94a3b8"
                  />
                  {{
                    modalChart.prevValues
                      ? 'período anterior'
                      : 'média do anterior'
                  }}
                </span>
                <span
                  v-if="modalChart.goal"
                  class="flex items-center gap-1"
                  style="color: #b8860b"
                >
                  ⭑ meta ≈ {{ chartFormat(kpiModal)(modalChart.goal) }} por
                  {{
                    modalBag?.granularity === 'month'
                      ? 'mês'
                      : modalBag?.granularity === 'week'
                        ? 'semana'
                        : 'dia'
                  }}
                </span>
                <span v-if="modalMarkers.length"
class="flex items-center gap-1"
                  >📌 ação da empresa</span>
              </div>
              <!-- 💡 o gráfico lido em uma frase: pico, média e total — quem
                 não lê gráfico entende o período mesmo assim -->
              <p
                v-if="modalInsight"
                class="text-[11px] mt-1.5 text-n-slate-11 flex items-start gap-1.5 leading-snug"
              >
                <span
                  class="i-lucide-sparkles text-xs mt-0.5 flex-shrink-0"
                  style="color: #b8860b"
                />
                <span>{{ modalInsight }}</span>
              </p>
              <!-- mini-régua do popup: recorte SÓ deste gráfico (a régua da
                 página fica intacta) — grupos com nome, sem adivinhação -->
              <div
                v-if="!modalChart.compare"
                class="mt-2 pt-2 space-y-1.5"
                style="border-top: 1px solid rgb(var(--cv-rgb) / 0.18)"
              >
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="text-[10px] text-n-slate-9 w-12 flex-shrink-0">Período</span>
                  <span class="cv-seg cv-seg-sm flex-wrap">
                    <button
                      v-for="p in MODAL_PRESETS"
                      :key="String(p[0])"
                      class="cv-seg-item"
                      :class="kpiModalPreset === p[0] ? 'cv-seg-on' : ''"
                      @click="setModalPreset(p[0])"
                    >
                      {{ p[1] }}
                    </button>
                  </span>
                </div>
                <div class="flex items-center gap-1.5 flex-wrap">
                  <span class="text-[10px] text-n-slate-9 w-12 flex-shrink-0">Ver por</span>
                  <span class="cv-seg cv-seg-sm flex-wrap">
                    <button
                      v-for="g in MODAL_GRAINS"
                      :key="String(g[0])"
                      class="cv-seg-item"
                      :class="kpiModalGranularity === g[0] ? 'cv-seg-on' : ''"
                      @click="setModalGranularity(g[0])"
                    >
                      {{ g[1] }}
                    </button>
                  </span>
                </div>
              </div>
            </div>
            <!-- 🧩 DE ONDE VEM ESTA TAXA (item 144): as séries que formam a
               conta — responde se o problema foi entrada ou conversão -->
            <div
              v-if="modalComponents.length"
              class="cv-sub px-3 py-2 space-y-2"
            >
              <p class="text-[11px] font-medium text-n-slate-11">
                🧩 De onde vem este número
                <span class="font-normal text-n-slate-9">· {{ modalRangeLabel }}</span>
              </p>
              <div v-for="comp in modalComponents" :key="comp.key">
                <div
                  class="flex items-center justify-between text-[10px] mb-0.5"
                >
                  <span class="text-n-slate-11">{{ comp.label }}</span>
                  <b class="text-n-slate-12">{{
                    componentFormat(comp)(comp.total)
                  }}</b>
                </div>
                <MiniBars
                  :values="comp.values"
                  :labels="modalChart?.labels || []"
                  color="#64748B"
                  :height="46"
                  :prev-values="comp.prevValues"
                  :format="componentFormat(comp)"
                />
              </div>
            </div>
            <!-- 🏥 POR UNIDADE (item 146): Paulista × Tatuapé lado a lado —
               consultas, comparecimento e a taxa de cada casa -->
            <div
              v-if="kpiModal.units?.length"
              class="cv-sub px-3 py-2 space-y-2"
            >
              <p class="text-[11px] font-medium text-n-slate-11">
                🏥 Por unidade
                <span class="font-normal text-n-slate-9">· consultas e comparecimento do período</span>
              </p>
              <div
                v-for="u in kpiModal.units"
                :key="u.unit || 'sem'"
                class="cv-row px-3 py-2"
              >
                <div
                  class="flex items-center justify-between gap-2 text-xs mb-1"
                >
                  <b class="text-n-slate-12">{{ u.label }}</b>
                  <span
                    class="text-[10px] px-2 py-0.5 rounded-full font-bold text-white"
                    :style="{
                      background:
                        (u.show_rate ?? 0) >= 80
                          ? 'linear-gradient(135deg, #065F46, #10B981)'
                          : (u.show_rate ?? 0) >= 60
                            ? 'linear-gradient(135deg, #B8860B, #D4A017)'
                            : 'linear-gradient(135deg, #B91C1C, #EF4444)',
                    }"
                  >
                    {{ u.show_rate ?? 0 }}% compareceram
                  </span>
                </div>
                <div
                  class="flex items-center gap-3 text-[10px] text-n-slate-10 flex-wrap"
                >
                  <span>{{ u.consultations }} consulta(s)</span>
                  <span style="color: #059669">✓ {{ u.attended }} vieram</span>
                  <span style="color: #dc2626">✗ {{ u.missed }} faltaram</span>
                  <span
                    v-if="u.consultations - u.attended - u.missed > 0"
                    class="text-n-slate-9"
                  >
                    {{ u.consultations - u.attended - u.missed }} sem
                    conferência
                  </span>
                </div>
                <div
                  class="h-1.5 rounded-full bg-n-alpha-2 overflow-hidden mt-1.5"
                >
                  <div
                    class="h-full rounded-full transition-all"
                    :style="{
                      width: Math.max(u.show_rate ?? 0, 2) + '%',
                      background:
                        (u.show_rate ?? 0) >= 80
                          ? 'linear-gradient(90deg, #065F46, #10B981)'
                          : (u.show_rate ?? 0) >= 60
                            ? 'linear-gradient(90deg, #B8860B, #D4A017)'
                            : 'linear-gradient(90deg, #B91C1C, #EF4444)',
                    }"
                  />
                </div>
              </div>
            </div>
            <!-- leads por caixa (card 1): barras lado a lado -->
            <div
              v-if="kpiModal.compareInboxes?.length"
              class="cv-sub px-3 py-2"
            >
              <p class="text-[11px] font-medium text-n-slate-11 mb-1">
                📥 Leads por caixa de entrada
              </p>
              <MiniBars
                :values="kpiModal.compareInboxes.map(i => i.value)"
                :labels="kpiModal.compareInboxes.map(i => i.label)"
                color="#7C3AED"
                :height="80"
              />
            </div>
            <div v-if="kpiModal.details?.length" class="space-y-1.5">
              <div
                v-for="(row, ri) in kpiModal.details"
                :key="ri"
                class="cv-row flex items-start justify-between gap-3 text-xs px-3 py-2"
              >
                <span class="text-n-slate-11 flex-shrink-0">{{
                  row.label
                }}</span>
                <b class="text-n-slate-12 text-right break-words min-w-0">{{
                  row.value
                }}</b>
              </div>
            </div>
            <p
              v-if="kpiModal.about"
              class="text-[11px] text-n-slate-10 leading-relaxed"
            >
              <span class="i-lucide-info text-xs align-middle mr-1" />{{
                kpiModal.about
              }}
            </p>
            <div
              v-if="isAdmin && kpiModal.kpi"
              class="flex items-center gap-2 pt-1"
            >
              <button
                class="cv-btn cv-btn-ghost"
                @click="openKpiBuilder(kpiModal.def)"
              >
                <span class="i-lucide-pencil text-xs" />Editar
              </button>
              <button
                class="cv-btn cv-btn-ghost cv-btn-danger"
                :disabled="isSavingKpi"
                @click="deleteKpi(kpiModal.def)"
              >
                <span class="i-lucide-trash-2 text-xs" />Remover
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
  <!-- ➕ Construtor de indicador (admin, item 141) -->
  <Teleport to="body">
    <div
      v-if="kpiBuilder"
      class="cv-page cv-overlay fixed inset-0 z-[71] flex items-center justify-center bg-black/50 p-4"
      :style="cvVars"
      @click.self="kpiBuilder = null"
    >
      <div class="cv-modal w-full max-w-2xl max-h-[92vh] flex flex-col">
        <div
          class="cv-modal-head !p-5 flex items-center gap-3"
          :style="{ background: kpiBuilder.color || panelFamily[0] }"
        >
          <span
            class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"
            ><span :class="kpiBuilder.icon"
class="text-lg"
          /></span>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-bold">
              {{ kpiBuilder.id ? 'Editar indicador' : 'Novo indicador' }}
            </p>
            <p class="text-[11px] text-white/80 hidden sm:block">
              aparece no Meu Painel com o período da régua, histórico e
              comparação com o anterior
            </p>
          </div>
          <!-- prévia viva -->
          <div class="text-right max-w-[40%] flex-shrink-0">
            <p v-if="kpiPreview.ok" class="text-2xl font-bold leading-none">
              {{ kpiPreview.text }}
            </p>
            <p v-else class="text-[11px] text-white/85 leading-snug">
              {{ kpiPreview.text }}
            </p>
            <p v-if="kpiPreview.delta" class="text-[10px] text-white/80 mt-1">
              {{ kpiPreview.delta }}
            </p>
          </div>
          <button class="cv-glass-btn cv-iconbtn" @click="kpiBuilder = null">
            <span class="i-lucide-x text-sm" />
          </button>
        </div>

        <div class="p-5 space-y-4 overflow-y-auto">
          <!-- nome -->
          <div>
            <p class="cv-label mb-1">Nome do card</p>
            <input
              v-model="kpiBuilder.label"
              type="text"
              maxlength="60"
              placeholder="ex.: Taxa de agendamento"
              class="cv-input w-full text-n-slate-12"
            />
          </div>

          <!-- modo -->
          <div class="flex items-center gap-1.5">
            <span class="cv-seg">
              <button
                class="cv-seg-item"
                :class="kpiBuilderMode === 'ready' ? 'cv-seg-on' : ''"
                @click="kpiBuilderMode = 'ready'"
              >
                Indicador pronto
              </button>
              <button
                class="cv-seg-item"
                :class="kpiBuilderMode === 'formula' ? 'cv-seg-on' : ''"
                @click="kpiBuilderMode = 'formula'"
              >
                Fórmula
              </button>
            </span>
            <span class="text-[10px] text-n-slate-9 ml-1">os números abaixo são do período da régua</span>
          </div>

          <!-- indicadores prontos: primeiro as TAXAS já formuladas por
               categoria (item 143), depois os números-base do período -->
          <div
            v-if="kpiBuilderMode === 'ready'"
            class="max-h-72 overflow-y-auto pr-1 space-y-3"
          >
            <div v-for="sec in readyFormulaSections" :key="sec.cat">
              <p class="cv-label mb-1">
                {{ sec.cat }}
                <span class="normal-case font-normal">· taxas prontas</span>
              </p>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                <button
                  v-for="f in sec.items"
                  :key="f.label"
                  class="cv-btn !justify-between !h-9 !rounded-xl text-left"
                  :class="
                    kpiBuilder.expr.trim() === f.expr ? '' : 'cv-btn-ghost'
                  "
                  :title="f.note"
                  @click="applyReadyFormula(f)"
                >
                  <span class="truncate">{{ f.label }}</span><b class="whitespace-nowrap">{{ f.value }}</b>
                </button>
              </div>
            </div>
            <div v-for="sec in kpiCatalogSections" :key="sec.cat">
              <p class="cv-label mb-1">{{ sec.cat }}</p>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                <button
                  v-for="m in sec.items"
                  :key="m.key"
                  class="cv-btn !justify-between !h-9 !rounded-xl text-left"
                  :class="
                    kpiBuilder.expr.trim() === m.key ? '' : 'cv-btn-ghost'
                  "
                  @click="
                    kpiBuilder.expr = m.key;
                    if (!kpiBuilder.label) kpiBuilder.label = m.label;
                  "
                >
                  <span class="truncate">{{ m.label }}</span><b class="whitespace-nowrap">{{ m.value }}</b>
                </button>
              </div>
            </div>
          </div>

          <!-- fórmula -->
          <div v-else class="space-y-2">
            <textarea
              v-model="kpiBuilder.expr"
              rows="2"
              placeholder="ex.: appointments_booked / new_leads * 100"
              class="cv-input w-full font-mono text-n-slate-12"
            />
            <p class="text-[10px] text-n-slate-9">
              clique num indicador pra inserir na fórmula · use + − × ÷ e
              parênteses · % = multiplique por 100
            </p>
            <div class="flex flex-wrap gap-1 max-h-28 overflow-y-auto">
              <button
                v-for="m in kpiCatalog"
                :key="m.key"
                class="cv-chip"
                :title="m.key"
                @click="insertKpiVar(m.key)"
              >
                {{ m.label }}
              </button>
            </div>
          </div>

          <!-- formato + painel -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <p class="cv-label mb-1">Formato</p>
              <div class="flex items-center gap-1.5">
                <button
                  v-for="f in [
                    ['number', 'Número'],
                    ['percent', '%'],
                    ['currency', 'R$'],
                  ]"
                  :key="f[0]"
                  class="cv-btn cv-btn-sm"
                  :class="kpiBuilder.format === f[0] ? '' : 'cv-btn-ghost'"
                  @click="kpiBuilder.format = f[0]"
                >
                  {{ f[1] }}
                </button>
              </div>
            </div>
            <div>
              <p class="cv-label mb-1">Aparece em</p>
              <div class="flex items-center gap-1.5 flex-wrap">
                <button
                  v-for="pp in [
                    ['all', 'Todos os painéis'],
                    ['agendamento', 'Agendamento'],
                    ['conducao', 'Condução'],
                    ['cirurgia', 'Cirurgias'],
                    ['medico', 'Médicos'],
                    ['gestor', 'Gestor'],
                  ]"
                  :key="pp[0]"
                  class="cv-btn cv-btn-sm"
                  :class="kpiBuilder.panel === pp[0] ? '' : 'cv-btn-ghost'"
                  @click="kpiBuilder.panel = pp[0]"
                >
                  {{ pp[1] }}
                </button>
              </div>
            </div>
          </div>

          <!-- cor -->
          <div>
            <p class="cv-label mb-1">Cor do card</p>
            <div class="flex items-center gap-1.5 flex-wrap">
              <button
                class="cv-btn cv-btn-sm"
                :class="!kpiBuilder.color ? '' : 'cv-btn-ghost'"
                @click="kpiBuilder.color = ''"
              >
                automática
              </button>
              <button
                v-for="c in kpiColorOptions"
                :key="c.key"
                class="w-8 h-8 rounded-lg border-2"
                :class="
                  kpiBuilder.color === c.grad
                    ? 'border-n-slate-12 scale-110'
                    : 'border-transparent'
                "
                :style="{ background: c.grad }"
                :title="c.title"
                @click="kpiBuilder.color = c.grad"
              />
              <input
                v-model="kpiHexColor"
                type="text"
                placeholder="#152C61"
                maxlength="7"
                class="cv-input !h-8 w-24 text-xs font-mono text-n-slate-12"
                @change="applyHexColor"
                @keydown.enter.prevent="applyHexColor"
              />
            </div>
          </div>

          <!-- nota -->
          <div>
            <p class="cv-label mb-1">Nota (aparece no popup do card)</p>
            <input
              v-model="kpiBuilder.note"
              type="text"
              maxlength="200"
              placeholder="ex.: meta da clínica é 15%"
              class="cv-input w-full text-n-slate-12"
            />
          </div>
        </div>

        <div class="cv-modal-foot flex items-center gap-2">
          <button
            v-if="kpiBuilder.id"
            class="cv-btn cv-btn-ghost cv-btn-danger"
            :disabled="isSavingKpi"
            @click="deleteKpi(kpiBuilder)"
          >
            <span class="i-lucide-trash-2 text-xs" />Remover
          </button>
          <span class="flex-1" />
          <button class="cv-btn cv-btn-ghost" @click="kpiBuilder = null">
            Cancelar
          </button>
          <button
            class="cv-btn"
            :disabled="
              isSavingKpi || !kpiPreview.ok || !kpiBuilder.label.trim()
            "
            @click="saveKpiBuilder"
          >
            {{ isSavingKpi ? 'Salvando…' : 'Salvar card' }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
  <!-- 🍎🍊 Paleta do painel e dos blocos (admin, rodada 162): componente
       compartilhado com os Relatórios (rodada 163) -->
  <CevicoPalettePicker
    :pal="pal"
    :title="`Paleta de cores · ${currentPanel.label}`"
  />
  <!-- 🎨 Cor de qualquer card (item 143): palheta do modo organizar -->
  <Teleport to="body">
    <div
      v-if="colorPicker"
      class="cv-page cv-overlay fixed inset-0 z-[72] flex items-center justify-center bg-black/50 p-4"
      :style="cvVars"
      @click.self="colorPicker = null"
    >
      <div class="cv-modal w-full max-w-md">
        <div
          class="cv-modal-head !p-4 flex items-center gap-2"
          :style="{ background: tileVisual(colorPicker).grad }"
        >
          <span :class="colorPicker.icon" class="text-base" />
          <p class="text-sm font-bold flex-1 truncate">
            Cor do card "{{ colorPicker.label }}"
          </p>
          <button class="cv-glass-btn cv-iconbtn" @click="colorPicker = null">
            <span class="i-lucide-x text-sm" />
          </button>
        </div>
        <div class="p-4 space-y-3">
          <p class="text-[11px] text-n-slate-10 leading-relaxed">
            A cor vale pra todo mundo que vê este painel. Se o card estiver
            julgado por meta (vermelho/âmbar/verde), o alerta continua por cima
            da cor escolhida.
          </p>
          <div class="flex items-center gap-1.5 flex-wrap">
            <button
              class="cv-btn"
              :class="!colorPicker.customGrad ? '' : 'cv-btn-ghost'"
              title="Volta pra cor automática (família do painel)"
              @click="setTileColor(null)"
            >
              automática
            </button>
            <button
              v-for="c in kpiColorOptions"
              :key="c.key"
              class="w-9 h-9 rounded-lg border-2 transition-transform"
              :class="
                colorPicker.customGrad === c.grad
                  ? 'border-n-slate-12 scale-110'
                  : 'border-transparent hover:scale-105'
              "
              :style="{ background: c.grad }"
              :title="c.title"
              @click="setTileColor(c.grad)"
            />
          </div>
          <div class="flex items-center gap-2">
            <input
              v-model="tileHexColor"
              type="text"
              placeholder="#152C61"
              maxlength="7"
              class="cv-input w-28 text-xs font-mono text-n-slate-12"
              @keydown.enter.prevent="applyTileHexColor"
            />
            <button class="cv-btn cv-btn-ghost" @click="applyTileHexColor">
              usar este tom
            </button>
            <span
              v-if="isSavingLayout"
              class="i-lucide-loader-circle animate-spin text-sm text-n-slate-10 ml-auto"
            />
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
/* card da frente do Radar: pulso verde (como Tarefas 100%) */
.cevico-radar-front {
  border: 1px solid rgba(16, 185, 129, 0.45);
  animation: cevico-radar-pulse 2.2s ease-in-out infinite;
}
@keyframes cevico-radar-pulse {
  0%,
  100% {
    box-shadow: 0 0 8px rgba(16, 185, 129, 0.3);
  }
  50% {
    box-shadow: 0 0 22px rgba(52, 211, 153, 0.65);
  }
}
/* meta batida / recorde: o card respira com brilho suave */
.cevico-meta-pulse {
  animation: cevicoMetaPulse 2.6s ease-in-out infinite;
}
@keyframes cevicoMetaPulse {
  0%,
  100% {
    box-shadow: 0 10px 24px rgba(0, 0, 0, 0.2);
  }
  50% {
    box-shadow:
      0 10px 24px rgba(0, 0, 0, 0.2),
      0 0 26px 4px rgba(244, 222, 142, 0.45);
  }
}

/* botão de atalho pulsante (Ir para agenda) — respiração suave */
.cevico-pulse-btn {
  animation: cevico-pulse 2.2s ease-in-out infinite;
  transition: transform 0.15s ease;
}
.cevico-pulse-btn:hover {
  transform: scale(1.05);
  animation-play-state: paused;
}
@keyframes cevico-pulse {
  0%,
  100% {
    box-shadow: 0 0 0 0 rgba(124, 58, 237, 0.45);
  }
  50% {
    box-shadow: 0 0 0 9px rgba(124, 58, 237, 0);
  }
}

/* "Atender agora" do Radar — botão que EMANA ENERGIA (pedido 17/07):
   respiração + anéis verdes saindo do botão + brilho varrendo por cima */
.cevico-energy-btn {
  position: relative;
  background: linear-gradient(135deg, #059669, #22c55e, #4ade80);
  background-size: 200% 200%;
  overflow: hidden;
  animation:
    cevico-energy-breathe 2s ease-in-out infinite,
    cevico-energy-rings 2s ease-out infinite,
    cevico-energy-grad 4s ease-in-out infinite;
  transition: transform 0.15s ease;
}
.cevico-energy-btn:hover {
  transform: scale(1.06);
}
.cevico-energy-btn::after {
  content: '';
  position: absolute;
  inset: 0;
  background: linear-gradient(
    115deg,
    transparent 30%,
    rgba(255, 255, 255, 0.45) 50%,
    transparent 70%
  );
  transform: translateX(-120%);
  animation: cevico-energy-shine 2.6s ease-in-out infinite;
}
@keyframes cevico-energy-breathe {
  0%,
  100% {
    transform: scale(1);
  }
  50% {
    transform: scale(1.035);
  }
}
@keyframes cevico-energy-rings {
  0% {
    box-shadow:
      0 0 0 0 rgba(34, 197, 94, 0.5),
      0 0 0 0 rgba(34, 197, 94, 0.3);
  }
  100% {
    box-shadow:
      0 0 0 10px rgba(34, 197, 94, 0),
      0 0 0 18px rgba(34, 197, 94, 0);
  }
}
@keyframes cevico-energy-grad {
  0%,
  100% {
    background-position: 0% 50%;
  }
  50% {
    background-position: 100% 50%;
  }
}
@keyframes cevico-energy-shine {
  0%,
  55% {
    transform: translateX(-120%);
  }
  85%,
  100% {
    transform: translateX(120%);
  }
}
@media (prefers-reduced-motion: reduce) {
  .cevico-energy-btn,
  .cevico-energy-btn::after {
    animation: none;
  }
}

/* 🔍 popup dos indicadores (item 152): entrada suave estilo folha — o fundo
   escurece em fade e o cartão sobe com leve escala; saída mais rápida.
   Quem pede menos movimento no sistema recebe só o fade. */
.cevico-kpi-pop-enter-active {
  transition: opacity 0.22s ease;
}
.cevico-kpi-pop-leave-active {
  transition: opacity 0.15s ease;
}
.cevico-kpi-pop-enter-active .cevico-kpi-panel {
  transition:
    transform 0.26s cubic-bezier(0.32, 1.25, 0.5, 1),
    opacity 0.2s ease;
}
.cevico-kpi-pop-leave-active .cevico-kpi-panel {
  transition:
    transform 0.15s ease-in,
    opacity 0.15s ease-in;
}
.cevico-kpi-pop-enter-from,
.cevico-kpi-pop-leave-to {
  opacity: 0;
}
.cevico-kpi-pop-enter-from .cevico-kpi-panel {
  transform: translateY(14px) scale(0.97);
  opacity: 0;
}
.cevico-kpi-pop-leave-to .cevico-kpi-panel {
  transform: translateY(8px) scale(0.98);
  opacity: 0;
}
@media (prefers-reduced-motion: reduce) {
  .cevico-kpi-pop-enter-from .cevico-kpi-panel,
  .cevico-kpi-pop-leave-to .cevico-kpi-panel {
    transform: none;
  }
}
</style>
