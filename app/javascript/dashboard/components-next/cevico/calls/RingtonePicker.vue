<script setup>
// 🔔 item 273: biblioteca de toques de chamada — ouça cada um e escolha o
// seu (fica salvo neste navegador; cada atendente escolhe o dela).
import { onBeforeUnmount, onMounted, ref } from 'vue';
import {
  RINGTONES,
  getRingtoneKey,
  setRingtoneKey,
  previewRingtone,
} from 'dashboard/helper/cevicoRingtones';

const emit = defineEmits(['close']);
const HEAD_GRAD = 'linear-gradient(135deg, #0f766e, #2dd4bf)';
const OFF_GRAD = 'linear-gradient(135deg, #475569, #94a3b8)';
const chosen = ref(getRingtoneKey());
const playing = ref('');
let stopPreview = null;

const stop = () => {
  if (stopPreview) stopPreview();
  stopPreview = null;
  playing.value = '';
};

const play = key => {
  if (playing.value === key) {
    stop();
    return;
  }
  stop();
  stopPreview = previewRingtone(key);
  playing.value = key;
  setTimeout(() => {
    if (playing.value === key) playing.value = '';
  }, 4500);
};

const choose = key => {
  chosen.value = key;
  setRingtoneKey(key);
  play(key);
};

const onKey = e => {
  if (e.key === 'Escape') emit('close');
};
onMounted(() => window.addEventListener('keydown', onKey));
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKey);
  stop();
});
</script>

<template>
  <Teleport to="body">
    <div
      class="cv-page cv-overlay fixed inset-0 z-[80] flex items-center justify-center bg-black/50 p-4"
      @click.self="emit('close')"
    >
      <div class="cv-modal w-full max-w-md max-h-[85vh] flex flex-col">
        <div class="cv-modal-head !p-5" :style="{ background: HEAD_GRAD }">
          <div class="flex items-center gap-2 text-white/90">
            <span class="i-lucide-bell-ring text-base" />
            <p class="text-sm font-bold flex-1">Toque das chamadas</p>
            <button
              class="cv-glass-btn cv-iconbtn"
              aria-label="Fechar"
              @click="emit('close')"
            >
              <span class="i-lucide-x text-sm" />
            </button>
          </div>
          <p class="text-xs text-white/85 mt-1">
            clique para ouvir · o marcado é o que toca quando alguém liga · vale
            para este computador
          </p>
        </div>
        <div class="p-4 overflow-y-auto">
          <button
            v-for="r in RINGTONES"
            :key="r.key"
            class="cv-sub cv-sub-hover w-full flex items-center gap-3 px-3 py-2.5 mb-1.5 text-left"
            :class="chosen === r.key ? 'ring-2 ring-emerald-400/70' : ''"
            @click="choose(r.key)"
          >
            <span
              class="w-8 h-8 rounded-full flex items-center justify-center text-white flex-shrink-0"
              :style="{ background: chosen === r.key ? HEAD_GRAD : OFF_GRAD }"
            >
              <span
                :class="playing === r.key ? 'i-lucide-volume-2' : r.icon"
                class="text-sm"
              />
            </span>
            <span class="flex-1 min-w-0">
              <span class="block text-xs font-semibold text-n-slate-12">
                {{ r.label }}
                <span
                  v-if="chosen === r.key"
                  class="ml-1 text-[10px] font-bold text-emerald-600"
                  >· em uso</span
                >
              </span>
              <span class="block text-[10px] text-n-slate-10">{{
                r.hint
              }}</span>
            </span>
            <span
              class="text-[10px] font-semibold text-n-slate-9 flex-shrink-0"
            >
              {{ playing === r.key ? 'tocando…' : 'ouvir' }}
            </span>
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
