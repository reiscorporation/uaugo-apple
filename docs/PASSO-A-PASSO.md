# UauGo — passo a passo simples

Atualizado em 19/11/2026. Para detalhes, veja `MANUTENCAO.md` e `ARQUITETURA.md`.

---

## Parte 1 — Compilar o app

Tudo é feito no **PowerShell**, dentro da pasta do projeto:

```powershell
cd E:\APP\comboio
```

### 1. Mudar o número da versão (sempre, antes de publicar)

Abra `E:\APP\comboio\pubspec.yaml` e altere a linha:

```
version: 1.2.22+54
```

- `1.2.22` = nome que o usuário vê.
- `54` = **código da versão**. A Play exige que ele **sempre suba** (54, 55, 56...).
  Um código que já foi usado é recusado ("O código de versão já foi usado").

### 2. Conferir se está tudo certo

```powershell
flutter test
```

Tem que terminar com **All tests passed!**

### 3a. Pacote para a Play Store (.aab)

Passe o nome e o número **também no comando** (assim não sai com o número antigo):

```powershell
flutter build appbundle --release --build-name=1.2.22 --build-number=54
```

O arquivo fica em:

```
E:\APP\comboio\build\app\outputs\bundle\release\app-release.aab
```

> **Importante:** esse arquivo é **sobrescrito** a cada compilação. Copie para
> `C:\UauGo-builds\<versão>\` antes de compilar de novo.

Envie pela Play Console: **Testes → Teste interno → Criar nova versão** → arrastar o `.aab`.
(Usa as rotas do Google. Não use `--dart-define-from-file`, que liga o motor próprio.)

### 3b. APK para instalar direto num celular (sem Play)

```powershell
flutter build apk --release --build-name=1.2.22 --build-number=54
```

Arquivo:

```
E:\APP\comboio\build\app\outputs\flutter-apk\app-release.apk
```

Para instalar com o celular no cabo USB (depuração USB ligada):

```powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

### 3c. Versão de teste "UauGo2" (instala ao lado do app da Play)

```powershell
flutter build apk --debug
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

Aparece no celular como **UauGo2** (pacote `helpaitech.comboio.v2`), com registros de teste.
Nunca envie essa versão para a Play.

### Tamanho

O `.aab` tem ~132 MB, mas o usuário baixa só ~25–30 MB: a Play entrega a cada
celular apenas a parte dele (os símbolos de depuração e as outras arquiteturas
ficam na Play).

---

## Parte 2 — Onde mexer nos problemas mais comuns

Todos os caminhos a partir de `E:\APP\comboio\`. No VS Code: **Ctrl+P** e digite o nome do arquivo;
dentro dele, **Ctrl+F** para procurar o texto indicado.

### Tela do mapa / navegação no celular
| Problema | Arquivo | Procure por |
|---|---|---|
| Botões, posição, tamanho (mapa e 3D) | `lib/screens/map_screen.dart` | `// Botões`, `_carLikeRow`, `_rightColumn` |
| Velocímetro e limite na tela | `lib/screens/map_screen.dart` | `// Velocímetro` |
| Barra de cima (manobra, chegada) | `lib/screens/map_screen.dart` | `_turnTitle` |
| Resumo da viagem | `lib/screens/map_screen.dart` | `_showTripSummary` |
| "Saiu da rota" / recálculo | `lib/screens/map_screen.dart` | `Recalculando` |
| Posição do ícone na rua / GPS pulando | `lib/logic/road_snapper.dart` | — |
| Narração das curvas (frases) | `lib/logic/navigation.dart` | — |
| Voz (volume, vozes, ligar/desligar) | `lib/services/voice_service.dart` | — |

### Rota
| Problema | Arquivo |
|---|---|
| Prévia da rota (opções, pedágio, "Iniciar") | `lib/widgets/trip_preview_sheet.dart` |
| Cálculo da rota (Google) | `lib/services/directions_service.dart` |
| Montagem da viagem / recálculo | `lib/services/trip_service.dart` |

### Avisos
| Problema | Arquivo |
|---|---|
| Radares (dados e frases) | `lib/logic/radars.dart`, `lib/services/radar_service.dart` |
| Limite de velocidade | `lib/logic/speed.dart`, `lib/services/speed_service.dart` |
| Pedágios (valor, cartão) | `lib/logic/tolls.dart`, `lib/services/toll_service.dart` |

### Visão 3D (celular e carro)
| Problema | Arquivo |
|---|---|
| Desenho da estrada, placas, painel do 3D | `assets/sim3d/index.html` |
| Ligação app ↔ 3D | `lib/widgets/sim3d_view.dart` |

### Android Auto (tela do carro)
| Problema | Arquivo |
|---|---|
| Telas e menus do carro (busca, destinos, SOS) | `android/app/src/main/kotlin/helpaitech/comboio/UauGoCarAppService.kt` |
| Mapa do carro (zoom, inclinação, linha da rota, trânsito) | `.../comboio/CarMapView.kt` |
| Botões, velocímetro, avisos amarelos no carro | `.../comboio/CarOverlay.kt` |
| Textos do carro em pt/en/es | `.../comboio/CarTexts.kt` |
| O que o celular manda para o carro | `lib/services/car_service.dart` |

### Outros
| Problema | Arquivo |
|---|---|
| Tela inicial (Casa, Trabalho, Dirigir agora) | `lib/screens/home_screen.dart` |
| Configurações | `lib/screens/settings_screen.dart` |
| Expedição (grupo) | `lib/services/expedition_service.dart` |
| Textos em inglês / espanhol | `lib/l10n/en_*.dart`, `lib/l10n/es_*.dart` |
| Conferir se falta tradução | `python scripts/conferir-idiomas.py` |

### Depois de mexer
1. `flutter test` (tudo verde).
2. Testar no celular com a versão **UauGo2** (Parte 1, 3c).
3. Subir o número da versão e gerar o `.aab` (Parte 1).

### Voltar a uma versão anterior
Cada versão publicada fica no histórico (Git). Ex.: a 1.2.22 é o código da 1.2.20.
Para ver o histórico: `git log --oneline`.
