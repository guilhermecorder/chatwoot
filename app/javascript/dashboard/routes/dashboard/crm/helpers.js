import { formatDistanceToNow } from 'date-fns';

// O backend do CRM serializa datas como ISO 8601 (string), enquanto o
// dynamicTime do Chatwoot espera unix timestamp — aceita ambos e nunca lança.
export const relativeTime = value => {
  if (!value) return null;
  const date = typeof value === 'number' ? new Date(value * 1000) : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return formatDistanceToNow(date, { addSuffix: true });
};
