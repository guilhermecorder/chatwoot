# 💸 item 232 (25/09): guardar quanto da entrada veio do cache (o e-mail
# "prompt cache hit rate is low" não dava para conferir sem isso).
class AddCacheTokensToCrmAiUsages < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_ai_usages, :cache_read_tokens, :integer, default: 0, null: false
    add_column :crm_ai_usages, :cache_write_tokens, :integer, default: 0, null: false
  end
end
