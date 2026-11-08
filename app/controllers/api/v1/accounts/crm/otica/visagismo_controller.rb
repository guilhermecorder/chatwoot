# 🪞 PROVA VIRTUAL — a parte da EQUIPE (08/11/2026): a tela de Produtos mostra
# se a prova virtual está pronta (chave do Gemini, armações com foto, gasto de
# hoje) e deixa testar com uma foto solta: sobe a foto, escolhe as armações
# (ou deixa o visagismo escolher) e vê o resultado na hora, sem WhatsApp.
# A foto de teste não é guardada: vai ao Gemini e volta como imagem em base64.
# Nó de acesso otica.produtos (ver = status; a prévia gasta imagem = editar).
class Api::V1::Accounts::Crm::Otica::VisagismoController < Api::V1::Accounts::BaseController
  include Crm::AccessControl

  PHOTO_MAX_BYTES = 8.megabytes

  def show
    account = Current.account
    ready = ::Otica::VirtualTryOn.candidates(account)
    render json: {
      otica: ::Otica::VirtualTryOn.otica?(account),
      gemini_key_set: ::Otica::TryOnImage.configured?(account),
      model: ::Otica::TryOnImage.chain(account).first,
      prontas: ready.size,
      prontas_ids: ready.map(&:id),
      hoje: ::Otica::VirtualTryOn.generated_today(account),
      teto_dia: ::Otica::VirtualTryOn.daily_cap(account),
      max_por_vez: ::Otica::VirtualTryOn::MAX_PER_CALL,
      max_por_dia_cliente: ::Otica::VirtualTryOn::MAX_CALLS_PER_DAY,
      # 💬 venda pelo WhatsApp (08/11): Pix, link e desconto padrão da loja
      venda: ::Otica::SalesTools.config(account),
      lentes_com_imagem: ::Otica::Product.where(account_id: account.id, kind: 'lente').active.priced.with_attached_photo.count { |l| l.photo.attached? },
      regras: ::Otica::Visagismo::RULES,
      face_shapes: ::Otica::Visagismo::FACE_SHAPES,
      frame_shapes: ::Otica::Visagismo::FRAME_SHAPES
    }
  end

  # 💬 config da venda pelo WhatsApp (chave Pix, link de pagamento, desconto padrão)
  def update
    saved = ::Otica::SalesTools.save_config!(Current.account, params.permit(:pix_key, :payment_link, :default_discount_pct).to_h)
    render json: { venda: saved }
  end

  def preview # rubocop:disable Metrics/AbcSize
    file = params[:selfie]
    return render json: { error: 'Envie a foto do rosto.' }, status: :unprocessable_entity if file.blank? || !file.respond_to?(:read)
    return render json: { error: 'Foto grande demais (até 8 MB).' }, status: :unprocessable_entity if file.size.to_i > PHOTO_MAX_BYTES
    return render json: { error: 'Configure a chave do Gemini em Integrações → IA.' }, status: :unprocessable_entity unless ::Otica::TryOnImage.configured?(Current.account)

    mime = file.content_type.to_s.presence || 'image/jpeg'
    ids = Array(params[:product_ids]).compact_blank
    result = ::Otica::VirtualTryOn.new(account: Current.account, live: true)
                                  .preview(selfie: file.read, selfie_mime: mime, product_ids: ids,
                                           quantidade: params[:quantidade].presence || 2, preferencia: params[:preferencia].to_s)
    render json: result
  rescue ::Otica::TryOnImage::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
