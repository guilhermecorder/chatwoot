require 'rails_helper'

# 🔒 Auditoria rodada 2 (#20/#150/#399/#428): o botão da página pública
# redireciona para o cta_url sem perguntar — só WhatsApp, caminho do próprio
# site ou https de domínio da clínica entram.
RSpec.describe CevicoPage, '.cta_url_allowed?' do
  let(:account) { create(:account) }

  def page(cta_url)
    described_class.new(account: account, title: 'Teste', slug: "teste-#{SecureRandom.hex(3)}",
                        cta_url: cta_url, sections: [], ab_variants: [], team_comments: [], daily_stats: {})
  end

  before do
    allow(Cevico::PublicSite).to receive_messages(host: 'clinica.cevico.com.br', app_host: 'sistema.cevico.com.br')
  end

  it 'aceita WhatsApp, caminho do site e https da clínica', :aggregate_failures do
    ['https://wa.me/5511999999999?text=Oi', 'https://api.whatsapp.com/send?phone=55', 'whatsapp://send?phone=55',
     '/forms/avaliacao', 'https://clinica.cevico.com.br/catarata', 'https://www.clinica.cevico.com.br/x',
     'https://sistema.cevico.com.br/forms/1', '', nil].each do |url|
      expect(page(url)).to be_valid, "devia aceitar #{url.inspect}"
    end
  end

  it 'recusa qualquer outro destino (inclusive disfarces)', :aggregate_failures do
    ['https://exemplo.com', 'http://wa.me/55', 'https://wa.me.golpe.com/55', 'https://clinica.cevico.com.br.golpe.com',
     'javascript:alert(1)', '//exemplo.com', 'ftp://clinica.cevico.com.br', 'https://'].each do |url|
      record = page(url)
      expect(record).not_to be_valid, "devia recusar #{url.inspect}"
      expect(record.errors[:cta_url].first).to include('WhatsApp')
    end
  end

  it 'aceita o domínio público da própria empresa e a lista extra CEVICO_CTA_HOSTS', :aggregate_failures do
    settings = CrmSetting.find_or_create_by!(account: account)
    settings.update!(agenda_config: (settings.agenda_config || {}).merge('company' => { 'public_host' => 'otica.exemplo.com.br' }))
    expect(page('https://otica.exemplo.com.br/oferta')).to be_valid

    other = create(:account)
    stranger = described_class.new(account: other, title: 'Outra', slug: 'outra-x', cta_url: 'https://otica.exemplo.com.br/oferta',
                                   sections: [], ab_variants: [], team_comments: [], daily_stats: {})
    expect(stranger).not_to be_valid

    with_modified_env(CEVICO_CTA_HOSTS: 'cevico.com.br, www.outra.com.br') do
      expect(page('https://www.cevico.com.br/lp')).to be_valid
      expect(page('https://outra.com.br/lp')).to be_valid
    end
  end

  it 'página antiga com link fora da régua continua salvando o resto até alguém trocar o link', :aggregate_failures do
    old = page('https://wa.me/55')
    old.save!
    old.update_column(:cta_url, 'https://antigo.exemplo.com') # rubocop:disable Rails/SkipsModelValidations

    old.reload
    expect(old.update(title: 'Só o título')).to be(true)
    expect(old.update(cta_url: 'https://outro.exemplo.com')).to be(false)
    expect(old.update(cta_url: 'https://wa.me/5511')).to be(true)
  end
end
