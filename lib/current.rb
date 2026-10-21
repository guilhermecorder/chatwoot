module Current
  thread_mattr_accessor :user
  thread_mattr_accessor :account
  thread_mattr_accessor :account_user
  thread_mattr_accessor :executed_by
  thread_mattr_accessor :contact
  thread_mattr_accessor :inbox
  # 🏷️ item 322 (carimbo de origem): como e de que fonte nasce o que for criado agora
  thread_mattr_accessor :cevico_via
  thread_mattr_accessor :cevico_source_id
  # 🧭 item 341 (Ambientes do CRM): passe livre da cerca do ambiente no card ('admin' | 'carga')
  thread_mattr_accessor :cevico_env_bypass

  def self.reset
    Current.user = nil
    Current.account = nil
    Current.account_user = nil
    Current.executed_by = nil
    Current.contact = nil
    Current.inbox = nil
    Current.cevico_via = nil
    Current.cevico_source_id = nil
    Current.cevico_env_bypass = nil
  end
end
