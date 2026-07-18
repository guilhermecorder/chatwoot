import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import ReportsWrapper from './components/ReportsWrapper.vue';
import Index from './Index.vue';

import AgentReportsIndex from './AgentReportsIndex.vue';
import InboxReportsIndex from './InboxReportsIndex.vue';
import TeamReportsIndex from './TeamReportsIndex.vue';
import LabelReportsIndex from './LabelReportsIndex.vue';

import AgentReportsShow from './AgentReportsShow.vue';
import InboxReportsShow from './InboxReportsShow.vue';
import TeamReportsShow from './TeamReportsShow.vue';
import LabelReportsShow from './LabelReportsShow.vue';

import AgentReports from './AgentReports.vue';
import InboxReports from './InboxReports.vue';
import LabelReports from './LabelReports.vue';
import TeamReports from './TeamReports.vue';

import CsatResponses from './CsatResponses.vue';
import BotReports from './BotReports.vue';
import LiveReports from './LiveReports.vue';
import SLAReports from './SLAReports.vue';
import LabelDashboard from './LabelDashboard.vue';
import CrmDashboardReport from './CrmDashboardReport.vue';
import WhatsappHealth from './WhatsappHealth.vue';
import TrafficFunnel from './TrafficFunnel.vue';
import DoctorsDashboard from './DoctorsDashboard.vue';
import AgentsDashboard from './AgentsDashboard.vue';
import GoogleDashboard from './GoogleDashboard.vue';
import AgendaDashboard from './AgendaDashboard.vue';
import AdsReport from './AdsReport.vue';

const meta = {
  featureFlag: FEATURE_FLAGS.REPORTS,
  permissions: ['administrator', 'report_manage'],
};

const oldReportRoutes = [
  {
    path: 'agent',
    name: 'agent_reports',
    meta,
    component: AgentReports,
  },
  {
    path: 'inboxes',
    name: 'inbox_reports',
    meta,
    component: InboxReports,
  },
  {
    path: 'label',
    name: 'label_reports',
    meta,
    component: LabelReports,
  },
  {
    path: 'teams',
    name: 'team_reports',
    meta,
    component: TeamReports,
  },
];

const revisedReportRoutes = [
  {
    path: 'agents_overview',
    name: 'agent_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentReportsIndex,
  },
  {
    path: 'agents/:id',
    name: 'agent_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: AgentReportsShow,
  },

  {
    path: 'inboxes_overview',
    name: 'inbox_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: InboxReportsIndex,
  },
  {
    path: 'inboxes/:id',
    name: 'inbox_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: InboxReportsShow,
  },
  {
    path: 'teams_overview',
    name: 'team_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: TeamReportsIndex,
  },
  {
    path: 'teams/:id',
    name: 'team_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: TeamReportsShow,
  },
  {
    path: 'labels_overview',
    name: 'label_reports_index',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelReportsIndex,
  },
  {
    path: 'labels/:id',
    name: 'label_reports_show',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelReportsShow,
  },
  {
    path: 'labels_dashboard',
    name: 'label_dashboard',
    meta: {
      permissions: ['administrator', 'report_manage'],
    },
    component: LabelDashboard,
  },
];

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/reports'),
      component: ReportsWrapper,
      children: [
        {
          path: '',
          redirect: to => {
            return { name: 'account_overview_reports', params: to.params };
          },
        },
        {
          path: 'overview',
          name: 'account_overview_reports',
          meta,
          component: LiveReports,
        },
        {
          path: 'conversation',
          name: 'conversation_reports',
          meta,
          component: Index,
        },
        ...oldReportRoutes,
        ...revisedReportRoutes,
        {
          path: 'sla',
          name: 'sla_reports',
          meta,
          component: SLAReports,
        },
        {
          path: 'csat',
          name: 'csat_reports',
          meta,
          component: CsatResponses,
        },
        {
          path: 'bot',
          name: 'bot_reports',
          meta,
          component: BotReports,
        },
        {
          path: 'crm_dashboard',
          name: 'crm_dashboard_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: CrmDashboardReport,
        },
        {
          path: 'whatsapp_health',
          name: 'whatsapp_health_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: WhatsappHealth,
        },
        {
          path: 'traffic_funnel',
          name: 'traffic_funnel_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: TrafficFunnel,
        },
        {
          path: 'doctors',
          name: 'doctors_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: DoctorsDashboard,
        },
        {
          path: 'google_dashboard',
          name: 'google_dashboard_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: GoogleDashboard,
        },
        {
          path: 'agents_dashboard',
          name: 'agents_dashboard_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: AgentsDashboard,
        },
        {
          path: 'agenda_dashboard',
          name: 'agenda_dashboard_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: AgendaDashboard,
        },
        {
          path: 'ads',
          name: 'ads_reports',
          meta: {
            permissions: ['administrator', 'agent', 'report_manage'],
          },
          component: AdsReport,
        },
      ],
    },
  ],
};
