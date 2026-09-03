# context-assistente-pessoal.md — Assistente Pessoal

> Este arquivo é a memória persistente do projeto. Ele documenta o que já foi
> feito, a stack usada, o objetivo do software e os próximos passos.
> **Toda sessão de trabalho neste projeto deve começar lendo este arquivo até
> o fim, e terminar atualizando-o.** Ver protocolo no final deste documento.
>
> **Nome do arquivo deliberadamente específico** (`context-assistente-pessoal.md`,
> não `CONTEXT.md` genérico): o Tiago tem outros projetos (ex: Setoriza) que
> também usam esse mesmo padrão de arquivo de memória. Um nome genérico
> `CONTEXT.md` repetido em vários repositórios cria risco de confusão entre
> sessões/projetos diferentes — o nome específico elimina esse risco.

## Sobre o repositório

- Código-fonte: `github.com/tiagocamargos1/Assistente`
- App ao vivo: `https://tiagocamargos1.github.io/Assistente/`
- Hospedagem: GitHub Pages (branch `main`, deploy automático a cada push)
- Backend: Firebase (projeto `assistente-ee1f4`, número `611661253806`)

## Objetivo do software

O Assistente Pessoal existe para ser um hub de organização pessoal **leve e
imediato** — não um sistema de gestão de projetos completo. A visão de fundo
(nas palavras do Tiago) é conseguir ser o mais organizado possível em todas
as frentes da vida: com Deus, consigo mesmo (ações pessoais, métricas, sonhos
e planos), com a família, com as finanças, com o ministério, e com os
negócios/empresas existentes, em desenvolvimento ou a criar.

Decisão de produto deliberada: o Assistente Pessoal deve continuar **simples
e rápido de usar**, evitando virar um app inchado de funcionalidades. Quem
cobre a gestão estruturada e detalhada de projetos/negócios é o **Setoriza**
(setoriza.pt), um produto irmão, tratado em outra conversa — não duplicar
escopo aqui. O único elo hoje entre os dois é conceitual (áreas da vida), sem
integração técnica implementada.

Segundo objetivo, mais recente: transformar o Assistente Pessoal em algo
testável por mais pessoas, com vistas a eventualmente vendê-lo — daí o
sistema de usuários dinâmico (qualquer pessoa pode entrar com Google, não só
Tiago e Monique).

## Stack técnica

- **Frontend**: arquivo único `index.html` — HTML + CSS + JavaScript puro
  (sem framework, sem build step). Fonte "DM Sans". Tema escuro
  dourado/preto.
- **Autenticação de usuário na UI**: OAuth2 implicit grant do Google
  (Calendar + identidade), reaproveitado também para autenticar no Firebase
  Auth via `signInWithCredential`.
- **Backend de dados**: Firebase Firestore (SDK client v10.12.0, via
  `<script type="module">` importando `firebase-app.js`,
  `firebase-firestore.js`, `firebase-auth.js`).
- **Autenticação real (Firebase Auth)**: cada usuário app-level (`tiago`,
  `monique`, ou `g_<googleId>` dinâmico) tem uma sessão Firebase Auth de
  verdade por trás, ligada via a coleção `authMap/{authUid} -> {appUid}`.
- **Login rápido**: PIN de 4-6 dígitos (hash SHA-256, guardado em
  `localStorage`), evita repetir o login completo do Google a cada sessão no
  mesmo aparelho.
- **PWA**: `manifest.json` + `sw.js` (service worker com cache-first e
  handlers de `push`/`notificationclick`). Instalável na tela de início.
- **Notificações push**: Web Push padrão (não Firebase Cloud Messaging) —
  par de chaves VAPID, `PushManager.subscribe()` no cliente, `web-push` no
  servidor.
- **Job do briefing diário**: `scripts/send-daily-briefing.js` (Node.js),
  rodado por **GitHub Actions** (`.github/workflows/daily-briefing.yml`) a
  cada 10 minutos, decidindo por pessoa se é a hora certa do briefing dela.
  Usa `@google-cloud/firestore` (não `firebase-admin` — ver nota técnica
  abaixo) e `web-push`.
- **Autenticação do GitHub Actions no Google Cloud**: Workload Identity
  Federation (WIF) — sem chave de service account baixada. Pool:
  `github-actions-pool`, provider: `github-actions-provider`, service
  account: `github-actions-briefing@assistente-ee1f4.iam.gserviceaccount.com`.
- **Segurança de dados**: `firestore.rules` (aplicado direto no Firebase
  Console, não faz parte do repo) — cada usuário só lê/escreve os próprios
  dados em `users/{uid}/...`; `shared_tasks` só para Tiago e Monique
  (família); tudo mais bloqueado por padrão.
- **Empacotamento nativo**: Capacitor (iOS via Xcode/SPM, Android via
  Android Studio/Gradle), publicado nas lojas como app "de verdade" — ver
  itens 29-30 e demais itens sobre login nativo/Play Console abaixo.
- **Custo mensal recorrente**: **zero**. Projeto Firebase `assistente-ee1f4`
  não tem conta de faturamento vinculada (confirmado no Google Cloud
  Console) — roda 100% no plano gratuito. Repositório GitHub é público
  (Actions e Pages ilimitados de graça). Único custo já pago foi a taxa
  única de US$25 do registro no Google Play Console (não é mensalidade).

### Nota técnica importante (evitar repetir o erro)

`firebase-admin` **não suporta** credenciais Workload Identity Federation
(`external_account`) — ele lança `Invalid contents in the credentials file`
ou `invalid-credential`. Por isso o script do briefing usa
`@google-cloud/firestore` diretamente (que usa `google-auth-library` por
baixo, e essa sim suporta WIF nativamente via Application Default
Credentials). Não trocar de volta para `firebase-admin` nesse script sem
resolver isso primeiro.

## O que já foi feito

1. Migração do fluxo de edição do app do GitHub direto para o Cowork
   (publicação via automação de navegador, já que o conector MCP do GitHub
   nunca ficou disponível nesta conta/sessão).
2. Edição de tarefas depois de criadas (antes não existia).
3. Login rápido por PIN (4-6 dígitos), evitando reautenticação completa do
   Google a cada sessão.
4. Sistema de usuários dinâmico: qualquer pessoa pode entrar com a própria
   conta Google e ganhar um perfil próprio (cor, nome, dados isolados),
   sem precisar hardcode. `shared_tasks` continua exclusiva da família
   (Tiago + Monique).
5. Campo único de "área" (Deus, Pessoal, Família, Finanças, Negócios) em
   tarefas/eventos/notas, só para filtro rápido — sem virar kanban, sem
   subtarefas, sem anexos (decisão deliberada de manter o app enxuto).
6. Rotinas/hábitos recorrentes (diários ou por dia da semana), aba própria
   "🔁 Rotinas".
7. PWA instalável (ícone na tela de início) + atalho de captura rápida
   (abrir o app com `?quick=1` já foca no campo de digitação; atalhos de
   teclado "/" e "n").
8. Notificação push com o briefing do dia, funcionando mesmo com o app
   fechado (via GitHub Actions + Web Push, não depende do navegador aberto).
9. Reformulação completa de segurança:
   - Firebase Auth real por trás do login (reaproveitando o token OAuth já
     existente, sem mudar a experiência do usuário).
   - Reestruturação de dados de coleções concatenadas (`tasks_${uid}`) para
     subcoleções por usuário (`users/{uid}/tasks`), porque regras do
     Firestore não conseguem casar um prefixo+sufixo dentro do mesmo
     segmento de path.
   - Migração automática e não destrutiva dos dados antigos para a nova
     estrutura, rodando no primeiro login de cada pessoa depois da mudança
     (função `fbMigrateCollection`).
   - Regras de segurança do Firestore escritas e publicadas (isolamento
     total por usuário).
10. Decisão de manter a stack em Firebase (não migrar para Supabase), depois
    de comparar custo/esforço das duas opções.
11. Infraestrutura de push 100% configurada e testada de ponta a ponta:
    VAPID keys geradas e salvas como GitHub Secrets, Workload Identity
    Federation configurada no Google Cloud, workflow do GitHub Actions
    rodando a cada 10 minutos e testado manualmente com sucesso (run #5).
12. Publicação de todos os arquivos no repositório: `index.html`,
    `manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png`,
    `scripts/package.json`, `scripts/send-daily-briefing.js`,
    `.github/workflows/daily-briefing.yml`.
13. Correções pós-publicação: paths do script do briefing atualizados para
    a nova estrutura de subcoleções; troca de `firebase-admin` por
    `@google-cloud/firestore` no script do briefing (ver nota técnica
    acima); versões das GitHub Actions atualizadas para as majors
    compatíveis com Node 24 (`actions/checkout@v5`, `actions/setup-node@v6`,
    `google-github-actions/auth@v3`), eliminando avisos de depreciação.
14. Confirmado (e documentado) que o clique único no banner de ativação de
    notificação é um limite de segurança do navegador — não dá pra
    automatizar mais que isso. O banner já aparece sozinho a cada login
    até a pessoa decidir (ativar ou recusar).
15. Tela inicial de login tornada genérica: antes mostrava sempre "Tiago &
    Monique — Quem está usando?" com os dois cartões fixos, o que confundia
    quem recebia o link pela primeira vez (ex: a Annie, testadora
    convidada) — parecia que o app só era para essas duas pessoas. Agora um
    aparelho novo vê só "Entre com sua conta Google para começar"; os
    cartões de acesso rápido (Tiago, Monique, ou qualquer usuário dinâmico)
    só aparecem naquele aparelho específico depois que a pessoa já logou
    nele alguma vez. De quebra, corrigido um bug real encontrado no mesmo
    trecho: o fallback de login via redirect (usado quando o navegador
    bloqueia pop-up) atribuía qualquer novo login automaticamente à
    identidade "tiago" antes de resolver quem realmente era — corrigido
    para sempre resolver a identidade a partir do perfil Google retornado.
16. Decisão de produto: testadores dinâmicos (ex: Annie) ficam com dados
    100% privados/isolados por padrão — sem compartilhamento com Tiago.
    `shared_tasks` continua exclusiva de Tiago + Monique (o "grupo família"
    é fixo no código, não configurável ainda). Se no futuro for necessário
    compartilhamento seletivo com outras pessoas, isso exigiria uma
    funcionalidade nova de "compartilhar com" por tarefa (não construída
    ainda — ver opção descartada por ora nos próximos passos).
17. Corrigido o bug do "loop de login" (relatado pelo Tiago: tanto no
    navegador quanto no app instalado via Google, o login voltava direto
    para a tela inicial, sem erro nenhum). Diagnóstico: o app usava um
    pop-up (`window.open`) + verificação por `setInterval` da URL do
    pop-up para capturar o token do Google — mecanismo cada vez mais
    quebrado porque o `accounts.google.com` aplica uma política de
    segurança (Cross-Origin-Opener-Policy) que impede a janela principal
    de ler a URL do pop-up depois do login, mesmo quando o login deu
    certo. O pop-up fechava sozinho e a janela principal nunca sabia que
    o token tinha chegado — daí o "loop" sem erro visível. Correção:
    substituído por um redirecionamento de página inteira
    (`window.location.href`) para a tela de login do Google, com a
    identidade pretendida (Tiago/Monique/perfil dinâmico) guardada em
    `localStorage` (`pendingLoginUid`) antes do redirect, já que a página
    recarrega por completo e perde qualquer variável em memória. Também
    foi adicionado log de erro real (`console.error` + notificação com a
    mensagem específica) nos blocos de autenticação, para não repetir um
    "falha silenciosa" no futuro. Corrigido e confirmado ao vivo: o site
    publicado já serve o código novo (`location.href`, sem `window.open`).
    Bug secundário identificado mas não corrigido (baixa prioridade,
    inofensivo): a atualização do avatar após login calcula o id do
    elemento como `limgTiago`/`limgMonique`, mas o HTML usa `limgT`/`limgM`
    — o `getElementById` retorna `null` e a foto simplesmente não
    atualiza (a letra inicial continua aparecendo no lugar da foto).
18. Corrigido um bug de cache separado, descoberto ao testar o item 17: o
    GitHub Pages serve `index.html`/`sw.js` com `Cache-Control: max-age=600`
    (10 minutos), e o service worker antigo repassava esse cache antigo em
    vez de buscar a versão nova na rede durante sua atualização em segundo
    plano — ou seja, depois de cada publicação, quem já tinha o app aberto
    podia continuar rodando a versão anterior por até 10 minutos. Corrigido
    adicionando `{cache: 'reload'}` na busca de atualização do `sw.js`, o
    que força ignorar o cache HTTP do navegador nessa checagem específica.
    Também adicionado auto-reload: quando um novo service worker assume o
    controle (`controllerchange`), a página recarrega sozinha uma vez, para
    que correções futuras cheguem a quem já está com o app aberto sem
    precisar limpar cache manualmente.
19. **Causa raiz real do loop de login, finalmente encontrada e corrigida.**
    Mesmo depois do item 17 (popup → redirect), o Tiago continuou
    reportando o mesmo loop, inclusive pelo iPhone. Isso mostrou que o
    popup nunca foi o problema de verdade. Para parar de adivinhar,
    adicionamos um log de diagnóstico que grava cada etapa do login em
    `localStorage` (sobrevive ao redirect) e mostra esse log direto na
    tela de login quando uma tentativa não termina em sucesso (funções
    `dbg()` / `renderLoginDebug()` em index.html). No primeiro teste com
    esse log, apareceu o erro real: `auth/configuration-not-found` — o
    provedor de login "Google" nunca tinha sido habilitado nas
    configurações do Firebase Authentication do projeto (Firebase Console
    → Authentication → Método de login). Ativamos o provedor (e-mail de
    suporte do projeto: tiagocamargos@tocsmartgroup.com). No teste
    seguinte, apareceu um SEGUNDO erro, mais específico:
    `auth/invalid-credential — access_token audience is not for this
    project`. Causa: o Client ID OAuth usado no app
    (`150189154211-br8invtfrin89lfes5d0488876ansq8c.apps.googleusercontent.com`)
    pertence a um projeto Google Cloud diferente do projeto Firebase
    (`611661253806`), e por padrão o Firebase só aceita tokens do próprio
    client ID. Corrigido adicionando esse Client ID à lista de permissões
    de "IDs de cliente externos" na configuração do provedor Google
    (Firebase Console → Authentication → Método de login → Google →
    "Adicionar IDs de cliente à lista de permissões usando projetos
    externos"). **Testado ao vivo com sucesso**: login completo, sem
    loop, entrando direto no app. Resumindo a causa raiz de verdade: o
    login nunca funcionou desde o início porque o backend do Firebase
    Authentication nunca esteve configurado para aceitar esse tipo de
    login — o popup e o cache eram problemas reais, mas secundários.
20. Ferramenta de diagnóstico deixada no código para o futuro: qualquer
    tentativa de login que não termine em sucesso agora deixa um rastro
    técnico (com timestamps) visível diretamente na tela de login, sem
    precisar de console/DevTools. Isso deve acelerar bastante qualquer
    bug de autenticação que apareça depois.
21. **Descoberto de onde vem o Client ID OAuth do app, e por que a Annie
    tomou "Acesso bloqueado".** O Client ID usado no app
    (`150189154211-...`) pertence a um projeto Google Cloud chamado
    **"Assistente TOC"** (ID `assistente-toc`, número `150189154211`) —
    um projeto DIFERENTE do projeto Firebase "Assistente"
    (`assistente-ee1f4`, número `611661253806`) que usamos para tudo mais
    (Firestore, Auth, Actions/WIF). Ou seja: hoje o login do app depende
    de DOIS projetos Google Cloud distintos ao mesmo tempo — vale lembrar
    disso em qualquer configuração futura relacionada a login/OAuth. A
    tela de permissão OAuth desse projeto "Assistente TOC" está em modo
    **"Testando"** (não verificada pelo Google), o que significa que só
    e-mails cadastrados manualmente como "usuários de teste" conseguem
    fazer login — qualquer outra pessoa recebe a tela "Acesso bloqueado
    (Erro 403: access_denied)". Era exatamente o caso da Annie
    (`nieelines1992@gmail.com`), que não estava nessa lista. Corrigido
    adicionando o e-mail dela em Google Cloud Console → projeto
    "Assistente TOC" → Google Auth Platform → Público-alvo → "Usuários de
    teste" → "Add users". Lista atual de testadores autorizados:
    moniqueabril@gmail.com, moniquegcamargos@gmail.com,
    nieelines1992@gmail.com (Annie), tiagocamargos@tocsmartgroup.com,
    tiolicam@gmail.com (limite: 100 usuários de teste). **Importante para
    o futuro**: qualquer pessoa nova que for testar o app precisa ser
    adicionada manualmente nessa lista antes de tentar o login, ou vai
    tomar "Acesso bloqueado" — isso não é um bug, é o comportamento
    esperado de um app OAuth ainda não verificado pelo Google. Para abrir
    o login para qualquer pessoa sem essa etapa manual, seria necessário
    completar a verificação oficial do Google para o projeto "Assistente
    TOC" (processo à parte: exige política de privacidade publicada,
    domínio verificado, e possivelmente avaliação de segurança por causa
    do escopo de Calendário, que é classificado como "restrito").
22. Corrigido bug real na lista de tarefas: o painel não tinha scroll
    interno (faltava `min-height:0` numa cadeia de containers flex/grid —
    bug clássico de CSS onde o conteúdo excedente é cortado em vez de
    rolável), então com muitas tarefas só as primeiras ~18 apareciam e o
    resto ficava inacessível. Corrigido em `.main`, `.left-panel`,
    `.tab-content` e `.right-panel`/`.briefing`. Também mudado o
    comportamento da lista: tarefas marcadas como feitas agora somem de
    todas as visões (Todas/Minhas/Compartilhadas/Urgente) e só aparecem
    no filtro "✓ Feitas" — antes ficavam misturadas (com risco), deixando
    a lista principal poluída.
23. **Atalho "Nova tarefa por voz" — tentativa 1 (manifest shortcuts) e
    correção para o caminho que realmente funciona no iPhone.** O Tiago
    pediu algo perto de um "widget" para criar tarefa por voz sem abrir
    o app manualmente. Como o Assistente é um PWA (não um app nativo),
    um widget real de tela inicial (tipo o de Lembretes do iPhone) ou
    integração direta e silenciosa com a Siri exigiriam um app nativo
    (Swift) — fora do escopo atual.
    Primeira tentativa: adicionado `shortcuts` no `manifest.json`
    (pressionar e segurar o ícone do app mostraria "🎤 Nova tarefa por
    voz" / "➕ Nova tarefa"). **Não funcionou** — confirmado por teste
    real do Tiago e por pesquisa: o **iOS/Safari não implementa o campo
    `shortcuts` da Web App Manifest spec** (suportado só em
    Android/Chrome e desktop). Pressionar e segurar o ícone no iPhone
    nunca mostra nada disso — limitação da Apple, não bug nosso. O
    código ficou no `manifest.json` (inofensivo, sem efeito no iPhone,
    passaria a funcionar se um dia o app for usado no Android).
    Caminho que realmente funciona no iPhone: um **Atalho da Apple**
    (app Atalhos, nativo do iOS) com uma única ação **"Abrir URLs"**
    apontando para `https://tiagocamargos1.github.io/Assistente/?quick=1&mic=1`,
    salvo na tela de início (e opcionalmente com frase de ativação da
    Siri, ex: "nova tarefa"). Isso sim abre o app já com o campo de
    texto em foco e tenta ligar o microfone sozinho (usa `toggleMic()`,
    a mesma função do botão 🎤 já existente). Guiado passo a passo pelo
    chat, incluindo a correção de um erro comum ao criar o Atalho: por
    padrão o Atalhos as vezes cria uma ação "Obter Conteúdo do URL" (só
    busca a página em segundo plano, não abre nada visível) em vez de
    "Abrir URLs" — atenção a isso se recriar o atalho no futuro.
    **Limitação final confirmada e aceita**: ao abrir a página através
    do app Atalhos (em vez de abrir direto pelo ícone normal do app), o
    iOS pede permissão de microfone TODA VEZ, mesmo já tendo permitido
    antes — isso é uma limitação documentada do próprio iOS (o
    mapeamento de permissões entre o app Atalhos e o conteúdo web não é
    persistente, ao contrário de abrir o app diretamente, onde a
    permissão é pedida só uma vez e fica salva). Não há correção
    possível do lado do código do Assistente. Decisão do Tiago: manter
    assim mesmo — um toque a mais em "Permitir" ainda é mais rápido que
    abrir o app manualmente e navegar até o botão 🎤.

24. **PIN com auto-submit.** O Tiago pediu para não precisar mais tocar em
    "Entrar" (ou dar Enter) depois de digitar o PIN. Adicionado
    `checkPinAutoSubmit()`, chamado a cada tecla digitada no campo de PIN
    (`oninput`): a cada dígito, calcula o hash SHA-256 do valor atual (a
    partir de 4 dígitos) e compara com o hash salvo (`pin_${uid}` no
    `localStorage`); se bater, chama `submitPin()` sozinho, sem esperar
    Enter/clique. Uma flag (`pinAutoSubmitting`) evita disparo duplicado
    caso o usuário continue digitando ou aperte Enter logo em seguida. Não
    mexeu em `submitPin()` em si (continua validando o hash de novo e
    tratando a sessão do Firebase Auth normalmente) — só adiciona um
    gatilho automático mais cedo. Testado localmente (sintaxe validada) e
    publicado no GitHub.

25. **Corrigida a renovação silenciosa do token do Google Calendar (causa
    real de precisar reconectar ao Google toda vez, mesmo já tendo PIN).**
    O Tiago relatou: depois de sair e voltar (PIN), tinha que reconectar
    ao Google de novo pra ver a agenda. Causa raiz: o app usa OAuth
    "implícito" do Google (`response_type=token`), cujo token de acesso à
    agenda expira sozinho em ~58 minutos e não tem refresh token (isso é
    uma limitação desse tipo de fluxo, não um bug em si). Já existia uma
    tentativa de renovação silenciosa via iframe escondido
    (`getValidToken()`), mas ela **nunca funcionou de verdade**: o token
    novo era gerado dentro do próprio iframe (uma página/contexto JS
    totalmente separado), e nunca era repassado de volta pra página
    principal — a função só esperava alguns segundos e devolvia o token
    antigo (ou `null`), e pior, um bug de sequência fazia ela mostrar
    "Sessão expirada" e desistir *imediatamente*, sem sequer esperar o
    iframe carregar. Corrigido em duas partes: (1) a cópia da página que
    carrega dentro do iframe agora detecta que está rodando dentro dele
    (`window.self!==window.top`) e, ao invés de rodar o login inteiro de
    novo, só repassa o token pra página principal via `postMessage`; (2)
    `getValidToken()` agora escuta essa mensagem e atualiza o token de
    verdade. Também corrigido `submitPin()`, que só chamava `fetchCal()`
    (e portanto só tentava a renovação) quando já havia um token válido
    guardado — ou seja, quando o token tinha expirado, nem tentava
    renovar, já mostrava direto "Conecte o Google". Agora sempre tenta.
    **Limitação que continua existindo, avisada ao Tiago antes de
    implementar**: esse tipo de renovação silenciosa depende do navegador
    ainda ter uma sessão ativa do Google e permitir esse iframe de
    terceiros — funciona bem no Chrome/Android/desktop, mas no
    Safari/iPhone a Apple bloqueia esse tipo de coisa por padrão (ITP —
    Intelligent Tracking Prevention), então mesmo com a correção pode
    ainda pedir reconexão de vez em quando nesse aparelho. Solução
    definitiva (sem essa limitação) exigiria trocar para OAuth com
    "refresh token" de verdade + um pequeno backend para guardá-lo com
    segurança — avaliado com o Tiago e adiado por ora (ver próximos
    passos) por causa do esforço/infra extra.

26. Adicionado e-mail de nova testadora (Lucileia, colaboradora de
    Portugal) à lista de "Usuários de teste" do OAuth consent screen do
    projeto Google Cloud "Assistente TOC" (mesmo processo do item 21):
    `lucyleiaoliveira@gmail.com`. Lista atual (6/100): moniqueabril@gmail.com,
    moniquegcamargos@gmail.com, nieelines1992@gmail.com,
    tiagocamargos@tocsmartgroup.com, tiolicam@gmail.com,
    lucyleiaoliveira@gmail.com.

27. **As 5 áreas padrão (Deus, Pessoal, Família, Finanças, Negócios)
    viraram opcionais por pessoa.** O Tiago apontou um problema real de
    produto: eram fixas e obrigatórias pra todo mundo — um ateu ou alguém
    solteiro que fosse testar o app não teria como tirar "Deus" ou
    "Família" da frente. Decisão tomada com o Tiago: manter as 5 áreas
    como estão (nada de área customizada por enquanto), mas cada pessoa
    pode ligar/desligar quais quer ver, a qualquer momento, através de um
    novo ícone no cabeçalho (🏷️ "Áreas"). Implementado: estado
    `enabledAreas` por usuário, salvo em `prefs/{uid}.enabledAreas`
    (Firestore); os botões de área no campo "Nova demanda" e no filtro da
    lista de tarefas agora são gerados dinamicamente a partir dessa lista,
    em vez de fixos no HTML; o dropdown de área no modal de editar tarefa
    também é gerado dinamicamente, mas sempre inclui a área atual da
    tarefa mesmo que ela tenha sido desligada depois (pra nunca mudar o
    dado de uma tarefa antiga sem querer). Padrão pra quem já usa o app
    (Tiago, Monique) e pra qualquer conta sem essa preferência salva
    ainda: as 5 áreas continuam todas ligadas, ou seja, ninguém teve a
    experiência mudada sem pedir — a pessoa nova é quem decide desligar o
    que não faz sentido pra ela, indo em 🏷️ Áreas.

28. **Áreas personalizadas.** Logo depois do item 27, o Tiago pediu um
    passo a mais: além de ligar/desligar as 5 áreas padrão, cada pessoa
    poder **criar as próprias áreas** (nome + emoji), pra cobrir qualquer
    necessidade pessoal que as 5 padrão não cubram (ex: "Estudos",
    "Ministério de louvor"). Implementado dentro do mesmo modal "🏷️
    Áreas": uma seção "Áreas personalizadas" com a lista das áreas já
    criadas (cada uma com checkbox pra ligar/desligar e um 🗑️ pra
    excluir) e um mini-formulário pra adicionar uma nova (campo de emoji
    + campo de nome + botão "+"). As mudanças (adicionar, excluir, marcar
    ligado, marcar desligado) só valem de verdade depois de tocar em
    "Salvar" — "Cancelar" descarta tudo o que foi mexido na sessão do
    modal. Estrutura de dados: `prefs/{uid}.customAreas` guarda a lista
    `[{key, label, emoji}]` de cada pessoa; `enabledAreas` (já existente
    do item 27) passou a poder conter tanto chaves padrão quanto chaves
    de áreas personalizadas (`custom_<timestamp+random>`). Uma função
    única `areaDef(key)` resolve o nome/emoji tanto pras 5 padrão quanto
    pras personalizadas, usada em todo lugar que mostra uma área (tag da
    tarefa, filtro rápido, filtro da lista, dropdown de editar tarefa) —
    editar uma tarefa antiga sempre mostra a área dela corretamente,
    mesmo que a área tenha sido desligada ou até excluída depois (nesse
    caso o dropdown ainda mostra aquela opção pontualmente, só pra não
    apagar o dado sem querer).
29. **Levantamento de custo pra virar app instalável de verdade (App
    Store + Google Play) — discussão feita, trabalho técnico AINDA NÃO
    iniciado.** O Tiago perguntou quanto custaria transformar o Assistente
    num app instalável. Esclarecido: o app já é instalável de graça hoje
    (PWA, "Adicionar à tela de início"); o que teria custo real é publicar
    como app "de verdade" nas lojas. Levantado (pesquisa na web, dados de
    2026):
    - Apple Developer Program: US$ 99/ano — **o Tiago já tem essa
      assinatura paga este ano**, custo zero adicional agora.
    - Google Play Console: US$ 25, pagamento único, sem mensalidade — o
      Tiago ainda **não confirmou** se já tem essa conta ou não (pergunta
      feita mas não respondida por uma falha técnica na ferramenta de
      pergunta — perguntar de novo na próxima sessão antes de prosseguir).
    - Custo condicional (só se um dia quiser abrir o login pra qualquer
      pessoa sem lista manual de testadores): verificação oficial do
      Google pro escopo "restrito" do Calendário exige uma auditoria de
      segurança anual (CASA), custando tipicamente US$ 500–4.500/ano.
      **Não é necessário só pra publicar nas lojas** — dá pra manter o
      OAuth em modo "Testando" e simplesmente cadastrar o e-mail do
      revisor da Apple/Google (ou usar uma conta de teste já autorizada)
      no campo "notas para o revisor" de cada loja, evitando esse custo
      por enquanto.
    - Sem custo, mas com trabalho: página de política de privacidade
      (posso gerar e hospedar no próprio GitHub Pages) e prints/tela pra
      ficha da loja.
    - Compilação nativa: o Tiago **tem Mac** (usa Apple no escritório) —
      então dá pra compilar/assinar o app iOS localmente com Xcode, sem
      precisar de Mac na nuvem. Ele também já está testando os itens
      Android com a Lucileia (colaboradora em Portugal), então o app já
      roda bem como PWA em Android também.
    - Abordagem técnica combinada, mas ainda não executada: empacotar o
      código atual (index.html/manifest.json/sw.js/ícones) com
      **Capacitor** (ferramenta gratuita e de código aberto) pra gerar os
      projetos nativos iOS e Android em volta do PWA existente. Como a
      publicação neste projeto é feita só via upload manual pelo
      navegador no GitHub (sem git/API), e os projetos nativos gerados
      pelo Capacitor têm centenas/milhares de arquivos — inviável de
      publicar assim —, o plano é: eu preparo os arquivos de configuração
      do Capacitor (`package.json`, `capacitor.config`) e publico só
      esses (pequenos, texto puro) no repo; o Tiago roda localmente no
      próprio Mac os comandos `npx cap add ios` e `npx cap add android`
      (que geram as pastas nativas ali mesmo, sem precisar subir pro
      GitHub), abrindo depois no Xcode/Android Studio pra compilar e
      assinar.
    - **Duas perguntas ainda em aberto, feitas mas sem resposta (falha
      técnica), pra retomar na próxima sessão antes de começar a
      configuração:** (1) qual bundle ID/identificador usar nas lojas
      (sugestão dada: `com.tocsmartgroup.assistente`, seguindo o domínio
      da empresa — não dá pra trocar depois sem recriar o app do zero em
      cada loja); (2) se o Tiago já tem conta no Google Play Console ou
      se ainda precisa criar e pagar o registro de US$ 25.

30. **Empacotamento nativo (Capacitor) — configuração publicada,
    execução real ainda pendente no Mac do Tiago.** Respostas do Tiago às
    duas perguntas do item 29: bundle ID confirmado como
    `com.tocsmartgroup.assistente`; ele ainda **não tem** conta no Google
    Play Console e quer criá-la — mas criação de conta + pagamento é uma
    ação proibida pra mim mesmo com autorização explícita (regra de
    segurança: nunca criar contas nem inserir dados de pagamento em nome
    do usuário), então isso fica para o próprio Tiago fazer em
    https://play.google.com/console/signup (taxa única de US$ 25).
    Enquanto isso, publiquei no repositório tudo que não depende dessa
    conta: `package.json` (dependências `@capacitor/core`,
    `@capacitor/cli`, `@capacitor/ios`, `@capacitor/android`, todas na
    major mais atual, 8.x, confirmada por pesquisa), `capacitor.config.json`
    (appId `com.tocsmartgroup.assistente`, appName "Assistente Pessoal",
    webDir `www`), a pasta `www/` (cópia de `index.html`,
    `manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png` — o
    Capacitor espera os assets web numa pasta própria, não na raiz do
    repo) e `GUIA-APP-NATIVO.md`, um guia passo a passo em português com
    os comandos exatos pro Tiago rodar no próprio Mac (`git clone`,
    `npm install`, `npx cap add ios`, `npx cap add android`, `npx cap open
    ios`/`android`, e um script `npm run cap:sync` pra manter a pasta
    `www/` atualizada sempre que eu publicar mudanças em
    `index.html`/`manifest.json`/`sw.js`/ícones no futuro). O guia também
    documenta, pro Tiago, como evitar o custo do CASA (deixar o OAuth em
    modo "Testando" e informar uma conta de teste já autorizada nas notas
    pro revisor da loja) e reforça a regra de nunca pedir senha/API
    key/segredo direto — essas credenciais (Apple ID no Xcode, conta
    Google no Android Studio/Play Console) só o próprio Tiago deve digitar.

31. **Removido o painel visual de log de erro da tela de login.** O
    Tiago reclamou que, sempre que abria o app, aparecia o log técnico da
    última tentativa de login que não deu certo (ferramenta de
    diagnóstico do item 20) — "fica feio". Causa: como esse log só é
    limpo quando um login completo via Google termina com sucesso
    (`clearLoginDebug()` dentro de `onToken()`), e o dia a dia normal é
    logar via PIN (que nunca toca nesse log), qualquer tentativa antiga
    que falhou ficava "presa" ali e reaparecia pra sempre na tela de
    login. Corrigido removendo só a `<div id="loginDebugPanel">` do HTML
    — como `renderLoginDebug()` já tinha um guard (`if(!panel)return;`),
    isso foi suficiente pra parar de aparecer, sem precisar mexer em
    nenhuma outra função. O registro em si (`dbg()` gravando em
    `localStorage.loginDebugLog`) continua funcionando por baixo dos
    panos, silenciosamente — não foi removido, só a exibição — então se
    precisar diagnosticar login de novo no futuro, dá pra reativar
    (recolocar a div) ou inspecionar `localStorage.getItem('loginDebugLog')`
    direto pelo DevTools. Aplicado tanto no `index.html` da raiz quanto
    na cópia em `www/index.html` (usada pelo empacotamento Capacitor).

32. **App nativo rodando de verdade, login Google corrigido no Android, e
    verificação visual sem depender de testadores humanos.** Instalado e
    confirmado rodando no iPhone físico do Tiago via Xcode. Testadoras
    Annie e Leandro reportaram falha de login no Android nativo — causa
    raiz: Google bloqueia OAuth dentro de WebView embutida
    (`disallowed_useragent`) quando `capacitor.config.json` navega a
    própria WebView pra `accounts.google.com`. Corrigido trocando pra
    `@capacitor/browser` (Custom Tabs/SFSafariViewController) com uma
    página-ponte estática (`oauth-bridge.html`, hospedada no GitHub
    Pages) que devolve o token pro app via esquema customizado
    `assistentepessoal://oauthcallback`. Exigiu: novo pacote nas duas
    plataformas, novo intent-filter no `AndroidManifest.xml`, nova
    dependência no `Package.swift` (SPM/iOS), novo redirect URI
    autorizado no Google Cloud Console, correção de colisão de
    `versionCode` no Gradle, e novo AAB assinado enviado e aprovado no
    Play Console. Nav inferior mobile (pill flutuante + mic dourado)
    confirmado batendo com o design usando um truque de iframe de 400px
    no Chrome (ativa de verdade as media queries mobile sem depender de
    redimensionar a janela, que não funciona neste ambiente). Selo
    "🔴 atrasado há Xm" e seu comportamento (atualiza sozinho a cada 30s,
    some ao concluir a tarefa) testados e confirmados via JS direto no
    app publicado. Único ponto que continua exigindo teste humano: o
    disparo real de notificações nativas repetidas (6x a cada 5min) só
    acontece dentro do plugin `LocalNotifications`, que não existe fora
    do app nativo — não dá pra simular num navegador comum.

33. **Renomeado `CONTEXT.md` para `context-assistente-pessoal.md`.**
    Decisão do Tiago: evitar o nome genérico `CONTEXT.md`, que se repete
    em outros projetos dele (ex: Setoriza) e cria risco de confundir
    sessões/arquivos entre projetos diferentes. Conteúdo idêntico, só o
    nome do arquivo (e as auto-referências dentro dele) mudou.

34. **Nova funcionalidade: Caixa de Ideias (captura rapida de ideias de negocio na rua).** Pedido do Tiago: um lugar unico para despejar ideias de negocio que surgem na rua, sem gastar tempo organizando ali na hora -- soh trata tudo depois, com calma, no escritorio. Decisao de design: reaproveitar o MESMO campo de captura rapida que ja existe ("Nova demanda"), em vez de criar um formulario novo -- basta falar ou escrever com o prefixo "Ideia: ..." (mesmo padrao ja usado para "Nota: ...") e o parser local (parseInput) direciona para a nova colecao ao inves de tasks/notes. Implementado: nova aba "Ideias" (com contador de pendentes no icone, igual as Tarefas), gravacao em Firestore em users/{uid}/ideas (mesmo padrao de isolamento por usuario das outras colecoes, sem precisar mexer nas regras do Firestore), e tres estados -- Por tratar / Em curso / Feita -- que ciclam com um toque no rotulo colorido de cada ideia (reaproveita as cores ttag tu/tt/tg ja existentes). Publicado tanto no index.html da raiz quanto na copia em www/index.html (usada pelo empacotamento Capacitor). Objetivo futuro, ainda nao implementado: dar acesso partilhado a essa caixa de ideias para a Annie (assistente remota da BELUTI).
35. **Corrigidos dois bugs reais na Caixa de Ideias (item 34), descobertos ao testar sozinho via automação de navegador.** Bug 1: faltava a regra de seguranca do Firestore para `users/{uid}/ideas/{ideaId}` -- sem ela, o catch-all padrao bloqueava toda leitura/escrita, gerando `FirebaseError: Missing or insufficient permissions` ao tentar salvar uma ideia. Corrigido publicando a regra no Firebase Console (mesmo padrao das outras colecoes: `allow read, write: if isMe(uid);`). Bug 2: as funcoes `renderIdeas()` e `setIdeaFilter()`, referenciadas pelo HTML da aba Ideias e pelo listener do Firestore, nunca tinham sido de fato definidas em `index.html` -- a aba existia, mas lancava `ReferenceError: renderIdeas is not defined` toda vez que uma ideia era criada ou um filtro clicado. Corrigido implementando as duas funcoes (mesmo padrao visual das outras abas, com as tags de cor tu/tt/tg reaproveitadas para Por tratar/Em curso/Feita) e publicando no `index.html` da raiz. Confirmado funcionando com um recarregamento limpo da pagina (sem service worker/cache antigo, sem injecao via console): criar ideia, ciclar status, filtrar e excluir todos testados com sucesso. Nao foi necessario replicar em `www/index.html` -- esse arquivo e regenerado automaticamente pelo comando `npm run cap:sync` (ver GUIA-APP-NATIVO.md) a partir do `index.html` da raiz sempre que o Tiago sincroniza o app nativo, entao nao e mantido manualmente.
36. **Corrigido bug real na exclusao de areas personalizadas (item 28), descoberto ao testar sozinho.** O item 28 documentava que editar uma tarefa antiga sempre mostraria a area dela corretamente mesmo apos excluir a area personalizada -- mas isso nunca funcionou de fato. Causa raiz: `areaDef(key)` retornava `null` assim que a area personalizada era removida de `customAreas` (a exclusao apaga o registro inteiro, nao so desativa), e as funcoes que dependiam dela (`areaTag()` no card da tarefa, e o preenchimento do dropdown "Area" no modal de editar) simplesmente pulavam a opcao quando recebiam `null`. Na pratica: a tag de area sumia do card da tarefa, e o seletor "Area" no modal de editar ficava em branco (nem "Geral" nem o nome antigo) -- e se a pessoa salvasse a tarefa sem mexer nesse campo (o caso mais comum), o valor em branco sobrescrevia silenciosamente o dado original, apagando de vez a area da tarefa. Corrigido em `areaDef()`: quando a chave nao e encontrada nem nas 5 areas padrao nem nas personalizadas atuais, mas comeca com `custom_` (ou seja, e uma area personalizada que existiu e foi excluida), agora retorna um rotulo generico `🔖 Area removida` em vez de `null` -- suficiente pra manter a tag visivel e o dropdown com a opcao certa selecionada, sem jamais sobrescrever o dado ao salvar. Testado ao vivo criando uma area personalizada, atribuindo a uma tarefa, excluindo a area, reabrindo a tarefa (dropdown mostrou "🔖 Area removida" corretamente em vez de branco) e salvando sem alterar o campo -- a area da tarefa permaneceu intacta.

## Próximos passos (pendentes)

- [ ] O Tiago precisa criar a conta no Google Play Console
      (https://play.google.com/console/signup, taxa única de US$ 25) —
      isso não pode ser feito por mim (regra de segurança: nunca criar
      contas ou inserir pagamento em nome do usuário).
- [ ] Testar ao vivo, no iPhone físico (com Apple Watch pareado), o
      atalho de Siri "Nova tarefa no Assistente Pessoal" / "Tarefa
      urgente no Assistente Pessoal" — único pedaço do app nativo que
      só dá pra confirmar com teste humano de verdade (ver item 32).
- [ ] Depois que os testes acima forem confirmados, ajudar com: texto e
      ficha da loja (descrição, categoria), política de privacidade
      publicada (posso gerar e hospedar no GitHub Pages), prints de tela
      pra loja, e o processo de submissão em si (App Store Connect) — o
      Tiago quem precisa clicar em "Enviar"/"Publicar", eu só preparo o
      material.

- [x] ~~Testar ao vivo as áreas personalizadas (item 28)~~ — CONFIRMADO (item 36): criar, atribuir a uma tarefa, excluir a área e reabrir a tarefa testados com sucesso. Um bug real foi encontrado nesse processo (a exclusão apagava silenciosamente a área da tarefa ao salvar) e corrigido — ver item 36.
- [ ] Testar ao vivo a nova configuração de áreas (item 27): abrir 🏷️
      Áreas no cabeçalho, desmarcar alguma área (ex: Deus ou Família),
      salvar, e confirmar que ela some do campo "Nova demanda" e do
      filtro da lista de tarefas, mas tarefas antigas com aquela área
      continuam aparecendo normalmente e continuam editáveis sem perder o
      valor da área.

- [ ] Testar ao vivo a correção da renovação silenciosa do token do
      Google (item 25): deixar o token expirar (ou simular) e ver se a
      agenda carrega sozinha ao entrar pelo PIN, sem precisar tocar em
      "Conectar Google" — testar tanto no navegador/desktop quanto no
      iPhone (esperado: funciona melhor no Chrome/desktop; no iPhone pode
      ainda pedir reconexão às vezes, por limitação do próprio Safari).
- [ ] Se a reconexão no iPhone continuar incomodando mesmo após o item 25,
      considerar a solução definitiva: trocar o login do Google Calendar
      para OAuth com refresh token + um pequeno backend (ex: Firebase
      Cloud Functions) pra manter a conexão de verdade sem depender de
      truques de navegador. Mais trabalho de configuração, mas resolve de
      vez, inclusive no iPhone.
- [ ] Testar ao vivo o auto-submit do PIN (item 24): digitar um PIN
      correto e confirmar que entra sozinho no app sem tocar em "Entrar";
      confirmar também que um PIN de 4 dígitos que é prefixo de um PIN de
      6 dígitos salvo não dispara entrada errada antes de completar o PIN
      certo.

(nenhum pendente relacionado ao atalho de voz — funcionalidade concluída
e limitações conhecidas aceitas pelo Tiago, ver item 23)

- [x] ~~Confirmar que o loop de login está resolvido~~ — CONFIRMADO ao vivo
      (item 19): login completo com sucesso, sem loop, tanto no teste
      técnico quanto no navegador/app do Tiago.
- [ ] Ao convidar qualquer pessoa nova para testar o app, lembrar de
      primeiro adicionar o e-mail dela em Google Cloud Console → projeto
      "Assistente TOC" → Google Auth Platform → Público-alvo → "Usuários
      de teste" (ver item 21) — senão ela toma "Acesso bloqueado".
- [ ] Decidir, quando fizer sentido (ex: se o plano for abrir o app para
      muita gente/vender de verdade), se vale a pena passar pela
      verificação oficial do Google para o projeto "Assistente TOC", para
      eliminar a necessidade de cadastrar cada testador manualmente.
- [ ] Ativar de fato as notificações push: alguém (Tiago/Monique) precisa
      abrir o app e clicar em "Ativar" no banner que aparece após o login.
      Sem isso não existe subscription salva e o job não tem para quem
      mandar.
- [ ] Confirmar visualmente que a migração automática dos dados antigos
      (`tasks_tiago`/`tasks_monique` → `users/{uid}/tasks`) rodou certo —
      abrir o app como Tiago e Monique e checar se as tarefas antigas
      aparecem normalmente.
- [ ] Convidar mais alguém para testar o app via "Entrar com Google"
      (sistema de usuário dinâmico), como parte do objetivo de eventualmente
      vender a ferramenta. Annie já recebeu o link; app agora mostra tela
      de login genérica pra ela (não mais os cartões do Tiago/Monique).
- [ ] Opcional: tornar o banner de ativação de push mais difícil de ignorar
      (remover o "✕" de dispensa rápida, obrigando escolher entre "Ativar"
      ou "Agora não" explicitamente).
- [ ] Não decidido/descartado por ora: compartilhamento seletivo de tarefas
      entre usuários dinâmicos e Tiago (feature nova de "compartilhar com",
      tarefa por tarefa). Decisão tomada: por enquanto NENHUM
      compartilhamento com testadores — cada um fica isolado até decidirmos
      o contrário.
- [ ] Opcional/sem urgência: depois de confirmar a migração, pode-se (não é
      obrigatório) limpar as coleções antigas `tasks_tiago`, `tasks_monique`,
      `notes_tiago`, `notes_monique`, `routines_tiago`, `routines_monique`
      no Firestore console — as regras já bloqueiam escrita nelas.
- [ ] Em aberto / não decidido ainda: ideias de integração conceitual entre
      Assistente Pessoal e Setoriza (tratar na conversa própria do Setoriza,
      não aqui).
- [ ] Considerar adicionar um README.md ao repositório (hoje o GitHub mostra
      "Add a README" — não é funcional, só cosmético/documentação pública).
- [x] ~~Testar ao vivo a Caixa de Ideias (item 34)~~ — CONFIRMADO (item 35): criar, ciclar status, filtrar e excluir ideias testados com sucesso num recarregamento limpo, sem cache antigo.

## Protocolo de sessão

**Início de sessão** — quando receber "Claude, bora trabalhar": ler este
context-assistente-pessoal.md até o fim antes de qualquer coisa, entender o
que já foi feito e o que está pendente, e retomar o trabalho a partir dos
"Próximos passos" listados acima (ou do que o Tiago pedir na hora).

**Fim de sessão** — quando receber "Claude, bora descansar": atualizar este
context-assistente-pessoal.md com tudo o que foi feito na sessão (mover itens
de "Próximos passos" para "O que já foi feito", registrar novas decisões
técnicas ou de produto, atualizar a stack se mudou), e então:
1. Se houver um repositório Git configurado localmente com acesso de
   commit, fazer `git add`, `git commit` (mensagem descrevendo o que mudou
   na sessão) e `git push`.
2. Se não houver Git local configurado nesta sessão (caso mais comum até
   aqui, já que a publicação é feita via automação de navegador no GitHub),
   publicar o context-assistente-pessoal.md atualizado e os demais arquivos
   alterados diretamente no repositório `tiagocamargos1/Assistente`, do
   mesmo jeito que os outros arquivos do projeto foram publicados.
