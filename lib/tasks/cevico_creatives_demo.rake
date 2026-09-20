# 🧪 Jornada de DEMONSTRAÇÃO para a Central de Criativos (v2, item 177):
# cria leads fictícios ligados aos anúncios existentes (meta_ads.source_id),
# consultas (algumas comparecidas) e cartões na etapa de cirurgia com valor,
# para ver custo por consulta, custo por cirurgia, ROAS e % de agendamento
# fora da produção. Tudo marcado com "[demo criativos]" para desfazer.
#
#   bundle exec rails cevico:creatives_demo_funnel ACCOUNT_ID=3          # cria
#   bundle exec rails cevico:creatives_demo_funnel ACCOUNT_ID=3 UNDO=1   # apaga
DEMO_SURGERY_VALUES = [4800, 6900, 9500, 12_000].freeze

desc 'Leads/consultas/cirurgias fictícios por anúncio para a Central de Criativos — ACCOUNT_ID= [UNDO=1]'
task 'cevico:creatives_demo_funnel' => :environment do # rubocop:disable Metrics/BlockLength
  account = Account.find(ENV.fetch('ACCOUNT_ID'))
  tag = '[demo criativos]'
  demo = account.contacts.where('name LIKE ?', "#{tag}%")
  if ENV['UNDO'].present?
    ids = demo.pluck(:id)
    Crm::Contact.where(contact_id: ids).find_each(&:destroy)
    account.tasks.where(contact_id: ids).delete_all
    demo.find_each(&:destroy)
    puts "🧹 #{ids.size} lead(s) de demonstração apagados"
    next
  end
  abort 'já existe demonstração — rode com UNDO=1 antes' if demo.exists?

  ads = Crm::AdCreative.where(account_id: account.id).pluck(:ad_id)
  abort 'nenhum anúncio na conta (sincronize a Central antes)' if ads.empty?
  stage = Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id })
                    .where('crm_stages.name ILIKE ?', '%cirurgia realizada%').first ||
          Crm::Stage.joins(:pipeline).where(crm_pipelines: { account_id: account.id }).where('crm_stages.name ILIKE ?', '%cirurgia%').first
  abort 'nenhuma etapa de cirurgia no CRM' unless stage
  rng = Random.new(42)
  creator = account.users.first || abort('a conta precisa de um usuário')
  created = 0
  ads.each_with_index do |ad_id, i|
    leads = 6 + ((i * 5) % 9)
    leads.times do |n|
      captured = (rng.rand(28) + 1).days.ago
      contact = account.contacts.create!(
        name: "#{tag} Lead #{ad_id}-#{n + 1}", phone_number: "+5511#{90_000_000 + (i * 1000) + n}",
        additional_attributes: { 'meta_ads' => { 'source_id' => ad_id, 'captured_at' => captured.iso8601 } }
      )
      created += 1
      next unless rng.rand < 0.55 # marcou consulta

      attended = rng.rand < 0.7
      account.tasks.create!(title: "#{tag} consulta", task_type: 'consulta', contact_id: contact.id, creator: creator,
                            due_at: captured + 5.days, attendance: attended ? 'attended' : 'missed')
      next unless attended && rng.rand < 0.45 # virou cirurgia

      Crm::Contact.create!(contact_id: contact.id, pipeline_id: stage.pipeline_id, stage_id: stage.id,
                           value: DEMO_SURGERY_VALUES.sample(random: rng))
    end
  end
  puts "🧪 #{created} lead(s) de demonstração criados em #{ads.size} anúncio(s) (etapa: #{stage.name}). Desfazer: UNDO=1"
end
