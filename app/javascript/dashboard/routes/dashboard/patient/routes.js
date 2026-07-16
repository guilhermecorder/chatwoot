import { frontendURL } from '../../../helper/URLHelper';
import PatientSpace from './PatientSpace.vue';

export default {
  routes: [
    {
      // Espaço do Paciente (Central do Paciente): aberto do card do CRM,
      // do balão, do painel da conversa e da Agenda
      path: frontendURL('accounts/:accountId/patient/:contactId'),
      name: 'patient_space',
      meta: { permissions: ['administrator', 'agent'] },
      component: PatientSpace,
    },
  ],
};
