// 🎨 CEVICO item 212: a cor de cada pessoa da equipe, pronta para usar em
// qualquer tela — lê a equipe (agents) e as cores escolhidas pelo admin
// (crm settings → person_colors) do store. Robô/Atendente IA = lilás.
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import {
  personColorFor,
  BOT_COLOR,
  UNASSIGNED_COLOR,
} from 'dashboard/helper/cevicoPersonColors';

export function useCevicoPersonColors() {
  const agents = useMapGetter('agents/getAgents');
  const settings = useMapGetter('crm/getSettings');
  const overrides = computed(() => settings.value?.person_colors || {});

  // agentLike = {id, name, assignee_type?|type?} ou só o id
  const colorFor = agentLike => {
    if (agentLike && typeof agentLike === 'object') {
      const kind = agentLike.assignee_type || agentLike.type;
      if (kind === 'AgentBot' || kind === 'agent_bot') return BOT_COLOR;
      return personColorFor(
        agents.value || [],
        agentLike.id ?? agentLike.name,
        overrides.value
      );
    }
    return personColorFor(agents.value || [], agentLike, overrides.value);
  };

  // 23/09 ("a cor dos pacientes da cor da atendente"): o degradê da "foto"
  // do paciente numa conversa = a cor de quem cuida; sem responsável = cinza
  const patientGradientFor = chat => {
    const assignee = chat?.meta?.assignee;
    if (!assignee?.id && !assignee?.name) return UNASSIGNED_COLOR.grad;
    return colorFor({
      id: assignee.id,
      name: assignee.name,
      assignee_type: chat?.meta?.assignee_type,
    }).grad;
  };

  return { agents, overrides, colorFor, patientGradientFor };
}
