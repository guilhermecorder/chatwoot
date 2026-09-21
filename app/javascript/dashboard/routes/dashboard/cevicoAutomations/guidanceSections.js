// ✍️ rodada 191: seções do Roteiro onde uma orientação pode entrar — usadas
// pelo GuidanceModal (escolha) e pelo GuidancesPanel (chip da lista).
export const GUIDANCE_SECTIONS = [
  { key: 'objections', label: 'Objeções', icon: 'i-lucide-shield-question' },
  { key: 'official_data', label: 'Dados oficiais', icon: 'i-lucide-database' },
  { key: 'persona', label: 'Quem ele é', icon: 'i-lucide-user-round' },
  { key: 'form_rules', label: 'Regras de forma', icon: 'i-lucide-text-quote' },
  { key: 'handoff', label: 'Passar p/ humano', icon: 'i-lucide-hand' },
  { key: 'stage', label: 'Passos do agente', icon: 'i-lucide-list-ordered' },
];

export const GUIDANCE_AGENT_LABEL = {
  atendente_agendamento: 'Atendente de Agendamento',
  atendente_pos: 'Atendente Pós-agendamento',
};

export const sectionLabel = key =>
  GUIDANCE_SECTIONS.find(s => s.key === key)?.label || key || '—';
