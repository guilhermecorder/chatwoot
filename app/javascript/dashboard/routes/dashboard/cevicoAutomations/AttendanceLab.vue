<script setup>
// 🧪 LABORATÓRIO DE ATENDIMENTO (item 403, 23/11, só admin): o ambiente de
// comparação dos testes A/B dos atendentes — feito para DECIDIR.
// Em ordem de leitura: o veredito (quem marca mais consulta e com que
// confiança) → a taxa andando dia a dia → o caminho do paciente em cada
// variante (conversa → respondeu → consulta → compareceu → cirurgia) →
// quanto custa cada uma → a conta da decisão (e se tudo fosse B?) → o que
// muda entre os dois prompts → decidir → testes anteriores.
// Quem monta o teste (variante B, caixas, liga/desliga) é o cartão do agente.
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import TimelineChart from 'dashboard/components-next/cevico/TimelineChart.vue';
import FunnelSteps from 'dashboard/components-next/cevico/FunnelSteps.vue';
import { useCevicoPalette } from 'dashboard/composables/useCevicoPalette';
import CrmAPI from 'dashboard/api/crm';

const emit = defineEmits(['openAgent']);

// identidade das variantes: A azul royal (a oficial), B laranja (a desafiante)
const COLOR = { a: '#2563eb', b: '#f97316' };
const GRAD = {
  a: 'linear-gradient(135deg, #1d4ed8, #3b82f6)',
  b: 'linear-gradient(135deg, #ea580c, #fb923c)',
};
const KIND = {
  prompt: { label: 'Teste de prompt', what: 'o prompt' },
  motor: { label: 'Teste de motor', what: 'o motor (a inteligência)' },
  ambos: { label: 'Prompt + motor juntos', what: 'o prompt e o motor' },
};
const MODE_LABEL = { a: 'tudo na A', b: 'tudo na B', split: 'sorteio' };
const VIEWS = [
  { key: 'taxa', label: 'Taxa de consulta' },
  { key: 'conversas', label: 'Conversas por dia' },
  { key: 'custo', label: 'Custo por dia' },
];

const { cvVars, blockVars } = useCevicoPalette({
  scope: 'report:laboratorio',
  blocks: [
    { id: 'veredito', label: 'Veredito', icon: 'i-lucide-scale' },
    { id: 'tempo', label: 'Dia a dia', icon: 'i-lucide-trending-up' },
    { id: 'funil', label: 'Caminho do paciente', icon: 'i-lucide-filter' },
    { id: 'custo', label: 'Custo', icon: 'i-lucide-coins' },
    { id: 'decisao', label: 'Conta da decisão', icon: 'i-lucide-calculator' },
    { id: 'prompt', label: 'O que muda', icon: 'i-lucide-file-diff' },
    { id: 'historico', label: 'Testes anteriores', icon: 'i-lucide-history' },
    {
      id: 'consultor',
      label: 'Consultor superior',
      icon: 'i-lucide-graduation-cap',
    },
    { id: 'marco', label: 'Antes × depois', icon: 'i-lucide-flag' },
    { id: 'volta', label: 'Ponto de volta', icon: 'i-lucide-undo-2' },
  ],
});

const loading = ref(true);
const busy = ref(false);
const data = ref(null);
const agentKey = ref('atendente_agendamento');
const viewingId = ref('');
const chartView = ref('taxa');
const note = ref('');
// 📍 24/11: marco escolhido para o antes × depois + campos do marco novo
const marcoId = ref('');
const marcoTitle = ref('');
const marcoAt = ref('');

const load = async () => {
  loading.value = true;
  try {
    const { data: payload } = await CrmAPI.getAttendanceLab({
      agent: agentKey.value,
      ...(viewingId.value ? { test: viewingId.value } : {}),
      ...(marcoId.value ? { marco: marcoId.value } : {}),
    });
    data.value = payload;
  } catch (e) {
    useAlert(
      e?.response?.data?.error || 'Não consegui carregar o Laboratório.'
    );
  } finally {
    loading.value = false;
  }
};
onMounted(load);

const pickAgent = key => {
  agentKey.value = key;
  viewingId.value = '';
  load();
};
const openTest = id => {
  viewingId.value = id;
  load();
};

// ── leitura do que veio ──
const test = computed(() => data.value?.test || {});
const report = computed(() => data.value?.report || {});
const arms = computed(() => report.value.arms || []);
const armOf = key => arms.value.find(a => a.arm === key) || {};
const A = computed(() => armOf('a'));
const B = computed(() => armOf('b'));
const stats = computed(() => report.value.stats || null);
const projection = computed(() => report.value.projection || null);
const history = computed(() => data.value?.history || []);
const hasTest = computed(() => !!report.value.started_at);
const hasScore = computed(() =>
  arms.value.some(a => a.conversas > 0 || a.custo_usd > 0)
);
const shadowOnly = computed(
  () => hasScore.value && arms.value.every(a => !a.respostas && a.sombras > 0)
);
const kind = computed(() => KIND[test.value.kind] || null);
const scriptOf = arm => {
  if (arm === 'a') return 'Roteiro 1';
  const used = B.value.script || test.value.script_b;
  return used === 'v2' ? 'Roteiro 2' : 'Roteiro 1';
};
// "claude-haiku-4-5" → "Claude Haiku 4.5"; "gpt-6.2-sol" → "GPT 6.2 Sol"
const modelName = id => {
  if (!id) return '—';
  return String(id)
    .replace(/(\d)-(\d)/g, '$1.$2')
    .split('-')
    .map(word => {
      if (word === 'gpt') return 'GPT';
      return word.charAt(0).toUpperCase() + word.slice(1);
    })
    .join(' ');
};
// 🧭 item 405 (motor por coluna): o mapa das duas variantes, coluna a coluna
// [{ slot, name, a, b }]. "Por coluna" = a A tem motor próprio em alguma
// coluna, ou a B troca o motor só em parte delas.
const stageRows = computed(() => test.value.stages || []);
const swappedRows = computed(() => stageRows.value.filter(r => r.a !== r.b));
const byStage = computed(
  () =>
    stageRows.value.some(r => r.a !== test.value.model_a) ||
    (swappedRows.value.length > 0 &&
      swappedRows.value.length < stageRows.value.length)
);
const modelOf = arm => {
  if (byStage.value) {
    if (arm === 'a' || !swappedRows.value.length) return 'motor por coluna';
    return `${modelName(test.value.model_b)} em ${swappedRows.value.length} coluna(s)`;
  }
  return modelName(
    armOf(arm).model || (arm === 'a' ? test.value.model_a : test.value.model_b)
  );
};

// ── formatos ──
const rate = computed(() => Number(data.value?.usd_brl) || 0);
const money = (usd, digits = null) => {
  if (usd === null || usd === undefined) return '—';
  const brl = usd * rate.value;
  if (rate.value) {
    const max = digits ?? (Math.abs(brl) < 1 ? 3 : 2);
    return brl.toLocaleString('pt-BR', {
      style: 'currency',
      currency: 'BRL',
      minimumFractionDigits: Math.min(2, max),
      maximumFractionDigits: max,
    });
  }
  const max = digits ?? (Math.abs(usd) < 1 ? 4 : 2);
  return `US$ ${Number(usd).toLocaleString('pt-BR', {
    minimumFractionDigits: Math.min(2, max),
    maximumFractionDigits: max,
  })}`;
};
const num = v => Number(v || 0).toLocaleString('pt-BR');

// 🧑‍🏫 item 414: contador do consultor superior deste atendente (7 dias)
const consultor = computed(() => data.value?.consultor || null);
const consultorTotal = computed(() => consultor.value?.stats?.total || {});
const consultorAnswered = computed(
  () =>
    (consultorTotal.value.consultas || 0) +
    (consultorTotal.value.testes || 0) -
    (consultorTotal.value.falhas || 0)
);
const consultorShown = computed(
  () =>
    !!consultor.value &&
    (consultor.value.enabled ||
      (consultorTotal.value.consultas || 0) +
        (consultorTotal.value.testes || 0) >
        0)
);
const consultorHeadline = computed(() => {
  const total = consultorTotal.value;
  const asked = (total.consultas || 0) + (total.testes || 0);
  if (!asked)
    return 'O consultor superior está ligado e ainda não foi chamado.';
  const changed = total.mudou || 0;
  const verb =
    consultor.value.mode === 'ativo' ? 'mudou' : 'mudaria (está em sombra)';
  return `O consultor superior foi chamado ${num(asked)} ${asked === 1 ? 'vez' : 'vezes'} em ${consultor.value.stats.span} dias e ${verb} ${num(changed)} ${changed === 1 ? 'resposta' : 'respostas'}.`;
});
const consultorRows = (bag, labels) =>
  Object.entries(bag || {})
    .sort((a, b) => b[1] - a[1])
    .map(([key, count]) => ({ key, count, label: labels?.[key] || key }));
const pct = v =>
  v === null || v === undefined
    ? '—'
    : `${Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const day = iso =>
  iso
    ? new Date(iso).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';

// ── veredito: o título conta a história ──
const leader = computed(() => {
  const a = A.value.taxa_consulta;
  const b = B.value.taxa_consulta;
  if (a === null || b === null || a === undefined || b === undefined) return '';
  if (a === b) return '';
  return b > a ? 'b' : 'a';
});
const headline = computed(() => {
  const v = report.value.verdict;
  if (!hasScore.value) return 'O teste ainda não atendeu ninguém.';
  if (shadowOnly.value) return 'Em sombra: por enquanto, compare o custo.';
  const score = `${pct(A.value.taxa_consulta)} na A × ${pct(B.value.taxa_consulta)} na B`;
  if (!v || v.status === 'cedo')
    return leader.value
      ? `Ainda é cedo. Hoje a ${leader.value.toUpperCase()} está na frente: ${score}.`
      : `Ainda é cedo: ${score}.`;
  if (v.status === 'empate') return `Empate técnico: ${score}.`;
  return `A variante ${v.status.toUpperCase()} marca mais consulta: ${score}.`;
});
const subline = computed(() => {
  const v = report.value.verdict;
  if (!hasScore.value)
    return 'O placar aparece depois do primeiro atendimento numa caixa do teste.';
  if (shadowOnly.value)
    return 'O atendente está em sombra: nada foi enviado ao paciente. Leia as respostas na tela Sombra e compare o custo de cada variante.';
  if (!v || v.status === 'cedo')
    return `Faltam ${num(v?.missing)} conversas na variante com menos atendimentos para a primeira leitura (mínimo de ${report.value.min_sample} em cada).`;
  if (v.status === 'empate') {
    const left = stats.value?.days_left;
    return left
      ? `Com esta amostra a diferença pode ser acaso. No ritmo de hoje, ela pediria mais uns ${num(left)} dia(s) de teste para virar certeza. Se o custo for parecido, vale esperar; se não, decida pelo custo.`
      : 'Com esta amostra não há diferença confiável de conversão entre as duas: decida pelo custo.';
  }
  return 'A diferença é grande demais para ser acaso (95% de confiança). Veja abaixo quanto custa e decida.';
});
const chanceB = computed(() => stats.value?.chance_b ?? null);
const chanceText = computed(() => {
  if (chanceB.value === null) return '';
  const side = chanceB.value >= 50 ? 'B' : 'A';
  const value = chanceB.value >= 50 ? chanceB.value : 100 - chanceB.value;
  return `${pct(Math.round(value))} de chance de a ${side} ser a melhor`;
});

// ── dia a dia ──
const daily = computed(() => report.value.daily || []);
const dayLabels = computed(() => daily.value.map(d => day(`${d.date}T12:00`)));
const cumulative = arm => {
  let talks = 0;
  let hits = 0;
  return daily.value.map(d => {
    talks += d[arm]?.conversas || 0;
    hits += d[arm]?.consultas || 0;
    return talks > 0 ? Math.round((hits / talks) * 1000) / 10 : null;
  });
};
const chartLines = computed(() => {
  const series = arm => {
    if (chartView.value === 'taxa') return cumulative(arm);
    if (chartView.value === 'conversas')
      return daily.value.map(d => d[arm]?.conversas || 0);
    return daily.value.map(d => (d[arm]?.custo_usd || 0) * (rate.value || 1));
  };
  const legend = arm => {
    if (chartView.value === 'taxa') return pct(armOf(arm).taxa_consulta);
    if (chartView.value === 'conversas') return num(armOf(arm).conversas);
    return money(armOf(arm).custo_usd);
  };
  return ['a', 'b'].map(arm => ({
    key: arm,
    label: `${arm.toUpperCase()} · ${scriptOf(arm)} · ${modelOf(arm)}`,
    color: COLOR[arm],
    values: series(arm),
    dots: daily.value.length <= 14,
    legendValue: legend(arm),
  }));
});
const chartFormat = computed(() => {
  if (chartView.value === 'taxa') return v => pct(v);
  if (chartView.value === 'conversas') return v => num(Math.round(v));
  return v =>
    Number(v || 0).toLocaleString('pt-BR', {
      style: 'currency',
      currency: rate.value ? 'BRL' : 'USD',
      maximumFractionDigits: 2,
    });
});
const chartTitle = computed(() => {
  if (chartView.value === 'taxa')
    return 'De cada 100 conversas, quantas viraram consulta';
  if (chartView.value === 'conversas')
    return 'Quantas conversas cada variante atendeu por dia';
  return 'Quanto cada variante gastou de IA por dia';
});
const chartHint = computed(() => {
  if (chartView.value === 'taxa')
    return 'taxa acumulada desde o começo do teste: as duas linhas se afastando e ficando afastadas é o sinal de diferença de verdade';
  if (chartView.value === 'conversas')
    return 'no sorteio as duas linhas andam juntas; se uma descola, a comparação fica injusta';
  return 'custo de IA de todas as chamadas do dia, mesmo as que deram erro';
});

// ── funil de cada variante ──
const funnel = arm => {
  const row = armOf(arm);
  return [
    { label: 'Conversas', value: row.conversas || 0 },
    { label: 'Paciente respondeu', value: row.respondeu || 0 },
    { label: 'Consulta marcada', value: row.com_consulta || 0 },
    { label: 'Compareceu', value: row.compareceu || 0 },
    { label: 'Cirurgia marcada', value: row.cirurgia || 0 },
  ].map(step => ({
    ...step,
    color: COLOR[arm],
    // fatia das conversas que chegou até aqui (a versão de celular usa)
    share: row.conversas ? (step.value / row.conversas) * 100 : 0,
  }));
};

// ── custo lado a lado: cada linha na própria escala ──
const costRows = computed(() => {
  const rows = [
    { label: 'Custo por conversa', key: 'custo_por_conversa_usd' },
    { label: 'Custo por consulta marcada', key: 'custo_por_consulta_usd' },
    { label: 'Custo por comparecimento', key: 'custo_por_comparecimento_usd' },
    { label: 'Custo por cirurgia marcada', key: 'custo_por_cirurgia_usd' },
    { label: 'Custo total do teste', key: 'custo_usd' },
  ];
  return rows
    .map(row => {
      const a = A.value[row.key];
      const b = B.value[row.key];
      const max = Math.max(Number(a) || 0, Number(b) || 0);
      const width = v => (max > 0 && v ? Math.max(3, (v / max) * 100) : 0);
      let cheaper = '';
      if (a && b && a !== b) cheaper = a < b ? 'a' : 'b';
      return { ...row, a, b, wa: width(a), wb: width(b), cheaper };
    })
    .filter(row => row.a || row.b);
});

// ── a conta da decisão, por extenso ──
const decisionText = computed(() => {
  const p = projection.value;
  if (!p) return '';
  const cost = p.extra_custo_usd;
  const hits = p.extra_consultas;
  const costPart =
    Math.abs(cost) < 0.005
      ? 'custaria o mesmo de IA'
      : `custaria ${money(Math.abs(cost), 2)} ${cost > 0 ? 'a mais' : 'a menos'} de IA por mês`;
  const hitsPart =
    Math.abs(hits) < 0.5
      ? 'marcaria o mesmo número de consultas'
      : `marcaria ${num(Math.abs(Math.round(hits)))} consulta(s) ${hits > 0 ? 'a mais' : 'a menos'} por mês`;
  let closing = '';
  if (p.custo_por_consulta_extra_usd !== null && cost > 0)
    closing = ` Cada consulta a mais sairia por ${money(p.custo_por_consulta_extra_usd, 2)} de IA.`;
  else if (cost <= 0 && hits > 0.5)
    closing = ' Mais consultas gastando o mesmo ou menos.';
  else if (cost > 0 && hits <= 0.5)
    closing = ' Gasta mais e não traz consulta a mais.';
  return `Se todas as ${num(p.conversas_mes)} conversas do mês fossem na B, ela ${costPart} e ${hitsPart}.${closing}`;
});

// ── o que muda entre os prompts ──
const promptDiff = computed(() => data.value?.prompt?.different || []);
const changedSince = computed(
  () => data.value?.prompt?.changed_since_start || {}
);
const usesScript2 = computed(() => test.value.script_b === 'v2');
const sameMotor = computed(() => {
  if (byStage.value) return !swappedRows.value.length;
  return modelOf('a') === modelOf('b') || !test.value.model_b;
});

// ── estado do teste ──
const isCurrent = computed(() => test.value.current !== false);
const ended = computed(() => !!(test.value.ended_at || report.value.ended_at));
const stateChip = computed(() => {
  if (!isCurrent.value || ended.value) return 'encerrado';
  return test.value.enabled ? 'ligado' : 'pausado';
});
const inboxes = computed(() => data.value?.inboxes || []);

// ── ações ──
const finish = async (decision, apply) => {
  if (busy.value) return;
  let question = 'Encerrar o teste e guardar no histórico, sem decisão?';
  if (decision === 'a')
    question =
      'Encerrar o teste e ficar com a variante A (a oficial)? Nada muda no atendimento.';
  if (decision === 'b') {
    const parts = [];
    if (usesScript2.value)
      parts.push(
        'o Roteiro 2 vira o Roteiro oficial (o de antes fica guardado nas versões do Roteiro, com "voltar para esta")'
      );
    if (!sameMotor.value && byStage.value)
      parts.push(
        `o motor por coluna passa a usar ${modelName(test.value.model_b)} em: ${swappedRows.value.map(r => r.name).join(', ')}`
      );
    else if (!sameMotor.value)
      parts.push(`o motor do cartão passa a ser ${modelOf('b')}`);
    question = `Adotar a variante B? ${parts.join(' e ')}. O teste é encerrado e todas as conversas passam a ser atendidas assim.`;
  }
  // eslint-disable-next-line no-alert
  if (!window.confirm(question)) return;
  busy.value = true;
  try {
    const { data: payload } = await CrmAPI.finishAttendanceLab({
      agent: agentKey.value,
      decision,
      apply,
      note: note.value,
    });
    data.value = payload;
    note.value = '';
    useAlert(
      decision === 'b'
        ? 'Variante B adotada. Teste guardado no histórico.'
        : 'Teste encerrado e guardado no histórico.'
    );
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui encerrar o teste.');
  } finally {
    busy.value = false;
  }
};

const copyScript = async () => {
  if (busy.value) return;
  if (
    // eslint-disable-next-line no-alert
    !window.confirm(
      'Recomeçar o Roteiro 2 como cópia exata do Roteiro 1? O texto atual do Roteiro 2 é substituído (fica guardado um passo atrás). Depois, mude no Roteiro 2 só o que quer testar.'
    )
  )
    return;
  busy.value = true;
  try {
    const { data: payload } = await CrmAPI.copyScriptToLab({
      agent: agentKey.value,
    });
    data.value = payload;
    useAlert('Roteiro 2 agora é uma cópia do Roteiro 1.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui copiar o Roteiro.');
  } finally {
    busy.value = false;
  }
};

// ── 📍 MARCO DO ATENDIMENTO: antes × depois por caixa ──
const marcos = computed(() => data.value?.marcos || []);
const beforeAfter = computed(() => data.value?.before_after || null);
const restorePoint = computed(() => data.value?.restore_point || null);
const dayTime = iso =>
  iso
    ? new Date(iso).toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
      })
    : '—';
const horizonLabel = computed(() => {
  const hours = Number(beforeAfter.value?.horizon_hours || 0);
  if (hours < 48) return `${Math.max(Math.round(hours), 1)} h`;
  return `${Math.round(hours / 24)} dias`;
});
// diferença em pontos percentuais (depois − antes); null quando falta um lado
const delta = row => {
  const before = row?.before?.taxa;
  const after = row?.after?.taxa;
  if (before === null || before === undefined) return null;
  if (after === null || after === undefined) return null;
  return Math.round((after - before) * 10) / 10;
};
const deltaLabel = row => {
  const d = delta(row);
  if (d === null) return 'sem base';
  if (d === 0) return 'igual';
  return `${d > 0 ? '+' : '−'}${Math.abs(d).toLocaleString('pt-BR')} pt`;
};
const deltaColor = row => {
  const d = delta(row);
  if (d === null || d === 0) return '';
  return d > 0 ? '#059669' : '#dc2626';
};
// título que conta a história do marco
const marcoHeadline = computed(() => {
  const ba = beforeAfter.value;
  if (!ba) return '';
  const after = ba.total?.after;
  const before = ba.total?.before;
  if (!after?.conversas)
    return 'Ainda não chegou conversa nova depois do marco.';
  if (before?.taxa === null || before?.taxa === undefined)
    return `Depois do marco, ${pct(after.taxa)} das conversas novas viraram consulta.`;
  return `Depois do marco, ${pct(after.taxa)} das conversas novas viraram consulta; antes eram ${pct(before.taxa)}.`;
});
const pickMarco = id => {
  marcoId.value = id;
  load();
};
const addMarco = async () => {
  if (busy.value || !marcoTitle.value.trim()) return;
  busy.value = true;
  try {
    const { data: payload } = await CrmAPI.markAttendanceLab({
      agent: agentKey.value,
      title: marcoTitle.value.trim(),
      at: marcoAt.value ? new Date(marcoAt.value).toISOString() : '',
    });
    data.value = payload;
    marcoId.value = '';
    marcoTitle.value = '';
    marcoAt.value = '';
    useAlert('Marco anotado.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui anotar o marco.');
  } finally {
    busy.value = false;
  }
};
const removeMarco = async marco => {
  if (busy.value) return;
  // eslint-disable-next-line no-alert
  if (!window.confirm(`Apagar o marco "${marco.title}"? Só a anotação some.`))
    return;
  busy.value = true;
  try {
    const { data: payload } = await CrmAPI.unmarkAttendanceLab({
      agent: agentKey.value,
      id: marco.id,
    });
    data.value = payload;
    marcoId.value = '';
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui apagar o marco.');
  } finally {
    busy.value = false;
  }
};
// 🔙 ponto de volta: um toque devolve o atendimento ao formato de antes de 24/11
const applyRestorePoint = async () => {
  if (busy.value) return;
  if (
    // eslint-disable-next-line no-alert
    !window.confirm(
      'Voltar o atendimento ao formato de antes de 24/11? O Roteiro 1 e os Passos do Atendente de Agendamento voltam ao texto de 23/11, o motor por coluna é apagado (volta o modelo do cartão) e o teste em andamento é encerrado. O que está valendo hoje fica guardado no Histórico do Roteiro.'
    )
  )
    return;
  busy.value = true;
  try {
    const { data: payload } = await CrmAPI.restoreAttendancePoint({
      agent: agentKey.value,
      confirm: true,
    });
    data.value = payload;
    useAlert('Atendimento de volta ao formato de antes de 24/11.');
  } catch (e) {
    useAlert(e?.response?.data?.error || 'Não consegui voltar ao ponto.');
  } finally {
    busy.value = false;
  }
};

const decisionLabel = entry => {
  if (entry.decision === 'b') return entry.adopted ? 'adotou a B' : 'B ganhou';
  if (entry.decision === 'a') return 'ficou a A';
  return 'sem decisão';
};
</script>

<template>
  <div class="cv-page cv-overlay max-w-5xl pb-10" :style="cvVars">
    <!-- linha de cima: o que é + qual atendente -->
    <div class="mb-4 flex items-center gap-3 flex-wrap">
      <p class="text-[11px] text-n-slate-9 flex-1 min-w-[220px]">
        Compare duas versões do mesmo atendente e decida com número: primeiro o
        prompt, depois a inteligência.
      </p>
      <button
        class="cv-btn cv-btn-ghost cv-btn-sm flex-shrink-0"
        :disabled="loading"
        @click="load"
      >
        <span class="i-lucide-refresh-cw text-xs" />
        Atualizar
      </button>
    </div>
    <div v-if="data" class="cv-seg mb-5 flex-wrap">
      <button
        v-for="agent in data.agents"
        :key="agent.key"
        class="cv-seg-item"
        :class="{ 'cv-seg-on': agentKey === agent.key }"
        @click="pickAgent(agent.key)"
      >
        <span
          v-if="agent.running"
          class="inline-block w-1.5 h-1.5 rounded-full bg-emerald-500"
          title="teste ligado"
        />
        {{ agent.name }}
      </button>
    </div>

    <SkeletonScreen v-if="loading && !data" variant="dashboard" />

    <template v-else-if="data">
      <!-- vendo um teste antigo -->
      <div
        v-if="!isCurrent"
        class="cv-sub px-4 py-3 mb-4 flex items-center gap-3 flex-wrap"
      >
        <span class="i-lucide-history text-base text-n-slate-10" />
        <p class="text-sm text-n-slate-12 flex-1 min-w-0">
          Você está vendo um teste encerrado em {{ day(test.ended_at) }}. O
          funil continua amadurecendo: comparecimento e cirurgia entram depois.
        </p>
        <button class="cv-btn cv-btn-sm" @click="openTest('')">
          Voltar ao teste de agora
        </button>
      </div>

      <!-- ainda não há teste: os três passos -->
      <div
        v-if="!hasTest"
        class="cv-block p-6 sm:p-9 mb-6"
        :style="blockVars('veredito')"
      >
        <h2
          class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
        >
          Nenhum teste rodando neste atendente.
        </h2>
        <p class="text-sm text-n-slate-11 mt-2 mb-6 max-w-2xl">
          Um teste compara a versão oficial (A) com uma desafiante (B) nas
          mesmas caixas, no mesmo horário, sorteando metade das conversas para
          cada uma. Mude uma coisa de cada vez.
        </p>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div class="cv-sub p-5">
            <p class="text-xs font-bold text-n-slate-10 mb-1">
              1 · Prepare a B
            </p>
            <p class="text-sm text-n-slate-12 mb-3">
              Copie o Roteiro 1 para o Roteiro 2 e mude no 2 só o que quer
              testar.
            </p>
            <button
              class="cv-btn cv-btn-sm"
              :disabled="busy"
              @click="copyScript"
            >
              Copiar Roteiro 1 para o 2
            </button>
          </div>
          <div class="cv-sub p-5">
            <p class="text-xs font-bold text-n-slate-10 mb-1">
              2 · Ligue o teste
            </p>
            <p class="text-sm text-n-slate-12 mb-3">
              No cartão do atendente, escolha o Roteiro 2 na variante B e ponha
              as caixas em Sorteio.
            </p>
            <button class="cv-btn cv-btn-sm" @click="emit('openAgent')">
              Abrir o cartão do agente
            </button>
          </div>
          <div class="cv-sub p-5">
            <p class="text-xs font-bold text-n-slate-10 mb-1">
              3 · Decida aqui
            </p>
            <p class="text-sm text-n-slate-12">
              Quando houver conversas suficientes, esta tela mostra quem marca
              mais consulta, quanto custa e o botão para adotar a vencedora.
              Depois, repita trocando o motor.
            </p>
          </div>
        </div>
      </div>

      <template v-else>
        <!-- ══ VEREDITO ══ -->
        <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('veredito')">
          <div class="flex items-center gap-2 flex-wrap mb-3">
            <span v-if="kind" class="cv-chip cv-chip-lg">{{ kind.label }}</span>
            <span class="cv-chip cv-chip-lg">{{ stateChip }}</span>
            <span class="text-[11px] text-n-slate-9">
              desde {{ day(report.started_at) }} ·
              {{ num(Math.round(report.days || 0)) }} dia(s)
            </span>
          </div>
          <p v-if="test.name" class="text-sm text-n-slate-10 mb-1">
            {{ test.name }}
          </p>
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            {{ headline }}
          </h2>
          <p class="text-sm text-n-slate-11 mt-2 max-w-3xl">{{ subline }}</p>

          <!-- régua da confiança -->
          <div v-if="chanceB !== null && !shadowOnly" class="mt-6">
            <div class="flex items-baseline justify-between gap-3 mb-1.5">
              <p class="text-xs font-medium text-n-slate-11">
                {{ chanceText }}
              </p>
              <p class="text-[11px] text-n-slate-9">a casa decide com 95%</p>
            </div>
            <!-- trilho de A (esquerda) a B (direita); as pontas cheias são a
                 zona de decisão (95%); a bolinha é onde o teste está hoje -->
            <div class="relative h-3 mx-2">
              <div
                class="absolute inset-0 rounded-full"
                :style="{
                  background: `linear-gradient(90deg, ${COLOR.a} 0%, ${COLOR.a} 5%, rgb(148 163 184 / 0.28) 5%, rgb(148 163 184 / 0.28) 95%, ${COLOR.b} 95%, ${COLOR.b} 100%)`,
                }"
              />
              <div
                class="absolute inset-y-0 w-0.5 left-1/2 bg-n-slate-9 opacity-50"
              />
              <div
                class="absolute top-1/2 w-5 h-5 -translate-x-1/2 -translate-y-1/2 rounded-full border-[3px] border-white shadow-md transition-all duration-700"
                :style="{
                  left: `${chanceB}%`,
                  background: chanceB >= 50 ? COLOR.b : COLOR.a,
                }"
              />
            </div>
            <div class="flex justify-between text-[10px] text-n-slate-9 mt-2">
              <span>A com certeza</span>
              <span>cara ou coroa</span>
              <span>B com certeza</span>
            </div>
          </div>

          <!-- as duas variantes, lado a lado -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-6">
            <div
              v-for="arm in ['a', 'b']"
              :key="arm"
              class="rounded-3xl p-5 text-white shadow-lg"
              :style="{ background: GRAD[arm] }"
            >
              <p class="text-[11px] font-medium text-white/80">
                Variante {{ arm.toUpperCase() }} ·
                {{ arm === 'a' ? 'a oficial' : 'a desafiante' }}
              </p>
              <p class="text-sm font-bold mt-0.5">
                {{ scriptOf(arm) }} · {{ modelOf(arm) }}
              </p>
              <p
                class="text-4xl font-bold tracking-tight mt-3 whitespace-nowrap"
              >
                {{ pct(armOf(arm).taxa_consulta) }}
              </p>
              <p class="text-xs text-white/85">
                {{ num(armOf(arm).com_consulta) }} consulta(s) em
                {{ num(armOf(arm).conversas) }} conversa(s)
              </p>
              <div class="grid grid-cols-2 gap-3 mt-4 text-xs">
                <div>
                  <p class="text-white/70 text-[10px]">Custo por conversa</p>
                  <p class="font-bold whitespace-nowrap">
                    {{ money(armOf(arm).custo_por_conversa_usd) }}
                  </p>
                </div>
                <div>
                  <p class="text-white/70 text-[10px]">Custo por consulta</p>
                  <p class="font-bold whitespace-nowrap">
                    {{ money(armOf(arm).custo_por_consulta_usd) }}
                  </p>
                </div>
              </div>
            </div>
          </div>

          <p
            v-if="changedSince.a || changedSince.b"
            class="text-xs text-amber-600 mt-4"
          >
            Atenção: o texto do
            {{
              changedSince.a && changedSince.b
                ? 'Roteiro das duas variantes'
                : changedSince.b
                  ? `${scriptOf('b')} (variante B)`
                  : 'Roteiro 1 (variante A)'
            }}
            foi editado depois que o teste começou. O placar mistura o antes e o
            depois: para medir limpo, zere o placar no cartão do agente.
          </p>
          <p v-if="test.kind === 'ambos'" class="text-xs text-amber-600 mt-2">
            Este teste muda o prompt e o motor ao mesmo tempo: se a B ganhar,
            não dá para saber qual dos dois fez a diferença.
          </p>
          <p v-if="report.mixed" class="text-[11px] text-n-slate-10 mt-2">
            {{ report.mixed }} conversa(s) viram as duas variantes (a caixa
            mudou de modo no meio) e ficaram fora do placar.
          </p>
          <p v-if="!rate" class="text-[11px] text-n-slate-10 mt-2">
            Sem a cotação do dólar de hoje: custos em US$.
          </p>
        </div>

        <template v-if="hasScore">
          <!-- ══ DIA A DIA ══ -->
          <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('tempo')">
            <div class="flex items-start gap-3 flex-wrap mb-1">
              <h2
                class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 flex-1 min-w-[240px]"
              >
                {{ chartTitle }}
              </h2>
              <div class="cv-seg cv-seg-sm flex-wrap max-w-full">
                <button
                  v-for="view in VIEWS"
                  :key="view.key"
                  class="cv-seg-item"
                  :class="{ 'cv-seg-on': chartView === view.key }"
                  @click="chartView = view.key"
                >
                  {{ view.label }}
                </button>
              </div>
            </div>
            <p class="text-xs text-n-slate-10 mt-2 mb-5">{{ chartHint }}</p>
            <TimelineChart
              :labels="dayLabels"
              :lines="chartLines"
              :left-format="chartFormat"
              :height="260"
              empty-text="ainda sem conversas no teste"
            />
          </div>

          <!-- ══ CAMINHO DO PACIENTE ══ -->
          <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('funil')">
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Até onde o paciente vai em cada variante
            </h2>
            <p class="text-xs text-n-slate-10 mt-1 mb-6">
              consulta, comparecimento e cirurgia são lidos na Agenda, depois
              que a conversa entrou no teste (pela IA ou pela equipe).
              Comparecimento e cirurgia demoram semanas para aparecer.
            </p>
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div v-for="arm in ['a', 'b']" :key="arm" class="cv-sub p-5">
                <p class="text-sm font-bold text-n-slate-12 mb-4">
                  <span
                    class="inline-block w-2.5 h-2.5 rounded-full mr-1.5"
                    :style="{ background: COLOR[arm] }"
                  />
                  {{ arm.toUpperCase() }} · {{ scriptOf(arm) }} ·
                  {{ modelOf(arm) }}
                </p>
                <!-- computador: degraus; celular: barras deitadas (5 degraus
                     não cabem em 375 px) -->
                <div class="hidden sm:block">
                  <FunnelSteps
                    :steps="funnel(arm)"
                    :height="140"
                    start-text="das conversas"
                  />
                </div>
                <div class="sm:hidden space-y-3">
                  <div v-for="step in funnel(arm)" :key="step.label">
                    <div class="flex items-baseline justify-between gap-2 mb-1">
                      <span class="text-xs text-n-slate-11">{{
                        step.label
                      }}</span>
                      <span
                        class="text-xs tabular-nums whitespace-nowrap text-n-slate-12"
                      >
                        <b class="text-sm">{{ num(step.value) }}</b>
                        · {{ pct(Math.round(step.share * 10) / 10) }}
                      </span>
                    </div>
                    <div
                      class="h-2.5 rounded-full bg-n-alpha-2 overflow-hidden"
                    >
                      <div
                        class="h-full rounded-full"
                        :style="{
                          width: `${Math.max(step.value ? 2 : 0, step.share)}%`,
                          background: GRAD[arm],
                        }"
                      />
                    </div>
                  </div>
                </div>
                <p class="text-[11px] text-n-slate-10 mt-3">
                  chamou a equipe em {{ num(armOf(arm).humano) }} conversa(s) ·
                  {{ num(armOf(arm).erros) }} falha(s)
                </p>
              </div>
            </div>
          </div>

          <!-- ══ CUSTO ══ -->
          <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('custo')">
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              Quanto custa cada uma
            </h2>
            <p class="text-xs text-n-slate-10 mt-1 mb-6">
              custo de IA medido em cada chamada do teste; cada linha na própria
              escala, a mais barata marcada
            </p>
            <div class="space-y-5">
              <div v-for="row in costRows" :key="row.key">
                <p class="text-xs font-medium text-n-slate-11 mb-1.5">
                  {{ row.label }}
                </p>
                <div
                  v-for="arm in ['a', 'b']"
                  :key="arm"
                  class="flex items-center gap-3 mb-1.5"
                >
                  <span class="text-xs font-bold text-n-slate-11 w-4">{{
                    arm.toUpperCase()
                  }}</span>
                  <div
                    class="flex-1 h-3.5 rounded-full bg-n-alpha-2 overflow-hidden"
                  >
                    <div
                      class="h-full rounded-full transition-all duration-500"
                      :style="{
                        width: `${arm === 'a' ? row.wa : row.wb}%`,
                        background: GRAD[arm],
                      }"
                    />
                  </div>
                  <span
                    class="text-sm tabular-nums whitespace-nowrap text-n-slate-12 w-28 text-right"
                    :class="row.cheaper === arm ? 'font-bold' : ''"
                  >
                    {{ money(row[arm]) }}
                    <span v-if="row.cheaper === arm">✓</span>
                  </span>
                </div>
              </div>
            </div>
          </div>

          <!-- ══ A CONTA DA DECISÃO ══ -->
          <div
            v-if="projection && !shadowOnly"
            class="cv-block p-6 sm:p-9 mb-6"
            :style="blockVars('decisao')"
          >
            <h2
              class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
            >
              E se todas as conversas fossem na B?
            </h2>
            <p class="text-sm text-n-slate-12 mt-3 mb-6 max-w-3xl">
              {{ decisionText }}
            </p>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div
                v-for="arm in ['a', 'b']"
                :key="arm"
                class="cv-sub p-5"
                :style="{ borderColor: COLOR[arm] }"
              >
                <p class="text-xs text-n-slate-10">
                  Tudo na {{ arm.toUpperCase() }}, por mês
                </p>
                <p
                  class="text-2xl font-bold text-n-slate-12 mt-1 whitespace-nowrap"
                >
                  {{ num(Math.round(projection[arm].consultas)) }}
                  <span class="text-sm font-medium">consultas</span>
                </p>
                <p class="text-sm text-n-slate-11 whitespace-nowrap">
                  {{ money(projection[arm].custo_usd, 2) }} de IA
                </p>
              </div>
              <div class="cv-sub p-5">
                <p class="text-xs text-n-slate-10">Diferença da B para a A</p>
                <p
                  class="text-2xl font-bold text-n-slate-12 mt-1 whitespace-nowrap"
                >
                  {{ projection.extra_consultas > 0 ? '+' : ''
                  }}{{ num(Math.round(projection.extra_consultas)) }}
                  <span class="text-sm font-medium">consultas</span>
                </p>
                <p class="text-sm text-n-slate-11 whitespace-nowrap">
                  {{ projection.extra_custo_usd > 0 ? '+' : ''
                  }}{{ money(projection.extra_custo_usd, 2) }} de IA
                </p>
              </div>
            </div>
            <p class="text-[11px] text-n-slate-10 mt-4">
              conta feita com o volume real do teste ({{
                num(projection.conversas_mes)
              }}
              conversas por mês nas caixas dele). É projeção: vale mais quanto
              maior a amostra.
            </p>
          </div>
        </template>

        <!-- ══ O QUE MUDA ENTRE A E B ══ -->
        <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('prompt')">
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            O que muda entre a A e a B
          </h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-5">
            <div class="cv-sub p-5">
              <p class="text-xs text-n-slate-10">Motor (a inteligência)</p>
              <p class="text-sm font-bold text-n-slate-12 mt-1">
                {{
                  sameMotor
                    ? `O mesmo nas duas: ${modelOf('a')}`
                    : `${modelOf('a')} × ${modelOf('b')}`
                }}
              </p>
              <!-- 🧭 item 405: o mapa coluna a coluna -->
              <div v-if="byStage" class="mt-3 space-y-1.5">
                <div
                  v-for="row in stageRows"
                  :key="row.slot"
                  class="flex flex-wrap items-baseline gap-x-2 text-xs"
                >
                  <span class="text-n-slate-11 flex-1 basis-32 min-w-0">{{
                    row.name
                  }}</span>
                  <span class="text-n-slate-12 whitespace-nowrap">
                    <b :style="{ color: COLOR.a }">A</b>
                    {{ modelName(row.a) }}
                  </span>
                  <span
                    class="whitespace-nowrap"
                    :class="
                      row.a === row.b
                        ? 'text-n-slate-10'
                        : 'text-n-slate-12 font-bold'
                    "
                  >
                    <b :style="{ color: COLOR.b }">B</b>
                    {{ row.a === row.b ? 'igual' : modelName(row.b) }}
                  </span>
                </div>
              </div>
            </div>
            <div class="cv-sub p-5">
              <p class="text-xs text-n-slate-10">Prompt (o Roteiro)</p>
              <p class="text-sm font-bold text-n-slate-12 mt-1">
                {{
                  usesScript2
                    ? `Roteiro 1 × Roteiro 2: ${promptDiff.length} de ${data.prompt.total} partes diferentes`
                    : 'O mesmo nas duas: Roteiro 1'
                }}
              </p>
            </div>
          </div>

          <template v-if="isCurrent">
            <div v-if="promptDiff.length" class="mt-5 space-y-2">
              <p class="text-xs text-n-slate-10">
                {{
                  usesScript2
                    ? 'As partes em que o Roteiro 2 é diferente do Roteiro 1 hoje:'
                    : 'O Roteiro 2 (ainda fora do teste) é diferente do Roteiro 1 nestas partes:'
                }}
              </p>
              <details
                v-for="section in promptDiff"
                :key="section.key"
                class="cv-sub px-4 py-3"
              >
                <summary
                  class="text-sm font-medium text-n-slate-12 cursor-pointer"
                >
                  {{ section.title }}
                </summary>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-3">
                  <div v-for="arm in ['a', 'b']" :key="arm">
                    <p
                      class="text-[11px] font-bold mb-1"
                      :style="{ color: COLOR[arm] }"
                    >
                      {{ arm === 'a' ? 'Roteiro 1' : 'Roteiro 2' }}
                    </p>
                    <pre
                      class="text-xs text-n-slate-11 whitespace-pre-wrap font-sans leading-relaxed max-h-72 overflow-y-auto"
                      >{{ section[arm] }}</pre
                    >
                  </div>
                </div>
              </details>
            </div>
            <p v-else class="text-xs text-n-slate-10 mt-5">
              Hoje o Roteiro 2 é idêntico ao Roteiro 1. Edite o Roteiro 2
              (cartão "Roteiro", chave v2) e mude só o que quer testar.
            </p>
            <div class="flex items-center gap-3 flex-wrap mt-5">
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                :disabled="busy"
                @click="copyScript"
              >
                <span class="i-lucide-copy text-xs" />
                Recomeçar o Roteiro 2 como cópia do Roteiro 1
              </button>
              <button
                class="cv-btn cv-btn-ghost cv-btn-sm"
                @click="emit('openAgent')"
              >
                <span class="i-lucide-settings-2 text-xs" />
                Montar o teste no cartão do agente
              </button>
            </div>
          </template>

          <!-- onde o teste roda -->
          <div v-if="inboxes.length" class="mt-6">
            <p class="text-xs text-n-slate-10 mb-2">Onde o teste roda</p>
            <div class="flex flex-wrap gap-2">
              <span
                v-for="inbox in inboxes"
                :key="inbox.id"
                class="cv-chip cv-chip-lg"
              >
                {{ inbox.name }} · {{ MODE_LABEL[inbox.mode] }}
              </span>
            </div>
          </div>
        </div>

        <!-- ══ DECIDIR ══ -->
        <div
          v-if="isCurrent && !ended"
          class="cv-block p-6 sm:p-9 mb-6"
          :style="blockVars('decisao')"
        >
          <h2
            class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
          >
            Decidir e encerrar
          </h2>
          <p class="text-sm text-n-slate-11 mt-2 mb-4 max-w-3xl">
            O teste vai para o histórico com o placar e a sua decisão.
            <template v-if="kind">
              Adotar a B faz {{ kind.what }} dela virar o oficial deste
              atendente.
            </template>
            O próximo teste começa do zero.
          </p>
          <input
            v-model="note"
            type="text"
            maxlength="300"
            class="w-full rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand mb-4"
            placeholder="Anotação da decisão (opcional): por que escolheu assim?"
          />
          <div class="flex items-center gap-3 flex-wrap">
            <button
              class="cv-btn"
              :style="{ background: GRAD.a }"
              :disabled="busy"
              @click="finish('a', false)"
            >
              Ficar com a A
            </button>
            <button
              class="cv-btn"
              :style="{ background: GRAD.b }"
              :disabled="busy"
              @click="finish('b', true)"
            >
              Adotar a B
            </button>
            <button
              class="cv-btn cv-btn-ghost"
              :disabled="busy"
              @click="finish('', false)"
            >
              Só encerrar
            </button>
          </div>
        </div>
      </template>

      <!-- ══ 🧑‍🏫 CONSULTOR SUPERIOR (item 414) ══ -->
      <div
        v-if="consultorShown"
        class="cv-block p-6 sm:p-9 mb-6"
        :style="blockVars('consultor')"
      >
        <p
          class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-9"
        >
          Consultor superior ·
          {{ consultor.mode === 'ativo' ? 'ativo' : 'em sombra' }} ·
          {{ modelName(consultor.model) }}
        </p>
        <h2
          class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 mt-1"
        >
          {{ consultorHeadline }}
        </h2>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mt-5">
          <div class="cv-sub p-4">
            <p class="text-xs text-n-slate-10">Hoje</p>
            <p class="text-lg font-bold text-n-slate-12 mt-1">
              {{ num(consultor.stats.today.consultas) }} de
              {{ num(consultor.stats.cap) }}
            </p>
            <p class="text-[11px] text-n-slate-10">consultas do teto do dia</p>
          </div>
          <div class="cv-sub p-4">
            <p class="text-xs text-n-slate-10">Em pacientes</p>
            <p class="text-lg font-bold text-n-slate-12 mt-1">
              {{ num(consultorTotal.consultas) }}
            </p>
            <p class="text-[11px] text-n-slate-10">
              + {{ num(consultorTotal.testes) }} no teste
            </p>
          </div>
          <div class="cv-sub p-4">
            <p class="text-xs text-n-slate-10">Mudou a resposta</p>
            <p class="text-lg font-bold text-n-slate-12 mt-1">
              {{ num(consultorTotal.mudou) }} de {{ num(consultorAnswered) }}
            </p>
            <p class="text-[11px] text-n-slate-10">
              {{ num(consultorTotal.aplicadas) }} valeram ·
              {{ num(consultorTotal.falhas) }} falhas
            </p>
          </div>
          <div class="cv-sub p-4">
            <p class="text-xs text-n-slate-10">Custo do consultor</p>
            <p class="text-lg font-bold text-n-slate-12 mt-1">
              {{ money(consultorTotal.custo_usd || 0) }}
            </p>
            <p class="text-[11px] text-n-slate-10">
              {{
                consultorAnswered
                  ? `${money((consultorTotal.custo_usd || 0) / consultorAnswered)} por consulta`
                  : 'sem consulta ainda'
              }}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap gap-1.5 mt-4">
          <span
            v-for="row in consultorRows(
              consultorTotal.gatilhos,
              consultor.trigger_labels
            )"
            :key="`g-${row.key}`"
            class="cv-chip cv-chip-wrap"
            >{{ num(row.count) }}× {{ row.label }}</span
          >
          <span
            v-for="row in consultorRows(
              consultorTotal.efeitos,
              consultor.effect_labels
            )"
            :key="`e-${row.key}`"
            class="cv-chip cv-chip-wrap cv-green"
            >{{ num(row.count) }}× {{ row.label }}</span
          >
        </div>
        <p class="text-[11px] text-n-slate-10 mt-4">
          Cada consulta, com o que o principal ia responder e o que o consultor
          devolveu, está no cartão do atendente (Consultor superior → últimas
          consultas).
          <button class="underline" @click="emit('openAgent')">
            Abrir o cartão
          </button>
        </p>
      </div>

      <!-- ══ 📍 ANTES × DEPOIS DO MARCO ══ -->
      <div class="cv-block p-6 sm:p-9 mb-6" :style="blockVars('marco')">
        <p
          class="text-[11px] font-semibold uppercase tracking-wide text-n-slate-9"
        >
          Antes × depois do marco
        </p>
        <h2
          class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12 mt-1"
        >
          {{
            beforeAfter
              ? marcoHeadline
              : 'Anote o dia em que o atendimento mudou para comparar o antes com o depois.'
          }}
        </h2>
        <p v-if="beforeAfter" class="text-xs text-n-slate-10 mt-1">
          {{ beforeAfter.marco.title }} · {{ dayTime(beforeAfter.at) }} ·
          conversas novas de cada caixa e quantas viraram consulta marcada em
          até {{ horizonLabel }} da primeira mensagem (o mesmo prazo nos dois
          lados). Antes = os {{ beforeAfter.before_days }} dias anteriores. Os
          dias mais recentes ainda amadurecem.
        </p>

        <div v-if="marcos.length > 1" class="flex gap-1.5 flex-wrap mt-4">
          <button
            v-for="marco in marcos"
            :key="marco.id"
            class="cv-chip"
            :class="{ 'cv-chip-on': beforeAfter?.marco?.id === marco.id }"
            @click="pickMarco(marco.id)"
          >
            {{ day(marco.at) }} · {{ marco.title }}
          </button>
        </div>

        <div v-if="beforeAfter" class="grid sm:grid-cols-2 gap-3 mt-5">
          <div
            v-for="row in [
              { name: 'Todas as caixas', ...beforeAfter.total, total: true },
              ...beforeAfter.rows,
            ]"
            :key="row.inbox_id || 'total'"
            class="cv-sub p-4"
            :class="{ 'sm:col-span-2': row.total }"
          >
            <div class="flex items-center gap-2 flex-wrap">
              <p class="text-sm font-semibold text-n-slate-12 flex-1 min-w-0">
                {{ row.name }}
              </p>
              <span
                class="text-xs font-semibold tabular-nums"
                :style="{ color: deltaColor(row) }"
              >
                {{ deltaLabel(row) }}
              </span>
            </div>
            <div class="grid grid-cols-2 gap-3 mt-3">
              <div v-for="side in ['before', 'after']" :key="side">
                <p class="text-[11px] text-n-slate-9">
                  {{ side === 'before' ? 'Antes' : 'Depois' }}
                </p>
                <p
                  class="text-2xl font-bold tabular-nums tracking-tight text-n-slate-12"
                >
                  {{ pct(row[side].taxa) }}
                </p>
                <p class="text-[11px] text-n-slate-10">
                  {{ num(row[side].consultas) }} consulta(s) em
                  {{ num(row[side].conversas) }} conversa(s) ·
                  {{ num(row[side].por_dia) }} por dia
                </p>
              </div>
            </div>
          </div>
        </div>

        <div class="cv-sub p-4 mt-5">
          <p class="text-xs font-semibold text-n-slate-12">Anotar um marco</p>
          <div class="flex items-center gap-2 flex-wrap mt-2">
            <input
              v-model="marcoTitle"
              type="text"
              maxlength="120"
              placeholder="O que mudou (ex.: ChatGPT na recepção)"
              class="flex-1 min-w-[200px] rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
            />
            <input
              v-model="marcoAt"
              type="datetime-local"
              class="rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-sm text-n-slate-12 outline-none focus:border-n-brand"
              title="Em branco = agora"
            />
            <button
              class="cv-btn cv-btn-sm"
              :disabled="busy || !marcoTitle.trim()"
              @click="addMarco"
            >
              <span class="i-lucide-flag text-xs" />
              Anotar
            </button>
          </div>
          <div v-if="marcos.length" class="mt-3 space-y-1">
            <div
              v-for="marco in marcos"
              :key="marco.id"
              class="flex items-start gap-2 text-[11px] text-n-slate-10"
            >
              <span class="tabular-nums whitespace-nowrap text-n-slate-12">
                {{ dayTime(marco.at) }}
              </span>
              <span class="flex-1 min-w-0">
                <b class="text-n-slate-12">{{ marco.title }}</b>
                <template v-if="marco.note"> · {{ marco.note }}</template>
              </span>
              <button
                class="text-n-slate-9 hover:text-n-slate-12"
                :disabled="busy"
                title="Apagar a anotação"
                @click="removeMarco(marco)"
              >
                <span class="i-lucide-x text-xs" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- ══ 🔙 PONTO DE VOLTA ══ -->
      <div
        v-if="restorePoint"
        class="cv-block p-6 sm:p-9 mb-6"
        :style="blockVars('volta')"
      >
        <h2
          class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
        >
          Se piorar, um toque volta ao atendimento de antes de 24/11
        </h2>
        <p class="text-xs text-n-slate-10 mt-1 leading-relaxed">
          Guardado: o Roteiro 1 e os Passos do Atendente de Agendamento com o
          texto exato que estava no ar até 23/11 (o que tem o histórico de
          conversão), com tudo no Sonnet. Voltar apaga o motor por coluna,
          encerra o teste em andamento e deixa o que vale hoje no Histórico do
          Roteiro, para desfazer. A regra da consulta de rotina a R$ 250 é de
          23/11 à noite e também sai; se quiser mantê-la, acrescente de novo no
          Roteiro.
        </p>
        <div class="flex items-center gap-3 flex-wrap mt-4">
          <button
            class="cv-btn cv-btn-ghost"
            :disabled="busy"
            @click="applyRestorePoint"
          >
            <span class="i-lucide-undo-2 text-sm" />
            Voltar ao atendimento antigo
          </button>
          <span
            v-if="restorePoint.applied_at"
            class="text-[11px] text-n-slate-10"
          >
            usado em {{ dayTime(restorePoint.applied_at) }}
            <template v-if="restorePoint.applied_by">
              por {{ restorePoint.applied_by }}
            </template>
          </span>
        </div>
      </div>

      <!-- ══ TESTES ANTERIORES ══ -->
      <div
        v-if="history.length"
        class="cv-block p-6 sm:p-9 mb-6"
        :style="blockVars('historico')"
      >
        <h2
          class="text-xl sm:text-2xl font-bold tracking-tight text-n-slate-12"
        >
          Testes anteriores
        </h2>
        <p class="text-xs text-n-slate-10 mt-1 mb-5">
          toque para abrir o funil completo, relido hoje
        </p>
        <div class="space-y-2">
          <button
            v-for="entry in history"
            :key="entry.id"
            class="cv-sub cv-sub-hover w-full text-left px-4 py-3 flex items-center gap-x-4 gap-y-1 flex-wrap"
            :class="{ 'cv-sub-on': viewingId === entry.id }"
            @click="openTest(entry.id)"
          >
            <span class="min-w-0 flex-1 basis-56">
              <span class="block text-sm font-medium text-n-slate-12">
                {{ entry.name || KIND[entry.kind]?.label || 'Teste' }}
              </span>
              <span class="block text-[11px] text-n-slate-10">
                {{ day(entry.started_at) }} a {{ day(entry.ended_at) }} ·
                {{ KIND[entry.kind]?.label }} ·
                {{ entry.script_b === 'v2' ? 'Roteiro 1 × 2' : 'Roteiro 1' }}
                ·
                {{
                  entry.model_a === entry.model_b
                    ? modelName(entry.model_a)
                    : `${modelName(entry.model_a)} × ${modelName(entry.model_b)}`
                }}
              </span>
            </span>
            <span
              class="text-sm tabular-nums whitespace-nowrap text-n-slate-12"
            >
              <b :style="{ color: COLOR.a }">A</b>
              {{ pct(entry.snapshot?.a?.taxa_consulta) }}
              <span class="text-n-slate-9 mx-1">×</span>
              <b :style="{ color: COLOR.b }">B</b>
              {{ pct(entry.snapshot?.b?.taxa_consulta) }}
            </span>
            <span class="cv-chip">{{ decisionLabel(entry) }}</span>
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
