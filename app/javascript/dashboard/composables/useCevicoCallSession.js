// 📞 Sessão de ÁUDIO das chamadas nativas de WhatsApp (item 167) — WebRTC
// puro, escrito do zero a partir da receita do contrato (docs/CHAMADAS_NATIVAS.md §6):
//   answer(sdpOffer) → getUserMedia({audio}) → RTCPeerConnection(STUN Google)
//     → setRemoteDescription(offer) → createAnswer → setLocalDescription
//     → espera iceGatheringState === 'complete' (3 s) → devolve o SDP local;
//   offer() idem para ligação da clínica; applyAnswer(sdp) fecha o aperto de mão;
//   remoto num <audio autoplay>; mudo; gravação = AudioContext misturando o
//   microfone + o áudio remoto → MediaStreamDestination → MediaRecorder
//   (webm/opus, fallback ogg/opus) → blob no fim; toque de chamada em WebAudio
//   (2 osciladores, "tum-tum … tum-tum"); Notification do navegador.
// É um SINGLETON por aba (uma chamada por vez): a store Pinia e o popup falam
// com a mesma sessão.
import { ref } from 'vue';

const ICE_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }];
const ICE_TIMEOUT_MS = 3000;
const MIME_CANDIDATES = ['audio/webm;codecs=opus', 'audio/ogg;codecs=opus'];

const isMuted = ref(false);
const isRecording = ref(false);
const hasRemote = ref(false);

let pc = null;
let localStream = null;
let remoteStream = null;
let remoteEl = null;

let mixCtx = null;
let mixDest = null;
let remoteSource = null;
let recorder = null;
let chunks = [];
let recordingStartedAt = null;

let ringCtx = null;
let ringTimer = null;

// ── áudio remoto ──
const attachRemoteAudio = () => {
  if (typeof document === 'undefined' || !remoteStream) return;
  if (!remoteEl) {
    remoteEl = document.createElement('audio');
    remoteEl.autoplay = true;
    remoteEl.setAttribute('playsinline', 'true');
    remoteEl.style.display = 'none';
    remoteEl.dataset.cevicoCallAudio = '1';
    document.body.appendChild(remoteEl);
  }
  remoteEl.srcObject = remoteStream;
  const playing = remoteEl.play();
  if (playing && playing.catch) playing.catch(() => {});
};

const detachRemoteAudio = () => {
  if (!remoteEl) return;
  try {
    remoteEl.pause();
    remoteEl.srcObject = null;
    remoteEl.remove();
  } catch {
    // já saiu do DOM
  }
  remoteEl = null;
};

// o remoto pode chegar depois da gravação começar: entra na mistura na hora
const mixRemoteIn = () => {
  if (!mixCtx || !mixDest || !remoteStream || remoteSource) return;
  try {
    remoteSource = mixCtx.createMediaStreamSource(remoteStream);
    remoteSource.connect(mixDest);
  } catch {
    remoteSource = null;
  }
};

// ── par WebRTC ──
const setupPeer = async () => {
  if (!navigator.mediaDevices?.getUserMedia) {
    throw new Error('Este navegador não permite chamadas de voz.');
  }
  localStream = await navigator.mediaDevices.getUserMedia({ audio: true });
  pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
  localStream.getTracks().forEach(track => pc.addTrack(track, localStream));
  pc.ontrack = event => {
    remoteStream =
      (event.streams && event.streams[0]) || new MediaStream([event.track]);
    hasRemote.value = true;
    attachRemoteAudio();
    mixRemoteIn();
  };
  isMuted.value = false;
  hasRemote.value = false;
};

const waitIceComplete = peer =>
  new Promise(resolve => {
    if (!peer || peer.iceGatheringState === 'complete') {
      resolve();
      return;
    }
    let timer = null;
    const check = () => {
      if (peer.iceGatheringState !== 'complete') return;
      clearTimeout(timer);
      peer.removeEventListener('icegatheringstatechange', check);
      resolve();
    };
    timer = setTimeout(() => {
      peer.removeEventListener('icegatheringstatechange', check);
      resolve();
    }, ICE_TIMEOUT_MS);
    peer.addEventListener('icegatheringstatechange', check);
  });

const answer = async sdpOffer => {
  if (!sdpOffer) throw new Error('A chamada veio sem a oferta de áudio.');
  await setupPeer();
  await pc.setRemoteDescription({ type: 'offer', sdp: sdpOffer });
  const localAnswer = await pc.createAnswer();
  await pc.setLocalDescription(localAnswer);
  await waitIceComplete(pc);
  return pc.localDescription.sdp;
};

const offer = async () => {
  await setupPeer();
  const localOffer = await pc.createOffer({ offerToReceiveAudio: true });
  await pc.setLocalDescription(localOffer);
  await waitIceComplete(pc);
  return pc.localDescription.sdp;
};

const applyAnswer = async sdp => {
  if (!pc || !sdp) return;
  if (pc.signalingState === 'stable') return; // já aplicada
  await pc.setRemoteDescription({ type: 'answer', sdp });
};

// ── mudo ──
const setMuted = muted => {
  isMuted.value = Boolean(muted);
  if (!localStream) return isMuted.value;
  localStream.getAudioTracks().forEach(track => {
    track.enabled = !isMuted.value;
  });
  return isMuted.value;
};
const mute = () => setMuted(true);
const unmute = () => setMuted(false);
const toggleMute = () => setMuted(!isMuted.value);

// ── gravação: mic + remoto misturados num MediaRecorder ──
const pickMime = () => {
  if (typeof MediaRecorder === 'undefined') return null;
  return (
    MIME_CANDIDATES.find(
      m => MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(m)
    ) || ''
  );
};

const closeMixer = () => {
  remoteSource = null;
  mixDest = null;
  if (mixCtx) {
    const closing = mixCtx.close();
    if (closing && closing.catch) closing.catch(() => {});
  }
  mixCtx = null;
};

const startRecording = () => {
  if (recorder || !localStream) return false;
  const mime = pickMime();
  if (mime === null) return false;
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return false;
  try {
    mixCtx = new Ctx();
    mixDest = mixCtx.createMediaStreamDestination();
    mixCtx.createMediaStreamSource(localStream).connect(mixDest);
    mixRemoteIn();
    recorder = new MediaRecorder(
      mixDest.stream,
      mime ? { mimeType: mime } : undefined
    );
    chunks = [];
    recorder.ondataavailable = event => {
      if (event.data && event.data.size) chunks.push(event.data);
    };
    recorder.start(1000);
    recordingStartedAt = Date.now();
    isRecording.value = true;
    return true;
  } catch {
    closeMixer();
    recorder = null;
    isRecording.value = false;
    return false;
  }
};

// devolve { blob, duration (s), mime, ext } ou null
const stopRecording = () =>
  new Promise(resolve => {
    if (!recorder) {
      resolve(null);
      return;
    }
    const current = recorder;
    const startedAt = recordingStartedAt;
    const finish = () => {
      const mime = current.mimeType || chunks[0]?.type || 'audio/webm';
      const blob = new Blob(chunks, { type: mime });
      const duration = startedAt
        ? Math.max(0, Math.round((Date.now() - startedAt) / 1000))
        : 0;
      chunks = [];
      recorder = null;
      recordingStartedAt = null;
      isRecording.value = false;
      closeMixer();
      resolve(
        blob.size
          ? { blob, duration, mime, ext: mime.includes('ogg') ? 'ogg' : 'webm' }
          : null
      );
    };
    current.onstop = finish;
    try {
      if (current.state !== 'inactive') current.stop();
      else finish();
    } catch {
      finish();
    }
  });

// ── encerrar tudo (devolve a gravação, se houver) ──
const hangup = async () => {
  const recording = await stopRecording();
  try {
    if (pc) {
      pc.ontrack = null;
      pc.getSenders().forEach(sender => {
        if (sender.track) sender.track.stop();
      });
      pc.close();
    }
  } catch {
    // o par já estava fechado
  }
  pc = null;
  if (localStream) localStream.getTracks().forEach(track => track.stop());
  localStream = null;
  remoteStream = null;
  detachRemoteAudio();
  isMuted.value = false;
  hasRemote.value = false;
  return recording;
};

// ── toque de chamada em WebAudio: 2 osciladores (440 + 480 Hz), "tum-tum" ──
const beep = (ctx, at, dur) => {
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0, at);
  gain.gain.linearRampToValueAtTime(0.18, at + 0.03);
  gain.gain.setValueAtTime(0.18, at + dur - 0.05);
  gain.gain.linearRampToValueAtTime(0, at + dur);
  gain.connect(ctx.destination);
  [440, 480].forEach(freq => {
    const osc = ctx.createOscillator();
    osc.type = 'sine';
    osc.frequency.value = freq;
    osc.connect(gain);
    osc.start(at);
    osc.stop(at + dur + 0.05);
  });
};

const ringOnce = () => {
  if (!ringCtx) return;
  const t = ringCtx.currentTime + 0.05;
  beep(ringCtx, t, 0.22); // tum
  beep(ringCtx, t + 0.34, 0.22); // tum
};

const startRingtone = () => {
  if (ringTimer) return;
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return;
  try {
    ringCtx = new Ctx();
    if (ringCtx.state === 'suspended') {
      const resuming = ringCtx.resume();
      if (resuming && resuming.catch) resuming.catch(() => {});
    }
    ringOnce();
    ringTimer = setInterval(ringOnce, 2600);
  } catch {
    ringCtx = null;
    ringTimer = null;
  }
};

const stopRingtone = () => {
  if (ringTimer) clearInterval(ringTimer);
  ringTimer = null;
  if (ringCtx) {
    const closing = ringCtx.close();
    if (closing && closing.catch) closing.catch(() => {});
  }
  ringCtx = null;
};

// ── Notification do navegador ("📞 Fulano está ligando") ──
const notify = (title, body = '', tag = 'cevico-call') => {
  if (typeof window === 'undefined' || !('Notification' in window)) return;
  if (Notification.permission !== 'granted') return;
  try {
    const n = new Notification(title, { body, tag, silent: true });
    n.onclick = () => {
      window.focus();
      n.close();
    };
    setTimeout(() => n.close(), 30000);
  } catch {
    // alguns navegadores bloqueiam fora de HTTPS
  }
};

// pedir a permissão só num gesto do usuário (Atender/Recusar/Ligar)
const ensureNotificationPermission = () => {
  if (typeof window === 'undefined' || !('Notification' in window)) return;
  if (Notification.permission !== 'default') return;
  try {
    const asking = Notification.requestPermission();
    if (asking && asking.catch) asking.catch(() => {});
  } catch {
    // ignorado
  }
};

export function useCevicoCallSession() {
  return {
    isMuted,
    isRecording,
    hasRemote,
    answer,
    offer,
    applyAnswer,
    mute,
    unmute,
    toggleMute,
    startRecording,
    stopRecording,
    hangup,
    startRingtone,
    stopRingtone,
    notify,
    ensureNotificationPermission,
  };
}
