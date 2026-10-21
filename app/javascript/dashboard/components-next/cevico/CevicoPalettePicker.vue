<script setup>
// 🍎🍊 Popup "Paleta de cores" (rodadas 162/163): o admin escolhe, para a
// página inteira ou bloco a bloco, a cor do dia (iMac G3), uma das 17
// paletas (iMac G3 + frutas da Apple) ou a salada de frutas. Recebe o
// objeto do composable useCevicoPalette e salva sozinho.
import {
  SALAD,
  IMAC_PALETTES,
  FRUIT_PALETTES,
} from 'dashboard/helper/cevicoPalettes';

const props = defineProps({
  pal: { type: Object, required: true }, // retorno do useCevicoPalette
  title: { type: String, default: 'Paleta de cores' },
});

const {
  palettePicker,
  isSavingPalette,
  closePalettePicker,
  cvVars,
  pagePalette,
  dayFlavor,
  panelPalette,
  blockPalette,
  paletteChoice,
  pickPalette,
  paletteTargets,
  ownBlockPalettes,
  setBlockPalette,
  clearPanelPalettes,
  paletteLabel,
  userPalette,
  paletteAudience,
  setPaletteAudience,
  clearUserPalette,
  isAdmin,
} = props.pal;
</script>

<template>
  <Teleport to="body">
    <div
      v-if="palettePicker"
      class="cv-page cv-overlay fixed inset-0 z-[73] flex items-center justify-center bg-black/50 p-4"
      :style="cvVars"
      @click.self="closePalettePicker"
    >
      <div class="cv-modal w-full max-w-2xl max-h-[92vh] flex flex-col">
        <div
          class="cv-modal-head flex items-center gap-3"
          :style="{ background: pagePalette.hero }"
        >
          <span
            class="cv-glass w-9 h-9 flex items-center justify-center flex-shrink-0"
            ><span class="i-lucide-palette text-base"/></span>
          <div class="flex-1 min-w-0">
            <h2 class="text-base font-bold leading-tight">{{ title }}</h2>
            <p class="text-[11px] opacity-85 mt-0.5">
              iMac G3, frutas da Apple ou salada de frutas — para a página
              inteira ou bloco a bloco
            </p>
          </div>
          <span
            v-if="isSavingPalette"
            class="i-lucide-loader-circle animate-spin text-base"
          />
          <button
            class="cv-glass-btn cv-iconbtn"
            aria-label="Fechar"
            @click="closePalettePicker"
          >
            <span class="i-lucide-x text-base" />
          </button>
        </div>
        <div class="p-5 space-y-4 overflow-y-auto">
          <!-- para quem: só para mim (todo mundo pode) × para a clínica (admin) -->
          <div>
            <p class="cv-label mb-1.5">Para quem</p>
            <div class="flex flex-wrap items-center gap-1.5">
              <button
                class="cv-btn cv-btn-sm"
                :class="paletteAudience === 'me' ? '' : 'cv-btn-ghost'"
                @click="setPaletteAudience('me')"
              >
                <span class="i-lucide-user-round text-xs" />
                Só para mim
              </button>
              <button
                v-if="isAdmin"
                class="cv-btn cv-btn-sm"
                :class="paletteAudience === 'everyone' ? '' : 'cv-btn-ghost'"
                @click="setPaletteAudience('everyone')"
              >
                <span class="i-lucide-users-round text-xs" />
                Para todo mundo (padrão da clínica)
              </button>
              <span class="text-[11px] text-n-slate-9">{{
                paletteAudience === 'me'
                  ? 'só você vê esta cor; dá pra trocar quando quiser'
                  : 'vale para quem não escolheu uma cor pessoal'
              }}</span>
            </div>
          </div>

          <!-- onde aplicar -->
          <div v-if="paletteAudience === 'everyone'">
            <p class="cv-label mb-1.5">Onde aplicar</p>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="t in paletteTargets"
                :key="t.id"
                class="cv-btn cv-btn-sm"
                :class="palettePicker.target === t.id ? '' : 'cv-btn-ghost'"
                @click="palettePicker.target = t.id"
              >
                <span :class="t.icon" class="text-xs" />
                {{ t.label }}
                <span
                  v-if="t.id !== 'panel'"
                  class="w-2 h-2 rounded-full flex-shrink-0"
                  :style="{
                    background:
                      blockPalette(t.id).swatch || blockPalette(t.id).dot,
                    boxShadow: '0 0 0 1.5px rgba(255,255,255,0.8)',
                  }"
                />
              </button>
            </div>
          </div>

          <!-- página inteira: os modos automáticos -->
          <div v-if="palettePicker.target === 'panel'">
            <p class="cv-label mb-1.5">Modo da página</p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
              <button
                v-if="paletteAudience === 'me'"
                class="cv-sub cv-sub-hover p-3 text-left flex items-center gap-3"
                :class="paletteChoice === '' ? 'cv-sub-on' : ''"
                @click="pickPalette('')"
              >
                <span class="cv-icon cv-icon-lg flex-shrink-0"><span class="i-lucide-building-2 text-base"/></span>
                <span class="min-w-0">
                  <b class="text-xs text-n-slate-12 block">Padrão da clínica</b>
                  <span class="text-[11px] text-n-slate-10 leading-snug block">seguir a cor que o admin escolheu para esta tela</span>
                </span>
              </button>
              <button
                class="cv-sub cv-sub-hover p-3 text-left flex items-center gap-3"
                :class="paletteChoice === 'day' ? 'cv-sub-on' : ''"
                @click="pickPalette('day')"
              >
                <span
                  class="cv-icon cv-icon-lg flex-shrink-0"
                  :style="{ background: dayFlavor.hero }"
                  ><span class="i-lucide-calendar-days text-base"/></span>
                <span class="min-w-0">
                  <b class="text-xs text-n-slate-12 block">Cor do dia (iMac G3)</b>
                  <span class="text-[11px] text-n-slate-10 leading-snug block">hoje é {{ dayFlavor.label }} — cada dia da semana muda
                    sozinho</span>
                </span>
              </button>
              <button
                class="cv-sub cv-sub-hover p-3 text-left flex items-center gap-3"
                :class="paletteChoice === 'salad' ? 'cv-sub-on' : ''"
                @click="pickPalette('salad')"
              >
                <span
                  class="cv-icon cv-icon-lg flex-shrink-0"
                  :style="{ background: SALAD.swatch }"
                  ><span class="i-lucide-citrus text-base"/></span>
                <span class="min-w-0">
                  <b class="text-xs text-n-slate-12 block">Salada de frutas</b>
                  <span class="text-[11px] text-n-slate-10 leading-snug block">cada bloco com uma fruta e os cards alternando — dá pra
                    trocar a fruta de qualquer bloco depois</span>
                </span>
              </button>
            </div>
          </div>
          <!-- um bloco: pode voltar a seguir a página -->
          <div v-else class="flex items-center gap-2 flex-wrap">
            <button
              class="cv-btn cv-btn-sm"
              :class="paletteChoice === '' ? '' : 'cv-btn-ghost'"
              @click="pickPalette('')"
            >
              <span class="i-lucide-link text-xs" />
              Igual à página
            </button>
            <span class="text-[11px] text-n-slate-9">ou escolha uma paleta só para este bloco:</span>
          </div>

          <!-- as 17 paletas -->
          <div>
            <p class="cv-label mb-1.5">
              {{
                palettePicker.target === 'panel'
                  ? 'Ou uma paleta fixa'
                  : 'Paleta deste bloco'
              }}
            </p>
            <p class="text-[10px] text-n-slate-9 mb-1">iMac G3 (1998–99)</p>
            <div class="flex flex-wrap gap-1.5 mb-3">
              <button
                v-for="p in IMAC_PALETTES"
                :key="p.key"
                class="cv-swatch text-n-slate-12"
                :class="paletteChoice === p.key ? 'cv-swatch-on' : ''"
                :title="p.label"
                @click="pickPalette(p.key)"
              >
                <span class="cv-swatch-dot" :style="{ background: p.hero }" />
                {{ p.label }}
              </button>
            </div>
            <p class="text-[10px] text-n-slate-9 mb-1">Frutas da Apple</p>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="p in FRUIT_PALETTES"
                :key="p.key"
                class="cv-swatch text-n-slate-12"
                :class="paletteChoice === p.key ? 'cv-swatch-on' : ''"
                :title="p.label"
                @click="pickPalette(p.key)"
              >
                <span class="cv-swatch-dot" :style="{ background: p.hero }" />
                {{ p.emoji }} {{ p.label }}
              </button>
            </div>
          </div>

          <!-- resumo dos blocos com paleta própria -->
          <div
            v-if="
              palettePicker.target === 'panel' && paletteAudience === 'everyone'
            "
          >
            <p class="cv-label mb-1.5">Blocos com paleta própria</p>
            <div v-if="ownBlockPalettes.length" class="flex flex-wrap gap-1.5">
              <span
                v-for="b in ownBlockPalettes"
                :key="b.id"
                class="cv-chip cv-chip-lg"
              >
                <span :class="b.icon" class="text-xs" />
                {{ b.label }} · {{ paletteLabel(b.palette) }}
                <button
                  class="i-lucide-x text-xs opacity-70 hover:opacity-100"
                  title="Voltar a seguir a página"
                  @click="setBlockPalette(b.id, '')"
                />
              </span>
            </div>
            <p v-else class="text-[11px] text-n-slate-9">
              nenhum — clique num bloco em "Onde aplicar" para dar uma cor só
              dele
            </p>
          </div>
        </div>
        <div class="cv-modal-foot flex items-center gap-2 flex-wrap">
          <button
            v-if="paletteAudience === 'me' && userPalette"
            class="cv-btn cv-btn-ghost cv-btn-danger"
            @click="clearUserPalette"
          >
            <span class="i-lucide-rotate-ccw text-xs" />
            Voltar ao padrão da clínica
          </button>
          <button
            v-else-if="
              paletteAudience === 'everyone' && Object.keys(panelPalette).length
            "
            class="cv-btn cv-btn-ghost cv-btn-danger"
            @click="clearPanelPalettes"
          >
            <span class="i-lucide-rotate-ccw text-xs" />
            Voltar ao padrão
          </button>
          <span class="flex-1 text-[11px] text-n-slate-9">{{
            paletteAudience === 'me'
              ? 'salva sozinho · só para você'
              : 'salva sozinho · vale para todo mundo que vê esta página'
          }}</span>
          <button class="cv-btn" @click="closePalettePicker">Pronto</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
