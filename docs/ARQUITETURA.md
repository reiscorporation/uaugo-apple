# Arquitetura do Comboio

Este documento explica **como o app é organizado e como os dados circulam**,
para quem for dar manutenção. Para o passo a passo de compilar, testar,
publicar e fazer mudanças comuns, veja [MANUTENCAO.md](MANUTENCAO.md).

- **App:** Flutter (Dart), um só código para Android e iPhone.
- **Servidor:** Firebase (Firestore, Storage, Auth anônima, Cloud Functions em
  Node.js, Cloud Messaging).
- **Mapas e rotas:** Google Maps SDK, Directions API e Places API.
- **Dados abertos:** radares e limites (projeto Pardal / OpenStreetMap / ANTT /
  DNIT / DERs), lombadas, postos policiais e pedágios (OpenStreetMap), trechos
  de radar portátil (PRF), previsão do tempo (Open-Meteo).

---

## 1. Visão geral

```
                ┌──────────────────────── celular ─────────────────────────┐
  GPS ─────────►│ LocationService ─► MapScreen (coração do app)             │
                │                      │  ├─ velocímetro / limite da via    │
                │                      │  ├─ radares, lombadas, postos      │
                │                      │  ├─ narração das curvas (voz)      │
                │                      │  ├─ chuva, trânsito, metade        │
                │                      │  └─ gravação da viagem (histórico) │
                │   dados guardados no celular: radares, limites, lombadas, │
                │   histórico, configurações                                 │
                └───────▲───────────────────────┬──────────────────────────┘
                        │ baixa 1x por semana   │ só o que é compartilhado
                        │ (por estado)          ▼ ao vivo
                ┌───────┴──────── Firebase ─────────────────────────────────┐
                │ Storage: public/radares, public/limites/UF, public/pois/UF│
                │ Firestore: expedições, membros, paradas, SOS, alertas,    │
                │            motoclubes, meta (versões dos arquivos)        │
                │ Functions: atualizam os dados toda semana, SOS por push,  │
                │            motoclube, exclusão de dados, limpeza          │
                └───────────────────────────────────────────────────────────┘
```

**Princípio de custo e leveza:** tudo o que dá para ficar no celular fica no
celular (radares, limites, lombadas, histórico, configurações). O Firebase só
guarda o que precisa ser compartilhado ao vivo (expedição em andamento e
alertas da comunidade). Os arquivos de dados são baixados **por estado** e só
quando mudam.

---

## 2. Pastas do projeto

| Pasta | O que tem |
|---|---|
| `lib/` | Código do app (Dart). Detalhado na seção 3. |
| `test/` | Testes automáticos da lógica (rodar com `flutter test`). |
| `functions/` | Cloud Functions (Node.js) que rodam no servidor. Seção 5. |
| `tests/` | Testes das regras de segurança do Firestore (`rules.test.js`). |
| `assets/branding/` | Logos, ícone do app e fotos dos créditos. |
| `scripts/` | Scripts PowerShell de instalação, configuração, teste e execução. |
| `android/`, `ios/` | Projetos nativos gerados pelo Flutter (permissões, chaves). |
| `config/` | `dart_defines.json` com a chave da Directions API (não versionar). |
| `docs/` | Esta documentação e o guia de publicação nas lojas (`lojas.md`). |
| `firestore.rules`, `storage.rules` | Regras de segurança do banco e dos arquivos. |
| `firestore.indexes.json` | Índices e TTL (apagar alertas vencidos sozinho). |
| `config.env` | Chaves e IDs locais (NÃO versionar; modelo em `config.env.example`). |

---

## 3. O app (`lib/`)

O código é dividido em 5 camadas. A regra é: **`logic/` não sabe nada de
tela nem de internet** (é testável), `services/` fala com o mundo de fora,
`screens/` e `widgets/` só montam a tela.

### 3.1 `lib/logic/` — regras puras (sem tela, sem internet)

| Arquivo | Responsabilidade |
|---|---|
| `geo.dart` | Codificar/decodificar o traçado das rotas (formato "encoded polyline" do Google) e simplificar traçados mantendo as curvas. |
| `navigation.dart` | Narração curva a curva (`TurnByTurn`): limpa o texto do Google ("Pegue a saída 210…"), decide quando falar (2 km, ~800 m e na hora) medindo a distância **pela rota**. |
| `simulation.dart` | `RouteWalker`: anda por um traçado por distância (posição, direção) e projeta a moto na rota (quanto já andou, quanto se afastou). Usado na simulação, na narração, nos radares e no limite da via. |
| `radars.dart` | Base de radares fixos e trechos da PRF (`RadarIndex`), regras para saber se um radar está na pista/sentido do piloto e as frases faladas. |
| `speed.dart` | Limites de velocidade (`SpeedLimitIndex`): escolhe o limite **da pista em que o piloto está** (rota ou linha da direção), alertas de excesso (`SpeedAlerter`). |
| `pois.dart` | Lombadas, postos policiais e pedágios (`PoiIndex`), numa grade de ~1 km para consulta rápida. |
| `speech.dart` | Frases faladas comuns ("a 500 metros") e as distâncias dos avisos repetidos (ex.: 1000 m e 500 m). |
| `weather.dart` | Classifica a chuva (fraca, forte, tempestade) e monta a frase. |
| `track.dart` | Grava o caminho percorrido e calcula km, tempo em movimento e velocidades. |
| `costs.dart` | Consumo e gastos: litros/custo estimados, consumo real, formatação em reais. |
| `itinerary.dart` | Agenda do roteiro da expedição (horários de chegada por parada e por dia). |
| `map_style.dart` | Mapa noturno: estilo escuro e cálculo do pôr do sol pela posição. |

### 3.2 `lib/models/` — formatos dos dados

| Arquivo | O que representa |
|---|---|
| `expedition.dart` | Expedição, plano (`TripPlan`), membro, parada (`Stop`), SOS. Converte de/para o Firestore. |
| `trip.dart` | Viagem **sem** expedição (navegação sozinho/simulação). Só no celular. |
| `trip_record.dart` | Viagem gravada em "Minhas viagens" (caminho, estatísticas, gastos). |
| `hazard.dart` | Tipos de alerta da comunidade (polícia, buraco, pipas, área de risco…) e quanto tempo duram. |
| `bike.dart` | Perfil do veículo (moto ou carro): marca, modelo, tipo, cor, foto. |
| `privacy.dart` | Autorizações da LGPD e cidade base (motoclube). |

### 3.3 `lib/services/` — comunicação com o mundo de fora

| Arquivo | O que faz |
|---|---|
| `location_service.dart` | GPS (1 leitura/s; 2 s na economia de bateria), com serviço em primeiro plano no Android. |
| `directions_service.dart` | Rotas do Google (Directions API): traçado detalhado, tempos, manobras, pedágio, alternativas (mais curta / evitar áreas de risco), trânsito. |
| `places_service.dart` | Busca de lugares por nome (Places API). |
| `trip_service.dart` | Monta uma `Trip` (rota sozinho) e recalcula a partir da posição atual. |
| `expedition_service.dart` | Expedição no Firestore: criar, entrar, membros, paradas, SOS, posição, encerrar. |
| `hazard_service.dart` | Alertas da comunidade no Firestore (células de ~11 km para não baixar o país todo). |
| `radar_service.dart` | Baixa e guarda a base de radares (Storage → celular). |
| `speed_service.dart` | Baixa por estado os limites de velocidade; configurações do alerta de velocidade. |
| `poi_service.dart` | Baixa por estado lombadas, postos e pedágios. |
| `weather_service.dart` | Previsão de chuva em vários pontos de uma vez (Open-Meteo). |
| `voice_service.dart` | Voz (texto para fala), fila de frases, abaixa a música, modo rápido da simulação. |
| `notification_service.dart` | Push (Firebase Messaging) e notificações locais. |
| `history_service.dart` | "Minhas viagens": arquivo `viagens.json` no celular. |
| `app_settings.dart` | Todas as configurações do app (tela, rotas, avisos, consumo, bateria), guardadas no celular. |
| `battery_service.dart` | Decide se liga a economia de bateria (nível, carregando, modo do sistema). |
| `simulated_drive.dart` | "GPS de mentira" da simulação (acelera/freia pelo limite da via). |
| `profile_service.dart` | Perfil do veículo no celular e foto no Storage. |
| `user_service.dart` | Autorizações, cidade base, motoclube, exclusão de dados (LGPD). |
| `club_service.dart` | Motoclube (Cloud Functions de membros próximos e avisos). |
| `auth_service.dart` | Login anônimo no Firebase. |

### 3.4 `lib/screens/` — telas

| Arquivo | Tela |
|---|---|
| `startup_gate.dart` | Primeira tela: manda para as autorizações (1º uso) ou para o início. |
| `consent_screen.dart` | Autorizações (LGPD). |
| `home_screen.dart` | Início: "Para onde?", "Só dirigir", expedições, motoclube, histórico. |
| `map_screen.dart` | **Mapa/navegação** — o coração do app (detalhado na seção 4). |
| `plan_screen.dart` | Roteiro da expedição (paradas, horários, opções de rota, simular). |
| `history_screen.dart` | "Minhas viagens" e o detalhe de cada viagem (gastos, compartilhar). |
| `settings_screen.dart` | Configurações e "Usar sem internet". |
| `profile_screen.dart` | "Minha moto / Meu carro" e consumo. |
| `club_screen.dart` | Motoclube. |
| `about_screen.dart` | Sobre: autoria (Ricardo Reis / HelpAITech) e créditos das fontes. |

### 3.5 `lib/widgets/` — peças de tela reaproveitadas

`speedometer.dart` (velocímetro com a placa do limite), `place_search.dart`
(busca de lugar), `trip_preview_sheet.dart` (prévia da rota: tempo, custo,
pedágio, riscos, Simular/Iniciar), `trip_share.dart` (imagem e GPX para redes
sociais), `trip_expenses.dart` (gastos da viagem), `bike_marker.dart` e
`emoji_marker.dart` (ícones no mapa), `club_nearby_sheet.dart` (motoclube).

---

## 4. A tela do mapa (`map_screen.dart`) passo a passo

É a maior tela porque concentra a navegação. Ela tem **3 modos**:

| Modo | Como abre | O que muda |
|---|---|---|
| Expedição | `MapScreen(code: 'ABC123', …)` | Envia a posição ao grupo (1x/min), SOS para o grupo, membros no mapa. |
| Sozinho ("Para onde?" / "Só dirigir") | `MapScreen(trip: …)` ou sem `trip` | Nada vai para o Firebase; recalcula a rota ao sair dela; trânsito ao vivo. |
| Simulação | `MapScreen(trip: …, simulate: true)` | GPS de mentira; nada é enviado; voz em modo rápido. |

**A cada leitura do GPS (`_onPosition`)**, nesta ordem:

1. Guarda a posição e calcula **uma vez** onde a moto está na rota (`_proj`).
2. `_updateSpeed`: velocidade, **limite da via** (só pontos da pista da rota) e
   aviso de **velocidade reduzida à frente**.
3. `_checkPois`: lombadas, postos policiais e pedágios à frente.
4. `_checkHalfway`: aviso de metade do trajeto.
5. Câmera (`_updateCamera`): de cima (Comboio) ou primeira pessoa (Solo).
6. Gravação do caminho para o histórico.
7. Envio da posição ao grupo (só expedição, no máximo 1x/min).
8. Alertas da comunidade, radares (`_checkRadars`) e narração (`_narrate`).

**Temporizadores:** chuva (5 min), trânsito (5 min, só sozinho e com a opção
ligada), salvamento do histórico (2 min), atualização dos textos (30 s),
bateria (2 min).

**Economia de bateria:** com a tela apagada ou o app minimizado
(`didChangeAppLifecycleState`), a tela não é redesenhada, mas voz, avisos e
gravação continuam. No modo econômico, o GPS lê a cada 2 s e o mapa fica sem
prédios 3D e sem trânsito.

---

## 5. Servidor (`functions/` — Cloud Functions, região `southamerica-east1`)

| Função | Quando roda | O que faz |
|---|---|---|
| `updateRadars` | Segunda e quinta 05:00 | Baixa radares (Pardal), junta duplicados (prefere fonte oficial), trechos da PRF; grava `public/radares.json.gz`. Arquivo: `radars.js`. |
| `updateSpeedLimits` | Segunda 05:30 | Limites de velocidade por estado → `public/limites/UF.json.gz`. Arquivo: `speedlimits.js`. |
| `updatePois` | Todo dia 04:10 | Lombadas, postos policiais rodoviários e pedágios (OpenStreetMap/Overpass) → `public/pois/UF.json.gz`. Refaz cada estado a cada 6 dias. Arquivo: `pois.js`. |
| `onSos` | Ao criar um SOS | Push para todo o grupo. |
| `onStop` | Ao criar uma parada | Push para o grupo. |
| `endExpedition` | Chamada pelo líder | Apaga a expedição inteira do servidor. |
| `clubNearby`, `clubNotify` | Chamadas pelo app | Motoclube: membros próximos (sem revelar a posição exata) e avisos. |
| `deleteMyData` | Chamada pelo app | Exclusão de dados (LGPD). |
| `cleanup` | Todo dia 04:00 | Apaga expedições paradas há 30 dias e avisos antigos do motoclube. |

Os índices `meta/limits`, `meta/pois` e `meta/radars` no Firestore guardam a
**versão** de cada arquivo; o app só baixa de novo quando a versão muda.

---

## 6. Banco de dados (Firestore)

| Coleção | Conteúdo | Quem lê/escreve |
|---|---|---|
| `expeditions/{código}` | Nome, líder, plano (rota). Subcoleções `members`, `stops`, `alerts` (SOS). | Membros da expedição. Apagada pelo líder ou após 30 dias. |
| `hazards/{id}` | Alertas da comunidade (tipo, posição, célula, votos, validade). | Todos os usuários logados. **TTL** em `expiresAt`: o Firebase apaga sozinho quando vence. |
| `users/{uid}` | Autorizações e cidade base (motoclube). Privado. | Só o dono (e as Functions). |
| `clubs/{id}` | Motoclubes e membros. | Membros do clube. |
| `meta/{doc}` | Versões dos arquivos públicos. | Leitura para logados; escrita só pelas Functions. |

As regras estão em `firestore.rules` e são testadas por `tests/rules.test.js`.

---

## 7. O que fica guardado no celular

| O quê | Onde |
|---|---|
| Configurações | `SharedPreferences` (`AppSettings`, `SpeedService`, `VoiceService`) |
| Perfil do veículo, autorizações | `SharedPreferences` (`ProfileService`, `UserService`) |
| Radares, limites, lombadas/postos/pedágios | Pasta de suporte do app (`radares*.json.gz`, `limites_UF.json.gz`, `pois_UF.json.gz`) |
| Histórico ("Minhas viagens") | `viagens.json` na pasta de suporte |
| Expedição em andamento | Cache offline do Firestore |

> Desinstalar o app apaga tudo isso. O histórico não vai para a nuvem (decisão
> de custo e privacidade).

---

## 8. Fontes de dados e licenças

| Dado | Fonte | Licença / observação |
|---|---|---|
| Mapa, rotas, lugares | Google Maps Platform | Pago por uso; mapa não pode ser baixado (termos do Google). |
| Radares e limites | Projeto Pardal (ANTT, DNIT, DERs, prefeituras, OpenStreetMap) | ODbL — exige crédito (tela Sobre). |
| Lombadas, postos, pedágios | OpenStreetMap via Overpass API | ODbL — exige crédito. Overpass é gratuito com uso moderado. |
| Radar portátil | PRF (lista oficial) + DNIT/SNV | Dados públicos. |
| Chuva | Open-Meteo | Grátis **para uso não comercial**; uso comercial exige plano pago. |
| Áreas de risco | Reportes dos próprios usuários | Não existe base pública nacional de assaltos. |
