// CEVICO (item 199, 22/09): "Nova conversa" fácil — um só modal, aberto de
// qualquer lugar (botão dourado em Conversas, lápis do menu, vazio da
// direita, ficha do contato). Quem quer abrir chama openNovaConversa();
// o modal (NovaConversaModal.vue, montado uma vez no Dashboard) escuta.
import { emitter } from 'shared/helpers/mitt';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export const NOVA_CONVERSA_EVENT = 'cevico:nova-conversa';

// { contactId?, inboxId? } — os dois opcionais: pré-seleciona a pessoa e/ou
// a caixa quando já se sabe (ficha do contato, caixa aberta em Conversas)
export const openNovaConversa = (opts = {}) => {
  emitter.emit(NOVA_CONVERSA_EVENT, opts || {});
};

// nome em PT-BR simples de cada tipo de caixa
export const channelLabel = (channelType, medium) => {
  switch (channelType) {
    case INBOX_TYPES.WHATSAPP:
      return 'WhatsApp';
    case INBOX_TYPES.TWILIO:
      return medium === 'whatsapp' ? 'WhatsApp (Twilio)' : 'SMS (Twilio)';
    case INBOX_TYPES.SMS:
      return 'SMS';
    case INBOX_TYPES.EMAIL:
      return 'E-mail';
    case INBOX_TYPES.WEB:
      return 'Chat do site';
    case INBOX_TYPES.API:
      return 'Canal externo (API)';
    case INBOX_TYPES.FB:
      return 'Facebook';
    case INBOX_TYPES.INSTAGRAM:
      return 'Instagram';
    case INBOX_TYPES.TELEGRAM:
      return 'Telegram';
    case INBOX_TYPES.LINE:
      return 'Line';
    case INBOX_TYPES.TIKTOK:
      return 'TikTok';
    default:
      return 'Canal';
  }
};

// ícone lucide por tipo de caixa
export const channelIcon = (channelType, medium) => {
  switch (channelType) {
    case INBOX_TYPES.WHATSAPP:
      return 'i-ri-whatsapp-line';
    case INBOX_TYPES.TWILIO:
      return medium === 'whatsapp' ? 'i-ri-whatsapp-line' : 'i-lucide-message-square-text';
    case INBOX_TYPES.SMS:
      return 'i-lucide-message-square-text';
    case INBOX_TYPES.EMAIL:
      return 'i-lucide-mail';
    case INBOX_TYPES.WEB:
      return 'i-lucide-globe';
    case INBOX_TYPES.API:
      return 'i-lucide-plug-zap';
    case INBOX_TYPES.FB:
      return 'i-ri-facebook-circle-line';
    case INBOX_TYPES.INSTAGRAM:
      return 'i-ri-instagram-line';
    default:
      return 'i-lucide-message-circle';
  }
};

// por que esta caixa NÃO serve para esta pessoa (quando não é contatável)
export const notContactableReason = (channelType, contact = {}) => {
  const hasPhone = !!contact.phoneNumber;
  const hasEmail = !!contact.email;
  switch (channelType) {
    case INBOX_TYPES.WHATSAPP:
    case INBOX_TYPES.TWILIO:
    case INBOX_TYPES.SMS:
      return hasPhone
        ? 'Esta caixa não aceita começar conversa por aqui'
        : 'Precisa de um telefone no cadastro';
    case INBOX_TYPES.EMAIL:
      return hasEmail
        ? 'Esta caixa não aceita começar conversa por aqui'
        : 'Precisa de um e-mail no cadastro';
    case INBOX_TYPES.WEB:
      return 'Só quem já chamou pelo chat do site (e sem conversa aberta)';
    case INBOX_TYPES.FB:
    case INBOX_TYPES.INSTAGRAM:
    case INBOX_TYPES.TELEGRAM:
    case INBOX_TYPES.LINE:
    case INBOX_TYPES.TIKTOK:
      return 'Por aqui só dá para responder quem chamou primeiro';
    default:
      return 'Esta caixa não aceita começar conversa por aqui';
  }
};

// telefone "do jeito que a pessoa digita" → formato internacional (+55…)
export const normalizePhone = raw => {
  const s = String(raw || '').trim();
  if (!s) return '';
  const digits = s.replace(/\D/g, '');
  if (!digits) return '';
  if (s.startsWith('+')) return `+${digits}`;
  if (digits.startsWith('55') && digits.length >= 12) return `+${digits}`;
  if (digits.length === 10 || digits.length === 11) return `+55${digits}`;
  return `+${digits}`;
};

// "hoje", "ontem", "há 3 dias"… a partir de epoch (segundos)
export const timeAgoPt = epochSeconds => {
  if (!epochSeconds) return '';
  const diff = Math.max(0, Date.now() / 1000 - Number(epochSeconds));
  const days = Math.floor(diff / 86400);
  if (days === 0) return 'hoje';
  if (days === 1) return 'ontem';
  if (days < 30) return `há ${days} dias`;
  const months = Math.floor(days / 30);
  if (months < 12) return months === 1 ? 'há 1 mês' : `há ${months} meses`;
  const years = Math.floor(days / 365);
  return years === 1 ? 'há 1 ano' : `há ${years} anos`;
};
