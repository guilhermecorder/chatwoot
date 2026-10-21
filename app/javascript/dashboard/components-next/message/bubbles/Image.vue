<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useLoadWithRetry } from 'dashboard/composables/loadWithRetry';
import BaseBubble from './Base.vue';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { downloadFile } from '@chatwoot/utils';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

const { t } = useI18n();

const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});

const { isLoaded, hasError, loadWithRetry } = useLoadWithRetry();

const showGallery = ref(false);
const isDownloading = ref(false);
// CEVICO item 204: leitura da imagem pela IA (o que a foto mostra + texto legível)
const showFullReading = ref(false);

onMounted(() => {
  if (attachment.value?.dataUrl) {
    loadWithRetry(attachment.value.dataUrl);
  }
});

const downloadAttachment = async () => {
  const { fileType, dataUrl, extension } = attachment.value;
  try {
    isDownloading.value = true;
    await downloadFile({ url: dataUrl, type: fileType, extension });
  } catch (error) {
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};

const handleImageError = () => {
  hasError.value = true;
};
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="image"
    @click="showGallery = true"
  >
    <div v-if="hasError" class="flex items-center gap-1 text-center rounded-lg">
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      <p class="mb-0 text-n-slate-11">
        {{ $t('COMPONENTS.MEDIA.IMAGE_UNAVAILABLE') }}
      </p>
    </div>
    <div v-else-if="isLoaded" class="relative group rounded-lg overflow-hidden">
      <img
        class="skip-context-menu"
        :src="attachment.dataUrl"
        :width="attachment.width"
        :height="attachment.height"
      />
      <div
        class="inset-0 p-2 pointer-events-none absolute bg-gradient-to-tl from-n-slate-12/30 dark:from-n-slate-1/50 via-transparent to-transparent hidden group-hover:flex"
      />
      <div class="absolute right-2 bottom-2 hidden group-hover:flex gap-2">
        <Button xs solid slate icon="i-lucide-expand" class="opacity-60" />
        <Button
          xs
          solid
          slate
          icon="i-lucide-download"
          class="opacity-60"
          :is-loading="isDownloading"
          :disabled="isDownloading"
          @click.stop="downloadAttachment"
        />
      </div>
    </div>
    <p
      v-if="attachment.transcribedText"
      class="mt-2 mb-0 text-xs leading-snug text-n-slate-11 break-words cursor-text"
      :class="showFullReading ? '' : 'line-clamp-3'"
      :title="attachment.transcribedText"
      @click.stop="showFullReading = !showFullReading"
    >
      <span
        class="i-lucide-sparkles inline-block align-[-2px] mr-1 text-[11px]"
      />{{ attachment.transcribedText }}
    </p>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="handleImageError"
    @close="() => (showGallery = false)"
  />
</template>
