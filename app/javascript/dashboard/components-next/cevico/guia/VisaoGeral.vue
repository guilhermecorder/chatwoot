<script setup>
// 🧭 item 337 — VISÃO GERAL do Meu Painel: as 14 perguntas do Guilherme em
// blocos do guia arejado. v3 (12/10 noite, "enquadrar melhor os blocos" e
// "mais gráficos"): cada bloco = fileira de NÚMEROS em cima (cartões na
// família da cor do dia, herói em degradê) + fileira de TRÊS GRÁFICOS da
// mesma altura embaixo (funil em degraus, área, barras, anéis). Clicar num
// número abre o PainelLateral com a história. Dinheiro e Médicos só admin.
// 🧹 item 342 (13/10, "indicador de agendamento descontaminado"): agendaram
// = SÓ quem chegou no período (os da base aparecem ao lado, nunca somados na
// taxa), quem chegou agendou por caixa, quando chegaram os que agendaram
// (safra) e o bloco "Volume do período" com 9 números, cada um com a fórmula.
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import CrmAPI from 'dashboard/api/crm';
import PeriodRuler from 'dashboard/components-next/cevico/PeriodRuler.vue';
import SkeletonScreen from 'dashboard/components-next/cevico/SkeletonScreen.vue';
import FunnelSteps from 'dashboard/components-next/cevico/FunnelSteps.vue';
import AreaChart from 'dashboard/components-next/cevico/AreaChart.vue';
import HBars from 'dashboard/components-next/cevico/HBars.vue';
import MiniBars from 'dashboard/components-next/cevico/MiniBars.vue';
import CvBloco from './CvBloco.vue';
import CvIndicador from './CvIndicador.vue';
import CvPainelLateral from './CvPainelLateral.vue';

const props = defineProps({
  // lente da fonte da chavinha do Meu Painel (cevico | oftalmofacil | all)
  source: { type: String, default: '' },
  // variáveis --cv* da página: cores dos gráficos e do painel lateral
  vars: { type: Object, default: () => ({}) },
});

const router = useRouter();
const { accountId } = useAccount();
const periodo = ref({ preset: 'last7', from: '', to: '' });
const isLoading = ref(true);
const data = ref(null);

const load = async () => {
  isLoading.value = true;
  try {
    const { data: payload } = await CrmAPI.getOverview({
      preset: periodo.value.preset,
      from: periodo.value.from,
      to: periodo.value.to,
      source: props.source || undefined,
    });
    data.value = payload;
  } catch {
    useAlert('Não consegui carregar a visão geral.');
  } finally {
    isLoading.value = false;
  }
};
onMounted(load);
watch(periodo, load, { deep: true });
watch(() => props.source, load);

// ── cores dos gráficos: a família da cor do dia + o destaque ──
// (hex para SVG/color-mix; degradês só onde o componente aceita CSS)
const cor = computed(() => props.vars['--cv'] || '#3060e0');
const corDeep = computed(() => props.vars['--cv-deep'] || cor.value);
const corDestaque = computed(() => props.vars['--cv-destaque'] || cor.value);
const corGrad = computed(() => props.vars['--cv-grad'] || cor.value);
const corGrad2 = computed(() => props.vars['--cv-grad-2'] || cor.value);
const corGrad3 = computed(() => props.vars['--cv-grad-3'] || cor.value);

// ── formatação ──
const n = v => Number(v || 0).toLocaleString('pt-BR');
const pctTxt = v =>
  `${Number(v || 0).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
const brl = v =>
  v === null || v === undefined
    ? '—'
    : Number(v).toLocaleString('pt-BR', {
        style: 'currency',
        currency: 'BRL',
        maximumFractionDigits: 0,
      });
const dias = v =>
  v === null || v === undefined
    ? '—'
    : `${Number(v).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} dias`;
// comparação com o período anterior: { texto, estado, seta }
const cmp = (atual, anterior, { bomQuandoSobe = true, sufixo = '' } = {}) => {
  if (anterior === null || anterior === undefined) return null;
  if (!anterior && !atual)
    return { texto: 'sem movimento nos dois períodos', estado: 'neutro' };
  if (!anterior) return { texto: `antes: 0${sufixo}`, estado: 'neutro' };
  const delta = ((atual - anterior) / anterior) * 100;
  const arred = Math.round(delta);
  if (arred === 0)
    return {
      texto: `igual ao período anterior (${n(anterior)}${sufixo})`,
      estado: 'neutro',
    };
  const subiu = delta > 0;
  return {
    texto: `${subiu ? '+' : ''}${arred}% vs anterior (${n(anterior)}${sufixo})`,
    estado: subiu === bomQuandoSobe ? 'bom' : 'atencao',
    seta: true,
  };
};
const cmpPct = (atual, anterior, opts = {}) => {
  if (anterior === null || anterior === undefined) return null;
  const delta = Math.round((atual - anterior) * 10) / 10;
  if (!delta)
    return {
      texto: `igual ao período anterior (${pctTxt(anterior)})`,
      estado: 'neutro',
    };
  const subiu = delta > 0;
  return {
    texto: `${subiu ? '+' : ''}${delta} pontos vs anterior (${pctTxt(anterior)})`,
    estado: subiu === (opts.bomQuandoSobe ?? true) ? 'bom' : 'atencao',
    seta: true,
  };
};
const estadoTaxa = (v, bom, atencao) => {
  if (v >= bom) return 'bom';
  return v >= atencao ? 'atencao' : 'problema';
};

const entrada = computed(() => data.value?.entrada);
const agenda = computed(() => data.value?.agenda);
const cirurgia = computed(() => data.value?.cirurgia);
const dinheiro = computed(() => data.value?.dinheiro);
const medicos = computed(() => data.value?.medicos || []);
const series = computed(() => data.value?.series);
const rotuloBalde = computed(() =>
  series.value?.balde === 'mes' ? 'por mês' : 'por dia'
);

// ── frases de contexto (a história em uma linha) ──
const ctxNovos = computed(() => {
  const c = entrada.value?.canal?.novos || [];
  if (!c.length) return '';
  const top = c[0];
  return `${top.label}: ${n(top.count)} (${pctTxt((top.count / Math.max(entrada.value.novos.valor, 1)) * 100)}).`;
});
const ctxAgendaram = computed(() => {
  const t = entrada.value?.tempo;
  const base = entrada.value?.agendaram_base?.valor || 0;
  const daBase = base
    ? ` + ${n(base)} da base (chegaram antes) também agendaram.`
    : '';
  if (!t) return `Ninguém que chegou no período agendou ainda.${daBase}`;
  return `${n(t.mesmo_dia)} no mesmo dia, ${n(t.ate_7)} em até 7 dias; média de ${dias(t.media_dias)} até agendar.${daBase}`;
});
// item 342: o nome do período nas frases ("hoje", "ontem", "no período")
const NOME_PERIODO = {
  today: 'hoje',
  yesterday: 'ontem',
  last7: 'nos últimos 7 dias',
  last_week: 'na semana passada',
  month: 'neste mês',
  last_month: 'no mês passado',
  last90: 'nos últimos 90 dias',
  year: 'neste ano',
};
const nomePeriodo = computed(
  () => NOME_PERIODO[periodo.value.preset] || 'no período'
);
const ctxCoortes = computed(() => {
  const c = entrada.value?.coortes;
  if (!c) return '';
  return `Hoje ${c.hoje.agendaram}/${c.hoje.chegaram} · 7 dias ${c.dias7.agendaram}/${c.dias7.chegaram} (${pctTxt(c.dias7.pct)}) · 30 dias ${c.dias30.agendaram}/${c.dias30.chegaram} (${pctTxt(c.dias30.pct)}).`;
});
const ctxTaxa = computed(() => {
  const e = entrada.value;
  if (!e) return '';
  return `${n(e.agendaram_novos.valor)} de ${n(e.novos.valor)} que chegaram ${nomePeriodo.value} já agendaram. ${ctxCoortes.value}`;
});
// 📈 item 345b: rendimento — todos que agendaram no período ÷ novos
const ctxTaxaGeral = computed(() => {
  const e = entrada.value;
  if (!e?.agendaram_total) return '';
  return `${n(e.agendaram_total.valor)} agendaram ${nomePeriodo.value} (${n(e.agendaram_novos.valor)} novos + ${n(e.agendaram_base.valor)} da base) para ${n(e.novos.valor)} contatos novos — rendimento do período.`;
});
const ctxOcupacao = computed(() => {
  const o = agenda.value?.ocupacao;
  if (!o) return '';
  const m = agenda.value.mix;
  const aval = m.tipos.find(t => t.key === 'avaliacao');
  const exa = m.tipos.find(t => t.key === 'exames');
  return `${n(o.ocupadas)} de ${n(o.vagas)} horários. Avaliação ${pctTxt(aval?.pct)} · exames ${pctTxt(exa?.pct)} · particular ${pctTxt(m.particular.pct)} · Oftalmofácil ${pctTxt(m.oftalmofacil.pct)}.`;
});
const ctxConfirmacao = computed(() => {
  const a = agenda.value;
  if (!a) return '';
  return `${n(a.reagendaram)} reagendaram (${pctTxt(a.taxa_reagendamento)}) · ${n(a.cancelaram)} cancelaram (${pctTxt(a.taxa_cancelamento)}) · ${n(a.recusaram)} disseram que não vão.`;
});
const ctxComparecimento = computed(() => {
  const a = agenda.value;
  if (!a) return '';
  return `${n(a.faltaram)} faltaram (${pctTxt(a.taxa_falta)})${a.pendentes ? ` · ${n(a.pendentes)} passadas sem conferir` : ''}.`;
});
const ctxIndicacao = computed(() => {
  const c = cirurgia.value;
  if (!c) return '';
  return `${n(c.sem_indicacao)} saíram sem indicação. ${n(c.fecharam)} fecharam (${pctTxt(c.taxa_fechamento)}), ${n(c.aguardando)} ainda não.`;
});
const ctxJornada = computed(() => {
  const j = cirurgia.value?.jornada;
  if (!j?.ate_cirurgia) return 'Ainda sem cirurgia realizada nesta turma.';
  return `Da chegada à cirurgia: média de ${dias(j.ate_cirurgia.media_dias)} (mediana ${dias(j.ate_cirurgia.mediana_dias)}), ${n(j.ate_cirurgia.amostra)} pacientes. ${n(j.pos_op)} retornos de pós-op no período.`;
});
const ctxCac = computed(() => {
  const d = dinheiro.value;
  if (!d) return '';
  const g = d.canais.find(c => c.key === 'google');
  const m = d.canais.find(c => c.key === 'meta');
  return `Google ${g?.cac ? brl(g.cac) : '—'} · Meta ${m?.cac ? brl(m.cac) : '—'} por paciente. Ticket médio ${brl(d.ticket_medio)}.`;
});
const ctxGastos = computed(() => {
  const g = dinheiro.value?.gastos;
  if (!g) return '';
  return `Meta ${brl(g.meta)} · Google ${brl(g.google)} · WhatsApp ${brl(g.whatsapp)} · IA ${brl(g.ia)}.`;
});
const ctxConversoes = computed(() => {
  const c = dinheiro.value?.conversoes;
  if (!c) return '';
  return `Por agendamento ${pctTxt(c.por_agendamento)} · por comparecimento ${pctTxt(c.por_comparecimento)} · por indicação ${pctTxt(c.por_indicacao)}.`;
});

// ── gráficos ──
const funilEntrada = computed(() => {
  const e = entrada.value;
  if (!e) return [];
  return [
    {
      key: 'novos',
      label: 'Novos',
      value: e.novos.valor,
      color: corDeep.value,
    },
    {
      key: 'orcamento',
      label: 'Orçamento',
      value: e.orcamento.valor,
      color: cor.value,
    },
    {
      key: 'agendaram',
      label: 'Agendaram',
      value: e.agendaram_novos.valor,
      color: corDestaque.value,
    },
  ];
});
// item 342: pessoas (1ª entrada de cada uma), lead novo × base em linhas separadas
const areaEntrada = computed(() => {
  const s = series.value;
  if (!s) return [];
  return [
    { key: 'novos', label: 'Novos', color: cor.value, values: s.novos },
    {
      key: 'agendaram',
      label: 'Agendaram (novos)',
      color: corDestaque.value,
      values: s.agendaram_novos || s.agendaram,
    },
    {
      key: 'agendaram_base',
      label: 'Agendaram (base)',
      color: corGrad3.value,
      values: s.agendaram_base || [],
    },
  ];
});
// item 342: quando chegaram os que agendaram no período
const barrasSafra = computed(() =>
  (entrada.value?.safra?.faixas || []).map((f, i) => ({
    label: f.label,
    values: [f.count],
    sub:
      f.media_dias !== null && f.media_dias !== undefined
        ? `${pctTxt(f.pct)} · ${dias(f.media_dias)} até agendar`
        : pctTxt(f.pct),
    color: i ? corGrad3.value : corGrad.value,
  }))
);
// média de dias até agendar, em palavras curtas (0 = no mesmo dia)
const mediaTxt = v => {
  if (v === null || v === undefined) return '—';
  return Number(v) === 0 ? 'mesmo dia' : dias(v);
};
const porCaixa = computed(() => entrada.value?.por_caixa?.linhas || []);
const totalPorCaixa = computed(() =>
  porCaixa.value.reduce(
    (acc, r) => ({
      chegaram: acc.chegaram + r.chegaram,
      agendaram: acc.agendaram + r.agendaram,
    }),
    { chegaram: 0, agendaram: 0 }
  )
);
// item 342: VOLUME DO PERÍODO — 9 números, cada um com fórmula e quebras
const volumes = computed(() => data.value?.volumes || []);
const RUIM_QUANDO_SOBE = ['reagendamentos', 'cancelamentos', 'faltas'];
const cmpVolume = v =>
  cmp(v.valor, v.anterior, {
    bomQuandoSobe: !RUIM_QUANDO_SOBE.includes(v.key),
  });
const ctxVolume = v => {
  if (v.key === 'agendamentos')
    return `${n(v.novos)} leads novos · ${n(v.base)} da base`;
  if (v.key === 'cirurgias_realizadas' && v.sem_coluna)
    return 'Nenhum funil tem a coluna "Cirurgia Realizada".';
  if (v.pessoas_distintas !== undefined && v.pessoas_distintas !== v.valor)
    return `${n(v.valor)} ${v.medida} de ${n(v.pessoas_distintas)} pessoa(s)`;
  return '';
};
// de onde vieram os novos (caixa da 1ª conversa) × quantos desses agendaram
const barrasOrigem = computed(() => {
  const e = entrada.value;
  if (!e) return [];
  const agendaram = Object.fromEntries(
    (e.origem.agendaram || []).map(r => [r.label, r.count])
  );
  return (e.origem.novos || []).slice(0, 6).map(r => ({
    label: r.label,
    values: [r.count, agendaram[r.label] || 0],
  }));
});
const areaAgenda = computed(() => {
  const s = series.value;
  if (!s) return [];
  return [
    {
      key: 'consultas',
      label: 'Consultas',
      color: cor.value,
      values: s.consultas,
    },
    {
      key: 'compareceram',
      label: 'Compareceram',
      color: corDestaque.value,
      values: s.compareceram,
    },
  ];
});
const barrasMix = computed(() => {
  const m = agenda.value?.mix;
  if (!m) return [];
  const rows = m.tipos.map(t => ({
    label: t.label,
    values: [t.count],
    sub: pctTxt(t.pct),
    color: corGrad2.value,
  }));
  rows.push({
    label: 'Particular',
    values: [m.particular.count],
    sub: pctTxt(m.particular.pct),
    color: corGrad3.value,
  });
  rows.push({
    label: 'Oftalmofácil',
    values: [m.oftalmofacil.count],
    sub: pctTxt(m.oftalmofacil.pct),
    color: corGrad3.value,
  });
  return rows;
});
const barrasConfirmacao = computed(() => {
  const a = agenda.value;
  if (!a) return [];
  return [
    {
      label: 'Confirmaram',
      values: [a.confirmaram],
      sub: pctTxt(a.taxa_confirmacao),
      color: corGrad.value,
    },
    {
      label: 'Compareceram',
      values: [a.compareceram],
      sub: pctTxt(a.taxa_comparecimento),
      color: corGrad2.value,
    },
    {
      label: 'Faltaram',
      values: [a.faltaram],
      sub: pctTxt(a.taxa_falta),
      color: corGrad3.value,
    },
    {
      label: 'Reagendaram',
      values: [a.reagendaram],
      sub: pctTxt(a.taxa_reagendamento),
      color: corGrad3.value,
    },
    {
      label: 'Cancelaram',
      values: [a.cancelaram],
      sub: pctTxt(a.taxa_cancelamento),
      color: corGrad3.value,
    },
    { label: 'Não vão', values: [a.recusaram], color: corGrad3.value },
  ];
});
const funilCirurgia = computed(() => {
  const c = cirurgia.value;
  if (!c) return [];
  return [
    {
      key: 'realizadas',
      label: 'Consultas',
      value: c.consultas_realizadas,
      color: corDeep.value,
    },
    {
      key: 'indicadas',
      label: 'Indicação',
      value: c.indicadas,
      color: cor.value,
    },
    {
      key: 'fecharam',
      label: 'Fecharam',
      value: c.fecharam,
      color: corDestaque.value,
    },
  ];
});
const barrasJornada = computed(() => {
  const etapas = cirurgia.value?.jornada?.etapas || [];
  return etapas
    .filter(e => e.key !== 'arrived')
    .map(e => ({
      label: e.label,
      values: [e.count],
      sub:
        e.mediana_dias !== null && e.mediana_dias !== undefined
          ? `+${dias(e.mediana_dias)}`
          : '',
      color: corGrad2.value,
    }));
});
const barrasTempo = computed(() => {
  const t = entrada.value?.tempo;
  if (!t) return [];
  return [
    { label: 'Mesmo dia', values: [t.mesmo_dia], color: corGrad.value },
    { label: 'Até 7 dias', values: [t.ate_7], color: corGrad2.value },
    { label: 'Depois', values: [t.depois], color: corGrad3.value },
  ];
});
const barrasGastos = computed(() => {
  const g = dinheiro.value?.gastos;
  if (!g) return [];
  return [
    { label: 'Meta Ads', values: [g.meta], color: corGrad.value },
    { label: 'Google Ads', values: [g.google], color: corGrad2.value },
    { label: 'WhatsApp', values: [g.whatsapp], color: corGrad3.value },
    { label: 'IA', values: [g.ia], color: corGrad3.value },
  ];
});
const barrasCanais = computed(() =>
  (dinheiro.value?.canais || []).map(c => ({
    label: c.label.replace(' / indicação', ''),
    values: [c.spend, c.revenue],
    sub: c.cac
      ? `CAC ${brl(c.cac)} · ${n(c.patients)} pacientes`
      : `${n(c.patients)} pacientes`,
  }))
);
const historico = computed(() => dinheiro.value?.historico || []);
const historicoValores = computed(() => historico.value.map(m => m.total));
const historicoRotulos = computed(() =>
  historico.value.map(m => `${m.month.slice(5, 7)}/${m.month.slice(2, 4)}`)
);
const nomeCurto = d => String(d || '').replace(/^Dra?\.\s*/, '');
const barrasMedicos = computed(() =>
  medicos.value.map(m => ({
    label: nomeCurto(m.doctor),
    values: [m.ocupacao ?? 0, m.show_rate],
    sub: `${n(m.consultations)} consultas`,
  }))
);
const barrasMedicosCirurgia = computed(() =>
  medicos.value.map(m => ({
    label: nomeCurto(m.doctor),
    values: [m.indications, m.conversions],
    sub: `conversão ${pctTxt(m.conversion_rate)}`,
  }))
);
const anelDe = pct => {
  const p = Math.max(0, Math.min(100, Number(pct || 0)));
  const r = 40;
  const c = 2 * Math.PI * r;
  return { r, c, offset: c * (1 - p / 100), pct: p };
};
const anelOcupacao = computed(() => anelDe(agenda.value?.ocupacao?.pct));
const anelIndicacao = computed(() => anelDe(cirurgia.value?.taxa_indicacao));
const anelFechamento = computed(() => anelDe(cirurgia.value?.taxa_fechamento));

// ── painel lateral ──
const painel = ref(null); // { key, titulo, valor, comparacao }
const abrir = (key, titulo, valor, comparacao = null) => {
  painel.value = { key, titulo, valor, comparacao };
};
const fechar = () => {
  painel.value = null;
};
const volumeAberto = computed(() => {
  const k = painel.value?.key || '';
  if (!k.startsWith('vol:')) return null;
  return volumes.value.find(v => v.key === k.slice(4)) || null;
});
const listaOrigem = computed(() => {
  const k = painel.value?.key;
  const e = entrada.value;
  if (!e) return [];
  if (k === 'novos') return e.origem.novos;
  if (k === 'orcamento') return e.origem.orcamento;
  if (k === 'agendaram') return e.origem.agendaram;
  if (k === 'agendaram_base') return e.origem.agendaram_base || [];
  return [];
});
const listaCanal = computed(() => {
  const k = painel.value?.key;
  const e = entrada.value;
  if (!e) return [];
  if (k === 'novos') return e.canal.novos;
  if (k === 'agendaram') return e.canal.agendaram;
  return [];
});
const listaPessoas = computed(() => {
  const k = painel.value?.key;
  if (!data.value) return [];
  if (k === 'novos') return entrada.value.pessoas.novos;
  if (k === 'agendaram') return entrada.value.pessoas.agendaram;
  if (k === 'agendaram_base') return entrada.value.pessoas.agendaram_base || [];
  if (volumeAberto.value) return volumeAberto.value.pessoas || [];
  if (k === 'indicadas') return cirurgia.value.pessoas.indicadas;
  if (k === 'fecharam') return cirurgia.value.pessoas.fecharam;
  return [];
});
const totalDe = rows => rows.reduce((s, r) => s + (r.count || 0), 0);
const abrirContato = id => {
  if (!id) return;
  router.push({
    name: 'contact_profile_dashboard',
    params: { accountId: accountId.value, contactId: id },
  });
};
const dataCurta = iso =>
  iso
    ? new Date(iso).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';
const pessoaSub = p => {
  const partes = [];
  if (p.origem || p.medico) partes.push(p.origem || p.medico);
  if (p.chegou_em) partes.push(`chegou ${dataCurta(p.chegou_em)}`);
  if (p.data) partes.push(dataCurta(p.data));
  if (p.dias !== null && p.dias !== undefined)
    partes.push(`agendou em ${p.dias} ${p.dias === 1 ? 'dia' : 'dias'}`);
  return partes.join(' · ');
};
</script>

<template>
  <section class="cvg-visao">
    <div class="cvg-visao-topo">
      <div>
        <h2 class="cvg-titulo-bloco">Visão geral</h2>
        <p class="cvg-subtitulo">
          As perguntas que importam, no período escolhido. Clique num número
          para ver a história.
        </p>
      </div>
      <PeriodRuler v-model="periodo" glass />
    </div>

    <SkeletonScreen v-if="isLoading && !data" variant="dashboard" />

    <template v-else-if="data">
      <!-- ══ 1–5 · ENTRADA ══ -->
      <CvBloco
        titulo="Quanto entrou e quanto virou"
        subtitulo="Contatos novos pelas portas de entrada, até o orçamento e até a consulta marcada"
        tom="dia"
        icon="i-lucide-door-open"
      >
        <div class="cvg-bloco-pilha">
          <div class="cvg-fila cvg-fila--5">
            <CvIndicador
              rotulo="Contatos novos"
              :valor="n(entrada.novos.valor)"
              :comparacao="cmp(entrada.novos.valor, entrada.novos.anterior)"
              :contexto="ctxNovos"
              :serie="series?.novos || []"
              heroi
              pe="de onde vieram"
              @abrir="
                abrir(
                  'novos',
                  'Contatos novos',
                  n(entrada.novos.valor),
                  cmp(entrada.novos.valor, entrada.novos.anterior)
                )
              "
            />
            <CvIndicador
              :rotulo="
                entrada.orcamento.coluna
                  ? 'Chegaram ao orçamento'
                  : 'Orçamento (coluna não definida)'
              "
              :valor="n(entrada.orcamento.valor)"
              :comparacao="
                cmp(entrada.orcamento.valor, entrada.orcamento.anterior)
              "
              :contexto="`${pctTxt(entrada.taxa_orcamento)} dos novos.`"
              pe="de onde vieram"
              @abrir="
                abrir(
                  'orcamento',
                  'Chegaram ao orçamento',
                  n(entrada.orcamento.valor)
                )
              "
            />
            <CvIndicador
              rotulo="Agendaram consulta (novos)"
              :valor="n(entrada.agendaram_novos.valor)"
              :comparacao="
                cmp(
                  entrada.agendaram_novos.valor,
                  entrada.agendaram_novos.anterior
                )
              "
              :contexto="ctxAgendaram"
              :pe="`+ ${n(entrada.agendaram_base.valor)} da base`"
              @abrir="
                abrir(
                  'agendaram',
                  'Agendaram consulta (leads novos)',
                  n(entrada.agendaram_novos.valor),
                  cmp(
                    entrada.agendaram_novos.valor,
                    entrada.agendaram_novos.anterior
                  )
                )
              "
            />
            <CvIndicador
              rotulo="Taxa novo → consulta"
              :valor="pctTxt(entrada.taxa_agendamento)"
              :comparacao="
                cmpPct(
                  entrada.taxa_agendamento,
                  entrada.taxa_agendamento_anterior
                )
              "
              :contexto="ctxTaxa"
              pe="novos que agendaram ÷ novos"
            />
            <!-- 📈 item 345b: rendimento do período (novos + base ÷ novos) -->
            <CvIndicador
              rotulo="Agendamentos ÷ novos"
              :valor="pctTxt(entrada.taxa_geral)"
              :comparacao="cmpPct(entrada.taxa_geral, entrada.taxa_geral_anterior)"
              :contexto="ctxTaxaGeral"
              pe="novos + base ÷ novos"
            />
          </div>
          <div class="cvg-graficos">
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Funil do período</span>
                <span
                  >{{ pctTxt(entrada.taxa_agendamento) }} viram consulta</span
                >
              </span>
              <div class="cvg-grafico-corpo">
                <FunnelSteps
                  :steps="funilEntrada"
                  :height="130"
                  start-text="dos novos"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Novos × agendaram</span>
                <span>{{ rotuloBalde }}</span>
              </span>
              <div class="cvg-grafico-corpo">
                <AreaChart
                  :series="areaEntrada"
                  :labels="series?.rotulos || []"
                  :height="150"
                  unit="pessoas"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Por onde chegaram</span>
                <span>novos × agendaram</span>
              </span>
              <div class="cvg-grafico-corpo">
                <HBars
                  :rows="barrasOrigem"
                  :series="[
                    { label: 'chegaram', color: corGrad2 },
                    { label: 'agendaram', color: corGrad },
                  ]"
                  :label-width="8"
                  :highlight-max="false"
                  empty-text="sem contato novo no período"
                />
              </div>
              <span class="cvg-grafico-nota"
                >caixa da primeira conversa de cada pessoa</span
              >
            </div>
          </div>
          <!-- item 342: quem chegou agendou (por caixa) × quando chegaram os que agendaram -->
          <div class="cvg-graficos cvg-graficos--2">
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Quem chegou {{ nomePeriodo }} agendou?</span>
                <span
                  >{{ n(totalPorCaixa.agendaram) }} de
                  {{ n(totalPorCaixa.chegaram) }}</span
                >
              </span>
              <div class="cvg-grafico-corpo">
                <div v-if="!porCaixa.length" class="cvg-vazio">
                  Nenhum contato novo no período.
                </div>
                <table v-else class="cvg-visao-tabela">
                  <thead>
                    <tr>
                      <th>Caixa de entrada</th>
                      <th>Chegaram</th>
                      <th>Agendaram</th>
                      <th>Em média</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="r in porCaixa" :key="r.label">
                      <td>{{ r.label }}</td>
                      <td>{{ n(r.chegaram) }}</td>
                      <td>
                        <b>{{ n(r.agendaram) }}</b>
                        <span class="cvg-legenda"> · {{ pctTxt(r.pct) }}</span>
                      </td>
                      <td>{{ mediaTxt(r.media_dias) }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <span class="cvg-grafico-nota">
                caixa da primeira conversa · agendou = entrou na coluna de
                agendamento no período{{
                  entrada.por_caixa?.parcial
                    ? ' · amostra dos primeiros 5.000'
                    : ''
                }}
              </span>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Quando chegaram os que agendaram</span>
                <span>{{ n(entrada.safra?.total) }} pessoas</span>
              </span>
              <div class="cvg-grafico-corpo">
                <HBars
                  :rows="barrasSafra"
                  :label-width="10"
                  :highlight-max="false"
                  empty-text="ninguém agendou no período"
                />
              </div>
              <span
                v-if="entrada.safra?.outros?.count"
                class="cvg-grafico-nota cvg-visao-nota-clicavel"
                role="button"
                tabindex="0"
                @click="
                  abrir(
                    'agendaram_base',
                    'Agendaram da base',
                    n(entrada.agendaram_base.valor),
                    cmp(
                      entrada.agendaram_base.valor,
                      entrada.agendaram_base.anterior
                    )
                  )
                "
                @keydown.enter="
                  abrir(
                    'agendaram_base',
                    'Agendaram da base',
                    n(entrada.agendaram_base.valor)
                  )
                "
              >
                {{ n(entrada.safra.outros.count) }} chegaram antes do período:
                em média {{ dias(entrada.safra.outros.media_dias) }} entre
                chegar e agendar · ver quem ›
              </span>
            </div>
          </div>
        </div>
      </CvBloco>

      <!-- ══ item 342 · VOLUME DO PERÍODO ══ -->
      <CvBloco
        v-if="volumes.length"
        titulo="Volume do período"
        subtitulo="Cada acontecimento um número, sem misturar: clique para ver de onde veio e como é contado"
        icon="i-lucide-list-ordered"
      >
        <div class="cvg-fila cvg-visao-volumes">
          <CvIndicador
            v-for="v in volumes"
            :key="v.key"
            :rotulo="v.label"
            :valor="n(v.valor)"
            :comparacao="cmpVolume(v)"
            :contexto="ctxVolume(v)"
            :pe="v.medida"
            @abrir="abrir(`vol:${v.key}`, v.label, n(v.valor), cmpVolume(v))"
          />
        </div>
      </CvBloco>

      <!-- ══ 6–8 · AGENDA ══ -->
      <CvBloco
        titulo="Agenda"
        subtitulo="Quanto está cheia, o que tem nela, quem confirmou e quem veio"
        tom="apoio"
        icon="i-lucide-calendar-check"
      >
        <div class="cvg-bloco-pilha">
          <div class="cvg-fila cvg-fila--3">
            <CvIndicador
              rotulo="Agenda ocupada"
              :valor="pctTxt(agenda.ocupacao.pct)"
              :comparacao="{
                texto: `${n(agenda.ativas)} consultas no período`,
                estado: 'neutro',
              }"
              :contexto="ctxOcupacao"
              :serie="series?.consultas || []"
              heroi
              pe="mix da agenda"
              @abrir="
                abrir('ocupacao', 'Agenda ocupada', pctTxt(agenda.ocupacao.pct))
              "
            />
            <CvIndicador
              rotulo="Confirmaram"
              :valor="n(agenda.confirmaram)"
              :comparacao="{
                texto: `${pctTxt(agenda.taxa_confirmacao)} das consultas`,
                estado: estadoTaxa(agenda.taxa_confirmacao, 70, 50),
              }"
              :contexto="ctxConfirmacao"
              pe="reagendaram · cancelaram"
              @abrir="
                abrir('confirmacao', 'Confirmação', n(agenda.confirmaram))
              "
            />
            <CvIndicador
              rotulo="Compareceram"
              :valor="n(agenda.compareceram)"
              :comparacao="{
                texto: `${pctTxt(agenda.taxa_comparecimento)} de presença`,
                estado: estadoTaxa(agenda.taxa_comparecimento, 80, 60),
              }"
              :contexto="ctxComparecimento"
            />
          </div>
          <div class="cvg-graficos">
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Ocupação e mix</span>
                <span>{{ n(agenda.mix.total) }} consultas</span>
              </span>
              <div class="cvg-grafico-corpo">
                <div class="cvg-anel">
                  <svg viewBox="0 0 100 100" aria-hidden="true">
                    <circle
                      class="trilho"
                      cx="50"
                      cy="50"
                      :r="anelOcupacao.r"
                    />
                    <circle
                      class="valor"
                      cx="50"
                      cy="50"
                      :r="anelOcupacao.r"
                      :stroke-dasharray="anelOcupacao.c"
                      :stroke-dashoffset="anelOcupacao.offset"
                      transform="rotate(-90 50 50)"
                    />
                    <text x="50" y="57" text-anchor="middle">
                      {{ Math.round(anelOcupacao.pct) }}%
                    </text>
                  </svg>
                  <p class="cvg-corpo">
                    <b>{{ n(agenda.ocupacao.ocupadas) }}</b> de
                    {{ n(agenda.ocupacao.vagas) }} horários
                  </p>
                </div>
                <HBars
                  :rows="barrasMix"
                  :label-width="7"
                  :highlight-max="false"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Consultas × compareceram</span>
                <span>{{ rotuloBalde }}</span>
              </span>
              <div class="cvg-grafico-corpo">
                <AreaChart
                  :series="areaAgenda"
                  :labels="series?.rotulos || []"
                  :height="150"
                  unit="consultas"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Confirmação e presença</span>
                <span>{{ n(agenda.total) }} marcadas</span>
              </span>
              <div class="cvg-grafico-corpo">
                <HBars
                  :rows="barrasConfirmacao"
                  :label-width="8"
                  :highlight-max="false"
                />
              </div>
            </div>
          </div>
        </div>
      </CvBloco>

      <!-- ══ 9–10 · CIRURGIA E JORNADA ══ -->
      <CvBloco
        titulo="Cirurgia e jornada"
        subtitulo="Das consultas realizadas, quem saiu com indicação, quem fechou e quanto tempo leva"
        icon="i-lucide-stethoscope"
      >
        <div class="cvg-bloco-pilha">
          <div class="cvg-fila cvg-fila--3">
            <CvIndicador
              rotulo="Indicações de cirurgia"
              :valor="n(cirurgia.indicadas)"
              :comparacao="{
                texto: `${pctTxt(cirurgia.taxa_indicacao)} das ${n(cirurgia.consultas_realizadas)} consultas realizadas`,
                estado: 'neutro',
              }"
              :contexto="ctxIndicacao"
              heroi
              pe="quem foi indicado"
              @abrir="
                abrir(
                  'indicadas',
                  'Indicações de cirurgia',
                  n(cirurgia.indicadas)
                )
              "
            />
            <CvIndicador
              rotulo="Fecharam cirurgia"
              :valor="n(cirurgia.fecharam)"
              :comparacao="{
                texto: `${pctTxt(cirurgia.taxa_fechamento)} das indicações`,
                estado: estadoTaxa(cirurgia.taxa_fechamento, 40, 20),
              }"
              :contexto="`${n(cirurgia.cirurgias_marcadas)} cirurgias marcadas e ${n(cirurgia.cirurgias_realizadas)} realizadas no período.`"
              pe="quem fechou"
              @abrir="
                abrir('fecharam', 'Fecharam cirurgia', n(cirurgia.fecharam))
              "
            />
            <CvIndicador
              rotulo="Tempo da jornada"
              :valor="
                cirurgia.jornada?.ate_cirurgia
                  ? dias(cirurgia.jornada.ate_cirurgia.media_dias)
                  : '—'
              "
              :comparacao="
                cirurgia.jornada?.ate_cirurgia
                  ? {
                      texto: 'da chegada à cirurgia realizada',
                      estado: 'neutro',
                    }
                  : null
              "
              :contexto="ctxJornada"
              pe="etapa por etapa"
              @abrir="
                abrir(
                  'jornada',
                  'Linha do tempo da turma',
                  cirurgia.jornada?.ate_cirurgia
                    ? dias(cirurgia.jornada.ate_cirurgia.media_dias)
                    : '—'
                )
              "
            />
          </div>
          <div class="cvg-graficos">
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Da consulta à cirurgia</span>
                <span>{{ pctTxt(cirurgia.taxa_fechamento) }} fecham</span>
              </span>
              <div class="cvg-grafico-corpo">
                <FunnelSteps
                  :steps="funilCirurgia"
                  :height="130"
                  start-text="das consultas"
                />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Indicação e fechamento</span>
              </span>
              <div class="cvg-grafico-corpo cvg-aneis">
                <div class="cvg-anel">
                  <svg viewBox="0 0 100 100" aria-hidden="true">
                    <circle
                      class="trilho"
                      cx="50"
                      cy="50"
                      :r="anelIndicacao.r"
                    />
                    <circle
                      class="valor"
                      cx="50"
                      cy="50"
                      :r="anelIndicacao.r"
                      :stroke-dasharray="anelIndicacao.c"
                      :stroke-dashoffset="anelIndicacao.offset"
                      transform="rotate(-90 50 50)"
                    />
                    <text x="50" y="57" text-anchor="middle">
                      {{ Math.round(anelIndicacao.pct) }}%
                    </text>
                  </svg>
                  <p class="cvg-corpo">
                    <b>indicação</b><br />
                    <span class="cvg-legenda"
                      >{{ n(cirurgia.indicadas) }} de
                      {{ n(cirurgia.consultas_realizadas) }} consultas</span
                    >
                  </p>
                </div>
                <div class="cvg-anel">
                  <svg viewBox="0 0 100 100" aria-hidden="true">
                    <circle
                      class="trilho"
                      cx="50"
                      cy="50"
                      :r="anelFechamento.r"
                    />
                    <circle
                      class="valor cvg-anel-destaque"
                      cx="50"
                      cy="50"
                      :r="anelFechamento.r"
                      :stroke-dasharray="anelFechamento.c"
                      :stroke-dashoffset="anelFechamento.offset"
                      transform="rotate(-90 50 50)"
                    />
                    <text x="50" y="57" text-anchor="middle">
                      {{ Math.round(anelFechamento.pct) }}%
                    </text>
                  </svg>
                  <p class="cvg-corpo">
                    <b>fechamento</b><br />
                    <span class="cvg-legenda"
                      >{{ n(cirurgia.fecharam) }} de
                      {{ n(cirurgia.indicadas) }} indicações</span
                    >
                  </p>
                </div>
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>{{
                  barrasJornada.length ? 'Etapa por etapa' : 'Tempo até agendar'
                }}</span>
                <span>{{
                  barrasJornada.length
                    ? 'mediana de dias'
                    : 'quem chegou e agendou'
                }}</span>
              </span>
              <div class="cvg-grafico-corpo">
                <HBars
                  v-if="barrasJornada.length"
                  :rows="barrasJornada"
                  :label-width="8"
                  :highlight-max="false"
                />
                <HBars
                  v-else
                  :rows="barrasTempo"
                  :label-width="7"
                  :highlight-max="false"
                  empty-text="ninguém agendou ainda"
                />
              </div>
            </div>
          </div>
        </div>
      </CvBloco>

      <!-- ══ 11–13 · DINHEIRO (só admin) ══ -->
      <CvBloco
        v-if="dinheiro"
        titulo="Quanto gasto e quanto ganho"
        subtitulo="Custo por paciente, ticket médio, gastos do período e as conversões de cirurgia. Só administradores veem."
        icon="i-lucide-wallet"
      >
        <div class="cvg-bloco-pilha">
          <div class="cvg-fila cvg-fila--3">
            <CvIndicador
              rotulo="CAC total"
              :valor="dinheiro.cac_total ? brl(dinheiro.cac_total) : '—'"
              :comparacao="{
                texto: `${n(dinheiro.pacientes)} pacientes · faturamento ${brl(dinheiro.faturamento)}`,
                estado: 'neutro',
              }"
              :contexto="ctxCac"
              heroi
              pe="por canal · por médico"
              @abrir="
                abrir(
                  'cac',
                  'Custo de aquisição',
                  dinheiro.cac_total ? brl(dinheiro.cac_total) : '—'
                )
              "
            />
            <CvIndicador
              rotulo="Gastos do período"
              :valor="brl(dinheiro.gastos.total)"
              :comparacao="{
                texto: `anúncios ${brl(dinheiro.gastos.anuncios)}`,
                estado: 'neutro',
              }"
              :contexto="ctxGastos"
              pe="mês a mês"
              @abrir="
                abrir('gastos', 'Gastos mês a mês', brl(dinheiro.gastos.total))
              "
            />
            <CvIndicador
              rotulo="Cirurgia por lead"
              :valor="pctTxt(dinheiro.conversoes.por_lead)"
              :comparacao="{
                texto: `${n(dinheiro.conversoes.cirurgias_realizadas)} cirurgias realizadas`,
                estado: 'neutro',
              }"
              :contexto="ctxConversoes"
            />
          </div>
          <div class="cvg-graficos">
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Gastos mês a mês</span>
                <span>{{ historico.length }} meses</span>
              </span>
              <div class="cvg-grafico-corpo">
                <MiniBars
                  v-if="historicoValores.length"
                  :values="historicoValores"
                  :labels="historicoRotulos"
                  :color="cor"
                  :height="130"
                  :format="brl"
                />
                <p v-else class="cvg-legenda">
                  Histórico aparece com dois meses ou mais no período.
                </p>
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Onde foi o dinheiro</span>
                <span>{{ brl(dinheiro.gastos.total) }}</span>
              </span>
              <div class="cvg-grafico-corpo">
                <HBars :rows="barrasGastos" :label-width="7" :format="brl" />
              </div>
            </div>
            <div class="cvg-grafico">
              <span class="cvg-grafico-titulo">
                <span>Gasto × faturamento por canal</span>
              </span>
              <div class="cvg-grafico-corpo">
                <HBars
                  :rows="barrasCanais"
                  :series="[
                    { label: 'gasto', color: corGrad3 },
                    { label: 'faturamento', color: corGrad },
                  ]"
                  :label-width="7"
                  :format="brl"
                  :highlight-max="false"
                />
              </div>
            </div>
          </div>
        </div>
      </CvBloco>

      <!-- ══ 14 · MÉDICOS (só admin) ══ -->
      <CvBloco
        v-if="dinheiro"
        titulo="Médicos"
        subtitulo="Agenda mais cheia e mais vazia, presença e conversão de cada médico no período"
        icon="i-lucide-user-round"
      >
        <div v-if="!medicos.length" class="cvg-vazio">
          Nenhuma consulta com médico no período.
        </div>
        <div v-else class="cvg-graficos cvg-graficos--2">
          <div class="cvg-grafico">
            <span class="cvg-grafico-titulo">
              <span>Agenda ocupada × presença</span>
              <span>em %</span>
            </span>
            <div class="cvg-grafico-corpo">
              <HBars
                :rows="barrasMedicos"
                :series="[
                  { label: 'agenda ocupada', color: corGrad2 },
                  { label: 'presença', color: corGrad },
                ]"
                :label-width="10"
                :format="v => pctTxt(v)"
                :highlight-max="false"
              />
            </div>
          </div>
          <div class="cvg-grafico">
            <span class="cvg-grafico-titulo">
              <span>Indicações × cirurgias</span>
            </span>
            <div class="cvg-grafico-corpo">
              <HBars
                :rows="barrasMedicosCirurgia"
                :series="[
                  { label: 'indicações', color: corGrad2 },
                  { label: 'cirurgias', color: corGrad },
                ]"
                :label-width="10"
                :highlight-max="false"
              />
            </div>
          </div>
        </div>
      </CvBloco>
    </template>

    <!-- ══ PAINEL LATERAL: a história do número ══ -->
    <CvPainelLateral
      :aberto="!!painel"
      :titulo="painel?.titulo || ''"
      :valor="painel?.valor ?? ''"
      :comparacao="painel?.comparacao"
      :vars="vars"
      @fechar="fechar"
    >
      <template v-if="painel && data">
        <section v-if="listaOrigem.length" class="cvg-painel-sec">
          <h3>De onde vieram (caixa de entrada)</h3>
          <div v-for="r in listaOrigem" :key="r.label" class="cvg-visao-barra">
            <div class="cvg-visao-barra-linha">
              <span>{{ r.label }}</span>
              <b>
                {{ n(r.count) }} ·
                {{
                  pctTxt((r.count / Math.max(totalDe(listaOrigem), 1)) * 100)
                }}
              </b>
            </div>
            <div class="cvg-visao-barra-trilho">
              <i
                :style="{
                  width: `${(r.count / Math.max(totalDe(listaOrigem), 1)) * 100}%`,
                }"
              />
            </div>
          </div>
        </section>
        <section v-if="listaCanal.length" class="cvg-painel-sec">
          <h3>Por canal (rastro de anúncio)</h3>
          <div v-for="r in listaCanal" :key="r.label" class="cvg-visao-barra">
            <div class="cvg-visao-barra-linha">
              <span>{{ r.label }}</span>
              <b>{{ n(r.count) }}</b>
            </div>
            <div class="cvg-visao-barra-trilho">
              <i
                :style="{
                  width: `${(r.count / Math.max(totalDe(listaCanal), 1)) * 100}%`,
                }"
              />
            </div>
          </div>
        </section>
        <section v-if="volumeAberto" class="cvg-painel-sec">
          <h3>Como é contado</h3>
          <p class="cvg-corpo">{{ volumeAberto.formula }}</p>
          <div
            v-for="x in volumeAberto.extra || []"
            :key="x.label"
            class="cvg-linha cvg-visao-linha2"
          >
            <span>{{ x.label }}</span>
            <b>{{ n(x.valor) }}</b>
          </div>
        </section>
        <template v-if="volumeAberto">
          <section
            v-for="q in volumeAberto.quebras"
            :key="q.titulo"
            class="cvg-painel-sec"
          >
            <h3>{{ q.titulo }}</h3>
            <div v-for="r in q.rows" :key="r.label" class="cvg-visao-barra">
              <div class="cvg-visao-barra-linha">
                <span>{{ r.label }}</span>
                <b>
                  {{ n(r.count) }} ·
                  {{ pctTxt((r.count / Math.max(totalDe(q.rows), 1)) * 100) }}
                </b>
              </div>
              <div class="cvg-visao-barra-trilho">
                <i
                  :style="{
                    width: `${(r.count / Math.max(totalDe(q.rows), 1)) * 100}%`,
                  }"
                />
              </div>
            </div>
          </section>
        </template>
        <section
          v-if="['agendaram', 'agendaram_base'].includes(painel.key)"
          class="cvg-painel-sec"
        >
          <h3>Como é contado</h3>
          <p class="cvg-corpo">
            {{
              painel.key === 'agendaram'
                ? entrada.agendaram_novos.formula
                : entrada.agendaram_base.formula
            }}
          </p>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Leads novos (chegaram {{ nomePeriodo }})</span>
            <b>{{ n(entrada.agendaram_novos.valor) }}</b>
          </div>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Da base (chegaram antes)</span>
            <b>{{ n(entrada.agendaram_base.valor) }}</b>
          </div>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Total de pessoas que agendaram</span>
            <b>{{ n(entrada.agendaram_total.valor) }}</b>
          </div>
        </section>
        <section
          v-if="painel.key === 'agendaram_base' && entrada.safra"
          class="cvg-painel-sec"
        >
          <h3>Quando tinham chegado</h3>
          <div
            v-for="f in entrada.safra.faixas.filter(x => x.key !== 'periodo')"
            :key="f.key"
            class="cvg-linha cvg-visao-linha2"
          >
            <span>{{ f.label }}</span>
            <b
              >{{ n(f.count)
              }}{{ f.media_dias !== null ? ` · ${dias(f.media_dias)}` : '' }}</b
            >
          </div>
          <template v-if="entrada.safra.semanas.length">
            <h3 class="mt-4">Semana de chegada</h3>
            <div
              v-for="w in entrada.safra.semanas"
              :key="w.inicio"
              class="cvg-linha cvg-visao-linha2"
            >
              <span>{{ w.label }}</span>
              <b
                >{{ n(w.count)
                }}{{
                  w.media_dias !== null ? ` · ${dias(w.media_dias)}` : ''
                }}</b
              >
            </div>
          </template>
        </section>
        <section
          v-if="painel.key === 'agendaram' && entrada.tempo"
          class="cvg-painel-sec"
        >
          <h3>Tempo até agendar</h3>
          <p class="cvg-corpo">
            Média de {{ dias(entrada.tempo.media_dias) }}, mediana
            {{ dias(entrada.tempo.mediana_dias) }}, em
            {{ n(entrada.tempo.amostra) }} pessoas que chegaram e agendaram no
            período.
          </p>
          <p class="cvg-corpo cvg-texto-2">
            {{ n(entrada.tempo.mesmo_dia) }} no mesmo dia ·
            {{ n(entrada.tempo.ate_7) }} em até 7 dias ·
            {{ n(entrada.tempo.depois) }} depois.
          </p>
        </section>
        <section v-if="painel.key === 'ocupacao'" class="cvg-painel-sec">
          <h3>O que tem na agenda</h3>
          <div
            v-for="t in agenda.mix.tipos"
            :key="t.key"
            class="cvg-visao-barra"
          >
            <div class="cvg-visao-barra-linha">
              <span>{{ t.label }}</span>
              <b>{{ n(t.count) }} · {{ pctTxt(t.pct) }}</b>
            </div>
            <div class="cvg-visao-barra-trilho">
              <i :style="{ width: `${t.pct}%` }" />
            </div>
          </div>
          <p class="cvg-corpo cvg-texto-2 mt-3">
            Particular {{ n(agenda.mix.particular.count) }} ({{
              pctTxt(agenda.mix.particular.pct)
            }}) · Oftalmofácil
            {{ n(agenda.mix.oftalmofacil.count) }}
            ({{ pctTxt(agenda.mix.oftalmofacil.pct) }}).
          </p>
          <h3 class="mt-4">Ocupação por médico</h3>
          <div
            v-for="m in agenda.ocupacao.por_medico"
            :key="m.medico"
            class="cvg-visao-barra"
          >
            <div class="cvg-visao-barra-linha">
              <span>{{ m.medico }}</span>
              <b>{{ n(m.ocupadas) }}/{{ n(m.vagas) }} · {{ pctTxt(m.pct) }}</b>
            </div>
            <div class="cvg-visao-barra-trilho">
              <i :style="{ width: `${m.pct}%` }" />
            </div>
          </div>
        </section>
        <section v-if="painel.key === 'confirmacao'" class="cvg-painel-sec">
          <h3>Confirmação, reagendamento e cancelamento</h3>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Confirmaram</span>
            <b
              >{{ n(agenda.confirmaram) }} ·
              {{ pctTxt(agenda.taxa_confirmacao) }}</b
            >
          </div>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Disseram que não vão</span>
            <b>{{ n(agenda.recusaram) }}</b>
          </div>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Reagendaram</span>
            <b
              >{{ n(agenda.reagendaram) }} ·
              {{ pctTxt(agenda.taxa_reagendamento) }}</b
            >
          </div>
          <div class="cvg-linha cvg-visao-linha2">
            <span>Cancelaram</span>
            <b
              >{{ n(agenda.cancelaram) }} ·
              {{ pctTxt(agenda.taxa_cancelamento) }}</b
            >
          </div>
          <template v-if="agenda.motivos_cancelamento.length">
            <h3 class="mt-4">Motivos de cancelamento</h3>
            <div
              v-for="r in agenda.motivos_cancelamento"
              :key="r.label"
              class="cvg-linha cvg-visao-linha2"
            >
              <span>{{ r.label }}</span>
              <b>{{ n(r.count) }}</b>
            </div>
          </template>
        </section>
        <section
          v-if="painel.key === 'jornada' && cirurgia.jornada"
          class="cvg-painel-sec"
        >
          <h3>Etapa por etapa (turma que chegou no período)</h3>
          <div
            v-for="e in cirurgia.jornada.etapas"
            :key="e.key"
            class="cvg-visao-barra"
          >
            <div class="cvg-visao-barra-linha">
              <span>{{ e.label }}</span>
              <b>
                {{ n(e.count) }} · {{ pctTxt(e.pct)
                }}{{
                  e.mediana_dias !== null && e.mediana_dias !== undefined
                    ? ` · +${dias(e.mediana_dias)}`
                    : ''
                }}
              </b>
            </div>
            <div class="cvg-visao-barra-trilho">
              <i :style="{ width: `${e.pct}%` }" />
            </div>
          </div>
        </section>
        <section v-if="painel.key === 'cac' && dinheiro" class="cvg-painel-sec">
          <h3>Por canal</h3>
          <div
            v-for="c in dinheiro.canais"
            :key="c.key"
            class="cvg-linha cvg-visao-linha2"
          >
            <span>
              {{ c.label }}<br />
              <span class="cvg-legenda"
                >{{ n(c.patients) }} pacientes · {{ n(c.leads) }} leads · gasto
                {{ brl(c.spend) }}</span
              >
            </span>
            <b>
              CAC {{ c.cac ? brl(c.cac) : '—' }}<br />
              <span class="cvg-legenda">ticket {{ brl(c.ticket_medio) }}</span>
            </b>
          </div>
          <h3 class="mt-4">Ticket médio por médico</h3>
          <div
            v-for="m in dinheiro.ticket_por_medico"
            :key="m.medico"
            class="cvg-linha cvg-visao-linha2"
          >
            <span>
              {{ m.medico }}<br />
              <span class="cvg-legenda"
                >{{ n(m.fechamentos) }} fechamentos</span
              >
            </span>
            <b>{{ brl(m.ticket_medio) }}</b>
          </div>
        </section>
        <section
          v-if="painel.key === 'gastos' && dinheiro"
          class="cvg-painel-sec"
        >
          <h3>Mês a mês</h3>
          <div
            v-for="m in dinheiro.historico"
            :key="m.month"
            class="cvg-linha cvg-visao-linha2"
          >
            <span>
              {{ m.month }}<br />
              <span class="cvg-legenda"
                >Meta {{ brl(m.meta) }} · Google {{ brl(m.google) }} · WhatsApp
                {{ brl(m.whatsapp) }} · IA {{ brl(m.ai) }}</span
              >
            </span>
            <b>
              {{ brl(m.total) }}<br />
              <span class="cvg-legenda"
                >CAC {{ m.cac_total ? brl(m.cac_total) : '—' }}</span
              >
            </b>
          </div>
        </section>
        <section v-if="listaPessoas.length" class="cvg-painel-sec">
          <h3>
            Pessoas ({{ n(listaPessoas.length)
            }}{{ listaPessoas.length >= 60 ? '+' : '' }})
          </h3>
          <button
            v-for="p in listaPessoas"
            :key="`${painel.key}-${p.id}-${p.telefone}`"
            type="button"
            class="cvg-linha cvg-visao-pessoa"
            @click="abrirContato(p.id)"
          >
            <span class="cvg-linha-quem">
              <b>{{ p.nome }}</b>
              <span class="cvg-legenda">{{ pessoaSub(p) }}</span>
            </span>
            <span class="cvg-legenda">›</span>
          </button>
        </section>
      </template>
    </CvPainelLateral>
  </section>
</template>

<style lang="scss">
/* 🧭 Visão geral do Meu Painel (item 337) */
/* item 342: tabela "quem chegou agendou" e a fileira do volume do período */
.cv-page .cvg-visao-volumes {
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
}
.cvg-visao-tabela {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  line-height: 20px;
  font-variant-numeric: tabular-nums;
}
.cvg-visao-tabela th {
  text-align: right;
  font-weight: 500;
  font-size: 12px;
  line-height: 16px;
  color: var(--g-texto-3);
  padding: 4px;
  vertical-align: bottom;
}
.cvg-visao-tabela td {
  text-align: right;
  padding: 6px 4px;
  border-top: 1px solid var(--g-borda);
  white-space: nowrap;
}
.cvg-visao-tabela th:first-child,
.cvg-visao-tabela td:first-child {
  text-align: left;
  white-space: normal;
}
.cvg-visao-tabela td b {
  font-weight: 600;
}
.cvg-visao-nota-clicavel {
  cursor: pointer;
}
.cvg-visao-nota-clicavel:hover {
  text-decoration: underline;
}
.cv-page .cvg-visao {
  display: flex;
  flex-direction: column;
  gap: 24px;
  margin-bottom: 24px;
}
.cv-page .cvg-visao-topo {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  justify-content: space-between;
  gap: 12px 24px;
}
.cv-page .cvg-aneis {
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.cv-page .cvg-anel-destaque {
  stroke: var(--gd);
}
.cvg-visao-barra {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 8px 0;
}
.cvg-visao-barra-linha {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  font-size: 15px;
  line-height: 22px;
}
.cvg-visao-barra-linha b {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.cvg-visao-barra-trilho {
  height: 6px;
  border-radius: 999px;
  background: rgb(var(--cv-rgb) / 0.14);
  overflow: hidden;
}
.cvg-visao-barra-trilho i {
  display: block;
  height: 100%;
  background: var(--cv-grad-2, var(--cv));
  border-radius: 999px;
}
.cvg-visao-linha2 {
  grid-template-columns: 1fr auto;
}
.cvg-visao-linha2 b {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  text-align: right;
}
.cvg-painel .cvg-visao-pessoa {
  grid-template-columns: 1fr auto;
  width: 100%;
  background: transparent;
  border-left: 0;
  border-right: 0;
  border-bottom: 0;
  text-align: left;
  cursor: pointer;
  color: inherit;
  font: inherit;
}
.cvg-painel .cvg-visao-pessoa:hover {
  background: rgb(var(--cv-rgb) / 0.08);
}
</style>
