<script setup>
// Teia de UM criativo / peça / campeão: os eixos escolhidos no ambiente
// (`env`), a força contra os parâmetros e, opcionalmente, o polígono
// tracejado da média da conta.
import { computed } from 'vue';
import MiniRadar from 'dashboard/components-next/cevico/MiniRadar.vue';
import { useRadarAxes, datasetFor, averageDataset } from './radarAxes';

const props = defineProps({
  row: { type: Object, required: true },
  env: { type: String, required: true },
  group: { type: String, default: 'copy' }, // qual teia (copy | video | asset)
  scope: { type: String, default: 'creative' },
  relativeOk: { type: Boolean, default: true },
  targets: { type: Object, default: () => ({}) },
  averages: { type: Object, default: () => ({}) },
  peers: { type: Array, default: () => [] },
  size: { type: Number, default: 120 },
  labels: { type: Boolean, default: true },
  showAverage: { type: Boolean, default: false },
  legend: { type: Boolean, default: false },
  color: { type: String, default: 'var(--cv)' },
  label: { type: String, default: 'este criativo' },
});

const { axesFor } = useRadarAxes(props.env);
const axes = computed(() =>
  axesFor(props.group, props.scope, props.relativeOk)
);
const ctx = computed(() => ({
  targets: props.targets,
  averages: props.averages,
  peers: props.peers && props.peers.length ? props.peers : [props.row],
}));
const datasets = computed(() => {
  const list = [
    datasetFor(props.row, axes.value, ctx.value, {
      key: 'row',
      label: props.label,
      color: props.color,
    }),
  ];
  if (props.showAverage && (props.averages || props.peers.length > 1))
    list.push(averageDataset(axes.value, ctx.value));
  return list;
});
const strength = computed(() => {
  const vals = Object.values(datasets.value[0].values);
  return vals.length
    ? Math.round(vals.reduce((a, b) => a + b, 0) / vals.length)
    : 0;
});
defineExpose({ strength });
</script>

<template>
  <MiniRadar
    :axes="axes"
    :datasets="datasets"
    :size="size"
    :labels="labels"
    :legend="legend"
  />
</template>
