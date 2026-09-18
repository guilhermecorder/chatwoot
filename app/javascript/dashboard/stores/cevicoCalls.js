// 📞 Store (Pinia) das CHAMADAS NATIVAS de WhatsApp — item 167, rodada 1.
// Recebe os 7 eventos `cevico_call.*` do ActionCable (helper/actionCable.js),
// decide se ESTA atendente deve ouvir tocar (ring_user_ids + disponibilidade)
// e conduz a chamada da aba: atender / recusar / desligar / ligar, gravação
// e o resumo de 6 s no fim. A parte de áudio mora em
// composables/useCevicoCallSession.js (uma sessão por aba).
import { defineStore } from 'pinia';
import vuexStore from 'dashboard/store';
import { useAlert } from 'dashboard/composables';
import CevicoCallsAPI from 'dashboard/api/cevicoCalls';
import { useCevicoCallSession } from 'dashboard/composables/useCevicoCallSession';
import { formatPhoneBR } from 'dashboard/helper/cevicoCallsFormat';

const ENDED_SUMMARY_MS = 6000;
const MAX_MISSED_BANNERS = 4;

const session = useCevicoCallSession();
// resposta SDP da ligação que pode chegar antes do /initiate responder
const pendingAnswers = {};
// chamadas já em encerramento (evita gravação enviada duas vezes)
const finishing = new Set();

const currentUserId = () => Number(vuexStore.getters.getCurrentUserID);
const availability = () => vuexStore.getters.getCurrentUserAvailability;
// chamada → timer da cascata "quem toca primeiro" (rodada 2)
const cascadeTimers = {};
const callsSettings = () => vuexStore.getters['crm/getSettings']?.calls || {};

export const useCevicoCallsStore = defineStore('cevicoCalls', {
  state: () => ({
    calls: {}, // id → payload (como veio da API/cable, snake_case)
    ringing: [], // ids tocando para mim
    active: null, // id da chamada desta aba (atendida ou ligando)
    activeSince: null, // ms — começo do timer (quando atendida)
    missedBanner: [], // [{ id, reason, at }]
    ended: [], // [{ id, at }] — resumo que some em 6 s
    permissions: {}, // contact_id → { status, expires_at }
    isMuted: false,
    isRecording: false,
    isBusy: false, // aceitando / ligando / desligando
    version: 0, // sobe a cada mudança relevante (cards refazem a lista)
  }),

  getters: {
    ringingCalls: s => s.ringing.map(id => s.calls[id]).filter(Boolean),
    activeCall: s => (s.active ? s.calls[s.active] : null),
    missedCalls: s =>
      s.missedBanner
        .map(m => ({ ...m, call: s.calls[m.id] }))
        .filter(m => m.call),
    endedCalls: s =>
      s.ended.map(e => ({ ...e, call: s.calls[e.id] })).filter(e => e.call),
    hasCards: s =>
      Boolean(
        s.ringing.length || s.active || s.missedBanner.length || s.ended.length
      ),
    permissionFor: s => contactId => s.permissions[contactId] || null,
  },

  actions: {
    upsert(call) {
      if (!call?.id) return;
      this.calls = {
        ...this.calls,
        [call.id]: { ...(this.calls[call.id] || {}), ...call },
      };
    },

    dropRinging(id) {
      clearTimeout(cascadeTimers[id]);
      delete cascadeTimers[id];
      this.ringing = this.ringing.filter(x => x !== id);
      if (!this.ringing.length) session.stopRingtone();
    },

    pushEnded(id) {
      if (this.ended.some(e => e.id === id)) return;
      this.ended = [...this.ended, { id, at: Date.now() }];
      setTimeout(() => this.dismiss(id), ENDED_SUMMARY_MS);
    },

    beginRecording() {
      const call = this.activeCall;
      if (!call || call.simulated) return;
      if (callsSettings().record === false) return;
      this.isRecording = session.startRecording();
    },

    // ── eventos do cable ──
    onRinging(data) {
      const call = data?.call;
      if (!call?.id) return;
      if (availability() === 'offline') return;
      const me = currentUserId();
      const ids = (data.ring_user_ids || []).map(Number);
      if (ids.length && !ids.includes(me)) return;
      if (call.status && call.status !== 'ringing') return;
      if (this.active === call.id || this.ringing.includes(call.id)) return;
      // "quem toca primeiro" (rodada 2): a linha de frente ouve na hora; o
      // resto só depois da espera, e só se a chamada ainda estiver tocando
      const firsts = (data.ring_first_user_ids || []).map(Number);
      if (firsts.length && !firsts.includes(me)) {
        this.upsert(call);
        clearTimeout(cascadeTimers[call.id]);
        const wait = Number(data.ring_cascade_seconds || 12) * 1000;
        cascadeTimers[call.id] = setTimeout(() => {
          delete cascadeTimers[call.id];
          const known = this.calls[call.id];
          if (!known || known.status !== 'ringing') return;
          if (this.active === call.id || this.ringing.includes(call.id)) return;
          this.ringNow(known);
        }, wait);
        return;
      }
      this.ringNow(call);
    },

    ringNow(call) {
      this.upsert(call);
      this.ringing = [...this.ringing, call.id];
      // em chamada, a segunda só aparece no card (sem toque por cima da voz)
      if (!this.active) session.startRingtone();
      session.notify(
        `📞 ${call.contact?.name || 'Paciente'} está ligando`,
        formatPhoneBR(call.contact?.phone_number || call.wa_id),
        `cevico-call-${call.id}`
      );
      this.version += 1;
    },

    onTaken(data) {
      const id = data?.call_id;
      if (!id || this.active === id) return; // esta aba atendeu
      this.dropRinging(id);
      const known = this.calls[id];
      if (known) {
        this.upsert({
          id,
          status: 'accepted',
          user: known.user || { id: data.user_id, name: data.user_name },
        });
      }
      this.version += 1;
    },

    onEnded(data) {
      const call = data?.call;
      if (!call?.id) return;
      this.upsert(call);
      this.dropRinging(call.id);
      if (this.active === call.id) this.finishActive(call.id);
      this.version += 1;
    },

    onMissed(data) {
      const call = data?.call;
      if (!call?.id) return;
      this.upsert(call);
      this.dropRinging(call.id);
      if (availability() === 'offline') return;
      if (!this.missedBanner.some(m => m.id === call.id)) {
        this.missedBanner = [
          {
            id: call.id,
            reason: data.reason || call.end_reason || 'not_answered',
            at: call.ended_at || new Date().toISOString(),
          },
          ...this.missedBanner,
        ].slice(0, MAX_MISSED_BANNERS);
      }
      this.version += 1;
    },

    onOutboundAnswer(data) {
      const id = data?.call_id;
      const sdp = data?.sdp_answer;
      if (!id || !sdp) return;
      if (this.active !== id) {
        pendingAnswers[id] = sdp;
        return;
      }
      session.applyAnswer(sdp).catch(() => {});
    },

    onStatus(data) {
      const id = data?.call_id;
      if (!id || !data.status) return;
      const status = String(data.status).toLowerCase();
      if (this.calls[id]) this.upsert({ id, status });
      if (this.active === id && status === 'accepted' && !this.activeSince) {
        this.activeSince = Date.now();
        this.upsert({ id, answered_at: new Date().toISOString() });
        this.beginRecording();
      }
    },

    onPermission(data) {
      const contactId = data?.contact_id;
      if (!contactId) return;
      this.permissions = {
        ...this.permissions,
        [contactId]: { status: data.status, expires_at: data.expires_at },
      };
      this.version += 1;
    },

    // ── ações da atendente ──
    async accept(id) {
      const call = this.calls[id];
      if (!call || this.isBusy) return;
      if (this.active && this.active !== id) {
        useAlert(
          'Você já está em uma chamada. Desligue antes de atender outra.'
        );
        return;
      }
      this.isBusy = true;
      session.stopRingtone();
      session.ensureNotificationPermission();
      try {
        let sdp = 'v=0 simulated-answer';
        if (!call.simulated) sdp = await session.answer(call.sdp_offer);
        const { data } = await CevicoCallsAPI.accept(id, sdp);
        this.upsert({ ...data, sdp_offer: null });
        this.ringing = this.ringing.filter(x => x !== id);
        this.active = id;
        this.activeSince = Date.now();
        this.isMuted = false;
        this.beginRecording();
      } catch (error) {
        await session.hangup();
        this.dropRinging(id);
        useAlert(
          error?.response?.data?.error ||
            (error?.name === 'NotAllowedError'
              ? 'Libere o microfone no navegador para atender.'
              : 'Não foi possível atender a chamada.')
        );
      } finally {
        this.isBusy = false;
        this.version += 1;
      }
    },

    async reject(id) {
      session.ensureNotificationPermission();
      this.dropRinging(id);
      this.version += 1;
      try {
        await CevicoCallsAPI.reject(id);
      } catch {
        // o webhook de terminate fecha do lado do servidor
      }
    },

    async hangup(id = this.active) {
      if (!id || this.isBusy) return;
      this.isBusy = true;
      try {
        await CevicoCallsAPI.hangup(id);
      } catch {
        // segue: encerra localmente mesmo assim
      }
      await this.finishActive(id);
      this.isBusy = false;
    },

    // encerra a sessão da aba, sobe a gravação e mostra o resumo de 6 s
    async finishActive(id) {
      if (finishing.has(id)) return;
      finishing.add(id);
      const call = this.calls[id];
      const talk = this.activeSince
        ? Math.round((Date.now() - this.activeSince) / 1000)
        : 0;
      const recording = await session.hangup();
      this.isRecording = false;
      this.isMuted = false;
      if (this.active === id) this.active = null;
      this.activeSince = null;
      if (recording?.blob?.size && !call?.simulated) {
        try {
          const fd = new FormData();
          fd.append(
            'recording',
            recording.blob,
            `chamada-${id}.${recording.ext}`
          );
          fd.append('duration', String(recording.duration));
          const { data } = await CevicoCallsAPI.uploadRecording(id, fd);
          this.upsert(data);
        } catch {
          useAlert('A gravação da chamada não pôde ser enviada.');
        }
      }
      if (!this.calls[id]?.duration && talk)
        this.upsert({ id, duration: talk });
      this.pushEnded(id);
      finishing.delete(id);
      this.version += 1;
    },

    dismiss(id) {
      this.ringing = this.ringing.filter(x => x !== id);
      if (!this.ringing.length) session.stopRingtone();
      this.missedBanner = this.missedBanner.filter(m => m.id !== id);
      this.ended = this.ended.filter(e => e.id !== id);
      this.version += 1;
    },

    toggleMute() {
      this.isMuted = session.toggleMute();
    },

    // ligação da clínica → paciente. Devolve o payload da chamada, ou
    // { error, permission } quando a Meta pede permissão (422), ou null.
    async startOutbound(contactId, inboxId = null) {
      if (this.active) {
        useAlert('Você já está em uma chamada.');
        return null;
      }
      if (this.isBusy) return null;
      this.isBusy = true;
      session.ensureNotificationPermission();
      try {
        const sdp = await session.offer();
        const { data } = await CevicoCallsAPI.initiate(contactId, sdp, inboxId);
        this.upsert({ ...data, sdp_answer: null });
        this.active = data.id;
        this.activeSince = null; // o timer começa no ACCEPTED
        const pending = pendingAnswers[data.id];
        if (pending) {
          delete pendingAnswers[data.id];
          await session.applyAnswer(pending);
        }
        return data;
      } catch (error) {
        await session.hangup();
        const resp = error?.response?.data;
        if (error?.response?.status === 422 && resp?.permission) {
          return { error: resp.error, permission: resp.permission };
        }
        useAlert(
          resp?.error ||
            (error?.name === 'NotAllowedError'
              ? 'Libere o microfone no navegador para ligar.'
              : 'Não foi possível iniciar a ligação.')
        );
        return null;
      } finally {
        this.isBusy = false;
        this.version += 1;
      }
    },
  },
});
