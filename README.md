# Assistente Pessoal

Hub de organização pessoal e familiar, leve e imediato: tarefas, rotinas, notas, ideias, agenda da semana, tarefas da casa partilhadas e lista de compras — tudo num único ficheiro HTML, a correr como PWA no GitHub Pages e como app nativa (iOS/Android) via Capacitor.

- **App ao vivo:** https://tiagocamargos1.github.io/Assistente/
- **Política de privacidade:** https://tiagocamargos1.github.io/Assistente/privacidade.html
- **Custo de operação:** zero (Firebase no plano gratuito, GitHub Pages e Actions públicos)

> Este projeto é pessoal, feito para a família Camargos e alguns testadores convidados. O código é público para simplificar a hospedagem e a automação; não há chaves secretas no repositório.

## O que faz

| Aba | Para quê |
|---|---|
| **Hoje** | Resumo do dia: tarefas com prazo, eventos do Google Calendar, rotinas e as tarefas da casa que ainda faltam |
| **Tarefas** | Captura rápida por texto ou voz (`"Ligar ao contabilista amanhã 15h #trabalho"`), urgência, áreas da vida, projetos, partilha em família |
| **Casa** | Tabela diária de tarefas do lar (refeições das crianças, comida do animal, etc.) partilhada por e‑mail entre os membros — quem marcou, a que horas, vista do dia / do mês / feed de atividade, lembretes antes da hora‑limite |
| **Rotinas** | Hábitos recorrentes com marcação diária |
| **Compras** | Lista de compras única do lar, por categorias, com sugestões do histórico e partilha por WhatsApp |
| **Notas / Ideias** | Notas soltas e uma caixa de ideias com estados |
| **Semana** | Grelha semanal com tarefas e eventos |

Extras: login por PIN depois do primeiro acesso Google, notificações push (Web Push no browser, notificações locais na app nativa), briefing diário à hora escolhida, atalhos de voz e modo claro/escuro.

## Stack

- **Frontend:** `index.html` — HTML, CSS e JavaScript puro, sem framework nem build. Tipografia DM Sans, tema dourado/escuro.
- **Dados:** Firebase Firestore (SDK v10, importado como módulo ES). Cada pessoa tem os seus dados em `users/{uid}/…`; a casa vive em `household/{id}` com pertença por e‑mail Google; regras de segurança geridas no Firebase Console.
- **Autenticação:** OAuth do Google (identidade + Calendar) reaproveitado para Firebase Auth via `signInWithCredential`; PIN local (SHA‑256 em `localStorage`) para entradas seguintes.
- **PWA:** `manifest.json` + `sw.js` (service worker network‑first, com handlers de `push` e `notificationclick`).
- **Push:** Web Push com chaves VAPID. O job `scripts/send-daily-briefing.js` corre no GitHub Actions a cada 10 minutos (`.github/workflows/daily-briefing.yml`), autenticado no Google Cloud por Workload Identity Federation — sem chaves descarregadas. Envia o briefing diário e os lembretes das tarefas da casa.
- **Nativo:** Capacitor 8. A app nativa carrega a versão publicada no GitHub Pages (`server.url` em `capacitor.config.json`), por isso atualiza‑se sozinha sem passar pelo Xcode/Android Studio. Plugins: `@capacitor/app`, `browser`, `local-notifications`. No iOS há App Intents para a Siri (`ios/App/App/AddTaskIntent.swift`).

## Estrutura

```
index.html                  app completa (UI + lógica + Firebase)
manifest.json, sw.js        PWA
icon-192.png, icon-512.png  ícones
privacidade.html            política de privacidade pública
oauth-bridge.html           ponte de OAuth para a app nativa
capacitor.config.json       configuração Capacitor (server.url → GitHub Pages)
www/                        cópia servida pelo Capacitor (gerada por npm run sync-www)
ios/                        projeto Xcode (Swift Package Manager)
scripts/                    job Node do briefing/lembretes (GitHub Actions)
.github/workflows/          agendamento do job
GUIA-APP-NATIVO.md          passo a passo para compilar iOS/Android
context-assistente-pessoal.md  memória do projeto: decisões, histórico, pendentes
```

## Desenvolver

Não há build: basta editar `index.html` e abrir no browser. Para servir localmente com service worker e push a funcionar, use qualquer servidor estático, por exemplo:

```bash
npx serve .
```

Publicar é fazer `git push` para `main` — o GitHub Pages atualiza em cerca de um minuto, e a app nativa apanha a versão nova na próxima abertura. Para a app nativa, `npm run sync-www && npx cap sync` regenera `www/` e sincroniza os plugins; o `GUIA-APP-NATIVO.md` cobre o resto (Xcode, assinatura, lojas).

## Configuração externa (não está no repositório)

- Projeto Firebase `assistente-ee1f4`: Firestore, Auth (Google), regras de segurança.
- Google Cloud: cliente OAuth com as origens autorizadas (GitHub Pages e app nativa) e a lista de utilizadores de teste enquanto a app não passa pela verificação do Google.
- Segredos do GitHub Actions: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`.
- Workload Identity Federation: pool `github-actions-pool`, provider `github-actions-provider`, service account `github-actions-briefing@assistente-ee1f4.iam.gserviceaccount.com`.

## Licença

Uso pessoal. Todos os direitos reservados — Tiago Camargos / TOC SMART GROUP.
