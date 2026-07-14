# Formulários padrão da CEVICO — cria/atualiza pelo slug (idempotente).
# Rodar: bundle exec rails cevico:seed_forms ACCOUNT_ID=1
namespace :cevico do
  desc 'Cria/atualiza os formulários Pré-Operatório e Antes da Avaliação'
  task seed_forms: :environment do
    account = Account.find(ENV.fetch('ACCOUNT_ID', Account.first.id))

    forms = [
      {
        slug: 'pre-operatorio',
        name: 'Pré-Operatório',
        intro_title: 'Vamos preparar tudo para a sua cirurgia 💙',
        intro_text: 'Faltam poucos passos! Estas perguntas ajudam nossa equipe médica a ' \
                    'preparar sua cirurgia com total segurança. Leva menos de 5 minutos ' \
                    'e suas respostas ficam guardadas com sigilo médico.',
        thank_you_text: 'Prontinho! 🎉 Recebemos suas informações e nossa equipe já está ' \
                        'preparando tudo. Se algo mudar (remédio novo, gripe, etc.), avise ' \
                        'a gente pelo WhatsApp. Até a cirurgia!',
        questions: [
          { 'id' => 'q1',  'label' => 'Como está sua saúde de modo geral?', 'type' => 'choice', 'required' => true,
            'options' => ['Ótima', 'Boa', 'Regular', 'Tenho condições de saúde em tratamento'] },
          { 'id' => 'q2',  'label' => 'Você tem alguma destas condições?', 'type' => 'multi', 'required' => true,
            'options' => ['Diabetes', 'Pressão alta', 'Doença autoimune (lúpus, artrite reumatoide...)',
                          'Problemas de cicatrização ou queloide', 'Doença cardíaca', 'Nenhuma delas'] },
          { 'id' => 'q3',  'label' => 'Está usando algum medicamento contínuo? Quais?', 'type' => 'text', 'required' => true },
          { 'id' => 'q4',  'label' => 'Tem alergia a algum medicamento, colírio ou anestésico?', 'type' => 'yesno', 'required' => true },
          { 'id' => 'q5',  'label' => 'Se sim, conte qual foi a alergia e a reação:', 'type' => 'text', 'required' => false },
          { 'id' => 'q6',  'label' => 'Já fez alguma cirurgia nos olhos antes?', 'type' => 'yesno', 'required' => true },
          { 'id' => 'q7',  'label' => 'Usa lentes de contato?', 'type' => 'choice', 'required' => true,
            'options' => ['Sim, uso todos os dias', 'Sim, de vez em quando', 'Não uso'] },
          { 'id' => 'q8',  'label' => 'Importante: você sabia que precisa SUSPENDER as lentes de contato antes da cirurgia (7 dias para gelatinosas, 21 dias para rígidas)? Vai conseguir?',
            'type' => 'choice', 'required' => true,
            'options' => ['Sim, já suspendi', 'Sim, vou suspender no prazo', 'Vou ter dificuldade — quero conversar sobre isso', 'Não uso lentes'] },
          { 'id' => 'q9',  'label' => 'Está usando algum colírio atualmente? Qual?', 'type' => 'text', 'required' => false },
          { 'id' => 'q10', 'label' => 'Teve gripe, COVID, conjuntivite, terçol ou infecção nos últimos 15 dias?', 'type' => 'yesno', 'required' => true },
          { 'id' => 'q11', 'label' => 'Está grávida ou amamentando?', 'type' => 'choice', 'required' => true,
            'options' => ['Não', 'Sim, grávida', 'Sim, amamentando', 'Não se aplica'] },
          { 'id' => 'q12', 'label' => 'No dia da cirurgia, você terá um acompanhante adulto para voltar para casa com você?', 'type' => 'choice', 'required' => true,
            'options' => ['Sim, já combinado', 'Ainda vou organizar', 'Vou precisar de ajuda com isso'] },
          { 'id' => 'q13', 'label' => 'Nome e telefone do seu contato de emergência:', 'type' => 'text', 'required' => true },
          { 'id' => 'q14', 'label' => 'De 0 a 10, quão ansioso(a) você está para a cirurgia?', 'type' => 'scale', 'required' => false },
          { 'id' => 'q15', 'label' => 'Tem alguma dúvida ou medo que gostaria de conversar antes da cirurgia?', 'type' => 'text', 'required' => false }
        ]
      },
      {
        slug: 'antes-da-avaliacao',
        name: 'Antes da Consulta de Avaliação',
        intro_title: 'Sua avaliação está chegando! 👁️',
        intro_text: 'Para o médico aproveitar ao máximo o seu horário, conte um pouco ' \
                    'sobre você e seus olhos. São 2 minutinhos — e sua consulta fica ' \
                    'muito mais completa.',
        thank_you_text: 'Perfeito! 🙌 O médico já vai receber suas respostas antes da ' \
                        'consulta. Lembre-se: se usa lentes de contato, venha SEM elas no ' \
                        'dia (traga os óculos). Até breve!',
        questions: [
          { 'id' => 'q1',  'label' => 'O que te trouxe até a CEVICO?', 'type' => 'choice', 'required' => true,
            'options' => ['Quero me livrar dos óculos/lentes (cirurgia refrativa)', 'Catarata',
                          'Ceratocone', 'Check-up / exames de rotina', 'Outro motivo'] },
          { 'id' => 'q2',  'label' => 'Há quanto tempo usa óculos ou lentes de contato?', 'type' => 'choice', 'required' => true,
            'options' => ['Não uso', 'Menos de 2 anos', 'De 2 a 10 anos', 'Mais de 10 anos'] },
          { 'id' => 'q3',  'label' => 'Você sabe seu grau aproximado? Conte para a gente:', 'type' => 'text', 'required' => false },
          { 'id' => 'q4',  'label' => 'Seu grau mudou no último ano?', 'type' => 'choice', 'required' => true,
            'options' => ['Não, está estável', 'Sim, mudou pouco', 'Sim, mudou bastante', 'Não sei'] },
          { 'id' => 'q5',  'label' => 'O que mais te incomoda no dia a dia?', 'type' => 'multi', 'required' => true,
            'options' => ['Dependência dos óculos', 'Lentes ressecando/incomodando', 'Esporte e lazer limitados',
                          'Estética / autoestima', 'Gasto constante com óculos e lentes', 'Visão embaçada mesmo com óculos'] },
          { 'id' => 'q6',  'label' => 'Alguém na sua família tem ou teve: glaucoma, ceratocone, catarata precoce ou descolamento de retina?', 'type' => 'multi', 'required' => true,
            'options' => ['Glaucoma', 'Ceratocone', 'Catarata precoce', 'Descolamento de retina', 'Ninguém / não sei'] },
          { 'id' => 'q7',  'label' => 'Você tem alguma destas condições?', 'type' => 'multi', 'required' => true,
            'options' => ['Diabetes', 'Pressão alta', 'Doença autoimune', 'Olho seco importante', 'Nenhuma delas'] },
          { 'id' => 'q8',  'label' => 'Já fez alguma cirurgia ou tratamento nos olhos?', 'type' => 'yesno', 'required' => true },
          { 'id' => 'q9',  'label' => 'Coça muito os olhos no dia a dia?', 'type' => 'choice', 'required' => true,
            'options' => ['Quase nunca', 'Às vezes', 'Com frequência (alergia, rinite...)'] },
          { 'id' => 'q10', 'label' => 'De 0 a 10, o quanto resolver isso mudaria sua vida?', 'type' => 'scale', 'required' => true },
          { 'id' => 'q11', 'label' => 'Se a avaliação mostrar que você é candidato(a), quando gostaria de fazer o procedimento?', 'type' => 'choice', 'required' => true,
            'options' => ['O quanto antes', 'Nos próximos 3 meses', 'Neste ano', 'Ainda estou pesquisando'] },
          { 'id' => 'q12', 'label' => 'Como você conheceu a CEVICO?', 'type' => 'choice', 'required' => false,
            'options' => ['Instagram/Facebook', 'Google', 'Indicação de amigo/família', 'Já sou paciente', 'Outro'] },
          { 'id' => 'q13', 'label' => 'Quer deixar alguma pergunta para o médico responder na consulta?', 'type' => 'text', 'required' => false }
        ]
      }
    ]

    forms.each do |attrs|
      form = Crm::Form.find_or_initialize_by(slug: attrs[:slug])
      form.account = account
      form.assign_attributes(attrs.merge(active: true))
      form.save!
      puts "✓ #{form.name} (#{form.questions.size} perguntas) — slug: #{form.slug}"
    end
  end
end
