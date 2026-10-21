# LEVANTAMENTO DE DUPLICADOS — SÓ LEITURA (não grava nada no banco).
#
# Rodar na VPS (Guilherme):
#   C=$(docker ps --format '{{.Names}}' | grep -E 'sistema_cevico_(web|chatwoot)' | head -1)
#   docker exec -i "$C" bundle exec rails runner - < levantamento_duplicados.rb
#
# Grupos:
#   ALTA    = mesmo celular, só muda o 9 depois do DDD, e o 1º nome bate
#             → candidato a juntar automático
#   CONFERIR_9 = mesmo celular com/sem 9, mas o 1º nome NÃO bate
#             → pode ser "mãe que agenda pro filho" (alerta manual)
#   MESMO_CPF  = CPF igual em contatos diferentes
#   MESMO_NOME = nome completo igual (2+ palavras), telefones diferentes
#             → alerta manual (caso Samuel de Andrade)
#   DUAS_PESSOAS = nome do contato com " e " ligando dois nomes
#             (ex.: "Francislene ... E Alice ...")
require 'set'

ACCOUNT_ID = (ENV['ACCOUNT_ID'] || Account.order(:id).pick(:id)).to_i
account = Account.find(ACCOUNT_ID)
LIMIT = (ENV['LIMIT'] || 15).to_i

# chave do celular brasileiro: 55 + DDD + 9 + 8 dígitos. Número de 8 dígitos
# começando com 6–9 (celular antigo, como o WhatsApp ainda guarda em vários
# DDDs) ganha o 9. Fixo (começa com 2–5) fica como está.
def phone_key(phone)
  d = phone.to_s.gsub(/\D/, '')
  d = "55#{d}" if [10, 11].include?(d.length)
  return nil unless d.start_with?('55') && [12, 13].include?(d.length)

  ddd = d[2, 2]
  local = d[4..]
  local = "9#{local}" if local.length == 8 && local[0].to_i >= 6
  "55#{ddd}#{local}"
end

def words(name)
  Crm::AppointmentRecorder.name_words(name)
end
def first_name(name)
  words(name).first
end
# nome inteiro sem acento/caixa (números contam: "Lead 1" ≠ "Lead 2")
def full_key(name)
  I18n.transliterate(name.to_s).downcase.gsub(/[^a-z0-9 ]/, ' ').squish
end

def labels_of(ids)
  ActsAsTaggableOn::Tagging.joins(:tag)
                           .where(taggable_type: 'Contact', taggable_id: ids, context: 'labels')
                           .pluck(:taggable_id, 'tags.name')
                           .group_by(&:first).transform_values { |v| v.map(&:last).sort }
end

contacts = account.contacts.select(:id, :name, :phone_number, :email, :custom_attributes, :additional_attributes, :created_at).to_a
by_id = contacts.index_by(&:id)
conv_count = Conversation.where(account_id: ACCOUNT_ID).group(:contact_id).count
labels = labels_of(contacts.map(&:id))

def line(c, convs, labels)
  of = c.additional_attributes.to_h.slice('origem', 'parceiro').presence
  [
    "##{c.id}", c.name.to_s.truncate(45), c.phone_number.presence || '-',
    "conv:#{convs[c.id] || 0}", "cpf:#{c.custom_attributes.to_h['cpf'].present? ? 'sim' : 'não'}",
    "etiq:#{(labels[c.id] || []).first(6).join(',')}", "criado:#{c.created_at.to_date}",
    (of ? "orig:#{of.values.first}" : nil)
  ].compact.join(' | ')
end

report = Hash.new { |h, k| h[k] = [] }

# 1) celular com/sem 9 (dígitos DIFERENTES, mesma chave)
contacts.select { |c| c.phone_number.present? }
        .group_by { |c| phone_key(c.phone_number) }
        .each do |key, group|
  next if key.nil? || group.size < 2
  next if group.map { |c| c.phone_number.gsub(/\D/, '') }.uniq.size < 2 # idênticos: a unificação atual já pega

  firsts = group.map { |c| first_name(c.name) }.compact.uniq
  bucket = firsts.size <= 1 ? 'ALTA' : 'CONFERIR_9'
  report[bucket] << group
end

# 2) mesmo CPF
contacts.select { |c| c.custom_attributes.to_h['cpf'].present? }
        .group_by { |c| c.custom_attributes['cpf'].to_s.gsub(/\D/, '') }
        .each { |cpf, g| report['MESMO_CPF'] << g if cpf.length >= 11 && g.size > 1 }

# 3) mesmo nome completo, telefones diferentes (nem com/sem 9)
seen = report.values.flatten(1).flatten.to_set(&:id)
contacts.reject { |c| Crm::AppointmentRecorder.placeholder_name?(c.name) }
        .group_by { |c| full_key(c.name) }
        .each do |key, g|
  next if key.split.size < 2 || g.size < 2
  next if g.map { |c| phone_key(c.phone_number) || c.id }.uniq.size < 2
  next if g.all? { |c| seen.include?(c.id) }

  report['MESMO_NOME'] << g
end

# 4) nome com duas pessoas ("Fulana ... E Sicrana ...")
contacts.each do |c|
  parts = c.name.to_s.split(/\s+e\s+/i)
  report['DUAS_PESSOAS'] << [c] if parts.size >= 2 && parts.all? { |p| words(p).size >= 2 }
end

# 5) etiquetas cevico + oftalmofacil juntas
both = labels.select { |_id, l| l.include?('cevico') && l.include?('oftalmofacil') }.keys

puts "=== LEVANTAMENTO DE DUPLICADOS — conta #{ACCOUNT_ID} (#{account.name}) — #{Time.current.strftime('%d/%m %H:%M')} ==="
puts "contatos na conta: #{contacts.size}"
puts
puts 'RESUMO'
%w[ALTA CONFERIR_9 MESMO_CPF MESMO_NOME DUAS_PESSOAS].each do |k|
  puts format('  %-13s %5d grupo(s) / %5d contato(s)', k, report[k].size, report[k].sum(&:size))
end
puts format('  %-13s %5d contato(s)', 'CEVICO+OF', both.size)
puts

%w[ALTA CONFERIR_9 MESMO_CPF MESMO_NOME DUAS_PESSOAS].each do |k|
  next if report[k].empty?

  puts "--- #{k} (mostrando até #{LIMIT}) ---"
  report[k].first(LIMIT).each do |g|
    g.sort_by(&:created_at).each { |c| puts "  #{line(by_id[c.id], conv_count, labels)}" }
    puts
  end
end
puts '=== fim (nada foi alterado) ==='
