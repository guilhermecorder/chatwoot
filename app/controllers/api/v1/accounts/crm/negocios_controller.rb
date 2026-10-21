# 🏢 Meus negócios (21/10/2026): lista os negócios do dono e gera o link de
# entrada em cada sistema. Só administrador E e-mail em MEUS_NEGOCIOS_DONOS;
# para todo o resto a lista vem vazia (sem 403 — o menu só esconde o item).
class Api::V1::Accounts::Crm::NegociosController < Api::V1::Accounts::BaseController
  before_action :exigir_dono, only: [:login]

  def index
    if dono?
      render json: { dono: true, negocios: Cevico::Negocios.publicos, este: ENV.fetch('MARCA', 'cevico') }
    else
      render json: { dono: false, negocios: [] }
    end
  end

  def login
    render json: { url: Cevico::Negocios.link_de_entrada(params[:chave], account: Current.account) }
  rescue Cevico::Negocios::Erro => e
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def dono?
    Current.account_user&.administrator? && Cevico::Negocios.dono?(Current.user)
  end

  def exigir_dono
    render json: { error: 'Só o dono dos negócios pode entrar por aqui.' }, status: :forbidden unless dono?
  end
end
