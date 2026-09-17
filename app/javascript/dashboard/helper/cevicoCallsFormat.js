// 📞 Formatadores das CHAMADAS NATIVAS de WhatsApp (item 167, rodada 1).
// Tudo em pt-BR, tom humano: telefone brasileiro bonito, tempo de conversa
// por extenso ("3 min 42 s"), relógio mm:ss do card em chamada e o título
// do card na conversa (espelho do Crm::Call#card_content do backend).

// "+5511999999999" → "+55 (11) 99999-9999" · "5511333344444" → "+55 (11) 3333-4444"
// "11999999999" → "(11) 99999-9999" · qualquer outro → "+<dígitos>"
export const formatPhoneBR = raw => {
  const digits = String(raw || '').replace(/\D/g, '');
  if (!digits) return '';
  let national = digits;
  let country = '';
  if (digits.length >= 12 && digits.startsWith('55')) {
    country = '+55 ';
    national = digits.slice(2);
  }
  if (national.length === 11) {
    return `${country}(${national.slice(0, 2)}) ${national.slice(2, 7)}-${national.slice(7)}`;
  }
  if (national.length === 10) {
    return `${country}(${national.slice(0, 2)}) ${national.slice(2, 6)}-${national.slice(6)}`;
  }
  return `+${digits}`;
};

// 0 → "0 s" · 42 → "42 s" · 222 → "3 min 42 s" · 3900 → "1 h 05 min"
export const formatTalkTime = seconds => {
  const total = Math.max(0, Math.round(Number(seconds) || 0));
  if (total < 60) return `${total} s`;
  const hours = Math.floor(total / 3600);
  const mins = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  if (hours > 0) return `${hours} h ${String(mins).padStart(2, '0')} min`;
  return secs > 0 ? `${mins} min ${secs} s` : `${mins} min`;
};

// relógio do card em chamada: 222 → "03:42" · 3723 → "1:02:03"
export const formatClock = seconds => {
  const total = Math.max(0, Math.floor(Number(seconds) || 0));
  const hours = Math.floor(total / 3600);
  const mins = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  const mmss = `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  return hours > 0 ? `${hours}:${mmss}` : mmss;
};

// "agora" · "há 2 min" · "há 3 h" · "há 2 d"
export const agoLabel = ts => {
  if (!ts) return '';
  const diffMs = Date.now() - new Date(ts).getTime();
  const mins = Math.floor(diffMs / 60000);
  if (mins < 1) return 'agora';
  if (mins < 60) return `há ${mins} min`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `há ${hours} h`;
  return `há ${Math.floor(hours / 24)} d`;
};

// "dd/mm hh:mm" no fuso do navegador
export const shortDateTime = ts => {
  if (!ts) return '';
  return new Date(ts).toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

export const initialsOf = name => {
  const parts = String(name || '')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (!parts.length) return '☎';
  const first = parts[0][0] || '';
  const last = parts.length > 1 ? parts[parts.length - 1][0] || '' : '';
  return `${first}${last}`.toUpperCase();
};

// o payload do card chega camelizado (MessageList) ou cru (API/cable):
// lê a chave nas duas grafias
const camel = key => key.replace(/_([a-z])/g, (_m, c) => c.toUpperCase());
export const pick = (obj, key) => {
  if (!obj) return undefined;
  if (obj[key] !== undefined) return obj[key];
  return obj[camel(key)];
};

export const END_REASON_LABELS = {
  completed: 'Atendida',
  not_answered: 'Ninguém atendeu',
  rejected: 'Recusada',
  outside_hours: 'Fora do horário',
  failed: 'Falha na ligação',
  canceled: 'Cancelada',
  hangup: 'Desligada',
  // 🤖 item 169: ligação da IA que ficou sem o webhook de fim
  sem_pos_chamada: 'Sem retorno da ElevenLabs',
  unknown: 'Sem registro',
};

export const STATUS_LABELS = {
  ringing: 'Tocando',
  accepted: 'Em chamada',
  completed: 'Atendida',
  missed: 'Perdida',
  rejected: 'Recusada',
  failed: 'Falha',
  canceled: 'Cancelada',
};

// ícone lucide + tom por direção/status (card na conversa, listas, dashboard)
export const callIcon = call => {
  const direction = pick(call, 'direction');
  const status = pick(call, 'status');
  if (direction === 'outbound') {
    if (['failed', 'canceled', 'missed', 'rejected'].includes(status)) {
      return { icon: 'i-lucide-phone-off', tone: 'text-amber-600' };
    }
    return { icon: 'i-lucide-phone-outgoing', tone: 'text-blue-600' };
  }
  if (status === 'missed') {
    return { icon: 'i-lucide-phone-missed', tone: 'text-red-500' };
  }
  if (['rejected', 'failed', 'canceled'].includes(status)) {
    return { icon: 'i-lucide-phone-off', tone: 'text-amber-600' };
  }
  if (status === 'ringing') {
    return { icon: 'i-lucide-phone', tone: 'text-emerald-600' };
  }
  return { icon: 'i-lucide-phone-incoming', tone: 'text-emerald-600' };
};

// espelho do Crm::Call#card_content: o título humano do card
export const callTitle = call => {
  const direction = pick(call, 'direction');
  const status = pick(call, 'status');
  const reason = pick(call, 'end_reason');
  const user = pick(call, 'user');
  const talk = formatTalkTime(pick(call, 'duration'));
  const answered = ['accepted', 'completed'].includes(status);

  if (direction === 'outbound') {
    if (status === 'ringing') return 'Ligação para o paciente · chamando…';
    if (status === 'accepted') return 'Ligação para o paciente · em andamento';
    if (status === 'completed') return `Ligação para o paciente · ${talk}`;
    if (status === 'failed') return 'Ligação para o paciente · falhou';
    if (status === 'canceled') return 'Ligação para o paciente · cancelada';
    return 'Ligação para o paciente · não atendida';
  }
  if (status === 'ringing') return 'Chamada recebida · tocando…';
  if (answered) {
    const who = user?.name ? ` · atendida por ${user.name}` : '';
    return status === 'accepted'
      ? `Chamada recebida${who} · em andamento`
      : `Chamada recebida${who} · ${talk}`;
  }
  if (status === 'rejected') {
    return reason === 'outside_hours'
      ? 'Chamada recusada · fora do horário'
      : 'Chamada recusada';
  }
  if (status === 'failed') return 'Chamada recebida · falhou';
  return 'Chamada perdida';
};
