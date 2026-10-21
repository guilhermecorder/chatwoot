// Os quadros do Painel do empresário e onde cada um nasce (grade de 12
// colunas; h em linhas de 16 px). Quadro novo? Acrescente aqui — quem já
// arrumou o painel recebe o novo no fim (mergeLayout).
import RadarCard from './widgets/RadarCard.vue';
import TimelineCard from './widgets/TimelineCard.vue';
import KanbanCard from './widgets/KanbanCard.vue';
import SpcCard from './widgets/SpcCard.vue';
import YearCard from './widgets/YearCard.vue';
import MatrixCard from './widgets/MatrixCard.vue';
import PeopleCard from './widgets/PeopleCard.vue';
import MetricsCard from './widgets/MetricsCard.vue';
import ProblemsCard from './widgets/ProblemsCard.vue';
import CoreActivitiesCard from './widgets/CoreActivitiesCard.vue';

export const CARDS = [
  {
    id: 'radar',
    title: 'Teia radar',
    sub: 'status atual × onde queremos chegar',
    icon: 'i-lucide-radar',
    color: '#0A84FF',
    comp: RadarCard,
    def: { x: 0, y: 0, w: 8, h: 26 },
  },
  {
    id: 'timeline',
    title: 'Linha do tempo',
    sub: 'tudo com data',
    icon: 'i-lucide-history',
    color: '#FF375F',
    comp: TimelineCard,
    def: { x: 8, y: 0, w: 4, h: 26 },
  },
  {
    id: 'kanban',
    title: 'Coisas muito importantes',
    sub: 'semana do empresário · a fazer, fazendo, feito',
    icon: 'i-lucide-star',
    color: '#FF9F0A',
    comp: KanbanCard,
    def: { x: 0, y: 26, w: 7, h: 17 },
  },
  {
    id: 'spc',
    title: 'Continuar · Parar · Começar',
    sub: 'o que manter, cortar e iniciar',
    icon: 'i-lucide-refresh-ccw',
    color: '#30A46C',
    comp: SpcCard,
    def: { x: 7, y: 26, w: 5, h: 17 },
  },
  {
    id: 'objectives',
    title: 'Objetivos do ano',
    sub: 'SMART: específico, mensurável, alcançável, realista, com tempo',
    icon: 'i-lucide-flag',
    color: '#C8962E',
    comp: YearCard,
    props: { section: 'objectives' },
    def: { x: 0, y: 43, w: 4, h: 13 },
  },
  {
    id: 'goals',
    title: 'Metas específicas',
    sub: 'até 8, com conquista',
    icon: 'i-lucide-target',
    color: '#0A84FF',
    comp: YearCard,
    props: { section: 'goals' },
    def: { x: 4, y: 43, w: 4, h: 13 },
  },
  {
    id: 'activities',
    title: 'Atividades estratégicas',
    sub: 'até 8, com conquista',
    icon: 'i-lucide-list-checks',
    color: '#30A46C',
    comp: YearCard,
    props: { section: 'activities' },
    def: { x: 8, y: 43, w: 4, h: 13 },
  },
  {
    id: 'priorities',
    title: 'Matriz de Prioridades',
    sub: 'importância × urgência',
    icon: 'i-lucide-grid-2x2',
    color: '#BF5AF2',
    comp: MatrixCard,
    props: { section: 'priorities' },
    def: { x: 0, y: 56, w: 6, h: 24 },
  },
  {
    id: 'people',
    title: 'Equipe',
    sub: 'pessoas estratégicas: sócios, mentores, fornecedores, parceiros',
    icon: 'i-lucide-users-round',
    color: '#152C61',
    comp: PeopleCard,
    def: { x: 0, y: 80, w: 4, h: 15 },
  },
  {
    id: 'opportunities',
    title: 'Matriz de Oportunidades',
    sub: 'resultados × esforço',
    icon: 'i-lucide-gem',
    color: '#FF9F0A',
    comp: MatrixCard,
    props: { section: 'opportunities' },
    def: { x: 6, y: 56, w: 6, h: 24 },
  },
  {
    id: 'metrics',
    title: 'Métricas da empresa',
    sub: 'Oftalmofácil · Financeiro · estimativas',
    icon: 'i-lucide-bar-chart-3',
    color: '#C8962E',
    comp: MetricsCard,
    def: { x: 4, y: 80, w: 8, h: 17 },
  },
  {
    id: 'problems',
    title: 'Problemas → Solução',
    sub: 'o que dói e a saída mais rápida',
    icon: 'i-lucide-flame',
    color: '#FF375F',
    comp: ProblemsCard,
    def: { x: 0, y: 97, w: 6, h: 15 },
  },
  {
    id: 'core',
    title: 'Atividades principais',
    sub: 'o que, bem feito, sustenta a empresa — ultra específico',
    icon: 'i-lucide-target',
    color: '#C8962E',
    comp: CoreActivitiesCard,
    def: { x: 6, y: 97, w: 6, h: 15 },
  },
];

export const CARD_BY_ID = Object.fromEntries(CARDS.map(c => [c.id, c]));
export const DEFAULT_LAYOUT = CARDS.map(c => ({
  id: c.id,
  ...c.def,
  hidden: false,
}));
