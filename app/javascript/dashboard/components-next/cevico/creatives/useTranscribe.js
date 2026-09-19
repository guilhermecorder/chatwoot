// "Transcrever" (item 172, rodada 4): copia o texto do gancho, do corpo, do
// CTA ou do anúncio inteiro para a área de transferência, para montar os
// blocos da copy fora daqui. Peça sozinha = texto puro; anúncio inteiro =
// bloco rotulado (Gancho / Corpo / CTA).
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useAlert } from 'dashboard/composables';

const PIECE_LABEL = {
  hook: 'Gancho',
  title: 'Gancho',
  hold: 'Corpo',
  body: 'Corpo',
  cta: 'CTA',
  call_to_action: 'CTA',
};

const clean = v => (v === null || v === undefined ? '' : String(v).trim());

// monta o texto a copiar a partir de um item (campeão do histórico, linha de
// criativo ou peça do pódio) e da parte pedida
export const transcriptOf = (item, part = 'all') => {
  if (!item) return { label: '', text: '' };
  const hook = clean(item.hook !== undefined ? item.hook : item.title);
  const body = clean(item.body);
  const cta = clean(item.cta_label || item.cta);
  const piece = clean(item.text !== undefined ? item.text : item.label);

  if (PIECE_LABEL[part]) {
    const byPart = {
      hook,
      title: hook,
      hold: body,
      body,
      cta,
      call_to_action: cta,
    };
    const text = piece || byPart[part] || '';
    return { label: PIECE_LABEL[part], text };
  }
  const lines = [];
  if (hook) lines.push(`Gancho: ${hook}`);
  if (body) lines.push(`Corpo: ${body}`);
  if (cta) lines.push(`CTA: ${cta}`);
  if (!lines.length && piece) lines.push(piece);
  return { label: 'Anúncio', text: lines.join('\n') };
};

// plano B quando a API moderna falha (janela sem foco, contexto sem HTTPS):
// caixa de texto invisível + comando de copiar do navegador
const legacyCopy = text => {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.top = '-1000px';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  ta.setSelectionRange(0, text.length);
  let ok = false;
  try {
    ok = document.execCommand('copy');
  } catch {
    ok = false;
  }
  document.body.removeChild(ta);
  return ok;
};

export const useTranscribe = () => {
  const transcribe = async (item, part = 'all') => {
    const { label, text } = transcriptOf(item, part);
    if (!text) {
      useAlert('Este campeão não tem texto para transcrever.');
      return false;
    }
    let copied = false;
    try {
      await copyTextToClipboard(text);
      copied = true;
    } catch {
      copied = legacyCopy(text);
    }
    if (!copied) {
      useAlert('Não consegui copiar. Selecione o texto e copie manualmente.');
      return false;
    }
    const short = text.replace(/\s+/g, ' ');
    useAlert(
      `${label} transcrito: “${short.length > 70 ? `${short.slice(0, 70)}…` : short}”`
    );
    return true;
  };
  return { transcribe, transcriptOf };
};
