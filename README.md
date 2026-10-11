# 🏍️🚗 UauGo — em grupo ou sozinho, qualquer caminho é UauGo

App Flutter (iPhone + Android) com Google Maps e Firebase.
Desenvolvido por **Ricardo Reis / HelpAITech**.

> 📘 **Documentação para manutenção:**
> [docs/ARQUITETURA.md](docs/ARQUITETURA.md) (como o app é organizado) e
> [docs/MANUTENCAO.md](docs/MANUTENCAO.md) (compilar, testar, publicar e
> mudanças comuns). Publicação nas lojas: [docs/lojas.md](docs/lojas.md).

**Navegação (sozinho, tipo Waze)**
- "Para onde?": rota do Google (mais rápida ou mais curta, evitar pedágios,
  rodovias, balsas e **locais de risco**), trânsito ao vivo e rota mais rápida
  automática, recálculo ao sair da rota
- Narração curva a curva, com **número da saída** e aviso antecipado a 2 km
- **Velocímetro** com o limite da pista em que você está (não da marginal) e
  aviso de **velocidade reduzida à frente**
- Avisos: **radares** (sempre com a velocidade), **lombadas**, **postos
  policiais**, **pedágios** (moto paga / isenta), **chuva à frente**, metade
  do trajeto, trechos de radar portátil da PRF
- **Simulação** da viagem (1x, 5x, 20x), modos COMBOIO (de cima) e Solo (1ª
  pessoa), **mapa noturno** automático, zoom e "Recentralizar"
- **Minhas viagens** (só no celular): caminho feito, estatísticas, **gastos e
  consumo**, imagem e GPX para redes sociais
- **Usar sem internet**: dados dos estados baixados antes de sair
- **Economia de bateria** automática

**Expedições em grupo**
- Criar expedição (gera código de 6 letras) ou entrar com o código
- Posição de todos os pilotos no mapa em tempo real (velocidade, "sem sinal há X min")
- Paradas compartilhadas: toque e segure no mapa → nome → todos veem
- Rota real pelas estradas passando pelas paradas (Directions API)
- "Navegar até aqui" abre o Google Maps com a rota
- **Alertas públicos estilo Waze** (🚓 polícia, 📷 radar móvel, 🕳️ buraco, ⚠️ perigo, 🛢️ óleo/areia, 🐄 animal, 💥 acidente, 🌫️ neblina, 🪁 pipas/cerol, 🚨 área de risco): visíveis para todos os usuários, com aviso falado e votação "ainda está lá / não está mais"
- **Minha moto / Meu carro:** cada piloto coloca foto, marca, modelo, tipo e cor. O mapa mostra o veículo de cada amigo com nome e modelo (ex: "João · Kawasaki Versys 650")
- **Autorizações no cadastro (LGPD):** no primeiro uso, o piloto escolhe o que autoriza; tudo opcional vem desligado e pode ser revogado depois
- **Clube:** pedir ajuda ao membro mais próximo, avisar quando passar pela cidade de alguém, e sugestão automática de aviso ao se aproximar (até 25 km) de um membro
- **Excluir meus dados** no app (Privacidade e autorizações) e limpeza automática diária conforme a política
- Botão **SOS** (segurar para enviar): alerta na tela + push para todo o grupo, mesmo com app fechado
- Funciona com sinal fraco: posições, paradas e SOS ficam salvos no celular e são enviados quando o sinal volta
- Rastreamento continua com o app minimizado

---

## ⚡ Início rápido no Windows (scripts automáticos)

Abra o **PowerShell** na pasta do projeto e rode, nesta ordem:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\instalar.ps1        # instala Git, Node, Android Studio, Google Cloud CLI, Flutter, Firebase CLI
.\scripts\configurar.ps1      # cria config.env, gera Android/iOS, aplica permissões e chaves
.\scripts\preparar-nuvem.ps1  # APIs, banco, chaves do Maps restritas, TTL, regras e funções
.\scripts\rodar.ps1           # instala e abre no celular conectado
```

Outros scripts:

| Script | Para quê |
|---|---|
| `scripts\testar.ps1` | Análise de código, testes do app e testes das regras de segurança |
| `scripts\simular-viagem.ps1` | Simula uma viagem no emulador Android (GPS em movimento) |

O que só você pode fazer: criar as contas, ativar o plano Blaze, o login Anônimo e o Storage no console do Firebase, e conectar os celulares.

> **iPhone no Windows:** o Windows não compila apps de iOS. Use a compilação na nuvem (abaixo) para checar o build de iOS. Para instalar em iPhones e publicar, será preciso um Mac ou um serviço de build na nuvem com assinatura (ex.: Codemagic).

## ☁️ Compilação na nuvem (GitHub Actions)

1. Crie um repositório **privado** no GitHub e envie o projeto.
2. A cada envio, a aba **Actions** roda: testes do app, testes das regras, build Android (gera um APK para baixar) e build iOS num Mac virtual.
3. Opcional: em *Settings → Secrets and variables → Actions*, cadastre `ANDROID_MAPS_KEY` para o APK já sair com o mapa (rotas e busca de lugares vêm do servidor).
4. Depois de rodar `flutterfire configure`, envie também `lib/firebase_options.dart` (repositório privado) para o APK da nuvem se conectar ao seu Firebase.

## 🔒 App Check (proteção do backend)

O app já ativa o App Check. Para passar a exigir:
1. Firebase → App Check → registre o app Android (Play Integrity) e o iOS (App Attest).
2. Em modo de depuração, o app imprime um *debug token* no log; cadastre-o em App Check → Apps → Gerenciar tokens de depuração.
3. Em `functions/.env`, mude para `ENFORCE_APP_CHECK=true` e rode `firebase deploy --only functions`.

---

## 1. Pré-requisitos (passo a passo manual)
- [Flutter](https://docs.flutter.dev/get-started/install) instalado (`flutter doctor` sem erros)
- Android Studio (para Android) e um Mac com Xcode (para iPhone)
- Node.js 20 e Firebase CLI: `npm install -g firebase-tools`
- Conta Google Cloud / Firebase

## 2. Gerar as pastas nativas
Dentro da pasta do projeto:
```bash
flutter create --org com.seunome --project-name comboio --platforms=android,ios .
flutter pub get
```
O comando cria o que falta sem sobrescrever os arquivos existentes (inclusive o `AndroidManifest.xml` já configurado).

Em `android/app/build.gradle` (ou `build.gradle.kts`), defina `minSdk = 23`.

## 3. Firebase
1. Crie um projeto em https://console.firebase.google.com
2. **Authentication → Sign-in method →** ative **Anônimo**
3. **Firestore Database →** criar banco (região `southamerica-east1` se estiver no Brasil)
4. Na raiz do projeto (ou use `scripts\\preparar-nuvem.ps1`):
```bash
dart pub global activate flutterfire_cli
flutterfire configure        # substitui lib/firebase_options.dart
firebase login
firebase use --add           # escolha o projeto
cd functions && npm install && cd ..
firebase deploy --only firestore:rules,storage,functions
```
5. **Storage →** criar bucket (fotos das motos)
6. **Firestore → TTL policies →** crie uma política na coleção `hazards`, campo `expiresAt` (apaga alertas vencidos automaticamente e mantém o custo baixo).

> As Cloud Functions (push do SOS) exigem o plano **Blaze** (pago por uso; o volume de um grupo de motos fica dentro da cota gratuita).

## 4. Chaves do Google Maps
No [Google Cloud Console](https://console.cloud.google.com) (mesmo projeto do Firebase), ative:
- Maps SDK for Android
- Maps SDK for iOS
- Directions API

Crie chaves e **restrinja** cada uma (por app Android / bundle iOS / API).

- **Android:** cole a chave em `android/app/src/main/AndroidManifest.xml` (`SUA_CHAVE_ANDROID_AQUI`).
- **iOS:** em `ios/Runner/AppDelegate.swift`, adicione `import GoogleMaps` no topo e, dentro de `application(...didFinishLaunchingWithOptions...)`, antes do `return`:
  ```swift
  GMSServices.provideAPIKey("SUA_CHAVE_IOS_AQUI")
  ```
- **Rotas e busca de lugares:** a chave fica no **servidor**, nunca no app. Grave em `functions/.env` a linha `MAPS_SERVER_KEY=SUA_CHAVE` (chave restrita à Directions API e à Places API (New)) e publique as funções. O `scripts\preparar-nuvem.ps1` faz isso sozinho.

## 5. Configuração extra do iOS
Em `ios/Runner/Info.plist`, dentro do `<dict>` principal:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Sua localização é compartilhada com os pilotos da expedição.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Para o comboio saber onde você está mesmo com o app minimizado.</string>
<key>NSCameraUsageDescription</key>
<string>Para tirar uma foto da sua moto.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Para escolher uma foto da sua moto.</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>remote-notification</string>
</array>
```
No Xcode (`ios/Runner.xcworkspace`) → Runner → *Signing & Capabilities*: adicione **Push Notifications** e **Background Modes** (Location updates + Remote notifications).

No `ios/Podfile`, use `platform :ios, '15.0'` (o configurar.ps1 já faz isso) e rode `cd ios && pod install`.

Push no iPhone: crie uma **APNs Key** no Apple Developer e envie em Firebase → Configurações do projeto → Cloud Messaging.

## 6. Rodar
```bash
flutter run
```
Teste com 2 celulares: um cria a expedição, o outro entra com o código.

---

## Material das lojas
Textos, respostas de privacidade das lojas e notas para o revisor: `docs/lojas.md`.

## Estrutura
```
lib/
  main.dart                      inicialização e tema
  models/expedition.dart         Expedition, Member, Stop, SosAlert
  models/hazard.dart             tipos de alerta e prazos
  widgets/emoji_marker.dart      marcadores com emoji no mapa
  services/
    auth_service.dart            login anônimo
    expedition_service.dart      tudo do Firestore
    location_service.dart        GPS em primeiro/segundo plano
    directions_service.dart      rota pelas estradas
    hazard_service.dart          alertas públicos (polícia, buraco...)
    notification_service.dart    push por expedição e do clube
    user_service.dart            autorizações, cidade base, telefone
    club_service.dart            clube e chamadas às Cloud Functions
  models/bike.dart               marcas, estilos, cores da moto
  services/profile_service.dart  salva perfil e envia foto
  widgets/bike_marker.dart       marcador com foto + etiqueta
  screens/
    home_screen.dart             nome, criar / entrar
    profile_screen.dart          "Minha moto"
    consent_screen.dart          autorizações (cadastro / privacidade)
    club_screen.dart             clube: entrar, membros, pedir ajuda
    map_screen.dart              mapa, paradas, grupo, SOS
  logic/geo.dart                 cálculos puros (direção, votos, polyline)
  screens/startup_gate.dart      exige autorizações no primeiro uso
functions/index.js               push; clube; exclusão de dados; limpeza diária
scripts/                         instalação e automação (PowerShell)
test/ e tests/rules/             testes do app e das regras de segurança
.github/workflows/build.yml      compilação e testes na nuvem
docs/lojas.md                    textos e formulários das lojas
firestore.rules                  segurança (só membros veem o grupo)
```

## Como funcionam os alertas públicos
- Botão amarelo (canto esquerdo) → escolhe o tipo → marca na posição atual.
- Se já existe o mesmo alerta a menos de 150 m, o app só confirma o existente.
- Cada tipo expira sozinho: polícia e animal 1 h, perigo/acidente/neblina 3 h, óleo 12 h, buraco 7 dias. Cada "👍 Ainda está lá" renova o prazo.
- Dois "👎 Não está mais" (ou mais votos contra do que a favor) removem o alerta.
- O aviso só aparece para o que está **à frente** da moto (±60° da direção), a até 500 m.
- O app escuta apenas alertas num raio de ~15–30 km (células de 0,1°), trocando conforme você anda.

Ajustes: `_alertRadius` em `map_screen.dart`; tipos, cores e prazos em `lib/models/hazard.dart`.

## Ícone da moto
Na tela inicial ("Configurar minha moto") ou no mapa (ícone de moto no topo):
- **Foto** (câmera ou galeria): recortada em círculo e mostrada para todos no mapa.
- **Marca e modelo**: aparecem como texto na etiqueta abaixo do marcador.
- **Estilo e cor**: usados para o ícone genérico quando a pessoa não tem foto.

> Logos e desenhos oficiais das fabricantes são marcas registradas e **não** são usados.
> Para incluí-los seria preciso autorização/licenciamento de cada marca.

## Clube e autorizações
**Cadastro:** a tela "Autorizações" aparece obrigatoriamente no primeiro uso.

| Autorização | Padrão | O que libera |
|---|---|---|
| Compartilhar localização com o comboio | desligada (obrigatória para usar) | posição ao vivo só para a expedição aberta |
| Ser encontrado pelo clube | desligada | nome, cidade base e distância aproximada visíveis ao clube |
| Receber pedidos de ajuda | desligada | notificação com a localização de quem precisa |
| Receber avisos de passagem | desligada | aviso quando um membro passa pela sua cidade |

- A cidade base é arredondada (~1 km) e fica num documento privado (`users/{uid}`). Só as Cloud Functions a leem; outros usuários recebem apenas cidade e distância em km.
- O telefone fica só no celular e é enviado apenas quando a própria pessoa marca "enviar meu telefone".
- Ao revogar "ser encontrado", a cidade é apagada do servidor na hora.
- Limite de 5 avisos por hora por pessoa, para evitar abuso.
- As autorizações ficam registradas com data (`acceptedAt`) e versão. Se mudar o texto, aumente `Consents.currentVersion` para pedir o aceite de novo.

**Clube:** um membro cadastra o clube e recebe um código; os demais entram com o código. Tela inicial → "Clube".

**No mapa:** botão verde-azulado (escudo) → pedir ajuda ao mais próximo / avisar que está passando.

> Recomendado antes de publicar: escrever uma Política de Privacidade e Termos de Uso (exigidos pela Apple e pelo Google) descrevendo esses dados.

## Economia de bateria e dados
A posição é enviada no máximo a cada 10 s e só após 25 m de deslocamento. Ajuste em
`map_screen.dart` (`_sendInterval`) e `location_service.dart` (`distanceFilter`).

## Próximos passos sugeridos
- Mapas offline para áreas sem sinal
- SOS por SMS como alternativa quando não há internet
- Reordenar paradas arrastando; papéis (líder / batedor / cerra-fila)
- Aviso quando alguém se distancia demais do grupo
- Ícones personalizados das motos no mapa
