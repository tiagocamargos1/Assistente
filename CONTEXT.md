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

## Próximos passos (pendentes)

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
      vender a ferramenta.
- [ ] Opcional: tornar o banner de ativação de push mais difícil de ignorar
      (remover o "✕" de dispensa rápida, obrigando escolher entre "Ativar"
      ou "Agora não" explicitamente).
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
