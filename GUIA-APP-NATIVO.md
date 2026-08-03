# Guia — Empacotar o Assistente Pessoal como app nativo (iOS + Android)

Este guia usa o [Capacitor](https://capacitorjs.com/) para envolver o PWA já
existente (`index.html`, `manifest.json`, `sw.js`, ícones) em projetos nativos
de iOS e Android. Os arquivos de configuração (`package.json`,
`capacitor.config.json`, pasta `www/`) já estão publicados neste repositório —
falta só rodar os comandos abaixo **no seu Mac**, porque a compilação/assinatura
do iOS exige Xcode (só roda em macOS).

## Pré-requisitos

- Mac com Xcode instalado (App Store) — você já tem.
- Android Studio instalado ([download aqui](https://developer.android.com/studio)) — necessário mesmo compilando só o iOS por enquanto? Não: só é preciso quando for a vez do Android.
- Node.js instalado (versão 18 ou mais recente). Verifique com `node -v` no Terminal.
- Git instalado (vem com o Xcode Command Line Tools, que você já deve ter).
- Conta no Apple Developer Program — você já tem.
- Conta no Google Play Console — **ainda pendente** (ver seção própria abaixo; essa parte eu não posso fazer por você).

## Passo 1 — Clonar o repositório

Abra o Terminal e rode:

```bash
git clone https://github.com/tiagocamargos1/Assistente.git
cd Assistente
```

Se você já tiver uma cópia local do repositório de antes, só dê `git pull`
dentro dela em vez de clonar de novo.

## Passo 2 — Instalar as dependências

```bash
npm install
```

Isso baixa o Capacitor (core, CLI, e os pacotes de iOS e Android).

## Passo 3 — Gerar os projetos nativos

```bash
npx cap add ios
npx cap add android
```

Isso cria as pastas `ios/` e `android/` com projetos completos do Xcode e do
Android Studio, já configurados com o `appId`
(`com.tocsmartgroup.assistente`) e o nome do app ("Assistente Pessoal")
definidos em `capacitor.config.json`. Essas pastas ficam só no seu computador
— não precisam (e não devem) ser publicadas no GitHub por upload manual, são
muito grandes.

## Passo 4 — Abrir e compilar no iOS

```bash
npx cap open ios
```

Isso abre o `App.xcworkspace` no Xcode. Lá dentro:

1. Selecione o projeto "App" → aba "Signing & Capabilities".
2. Escolha seu Team (sua conta Apple Developer).
3. Rode num simulador ou aparelho físico pra testar (▶ no Xcode).
4. Quando estiver pronto pra loja: Product → Archive, depois "Distribute App"
   → App Store Connect, seguindo o assistente do Xcode.

## Passo 5 — Abrir e compilar no Android

```bash
npx cap open android
```

Isso abre o projeto no Android Studio. Lá dentro:

1. Deixe o Gradle sincronizar sozinho na primeira vez (pode demorar).
2. Rode num emulador ou aparelho físico pra testar (▶).
3. Quando estiver pronto pra loja: Build → Generate Signed Bundle / APK,
   criando (na primeira vez) uma keystore de assinatura — guarde esse
   arquivo e a senha dele com cuidado, ele é necessário pra toda atualização
   futura do app.

## Sempre que o código web mudar (`index.html`, `manifest.json`, `sw.js`, ícones)

Depois de eu publicar uma atualização desses arquivos no repositório, você
roda no seu Mac (dentro da pasta clonada, depois de um `git pull`):

```bash
npm run cap:sync
```

Isso copia a versão mais nova desses arquivos pra dentro de `www/` e
sincroniza com os projetos iOS/Android — sem precisar rodar `cap add` de
novo.

## Sobre a conta do Google Play Console

Por segurança, não posso criar contas nem inserir dados de pagamento em
nenhum site em seu nome — isso inclui a conta do Google Play Console. Esse
passo precisa ser feito por você diretamente:

1. Acesse **https://play.google.com/console/signup**.
2. Entre com a conta Google que você quer usar como conta de desenvolvedor.
3. Preencha os dados solicitados e pague a taxa única de US$ 25.
4. A verificação de identidade do Google pode levar de algumas horas a
   poucos dias.

Assim que tiver a conta, me avisa que eu ajudo com o resto: ficha da loja
(descrição, política de privacidade, prints), e como evitar o custo da
verificação OAuth (CASA) usando uma conta de teste já autorizada nas notas
pro revisor.

## Notas de segurança para o Xcode/Android Studio

Nunca digite senhas, chaves de API ou segredos direto pedidos por mim — eu
não tenho e não devo ter acesso a essas credenciais. Tudo que exigir login
(Apple ID no Xcode, conta Google no Android Studio/Play Console) deve ser
feito por você, na sua própria máquina.
