<script setup>
import { watch, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import NextButton from 'dashboard/components-next/button/Button.vue';
import ContactNoteItem from 'next/Contacts/ContactsSidebar/components/ContactNoteItem.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  contactId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const uiFlags = useMapGetter('contactNotes/getUIFlags');
const notesByContact = useMapGetter('contactNotes/getAllNotesByContactId');
const isFetchingNotes = computed(() => uiFlags.value.isFetching);
const isCreatingNote = computed(() => uiFlags.value.isCreating);
const contactId = computed(() => props.contactId);
const noteContent = ref('');
const notes = computed(() => {
  if (!contactId.value) {
    return [];
  }
  return notesByContact.value(contactId.value) || [];
});

const getWrittenBy = ({ user } = {}) => {
  const currentUserId = currentUser.value?.id;
  return user?.id === currentUserId
    ? t('CONTACTS_LAYOUT.SIDEBAR.NOTES.YOU')
    : user?.name || t('CONVERSATION.BOT');
};

const onAdd = async () => {
  if (!contactId.value || !noteContent.value.trim() || isCreatingNote.value) {
    return;
  }

  await store.dispatch('contactNotes/create', {
    content: noteContent.value.trim(),
    contactId: contactId.value,
  });
  noteContent.value = '';
};

const onDelete = noteId => {
  if (!contactId.value || !noteId) {
    return;
  }

  store.dispatch('contactNotes/delete', {
    noteId,
    contactId: contactId.value,
  });
};

const keyboardEvents = {
  '$mod+Enter': {
    action: onAdd,
    allowOnFocusedInput: true,
  },
};

useKeyboardEvents(keyboardEvents);

watch(
  contactId,
  newContactId => {
    noteContent.value = '';
    if (newContactId) {
      store.dispatch('contactNotes/get', { contactId: newContactId });
    }
  },
  { immediate: true }
);
</script>

<!-- CEVICO: notas sem modal e sem gaveta — a lista em cima e a CAIXA DE
     TEXTO direta embaixo (Cmd/Ctrl+Enter também salva) -->
<template>
  <div>
    <div
      v-if="isFetchingNotes"
      class="flex items-center justify-center py-6 text-n-slate-11"
    >
      <Spinner />
    </div>
    <div
      v-else-if="notes.length"
      class="flex flex-col max-h-[260px] overflow-y-auto"
    >
      <ContactNoteItem
        v-for="note in notes"
        :key="note.id"
        class="py-3 last-of-type:border-b-0 px-1"
        :note="note"
        :written-by="getWrittenBy(note)"
        allow-delete
        collapsible
        @delete="onDelete"
      />
    </div>

    <div class="mt-1.5">
      <textarea
        v-model="noteContent"
        rows="2"
        :placeholder="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.PLACEHOLDER')"
        class="w-full rounded-lg border border-n-weak bg-n-solid-2 px-2.5 py-2 text-sm text-n-slate-12 resize-y focus:outline-none focus:border-n-brand"
        :disabled="!contactId"
      />
      <div class="flex justify-end mt-1">
        <NextButton
          solid
          blue
          xs
          :label="t('CONTACTS_LAYOUT.SIDEBAR.NOTES.SAVE')"
          :is-loading="isCreatingNote"
          :disabled="!noteContent.trim() || isCreatingNote"
          @click="onAdd"
        />
      </div>
    </div>
  </div>
</template>
