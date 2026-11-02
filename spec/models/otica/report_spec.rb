require 'rails_helper'

# 📊 SUA ÓTICA — ANÁLISE DA LOJA (02/11/2026): cada envio do index.html é uma
# versão (Otica::Report + arquivo no ActiveStorage); a mais nova é a que abre.
RSpec.describe Otica::Report do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:html) { "<!DOCTYPE html>\n<html lang=\"pt-BR\"><head><title>Raio-X</title></head><body><h1>Análise</h1></body></html>" }

  def build_report(content = html, **attrs)
    report = described_class.new({ account: account, created_by: admin }.merge(attrs))
    report.file.attach(io: StringIO.new(content), filename: 'index.html', content_type: 'text/html') unless content.nil?
    report
  end

  describe 'validations' do
    it 'is valid with an HTML file and fills the defaults', :aggregate_failures do
      report = build_report
      expect(report).to be_valid
      report.save!
      expect(report.title).to eq('Análise da loja')
      expect(report.size_bytes).to eq(html.bytesize)
      expect(report.created_by).to eq(admin)
    end

    it 'requires a file' do
      report = build_report(nil)
      expect(report).not_to be_valid
      expect(report.errors[:file].join).to include('index.html')
    end

    it 'rejects a file that is not an HTML page' do
      report = build_report('codigo,grife,modelo')
      expect(report).not_to be_valid
      expect(report.errors[:file].join).to include('não parece ser uma página HTML')
    end

    it 'rejects a file bigger than the limit' do
      stub_const('Otica::Report::MAX_BYTES', 64)
      expect(build_report).not_to be_valid
    end

    it 'trims the title and note' do
      report = build_report(title: "  Raio-X de novembro  \n", note: ' leitura de 22/10 ')
      report.save!
      expect(report.reload.attributes.values_at('title', 'note')).to eq(['Raio-X de novembro', 'leitura de 22/10'])
    end
  end

  describe '.latest and #html' do
    it 'returns the newest version of the account with its content', :aggregate_failures do
      old = build_report('<html><body>antiga</body></html>', title: 'v1')
      old.save!
      old.update_column(:created_at, 2.days.ago) # rubocop:disable Rails/SkipsModelValidations
      build_report('<html><body>nova</body></html>', title: 'v2').save!
      expect(account.otica_reports.latest.title).to eq('v2')
      expect(account.otica_reports.latest.html).to include('nova')
      expect(account.otica_reports.latest.html.encoding).to eq(Encoding::UTF_8)
      expect(account.otica_reports.newest_first.pluck(:title)).to eq(%w[v2 v1])
    end

    it 'is scoped by account' do
      build_report.save!
      expect(create(:account).otica_reports.latest).to be_nil
    end
  end

  describe '#as_json_otica' do
    it 'exposes what the screen needs' do
      report = build_report(title: 'Raio-X', note: 'nota')
      report.save!
      json = report.as_json_otica
      expect(json).to include(id: report.id, title: 'Raio-X', note: 'nota', size_bytes: html.bytesize)
      expect(json[:created_by]).to eq(id: admin.id, name: admin.name)
    end
  end
end
