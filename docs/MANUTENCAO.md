# Guia de manutenção do Comboio

Passo a passo para quem vai mexer no código. Para entender a organização do
app, leia antes [ARQUITETURA.md](ARQUITETURA.md).

---

## 1. Onde está o código

- **Pasta do projeto:** `E:\APP\comboio` (neste computador).
- **Histórico de versões:** o projeto usa Git (pasta `.git`). Cada backup
  registra uma "foto" do código; dá para ver e voltar a qualquer versão.
- **Backup no Google Drive da HelpAITech:** rode `.\scripts\backup.ps1`. Ele
  registra as mudanças e copia para `Meu Drive\HelpAITech\Comboio\backup`:
  `comboio-historico.bundle` (todas as versões) e um `.zip` do código atual.
  **Restaurar:** `git clone comboio-historico.bundle comboio`.
- As chaves (`config.env`, `config/dart_defines.json`, `functions/.env`) não
  entram no histórico. Para guardá-las também: `.\scripts\backup.ps1 -IncluirChaves`
  (só em pasta do Drive restrita).
- **Chave de assinatura da Play Store** (quando for criada): guarde à parte, com
  a senha, em local seguro. Sem ela não é possível atualizar o app na loja.

## 2. Ferramentas

Tudo é instalado por `scripts\instalar.ps1`: Flutter, Android Studio (SDK e
emulador), Node.js, Firebase CLI, Google Cloud CLI e Git.

| Ferramenta | Para quê |
|---|---|
| Flutter / Dart | Compilar e testar o app |
| Android Studio | SDK Android e emulador |
| Node.js + Firebase CLI | Cloud Functions, regras e emuladores do Firebase |
| VS Code ou Android Studio | Editar o código (instale a extensão "Flutter") |

## 3. Comandos do dia a dia

Na pasta `E:\APP\comboio`, no PowerShell:

```powershell
.\scripts\rodar.ps1          # instala e abre no celular conectado (USB)
.\scripts\testar.ps1         # análise do código + testes do app + regras
.\scripts\testar-local.ps1   # app no emulador usando o Firebase local
.\scripts\simular-viagem.ps1 # GPS andando no emulador
```

Comandos diretos do Flutter:

```powershell
flutter analyze                     # procura erros e más práticas
flutter test                        # roda os testes de test/
flutter build apk --release --dart-define-from-file=config/dart_defines.json
flutter build appbundle --release --dart-define-from-file=config/dart_defines.json  # Play Store
```

> No Windows, se `flutter test` travar, rode um arquivo por vez:
> `flutter test test/speed_test.dart`.

## 4. Publicar mudanças no servidor

```powershell
firebase deploy --only functions --project helpaitechcomboio        # todas as funções
firebase deploy --only functions:updatePois --project helpaitechcomboio  # só uma
firebase deploy --only firestore:rules,storage --project helpaitechcomboio
```

As funções agendadas (radares, limites, lombadas) rodam sozinhas. Para forçar
uma execução agora: Console do Google Cloud → Cloud Scheduler → a tarefa →
"Forçar execução".

## 5. Receitas de mudanças comuns

### Adicionar um tipo de alerta da comunidade (ex.: "Obra na pista")
1. `lib/models/hazard.dart`: inclua o tipo no `enum HazardType` (nome, emoji,
   cor, duração, distância do aviso, frase falada).
2. `firestore.rules`: inclua o nome na lista `type in [...]` de `hazards`.
3. Rode os testes e publique as regras (`firestore:rules`).

### Mudar distâncias e padrões dos avisos
- Padrões das opções: `lib/services/app_settings.dart` (`AlertPrefs`).
- Distâncias da narração das curvas: `lib/logic/navigation.dart`
  (`updateAlong`: `nearAt`, `farAt`, aviso de 2 km das saídas).
- Radares: `lib/screens/map_screen.dart` → `_checkRadars`.

### Adicionar uma configuração nova
1. `lib/services/app_settings.dart`: o campo, a leitura em `load()` e o
   método `set…` que salva.
2. `lib/screens/settings_screen.dart`: o interruptor/opção na tela.
3. Use o valor onde precisar com `AppSettings.instance.<campo>.value`.

### Trocar cores, logo e ícone
- Cor da rota: `MapScreen.routeBlue` / `routeBorder` (`map_screen.dart`).
- Cores do app: `lib/main.dart` (`seedColor`).
- Logo/ícone: substitua os PNG em `assets/branding/` (1024×1024) e rode
  `dart run flutter_launcher_icons`.

### Mudar a lógica do limite de velocidade
`lib/logic/speed.dart` → `SpeedLimitIndex.lookup`. Os testes em
`test/speed_test.dart` cobrem a pista principal x marginal; rode-os depois.

### Nova fonte de dados por estado (como lombadas)
Siga o modelo de `functions/pois.js` (servidor) + `lib/services/poi_service.dart`
(baixa e guarda por estado) + `lib/logic/pois.dart` (índice rápido).

## 6. Testes

| Arquivo | O que testa |
|---|---|
| `test/navigation_test.dart` | Narração: limpeza do texto do Google, saídas, avisos pela rota |
| `test/speed_test.dart` | Limite da via (pista x marginal), alertas de velocidade |
| `test/radars_test.dart` | Radar na pista/sentido certo, frases |
| `test/simulation_test.dart` | Andar pela rota e projeção da moto |
| `test/pois_weather_test.dart` | Lombadas/postos e chuva |
| `test/costs_theme_test.dart` | Gastos, consumo, pôr do sol, pedágio |
| `test/track_test.dart` | Gravação do caminho e histórico |
| `test/itinerary_test.dart`, `models_test.dart`, `geo_test.dart`, `speech_test.dart` | Agenda, modelos, traçados, frases |
| `tests/rules.test.js` | Regras de segurança do Firestore |

**Regra de ouro:** ao mudar algo em `lib/logic/`, rode o teste correspondente.

## 6.1 Login e documentos legais

- **Provedores de login** (Firebase → Authentication → Sign-in method):
  anônimo e e-mail/senha ativos; **Google** precisa ser ativado no console;
  **Apple** depois da conta Apple Developer (o botão só aparece no iPhone).
- **Google no Android** exige a impressão digital (SHA-1/SHA-256) de cada
  chave que assina o app: a de teste já está cadastrada; ao criar a chave da
  Play Store, cadastre a dela também e baixe de novo o `google-services.json`.
- **Termos de Uso / Política de Privacidade:** textos em `assets/legal/`.
  Mudou algo relevante? Aumente `TermsService.version` (terms_screen.dart):
  todos aceitam de novo.
- **Funções chamadas pelo app** (`deleteMyData`, `endExpedition`,
  `clubNearby`, `clubNotify`) precisam da permissão pública de chamada
  (Cloud Run → `roles/run.invoker` para `allUsers`); cada uma confere por
  dentro quem chamou. Se uma função nova recusar chamadas ("not authorized to
  invoke"), rode:
  `gcloud run services add-iam-policy-binding NOME --region southamerica-east1 --member=allUsers --role=roles/run.invoker`

## 7. Problemas conhecidos

| Problema | Solução |
|---|---|
| Emulador lento ou fecha sozinho | Usar o emulador "Comboio_Leve" com `-gpu host` (driver NVIDIA 553+). |
| GPS do emulador não anda | Emulador → ⋯ → Location → Routes → Play route. |
| Disco C: cheio | Cache do Gradle e emuladores estão em `E:\DevCache` (variáveis `GRADLE_USER_HOME` e `ANDROID_AVD_HOME`). |
| Função de lombadas falhou em um estado | O Overpass às vezes fica ocupado (HTTP 504); a função tenta de novo no dia seguinte. |
| Alerta sumiu do mapa | Normal: cada tipo tem validade (polícia 1 h). O Firebase apaga os vencidos (TTL). |
| iPhone | Precisa de Mac com Xcode ou serviço de build na nuvem (Codemagic) e conta Apple Developer. |

## 8. Custos (resumo)

- **Google:** rotas (Directions) e busca (Places) são pagas por consulta; o
  mapa em si é gratuito no app. Trânsito ao vivo custa mais por consulta.
- **Firebase:** quase tudo cabe no plano gratuito; o histórico fica no celular
  justamente para não gastar.
- **Open-Meteo:** grátis só para uso não comercial.

## 9. Convenções do código

- Comentários e textos em **português**.
- `logic/` = funções puras (testáveis), sem tela e sem internet.
- Toda função que roda a cada leitura do GPS deve ser leve (índices em grade,
  nada de percorrer listas inteiras).
- Antes de entregar: `flutter analyze` sem erros novos e testes passando.
