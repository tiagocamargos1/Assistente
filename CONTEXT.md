# CONTEXT.md — Assistente Pessoal

> Este arquivo é a memória persistente do projeto. Ele documenta o que já foi
> feito, a stack usada, o objetivo do software e os próximos passos.
> **Toda sessão de trabalho neste projeto deve começar lendo este arquivo até
> o fim, e terminar atualizando-o.** Ver protocolo no final deste documento.

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

## Próximos passos (pendentes)

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

## Protocolo de sessão

**Início de sessão** — quando receber "Claude, bora trabalhar": ler este
CONTEXT.md até o fim antes de qualquer coisa, entender o que já foi feito e
o que está pendente, e retomar o trabalho a partir dos "Próximos passos"
listados acima (ou do que o Tiago pedir na hora).

**Fim de sessão** — quando receber "Claude, bora descansar": atualizar este
CONTEXT.md com tudo o que foi feito na sessão (mover itens de "Próximos
passos" para "O que já foi feito", registrar novas decisões técnicas ou de
produto, atualizar a stack se mudou), e então:
1. Se houver um repositório Git configurado localmente com acesso de
   commit, fazer `git add`, `git commit` (mensagem descrevendo o que mudou
   na sessão) e `git push`.
2. Se não houver Git local configurado nesta sessão (caso mais comum até
   aqui, já que a publicação é feita via automação de navegador no GitHub),
   publicar o CONTEXT.md atualizado e os demais arquivos alterados
   diretamente no repositório `tiagocamargos1/Assistente`, do mesmo jeito
   que os outros arquivos do projeto foram publicados.
