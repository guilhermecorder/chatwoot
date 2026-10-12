require 'rake'
require 'rails_helper'

# 🏢 rodada 334: criar a empresa irmã (conta nova + identidade + admins)
RSpec.describe Cevico::CompanyCreator do
  let!(:ana) { create(:user, email: 'ana@exemplo.com') }
  let!(:beto) { create(:user, email: 'beto@exemplo.com') }
  # nome único: o banco local pode já ter uma "Sua Ótica" criada pelo rake
  let(:name) { "Ótica Spec #{SecureRandom.hex(3)}" }

  it 'cria a conta, grava nome e ramo e coloca os usuários existentes como administradores', :aggregate_failures do
    result = described_class.new(name: name, segment: 'otica', admin_emails: 'Ana@exemplo.com, beto@exemplo.com, ninguem@x.com').call

    account = result.account
    expect(account).to be_persisted
    expect(account.name).to eq(name)
    expect(result.created).to be(true)
    company = Cevico::Company.for(account)
    expect(company.name).to eq(name)
    expect(company.segment).to eq('otica')
    expect(company.word(:paciente)).to eq('cliente')
    expect(account.account_users.where(role: :administrator).map(&:user)).to contain_exactly(ana, beto)
    expect(result.admins_added).to contain_exactly('ana@exemplo.com', 'beto@exemplo.com')
    expect(result.missing).to eq(['ninguem@x.com'])
    expect(User.from_email('ninguem@x.com')).to be_nil
    summary = result.lines.join("\n")
    expect(summary).to include("Conta nova: \"#{name}\"").and include('Não existem no sistema')
    expect(summary).to include('cliente, atendimento, consultor, loja')
  end

  it 'DRY=1 só mostra o que faria' do
    result = described_class.new(name: name, segment: 'otica', admin_emails: ['ana@exemplo.com'], dry: true).call
    expect(Account.find_by(name: name)).to be_nil
    expect(result.lines.first).to include('MODO DE TESTE')
    expect(result.admins_added).to eq(['ana@exemplo.com'])
  end

  it 'rodar de novo não duplica: completa os admins que faltam', :aggregate_failures do
    described_class.new(name: name, segment: 'otica', admin_emails: ['ana@exemplo.com']).call
    result = described_class.new(name: name, segment: 'otica', admin_emails: ['ana@exemplo.com', 'beto@exemplo.com']).call
    expect(Account.where(name: name).count).to eq(1)
    expect(result.admins_already).to eq(['ana@exemplo.com'])
    expect(result.admins_added).to eq(['beto@exemplo.com'])
  end

  it 'sem nome, explica o que falta' do
    expect { described_class.new(name: '').call }.to raise_error(ArgumentError, /NAME=/)
  end

  describe 'rake cevico:company:create' do
    subject(:task) { Rake::Task['cevico:company:create'] }

    before { task.reenable }

    it 'cria pela linha de comando (ENV) e imprime o resumo' do
      with_modified_env NAME: name, SEGMENT: 'otica', ADMINS: 'ana@exemplo.com', DRY: '0' do
        expect { task.invoke }.to output(/GRAVADO.*#{Regexp.escape(name)}.*ana@exemplo\.com/m).to_stdout
      end
      expect(Cevico::Company.for(Account.find_by(name: name)).segment).to eq('otica')
    end

    it 'aceita os argumentos entre colchetes' do
      with_modified_env NAME: nil, SEGMENT: nil, ADMINS: nil, DRY: '1' do
        expect { task.invoke(name, 'outro', 'beto@exemplo.com') }.to output(/MODO DE TESTE.*#{Regexp.escape(name)}/m).to_stdout
      end
      expect(Account.find_by(name: name)).to be_nil
    end
  end
end
