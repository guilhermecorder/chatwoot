<script>
import { getContrastingTextColor } from '@chatwoot/utils';

export default {
  props: {
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      default: '',
    },
    href: {
      type: String,
      default: '',
    },
    bgColor: {
      type: String,
      default: '',
    },
    small: {
      type: Boolean,
      default: false,
    },
    showClose: {
      type: Boolean,
      default: false,
    },
    icon: {
      type: String,
      default: '',
    },
    color: {
      type: String,
      default: '',
    },
    colorScheme: {
      type: String,
      default: '',
    },
    variant: {
      type: String,
      default: '',
    },
  },
  emits: ['remove'],
  computed: {
    textColor() {
      if (this.variant === 'smooth') return '';
      if (this.variant === 'dashed') return '';
      return this.color || getContrastingTextColor(this.bgColor);
    },
    labelClass() {
      return `label ${this.colorScheme} ${this.variant} ${
        this.small ? 'small' : ''
      }`;
    },
    labelStyle() {
      if (this.bgColor) {
        return {
          '--lb': this.bgColor,
          background: this.bgColor,
          color: this.textColor,
          border: `1px solid ${this.bgColor}`,
        };
      }
      // CEVICO 212: a cor da etiqueta vira a TINTA da pílula (fundo claro na
      // cor, letra na cor escurecida) — sem quadradinho colorido
      if (this.color) return { '--lb': this.color };
      return {};
    },
    // com tinta (smooth/dashed + cor), a bolinha some: a cor já está na pílula
    showDot() {
      return (
        ['smooth', 'dashed'].includes(this.variant) &&
        this.title &&
        !this.icon &&
        !this.color
      );
    },
    anchorStyle() {
      if (this.bgColor) {
        return { color: this.textColor };
      }
      return {};
    },
  },
  methods: {
    onClick() {
      this.$emit('remove', this.title);
    },
  },
};
</script>

<template>
  <div
    class="inline-flex ltr:mr-1 rtl:ml-1 mb-1"
    :class="labelClass"
    :style="labelStyle"
    :title="description"
  >
    <span v-if="icon" class="label-action--button">
      <fluent-icon :icon="icon" size="12" class="label--icon cursor-pointer" />
    </span>
    <span
      v-if="showDot"
      :style="{ background: color }"
      class="label-color-dot flex-shrink-0"
    />
    <span v-if="!href" class="whitespace-nowrap text-ellipsis overflow-hidden">
      {{ title }}
    </span>
    <a v-else :href="href" :style="anchorStyle">{{ title }}</a>
    <button
      v-if="showClose"
      class="label-close--button p-0"
      :style="{ color: textColor }"
      @click="onClick"
    >
      <fluent-icon icon="dismiss" size="12" class="close--icon" />
    </button>
  </div>
</template>

<style scoped lang="scss">
/* CEVICO item 212 (23/09): etiquetas no design Apple — pílula, tinta da
   própria cor (fundo bem claro na cor, letra na cor escurecida), sem
   quadradinho. Vale para o sistema inteiro (cartões, painel, contatos,
   relatórios): tudo passa por este componente. */
.label {
  --lb: #64748b;
  @apply items-center font-semibold text-[11px] rounded-full gap-1.5 px-2.5 h-6 leading-none whitespace-nowrap;
  letter-spacing: -0.005em;
  background: color-mix(in srgb, var(--lb) 13%, #fff);
  color: color-mix(in srgb, var(--lb) 78%, #111);
  border: 1px solid color-mix(in srgb, var(--lb) 28%, transparent);

  &.small {
    @apply text-[10.5px] px-2 h-5 leading-none;
  }

  &.small .label--icon,
  &.small .close--icon {
    @apply text-[0.5rem];
  }

  a {
    @apply text-xs;
    &:hover {
      @apply underline;
    }
  }

  /* Color Schemes */
  &.primary {
    @apply bg-n-blue-5 text-n-blue-12 border border-solid border-n-blue-7;

    a {
      @apply text-n-blue-12;
    }
    .label-color-dot {
      @apply bg-n-blue-9;
    }
  }
  &.secondary {
    @apply bg-n-slate-5 text-n-slate-12 border border-solid border-n-slate-7;

    a {
      @apply text-n-slate-12;
    }
    .label-color-dot {
      @apply bg-n-slate-9;
    }
  }
  &.success {
    @apply bg-n-teal-5 text-n-teal-12 border border-solid border-n-teal-7;

    a {
      @apply text-n-teal-12;
    }
    .label-color-dot {
      @apply bg-n-teal-9;
    }
  }
  &.alert {
    @apply bg-n-ruby-5 text-n-ruby-12 border border-solid border-n-ruby-7;

    a {
      @apply text-n-ruby-12;
    }
    .label-color-dot {
      @apply bg-n-ruby-9;
    }
  }
  &.warning {
    @apply bg-n-amber-5 text-n-amber-12 border border-solid border-n-amber-7;

    a {
      @apply text-n-amber-12;
    }
    .label-color-dot {
      @apply bg-n-amber-9;
    }
  }

  &.smooth {
    background: color-mix(in srgb, var(--lb) 13%, #fff);
    color: color-mix(in srgb, var(--lb) 78%, #111);
    border: 1px solid color-mix(in srgb, var(--lb) 28%, transparent);
  }

  &.dashed {
    background: transparent;
    color: color-mix(in srgb, var(--lb) 70%, #111);
    border: 1px dashed color-mix(in srgb, var(--lb) 45%, transparent);
  }
}
.dark .label,
.dark .label.smooth {
  background: color-mix(in srgb, var(--lb) 26%, #0f1115);
  color: color-mix(in srgb, var(--lb) 62%, #fff);
  border-color: color-mix(in srgb, var(--lb) 42%, transparent);
}
.dark .label.dashed {
  background: transparent;
  color: color-mix(in srgb, var(--lb) 65%, #fff);
}

.label-close--button {
  @apply -mr-1 rounded-full cursor-pointer flex items-center justify-center w-4 h-4;
  color: inherit;
  opacity: 0.7;
  &:hover {
    opacity: 1;
    background: color-mix(in srgb, var(--lb) 22%, transparent);
  }

  svg {
    color: inherit;
  }
}

.label-action--button {
  @apply flex mr-1;
}

.label-color-dot {
  @apply inline-block w-2 h-2 rounded-full;
}
.label.small .label-color-dot {
  @apply w-1.5 h-1.5 rounded-full;
}
</style>
