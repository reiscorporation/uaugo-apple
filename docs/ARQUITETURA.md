# Arquitetura do UauGo (padrão TOGAF)

Este documento descreve a arquitetura do UauGo seguindo o **TOGAF**
(The Open Group Architecture Framework), organizado pelas fases do seu
método, o **ADM** (Architecture Development Method). Ele é atualizado **a
cada mudança no app** (ver [Fase H](#fase-h--gestão-de-mudanças-da-arquitetura)).

Para compilar, testar, publicar e fazer mudanças comuns, veja
[MANUTENCAO.md](MANUTENCAO.md).

| Item | Valor |
|---|---|
| Sistema | UauGo — navegação e viagens em grupo de moto e carro |
| Responsável | Ricardo Reis — HelpAITech (helpaitech.ricardo@gmail.com) |
| Versão do documento | 2.0 (2026-10-06) |
| Projeto Firebase | `helpaitechcomboio` (região `southamerica-east1`) |

**Mapa do documento (fases do ADM):**

| Fase TOGAF | Seção |
|---|---|
| Preliminar | [Princípios de arquitetura](#fase-preliminar--princípios-de-arquitetura) |
| A — Visão | [Visão da arquitetura](#fase-a--visão-da-arquitetura) |
| B — Negócio | [Arquitetura de negócio](#fase-b--arquitetura-de-negócio) |
| C — Sistemas de informação | [Dados](#fase-c1--arquitetura-de-dados) e [Aplicação](#fase-c2--arquitetura-de-aplicação) |
| D — Tecnologia | [Arquitetura de tecnologia](#fase-d--arquitetura-de-tecnologia) |
| Transversal | [Arquitetura de segurança](#arquitetura-de-segurança-transversal) |
| E/F — Oportunidades e migração | [Roteiro](#fases-e-e-f--oportunidades-soluções-e-plano-de-migração) |
| G — Governança | [Governança da implementação](#fase-g--governança-da-implementação) |
| H — Mudanças | [Registro de mudanças](#fase-h--gestão-de-mudanças-da-arquitetura) |
| Requisitos | [Requisitos e decisões (ADRs)](#gestão-de-requisitos-e-decisões-de-arquitetura-adrs) |

---

## Fase Preliminar — Princípios de arquitetura

Regras que orientam **todas** as decisões. Uma mudança que contrarie um
princípio precisa de um ADR (decisão registrada) explicando o motivo.

| # | Princípio | O que significa na prática |
|---|---|---|
| P1 | **Leveza no celular** | O app tem que rodar bem em celulares simples: índices em grade, cálculos uma vez por leitura do GPS, tela não redesenha minimizada, dados baixados por estado. |
| P2 | **Celular primeiro (dados locais)** | Tudo o que não precisa ser compartilhado fica no celular (histórico, configurações, radares). O servidor guarda só o que é compartilhado ao vivo. |
| P3 | **Custo mínimo** | Downloads só quando a versão muda; rotas da expedição calculadas uma vez e gravadas; limites diários por usuário nas APIs pagas. |
| P4 | **Privacidade (LGPD)** | Coleta mínima, autorização explícita, exclusão de dados pelo próprio usuário, prazos de retenção curtos. Coordenadas nunca vão para o clube. |
| P5 | **Segurança por padrão** | Nenhuma chave paga dentro do app; toda escrita validada pelas regras do servidor; conta de verdade para tudo que é compartilhado; só o app legítimo acessa o backend (App Check). |
| P6 | **Funciona sem sinal** | Estrada tem trechos sem internet: escritas entram na fila do Firestore; navegação, radares e limites funcionam offline. |
| P7 | **Simples de manter** | Código comentado em português, camadas claras, testes automáticos para a lógica e para as regras de segurança. |

---

## Fase A — Visão da arquitetura

**Propósito.** Um app para quem viaja em grupo de moto ou carro: ver o grupo
no mapa, seguir o mesmo roteiro, receber avisos (radares, lombadas, limite da
via, chuva, alertas da comunidade) e pedir ajuda (SOS). Também navega sozinho.

**Partes interessadas.**

| Parte | Interesse |
|---|---|
| Piloto/motorista | Navegação segura, avisos por voz, app leve, privacidade. |
| Líder da expedição | Montar roteiro, acompanhar o grupo, encerrar a viagem. |
| Administrador do clube | Ativar o clube (código de ativação da HelpAITech, um por pessoa), convidar e remover membros, promover outros administradores. |
| Membro do clube | Encontrar e avisar membros próximos sem expor a posição. |
| HelpAITech (dona) | Custo baixo, conformidade (LGPD, lojas), marca, manutenção simples. |
| Lojas (Google/Apple) | Política de privacidade, exclusão de conta, permissões justificadas. |
| Provedores de dados | Créditos e licenças (OpenStreetMap/ODbL, Pardal, Open-Meteo). |

**Escopo.** App Android e iPhone (Flutter), backend Firebase. Fora do escopo:
versão web, mapas offline do Google (proibido pelos termos), base pública de
crimes (não existe).

**Restrições.** Orçamento pequeno (plano Blaze pago por uso); desenvolvedor
pessoa física. Nome do app: **UauGo** (antes "Convoyar", "RodaJunto" e "Comboio"); o identificador interno `helpaitech.comboio`, o projeto Firebase e os nomes das chaves continuam com "comboio" (não aparecem para o usuário e não podem mudar depois de publicar).

---

## Fase B — Arquitetura de negócio

**Atores:** usuário anônimo (só navega sozinho), usuário com conta (Google,
Apple ou e-mail), líder, membro, administrador de clube, membro de clube, HelpAITech (emite códigos de ativação), servidor (rotinas). "Clube" serve para qualquer tipo de grupo (motoclube, jipeiros, carros antigos...).

**Capacidades e processos principais.**

| Capacidade | Processo | Exige conta? |
|---|---|---|
| Aceite dos termos | 1º uso: Termos (rolar até o fim) → autorizações → início. Registro em `users/{uid}.terms`. | Não |
| Navegar sozinho | "Para onde?" → prévia (tempo, custo, pedágio, riscos) → navegar/simular. | Não |
| Expedição | Líder cria (código de 8 caracteres) → monta roteiro → membros entram pelo código → posições ao vivo → líder encerra (apaga tudo do servidor). | **Sim** |
| SOS | Membro aciona → push para o grupo → qualquer membro marca "resolvido". | **Sim** |
| Alertas da comunidade | Reportar (polícia, buraco…) → outros confirmam/descartam (1 voto por pessoa) → some ao vencer. | **Sim** para criar/votar; ver é livre |
| Clube oficial | HelpAITech pré-cadastra clubes conhecidos (`scripts/criar-clubes.js`, invisíveis até a ativação) e gera um código de ativação por administrador (`scripts/gerar-codigos-clube.js --clube ID`) → o administrador ativa → gera **convites de uso único** (7 dias) → cada membro entra com o seu → administradores removem membros e promovem/rebaixam administradores (nunca fica sem nenhum) → ver membros (cidade, nunca coordenadas) → pedir ajuda/avisar (só a quem autorizou). | **Sim** |
| Histórico | Gravação da viagem no celular → "Minhas viagens" → compartilhar imagem/GPX. | Não |
| Exclusão de dados | Configurações → "Excluir meus dados" (função `deleteMyData`). | Não |

---

## Fase C1 — Arquitetura de dados

### Visão geral do fluxo

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
                        │ baixa só quando muda  │ só o que é compartilhado
                        │ (por estado)          ▼ ao vivo + rotas/lugares
                ┌───────┴──────── Firebase ─────────────────────────────────┐
                │ Storage: public/radares, public/limites/UF, public/pois/UF│
                │          bikes/{uid}/ (fotos, até 2 MB)                   │
                │ Firestore: expedições, membros, paradas, SOS, alertas,    │
                │            votos, clubes, meta, usage                 │
                │ Functions: rotas/lugares (chave do Google), dados abertos,│
                │            SOS por push, clube, exclusão, limpeza     │
                └───────────────────────────────────────────────────────────┘
```

### Firestore (servidor)

| Coleção | Conteúdo | Quem lê/escreve | Retenção |
|---|---|---|---|
| `expeditions/{código}` | Nome, líder, plano (rota). | Com conta e código: lê. Só o líder altera. | Apagada pelo líder ou após 30 dias parada. |
| `…/members/{uid}` | Nome, veículo (foto só do Storage do app), posição, velocidade. | Membros leem; cada um escreve só o seu (campos e tamanhos validados). | Com a expedição. |
| `…/stops/{id}` | Paradas do roteiro, trechos e manobras. | Membros leem; só o líder escreve. | Com a expedição. |
| `…/alerts/{id}` | SOS (quem, onde, resolvido). | Membro cria em nome próprio; outros só marcam "resolvido". | Com a expedição. |
| `hazards/{id}` | Alertas da comunidade (tipo, posição, célula, contagens, validade). | Todos leem; com conta cria; votos só pelo processo de voto. | **TTL** em `expiresAt`. |
| `hazards/{id}/votes/{uid}` | Voto da pessoa (confirma/descarta). Garante 1 voto por pessoa. | Cada um vê só o seu; não muda nem apaga. | **TTL** em `expiresAt` (7 dias). |
| `users/{uid}` | Aceite dos termos, autorizações, cidade base, token de push. Privado. | Só o dono (e as Functions). | Até a exclusão de dados. |
| `clubs/{id}` + `members` | Clube: nome, UF, situação (`reserved` = pré-cadastrado, `active`), administradores (`admins`); membros com nome, cidade, veículo, papel (`admin`/`member`) e quem convidou. | Só membros leem (clube reservado é invisível). Ativar, entrar e mudar administradores: **só o servidor**. Cada um muda nome/cidade/veículo; administradores removem membros (não administradores). Nunca coordenadas. | Avisos: 180 dias. |
| `clubActivations/{código}` | Códigos de ativação emitidos pela HelpAITech (situação, anotação, clube criado). | Só o servidor e o script da HelpAITech. | Permanente (registro). |
| `clubInvites/{código}` | Convites de uso único (clube, quem gerou, quem usou, validade). | Só o servidor. | **TTL**: 7 dias. |
| `meta/{doc}` | Versão dos arquivos públicos. | Logados leem; só as Functions escrevem. | — |
| `usage/{uid}` | Contagem diária de consultas de rotas/lugares e de códigos de clube errados. | Só as Functions. | Sobrescrito a cada dia. |

As regras estão em `firestore.rules` e são testadas em `tests/rules/rules.test.js`
(57 testes).

### Storage (servidor)

| Caminho | Conteúdo | Regras |
|---|---|---|
| `public/radares.json.gz`, `public/limites/UF.json.gz`, `public/pois/UF.json.gz` | Dados abertos processados. | Logados leem; só as Functions escrevem. |
| `bikes/{uid}/{arquivo}` | Foto do veículo. | Logados leem; só o dono envia; até 2 MB; só JPEG/PNG/WebP. |

### Dados no celular

| O quê | Onde |
|---|---|
| Configurações | `SharedPreferences` (`AppSettings`, `SpeedService`, `VoiceService`) |
| Perfil do veículo, autorizações | `SharedPreferences` (`ProfileService`, `UserService`) |
| Radares, limites, lombadas/postos/pedágios | Pasta de suporte do app (`radares*.json.gz`, `limites_UF.json.gz`, `pois_UF.json.gz`) |
| Histórico ("Minhas viagens") | `viagens.json` na pasta de suporte |
| Expedição em andamento | Cache offline do Firestore |

> Desinstalar o app apaga tudo isso. O histórico não vai para a nuvem (ADR-02).

### Fontes de dados e licenças

| Dado | Fonte | Licença / observação |
|---|---|---|
| Mapa, rotas, lugares | Google Maps Platform | Pago por uso; mapa não pode ser baixado (termos do Google). |
| Radares e limites | Projeto Pardal (ANTT, DNIT, DERs, prefeituras, OpenStreetMap) | ODbL — exige crédito (tela Sobre). |
| Lombadas, postos, pedágios | OpenStreetMap via Overpass API | ODbL — exige crédito. Overpass é gratuito com uso moderado. |
| Radar portátil | PRF (lista oficial) + DNIT/SNV | Dados públicos. |
| Chuva | Open-Meteo | Grátis **para uso não comercial**; uso comercial exige plano pago. |
| Áreas de risco | Reportes dos próprios usuários | Não existe base pública nacional de assaltos. |

---

## Fase C2 — Arquitetura de aplicação

### Pastas do projeto

| Pasta | O que tem |
|---|---|
| `lib/` | Código do app (Dart), detalhado abaixo. |
| `test/` | Testes automáticos da lógica (`flutter test`, 103 testes). |
| `functions/` | Cloud Functions (Node.js) que rodam no servidor. |
| `tests/rules/` | Testes das regras de segurança do Firestore. |
| `assets/branding/`, `assets/legal/` | Logos, ícone, créditos; Termos e Política. |
| `scripts/` | Scripts PowerShell de instalação, configuração, teste e execução. |
| `android/`, `ios/` | Projetos nativos (permissões, chave do mapa). |
| `config/` | `dart_defines.json` (vazio: nenhuma chave paga vai no app). |
| `docs/` | Esta documentação, manutenção, lojas, termos e política. |
| `firestore.rules`, `storage.rules` | Regras de segurança do banco e dos arquivos. |
| `firestore.indexes.json` | Índices e TTL. |
| `config.env`, `functions/.env` | Chaves locais (NÃO versionar; modelo em `config.env.example`). |

### App (`lib/`) em camadas

**`logic/` não sabe nada de tela nem de internet** (é testável),
`services/` fala com o mundo de fora, `screens/` e `widgets/` montam a tela.

#### `lib/logic/` — regras puras

| Arquivo | Responsabilidade |
|---|---|
| `geo.dart` | Codificar/decodificar o traçado das rotas ("encoded polyline"), simplificar traçados, regra de remoção de alerta por votos. |
| `navigation.dart` | Narração curva a curva (`TurnByTurn`): limpa o texto do Google, decide quando falar (2 km, ~800 m e na hora) medindo **pela rota**. |
| `simulation.dart` | `RouteWalker`: anda por um traçado e projeta a moto na rota. Usado na simulação, narração, radares e limite da via. |
| `radars.dart` | Radares fixos e trechos da PRF (`RadarIndex`), pista/sentido, frases faladas. |
| `speed.dart` | Limites de velocidade (`SpeedLimitIndex`) da pista do piloto, alertas de excesso (`SpeedAlerter`). |
| `pois.dart` | Lombadas, postos policiais e pedágios (`PoiIndex`), grade de ~1 km. |
| `speech.dart` | Frases comuns e distâncias dos avisos repetidos. |
| `weather.dart` | Classifica a chuva e monta a frase. |
| `track.dart` | Grava o caminho e calcula km, tempo e velocidades. |
| `costs.dart` | Consumo e gastos. |
| `itinerary.dart` | Agenda do roteiro (horários por parada e por dia). |
| `map_style.dart` | Mapa noturno e pôr do sol. |

#### `lib/models/` — formatos dos dados

| Arquivo | O que representa |
|---|---|
| `expedition.dart` | Expedição, plano (`TripPlan`), membro, parada (`Stop`), SOS. |
| `trip.dart` | Viagem **sem** expedição. Só no celular. |
| `trip_record.dart` | Viagem gravada em "Minhas viagens". |
| `hazard.dart` | Tipos de alerta da comunidade e quanto duram. |
| `bike.dart` | Perfil do veículo. `safePhotoUrl` descarta fotos fora do Storage do app. |
| `privacy.dart` | Autorizações da LGPD e cidade base. |

#### `lib/services/` — comunicação com o mundo de fora

| Arquivo | O que faz |
|---|---|
| `location_service.dart` | GPS (1 leitura/s; 2 s na economia de bateria), serviço em primeiro plano no Android. |
| `directions_service.dart` | Rotas pela **função `directions`** do servidor: traçado, tempos, manobras, pedágio, alternativas, trânsito. |
| `places_service.dart` | Busca de lugares pela **função `places`** do servidor (sessões para baratear). |
| `trip_service.dart` | Monta uma `Trip` e recalcula a partir da posição atual. |
| `expedition_service.dart` | Expedição: criar (código de 8), entrar, membros, paradas, SOS, posição, encerrar. |
| `hazard_service.dart` | Alertas da comunidade (células de ~11 km); voto em lote (voto + contagem). |
| `radar_service.dart`, `speed_service.dart`, `poi_service.dart` | Baixam e guardam os dados abertos por estado. |
| `weather_service.dart` | Previsão de chuva (Open-Meteo). |
| `voice_service.dart` | Voz, fila de frases, abaixa a música. |
| `notification_service.dart` | Push e notificações locais. |
| `history_service.dart` | "Minhas viagens" (`viagens.json`). |
| `app_settings.dart`, `battery_service.dart` | Configurações e economia de bateria. |
| `simulated_drive.dart` | GPS de mentira da simulação. |
| `profile_service.dart` | Perfil do veículo e foto no Storage. |
| `user_service.dart` | Autorizações, cidade base, exclusão de dados. |
| `voice_command_service.dart` | Comandos de voz (opcional): baixa o modelo, pede o microfone, ouve com o mapa aberto e pausa enquanto o app fala. Frases em `logic/voice_commands.dart`. |
| `club_service.dart` | Clube oficial: criar com código de ativação, convites, entrar, remover membro (pelas funções `createClub`, `createClubInvite`, `joinClub`). |
| `auth_service.dart` | Conta anônima **vinculada** (mesmo uid) a Google, Apple ou e-mail; renova o token após vincular. |

#### `lib/screens/` e `lib/widgets/`

| Tela | Função |
|---|---|
| `startup_gate.dart` | Termos → autorizações → início. |
| `terms_screen.dart` | Termos e Política; aceite após rolar até o fim; registro do aceite. |
| `login_screen.dart` | Entrar/criar conta; `requireAccount` para expedição, alertas e clube. |
| `consent_screen.dart` | Autorizações (LGPD). |
| `home_screen.dart` | Início: "Para onde?", "Só dirigir", expedições, clube, histórico. |
| `map_screen.dart` | **Mapa/navegação** (abaixo). |
| `plan_screen.dart` | Roteiro da expedição. |
| `history_screen.dart` | "Minhas viagens". |
| `settings_screen.dart` | Configurações, conta, uso sem internet. |
| `profile_screen.dart` | Veículo e consumo. |
| `club_screen.dart` | Clube: entrar com convite, ativar como administrador, convidar, remover membros, promover/rebaixar administradores. |
| `about_screen.dart` | Autoria e créditos. |

Widgets: `speedometer.dart`, `place_search.dart`, `trip_preview_sheet.dart`
(prévia, paradas, trocar saída), `trip_share.dart`, `trip_expenses.dart`,
`bike_marker.dart` (foto só do Storage do app, até 2 MB), `emoji_marker.dart`,
`club_nearby_sheet.dart`.

### A tela do mapa (`map_screen.dart`)

| Modo | Como abre | O que muda |
|---|---|---|
| Expedição | `MapScreen(code: …)` | Envia a posição ao grupo (1x/min), SOS, membros no mapa. |
| Sozinho | `MapScreen(trip: …)` ou sem `trip` | Nada vai para o Firestore; recalcula ao sair da rota; trânsito ao vivo. |
| Simulação | `MapScreen(trip: …, simulate: true)` | GPS de mentira; nada é enviado; voz em modo rápido. |

**A cada leitura do GPS (`_onPosition`)**, nesta ordem: posição na rota
(`_proj`, calculada uma vez) → velocidade e limite da via → lombadas, postos e
pedágios → aviso de metade → câmera → gravação do caminho → envio ao grupo
(só expedição, máx. 1x/min) → alertas, radares e narração.

**Temporizadores:** chuva (5 min), trânsito (5 min), salvamento do histórico
(2 min), textos (30 s), bateria (2 min). Minimizado, a tela não redesenha, mas
voz, avisos e gravação continuam.

### Servidor (`functions/`, região `southamerica-east1`)

| Função | Quando roda | O que faz |
|---|---|---|
| `directions` | Chamada pelo app | Rotas (Directions API) com a chave do servidor. Login obrigatório; 300/dia por usuário. Arquivo: `maps.js`. |
| `places` | Chamada pelo app | Busca e detalhe de lugares (Places API New). Login obrigatório; 1500/dia. `maps.js`. |
| `updateRadars` | Todo dia 05:00 (publica só se mudou) | Radares (Pardal) + trechos da PRF → `public/radares.json.gz`. `radars.js`. |
| `updateSpeedLimits` | Segunda 05:30 | Limites por estado → `public/limites/UF.json.gz`. `speedlimits.js`. |
| `updatePois` | Todo dia 04:10 | Postos e pedágios (OSM) → `public/pois/UF.json.gz` (sempre baixado); lombadas → `public/lombadas/UF.json.gz` e semáforos → `public/semaforos/UF.json.gz` (opcionais: o app só baixa com o aviso ligado). `pois.js`. |
| `updateTolls` | Dia 5, 06:00 | Praças de pedágio (cabines do OSM) + preço do carro e regra da moto das federais (dados abertos da ANTT: receita ÷ veículos equivalentes) → `public/pedagios.json.gz`, `meta/tolls`. `tolls.js`. |
| `onSos`, `onStop` | Ao criar SOS / parada | Push para o grupo. |
| `endExpedition` | Chamada pelo líder (com conta) | Apaga a expedição inteira. |
| `createClub` | Chamada por quem recebeu código de ativação | Torna a pessoa administradora do clube do código (ou cria clube novo). Uso único. `clubs.js`. |
| `createClubInvite` | Chamada por administrador | Gera convite de uso único (7 dias; até 50/dia por administrador). `clubs.js`. |
| `setClubAdmin` | Chamada por administrador | Promove/rebaixa administrador; recusa deixar o clube sem nenhum. `clubs.js`. |
| `joinClub` | Chamada pelo novo membro | Entra com o convite e o invalida. Tentativas erradas: até 20/dia. `clubs.js`. |
| `clubNearby`, `clubNotify` | Chamadas pelo app (com conta) | Clube: membros próximos (sem posição exata) e avisos (5/hora). |
| `deleteMyData` | Chamada pelo app | Exclusão de dados (LGPD). |
| `cleanup` | Todo dia | Expedições paradas há 30 dias, avisos antigos do clube. |

`meta/{limits,pois,radars}` guardam a **versão** de cada arquivo; o app só
baixa de novo quando muda.

---

## Fase D — Arquitetura de tecnologia

| Camada | Tecnologia |
|---|---|
| App | Flutter 3.47 (Dart), Android (minSdk 23) e iOS 15+. |
| Mapa | Google Maps SDK (chaves restritas por app: SHA-1/pacote no Android, bundle no iOS). |
| Autenticação | Firebase Auth: anônima → vinculada a Google, Apple, e-mail/senha. |
| Banco | Cloud Firestore (cache offline ligado). TTL em `hazards` e `votes`. |
| Arquivos | Cloud Storage for Firebase (`helpaitechcomboio.firebasestorage.app`). |
| Servidor | Cloud Functions v2 (Node 20, Cloud Run), `firebase-functions` 7, `firebase-admin` 14. Funções chamáveis precisam de `roles/run.invoker` para `allUsers`. |
| Push | Firebase Cloud Messaging (tópico por expedição). |
| Integridade do app | Firebase App Check: Play Integrity (Android), App Attest/DeviceCheck (iOS), provedor de depuração em testes. |
| APIs externas | Directions API e Places API (só pelo servidor), Overpass, Pardal, Open-Meteo. |
| CI | GitHub Actions: testes, APK debug, build iOS sem assinatura. |
| Site público | Firebase Hosting `helpaitechcomboio.web.app`: `/privacidade`, `/termos`, `/excluir-dados` (exigidos pelas lojas). |
| Distribuição | Google Play (conta pessoal); AAB assinado com a chave de upload (`android/key.properties` → `.jks` fora do repositório); a Play reassina com a chave de assinatura do app. |
| Ambientes | Produção (`helpaitechcomboio`); emulador local (`demo-comboio`, `scripts/testar-local.ps1`). O emulador exige Java 21+ (usar o do Android Studio: `jbr`). |

**Chaves e segredos**

| Chave | Onde fica | Restrição |
|---|---|---|
| Comboio Android / iOS (mapa) | Dentro do app (necessário para o SDK do mapa) | Só o SDK de mapas, só o app assinado. |
| Comboio Servidor (rotas e lugares) | `functions/.env` → `MAPS_SERVER_KEY` (só no servidor) | Só Directions e Places. |
| ~~Comboio Rotas~~ | Antiga, estava dentro do app | **Bloqueada** (só aceita um site inexistente); apagar de vez depois. |

---

## Arquitetura de segurança (transversal)

Resultado da auditoria de segurança de 2026-10 e os controles aplicados.

| # | Ameaça | Controle | Situação |
|---|---|---|---|
| S1 | Extrair a chave do Google do APK e gerar cobranças | Chave só no servidor (`directions`/`places`), login obrigatório, limite diário por usuário | ✅ Feito (chave antiga bloqueada) |
| S2 | Scripts/robôs chamando o backend fora do app | App Check (Play Integrity / App Attest) | ✅ Exigido (funções, Firestore e Storage) desde 2026-10-06 |
| S3 | Foto maliciosa ou enorme baixada pelos celulares do grupo | Só URLs do Storage do app, pasta do próprio usuário (regras + app), até 2 MB, só JPEG/PNG/WebP | ✅ Feito |
| S4 | Spam com contas anônimas descartáveis | Conta de verdade para expedição, SOS, alertas, votos e clube (regras + funções) | ✅ Feito |
| S5 | Votos repetidos para apagar/manter alertas | 1 voto por pessoa (`votes/{uid}` no mesmo lote, validado nas regras) | ✅ Feito |
| S6 | Adulterar SOS de outro membro | SOS só muda para "resolvido"; resto imutável | ✅ Feito |
| S7 | Dados inválidos/gigantes no banco | Validação de campos, tipos, coordenadas e tamanhos | ✅ Feito |
| S8 | Adivinhar o código de uma expedição/clube | Códigos novos com 8 caracteres (32^8 ≈ 1 trilhão) | ✅ Feito |
| S10 | Clubes falsos ou pessoas de fora em clubes | Clube só com código de ativação da HelpAITech; administradores só com código de ativação; entrada só com convite de uso único de um administrador; tudo no servidor; tentativas erradas limitadas (20/dia) | ✅ Feito |
| S9 | Dependências do servidor vulneráveis | `firebase-admin` 14, `firebase-functions` 7, `uuid` corrigido (0 vulnerabilidades) | ✅ Feito |
| — | Invadir o celular do usuário | O app não executa código baixado, não abre arquivos de terceiros e só pede permissões necessárias | ✅ Sem risco identificado |

Testes de segurança: `tests/rules/rules.test.js` (regras do Firestore) e
`test/models_test.dart` (filtro de fotos).

---

## Fases E e F — Oportunidades, soluções e plano de migração

| Pacote de trabalho | Dependência | Situação |
|---|---|---|
| Publicar regras, Storage e funções das correções S1–S9 | Autorização do responsável | ✅ Publicado em 2026-10-06 |
| Instalar a nova versão no aparelho de teste | Publicação acima | ✅ Galaxy S24 |
| Desativar a chave "Comboio Rotas" | App atualizado | ✅ Bloqueada (o Google só deixa apagar após alguns dias sem uso) |
| Apagar de vez a chave "Comboio Rotas" | ~7 dias sem uso | Pendente |
| Site público com Termos, Política e exclusão de dados | — | ✅ No ar |
| Chave de upload e AAB assinado | — | ✅ Gerados |
| Enviar o AAB ao teste fechado e cadastrar o SHA da chave de assinatura da Play no Firebase e no mapa | Conta Play | ✅ Feito (2026-10-18/20): AAB no teste interno; SHA-1/256 da Play no Firebase e na chave do Maps |
| Vincular o projeto do Google Cloud no Play Console (Integridade do app → Play Integrity API), senão o App Check recusa quem baixar da loja | 1º envio do AAB | ✅ Feito (2026-10-18): projeto vinculado; Play Integrity funcionando |
| ✅ Exigir App Check (funções: `ENFORCE_APP_CHECK=true`; Firestore e Storage no console) | Tokens de depuração dos aparelhos de teste registrados | ✅ Feito |
| Ativar o login com Google no console do Firebase | — | Pendente (responsável) |
| Contas nas lojas (Google Play, Apple Developer) | Definição do nome | ✅ Google Play feito; Apple Developer pendente (responsável) |
| Nome do app: UauGo (trocado em 2026-10-07) | — | ✅ Feito |
| Registro da marca UauGo no INPI | Responsável | Pendente |
| Backup no Google Drive da HelpAITech | Google Drive para computador | Pendente (responsável) |

### Próximas versões (anotado para tratar)

| Item | Detalhe | Onde mexer | Situação |
|---|---|---|---|
| Narração lê algarismos romanos letra por letra | "Av. Leão XIII" é falado "Leão X I I I"; o certo é "Leão Treze". Converter números romanos nos nomes de rua (XIII → treze, Pio X → Pio Décimo/Dez, D. Pedro II → Dom Pedro Segundo) antes de falar, sem confundir siglas comuns (ex.: "MG", "BR", "CIC"). | `cleanInstruction` em `lib/logic/navigation.dart` (+ teste em `test/navigation_test.dart`) | ✅ Feito (2.22) |
| Alertas que não mudam viram fixos após 3 confirmações | Hoje todo alerta da comunidade expira (lombada: 7 dias). Lombada e **semáforo** (novo tipo de alerta a criar, para semáforos que faltam no OpenStreetMap; depois de fixo, também alimenta a voz "No semáforo, vire...") confirmados por **3 pessoas diferentes** (contas distintas) deve ficar **fixa**, sem expirar. Continua a pergunta "ainda está lá?": se 3 pessoas disserem que não está mais, sai. Tipos que mudam (polícia, radar móvel, óleo, animal, acidente, neblina, buraco) continuam expirando. | `HazardType` em `lib/models/hazard.dart` (marcar tipos permanentes), `HazardService` (`expiresAt` ao confirmar), regras do Firestore (permitir sem prazo só com 3 confirmações), TTL de `hazards` | ✅ Feito (2.22) |
| **Usuário Gold: alertas permanentes sem expirar** | Alerta de tipo permanente (**radar fixo**, **lombada**, **semáforo**) marcado por um **usuário Gold** já nasce fixo, sem expirar e sem precisar das 3 confirmações. Tipos que mudam (buraco, acidente, óleo, polícia, radar móvel, animal, neblina) continuam expirando, mesmo vindo de Gold. **Gold** = o responsável (Ricardo) e usuários convidados por ele, por exemplo pelas muitas horas de uso. O selo fica só no servidor (campo em `users/{uid}` ou *custom claim* do Firebase Auth, gravado por função de administrador), e as regras do Firestore só aceitam alerta sem prazo de quem é Gold. Criar os tipos "radar fixo" e "semáforo" nos alertas da comunidade. Base para os convites: contar as horas de uso por usuário. Remoção (decidido 2026-10-15): um alerta Gold só sai com **5** respostas "não está mais" de usuários diferentes (alerta comum: 3). | `HazardType` (`lib/models/hazard.dart`), `HazardService`, regras do Firestore, `functions/` (marcar Gold), contagem de horas de uso | ✅ Feito (2.22) |
| **Bateria: consumo alto mesmo com o app fechado** (relatado em 2026-10-11, prioridade) | 1) **Fora de comboio** a posição não é enviada a ninguém e o GPS não roda fora da tela. 2) **Em comboio com o app fora da tela**: só continua se a nova opção **"Compartilhar posição em segundo plano"** estiver ligada (desligada por padrão); mesmo ligada, GPS econômico (leitura a cada 10–15 s, precisão menor, sem `enableWakeLock`). 3) **Ao sair da tela**: pausar todos os temporizadores (relógio de 30 s, gravação de 2 min, bateria de 2 min, chuva, trânsito) e os ouvintes do Firestore; retomar ao abrir. 4) **Navegação**: a tela nunca apaga sozinha (wakelock em todos os modos). 5) **Chuva e trânsito**: só com rota traçada **e** com a opção ligada — **duas opções separadas** em Configurações, cada uma avisando que aumenta o consumo de dados e de bateria. Antes de mexer, medir com `adb shell dumpsys batterystats helpaitech.comboio` no S24. | `LocationService.track`, `MapScreen` (`_keepGpsInBackground`, `didChangeAppLifecycleState`, `_rainTimer`, `_trafficTimer`, `_ticker`), `BatteryService`, `AppSettings`, `SettingsScreen` | ✅ Feito (2.16) |
| Anúncios na versão gratuita (ideia; responsável decide quando) | Venda direta pela HelpAITech: "locais patrocinados" no roteiro (postos, restaurantes, pousadas, oficinas) + banners só em telas paradas (início, histórico, clube), **nunca na navegação**; selo "Patrocinado"; sem bebida alcoólica. Página de administração (anunciante, imagem, link, período, região) e relatório de exibições/cliques. Opcional: AdMob para preencher espaço vazio e compra "sem anúncios" (Google Play Billing). Exige: nova versão da Política (localização em anúncios), declaração "contém anúncios" e segurança dos dados na Play, `app-ads.txt` se usar AdMob, nota fiscal (ver contador). | Nova coleção no Firestore + regras, página no Hosting, widgets nas telas paradas | Ideia |
| Bateria: consumo alto mesmo com o app fechado (relatado de novo em 2026-10-15, depois da correção 2.16) | Medir com `adb shell dumpsys batterystats helpaitech.comboio` (o contador foi zerado em 2026-10-13; a versão antiga gastou ~822 mAh, 429 só com o serviço de GPS por 18 h). Conferir: serviço do Geolocator parado, wake locks, rede (Firestore/FCM), Vosk (comandos de voz) fora da tela, `BatteryService`, e se a versão instalada é a 2.16 ou posterior. | `LocationService`, `MapScreen` (`_pauseWork`), `VoiceCommandService`, `NotificationService` | Pendente |
| Locais salvos (Casa, Trabalho e outros) | Salvar lugares com nome; atalhos no "Para onde?" e por voz ("UauGo, ir para casa"). Guardados no celular (e na conta, para trocar de aparelho). | `HomeScreen`, `PlaceSearchPage`, `UserService`, `voice_commands.dart` | ✅ Feito (2.22) |
| Refazer a rota a partir do histórico | Em "Minhas viagens", botão para traçar de novo a mesma rota (saída, paradas e destino) ou só ir ao destino. | `HistoryScreen`, `TripService`, `TripPreviewSheet` | ✅ Feito (2.22) |
| Tirar os limites de consulta por usuário | Hoje: rotas 300/dia, busca de lugares 1500/dia, "procurar no caminho" 10/dia (`functions/maps.js`, `LIMITS`). Os limites protegem a conta do Google contra abuso e custo; antes de tirar, avaliar alerta de orçamento no Google Cloud e limite global por dia. | `functions/maps.js` | ✅ Só tetos contra abuso (2.22) |
| Integração com o Gemini | Avaliar o Gemini (Google) como a IA da "Etapa 2" da voz: entender pedidos livres ("o posto mais perto na rota"), resumir a viagem etc. Comparar custo, latência e privacidade com o Claude; possível via Firebase AI Logic (Vertex AI), sem chave no app. | `functions/`, `VoiceCommandService` | ✅ Feito (2.22) |
| **Administração UauGo no app (clubes na hora)** | Área visível só para administradores da plataforma (o responsável e quem ele nomear; selo só no servidor, como o Gold): (1) cadastrar clube novo na hora (nome, cidade); (2) gerar **código de ativação** de administrador do clube (hoje só pelo script `scripts/gerar-codigos-clube.js`); (3) gerar **convite de membro** para qualquer clube sem ser administrador dele; (4) mostrar o código grande, com envio pelo WhatsApp e **QR code**; (5) lista de clubes com administradores e número de membros. Caso de uso: apresentar o app num rolê e já ativar o clube e os membros. | `functions/clubs.js` (funções de administrador da plataforma), regras do Firestore, nova tela no app (`club_screen.dart` ou `admin_screen.dart`) | ✅ Feito (2.22) |
| Placa do limite cortada ("110" aparece "11") | Causa: círculo de 44 px com a fonte grande do celular; o "110" quebra em duas linhas e o último dígito some. Correção: `FittedBox` + uma linha, sem escala de fonte do sistema dentro da placa. | `lib/widgets/speedometer.dart` | ✅ Feito (2.22) |
| Faixa de aviso do radar com contagem até o radar | Igual à faixa de "velocidade reduzida": aparece ao se aproximar e mostra a distância diminuindo até passar pelo radar, com o limite do radar. | `MapScreen` (avisos de radar), `lib/logic/radars.dart` | ✅ Feito (2.22) |
| Limite de velocidade da via certa | Com rota traçada: usar só os trechos da malha que coincidem com a rota (ignorar saídas, marginais e vias paralelas). Sem rota: só a via em que o piloto está (direção + continuidade com a via anterior), nunca a mais próxima de outra. Revisar também vias com limite incoerente relatadas pelo responsável. | `SpeedService`/`lib/logic/speed.dart`, `RouteWalker` | ✅ Feito (2.22) |
| Pedágio: aviso de moto errado | O aviso falado da praça diz "moto paga" quando o OSM não informa; usar a tabela de pedágios (regra da moto da ANTT por praça) e, sem informação, dizer "não informado" em vez de afirmar que paga. | `MapScreen._checkPois`, `TollService` | ✅ Feito (2.22) |
| **Expedição: capitão e ferrolhos** | Papéis: 1 **capitão** e até 3 **ferrolhos**; os demais são membros. Só o desvio do **capitão** recalcula a rota da expedição para todos; desvio de membro/ferrolho: avisa "fora da rota" e recalcula só a rota dele até voltar à rota da expedição. Capitão e ferrolhos têm visão própria: alternar entre **todos os pilotos no mapa** (bolinhas) e uma **grade no canto com os apelidos**; quem sai do trajeto ganha **exclamação amarela**; tocar no nome mostra o piloto no mapa. | `ExpeditionService`, regras do Firestore (papéis), `MapScreen`, `PlanScreen` | ✅ Feito (2.22) |
| Alerta automático "veículo parado no acostamento" | Usuário do app parado na rodovia (fora de cruzamento/posto, alguns minutos) vira alerta para quem vem atrás na mesma rota; expira sozinho ao sair. Precisa de aviso/consentimento (é a posição dele) e de cuidado para não marcar paradas normais (semáforo, trânsito). | `MapScreen`, `HazardService`, Política de Privacidade | ✅ Feito (2.22) |
| Chuva: alerta mais certeiro | Teste real: avisou chuva que não houve e não avisou a que houve. A previsão (Open-Meteo) é de modelo, não de radar. Avaliar dados de agora (nowcast/radar de chuva, ex.: RainViewer, Open-Meteo 15 min, INMET/CPTEC), exigir probabilidade/intensidade mínimas e confirmar em mais de um ponto à frente. Só religar como padrão quando estiver confiável. | `lib/services/weather_service.dart`, `lib/logic/weather.dart` | Parcial (2.22): consenso de 3 modelos (GFS, ICON, ECMWF; avisa só se 2 concordam). Falta: radar de chuva de agora (avaliar cobertura no Brasil e termos de uso) e **plano comercial do Open-Meteo** (grátis só para uso não comercial). |
| Polícia/radar móvel na pista não avisados | A lista da PRF são **trechos onde pode haver** radar móvel (não é tempo real) e já é atualizada 2x por semana; passar para diária custa quase nada, mas não mostra a polícia de agora. Tempo real só vem dos **alertas da comunidade** ("UauGo, polícia/radar"): incentivar o uso (Gold, voz, lembrete) e avaliar outras fontes abertas. | `functions/radars.js` (agenda), alertas da comunidade | ✅ Atualização diária (2.22); tempo real depende dos alertas da comunidade |
| Planejar a saída na rota normal (sozinho) | Na prévia do "Para onde?", escolher **data e hora de saída** (como no roteiro da expedição): chegada prevista, trânsito estimado para aquele horário, e guardar a viagem planejada para iniciar depois. Relatado em 2026-10-16 (confirmar com o responsável se é isso). | `TripPreviewSheet`, `TripService`, `HistoryService`/viagens planejadas | ✅ Feito (2.34): "Saída" com data/hora na prévia, chegada, rodízio no horário, "Viagens planejadas" na tela inicial |
| Adicionar parada na rota normal (sozinho) | Durante a navegação sozinho, incluir uma parada no caminho: botão "Adicionar parada" (busca por nome) ou segurar no mapa; entra como a próxima parada, antes do destino, e a rota é recalculada de onde o piloto está. Relatado em 2026-10-17. | `MapScreen` (`_insertSoloStop`, `_addSoloStopBySearch`, `_addSoloStopAt`), `PlaceSearchPage`, `TripService` | ✅ Feito (2.23) |
| Cancelar parada já incluída | Tocar na parada no mapa e escolher **Cancelar parada**, ou por voz ("UauGo, cancelar parada"); a rota é recalculada sem ela. Vale para a rota normal (e, na expedição, para o líder/capitão). Relatado em 2026-10-18. | `MapScreen` (marcadores das paradas, `_insertSoloStop`), `voice_commands.dart`, `VoiceCommandService` (gramática) | ✅ Feito (2.34): tocar na parada → Cancelar; voz "UauGo, cancelar parada" (confirma) |
| **[Defeito] Expedição sem "Salvar" e "Iniciar" no roteiro** | No planejamento da expedição só aparece "Simular viagem"; faltam os botões **Salvar** e **Iniciar**. Relatado em 2026-10-18. | `PlanScreen` | ✅ Feito (2.24) |
| **[Defeito] Travou ao incluir várias paradas na expedição** | Ao escolher mais de um destino o app travou: deixa simular, mas não deixa incluir quantas paradas quiser. Investigar (limite de paradas, recálculo da rota, tela). Relatado em 2026-10-18. | `PlanScreen`, `ExpeditionService` (paradas), `TripService` | ✅ Feito (2.24) |
| **[Defeito] Botão do planejamento atrás dos botões do celular** | No planejamento da expedição o botão de baixo fica escondido pela barra de navegação do Android (falta respeitar a área segura). Relatado em 2026-10-18. | `PlanScreen` (`SafeArea` / `viewPadding`) | ✅ Feito (2.24) |
| Mais de uma expedição ao mesmo tempo | Poder criar (e participar de) mais de uma expedição; hoje o app guarda só a última (`lastCode`). Lista "Minhas expedições" na tela inicial para escolher qual abrir. Relatado em 2026-10-18. | `HomeScreen` (`lastCode` → lista), `ExpeditionService` | ✅ Feito (2.24): lista "Minhas expedições" na tela inicial (as que ainda existem; encerradas somem e saem do histórico local) |
| **App lento no celular** | Analisar se é o app ou o aparelho: medir no Galaxy A14 (perfil de desempenho do Flutter, quadros por segundo, uso de memória e CPU, mapa 3D/prédios, quantidade de marcadores) e comparar com o S24. Possíveis ganhos: desligar prédios 3D em aparelhos simples, menos redesenhos do mapa, imagens menores. Relatado em 2026-10-18. | `MapScreen` (mapa, marcadores, `setState` a cada leitura do GPS), `AppSettings` (modo leve) | ✅ Em parte (2.34): modo leve automático (< 4,5 GB RAM: sem prédios 3D e trânsito) |
| Contato de emergência + aviso pelo WhatsApp | Salvar um número de emergência. No SOS/alerta, enviar a mensagem com a localização para esse número pelo WhatsApp. **Limite técnico:** o WhatsApp não deixa um app enviar sozinho pelo aplicativo do celular: o app abre a conversa com a mensagem pronta e a pessoa toca em Enviar. Envio 100% automático só pela **API oficial do WhatsApp Business** (pelo servidor, modelo de mensagem aprovado, custo por conversa). Alternativa automática: SMS (a Play restringe a permissão; avaliar se o caso "emergência" é aceito). Relatado em 2026-10-18. | `UserService` (contato), SOS em `MapScreen`, `functions/` (se API do WhatsApp Business) | ✅ Feito (2.34): Configurações → Contato de emergência; SOS → "Avisar <nome> pelo WhatsApp" |
| Alerta de roubo com vídeo | No alerta de roubo, gravar a **câmera frontal** em trechos de **10 s** e subir cada trecho para a **nuvem** (Firebase Storage), apagado em **no máximo 24 horas**; tudo automático, sem o piloto tocar em nada. **Não vai pelo WhatsApp** (exigiria o toque do piloto). Proposta (2026-10-18): ao cadastrar o contato de emergência, o app gera um **link fixo e secreto** do piloto, enviado uma vez pelo WhatsApp com 1 toque, com calma; no roubo, o contato abre esse link e vê os vídeos chegando + a localização; aviso automático na hora por **e-mail** (servidor) e **notificação** se o contato tiver o UauGo. O Android exige notificação visível e o acionamento com o app aberto (botão de alerta) para usar a câmera. Ao vivo (YouTube Live/WebRTC) fica para depois. Atualizar a Política de Privacidade (imagem de terceiros, LGPD) e avaliar o custo do armazenamento. Relatado em 2026-10-18. | Serviço de câmera (Android, primeiro plano tipo câmera), Storage + expiração 24 h, página do link no Hosting, `functions/` (e-mail, push) | Pendente (proposta a confirmar) |
| **[Defeito] Expedição tenta calcular a rota antes do destino** | No roteiro da expedição, com só o ponto de saída, o app já tenta calcular a rota (barra de carregando / aviso de rota). Calcular só a partir de 2 pontos (saída + destino); com 1 ponto, nada de "rota não calculada". Relatado em 2026-10-18. | `PlanScreen` (`_addPoint`, `_recalc`, `_routeFailed`), `ExpeditionService.addToItinerary` / `recalculateRoute` | ✅ Feito (2.34) |
| Paradas a cada X km na expedição (com posto sugerido) | No roteiro, o líder informa "parada a cada **X km**" (ex.: 100, 150). Com saída e destino definidos, o app marca na rota os pontos a cada X km e, para cada um, **sugere postos de combustível** próximos daquela distância, **à frente no sentido da rota** (busca ao longo da rota, como o "procurar posto"). O líder escolhe o posto (ou mantém o ponto) e ele entra como parada do tipo abastecimento; dá para ajustar ou remover depois. Relatado em 2026-10-18. | `PlanScreen` (opção "a cada X km"), `TripPlan` (campo do intervalo), `RouteWalker` (ponto a X km na rota), `PlacesService.find` (posto ao longo da rota), `ExpeditionService.addToItinerary` | ✅ Feito (2.34): "Paradas para abastecer a cada X km" no roteiro (líder) |
| Sem internet: aviso claro e destinos conhecidos | Sem internet, a busca de destino mostra "Sem internet: a busca precisa de conexão (os avisos de radar e velocidade continuam)" em vez da lista vazia, e oferece casa, trabalho, locais salvos e **destinos recentes**; rota já calculada antes fica guardada no celular e pode ser usada. Com a navegação offline desligada (padrão), avisa: "Para traçar rota sem internet, ative **Navegação offline** em Configurações e baixe o estado". Relatado em 2026-10-18. | `PlaceSearchPage`, `HomeScreen`, `SavedPlacesService`, `HistoryService` (rotas guardadas), `AppSettings` | ✅ Feito (2.34): busca explica "Sem internet" + destinos recentes |
| Rota traçada com internet continua sem internet | Se a conexão cair no meio da viagem, a navegação segue até o destino (rota, manobras, voz e avisos já estão no celular). Conferir e garantir: o mapa do Google mostra o que já estava em cache; ao sair da rota sem internet, em vez de recalcular, avisar "Sem internet: volte para a rota" e guiar de volta; recalcular sozinho quando a internet voltar. Relatado em 2026-10-18. | `MapScreen` (recálculo/`_reroute`, aviso), `TripService`, `LocationService` | ✅ Feito (2.34): aviso único "volte para a rota", tenta recalcular a cada 20 s |
| Navegação offline com OpenStreetMap (opcional) | **Escolha do usuário, desligada por padrão** (Configurações → Navegação offline). Ligada: baixa por estado o mapa aberto (OpenStreetMap, mapa vetorial) e o pacote de rotas. O mapa principal continua o do **Google**; só quando for preciso **traçar rota sem internet** o app busca o destino nos dados baixados, calcula a rota no próprio celular e mostra no mapa OpenStreetMap. Ao voltar a internet, volta ao Google. Avaliar: MapLibre (mapa) + GraphHopper/Valhalla offline (rotas) + busca de endereços offline; tamanho estimado de centenas de MB por estado (avisar antes de baixar, só no Wi-Fi). Projeto grande. Relatado em 2026-10-18. | Novo módulo offline (mapa MapLibre, motor de rotas no aparelho, busca offline), `AppSettings`, `OfflineService` (downloads por UF), `MapScreen` (troca de mapa) | Pendente (futuro, escolha do usuário) |
| **IA no comando de voz (assistente)** | Prioridade (pedido do responsável: "não podemos demorar na era da IA"). Hoje o Gemini (Vertex AI, função `interpret`) só entende o pedido livre do "procurar". Próximo passo: um **assistente de voz** — depois do "UauGo" (reconhecido no celular, Vosk), a frase vai para a IA, que escolhe a ação do app (*function calling*): "quanto falta?", "avisa o grupo que vou parar no próximo posto", "tem radar até a próxima cidade?", "vai chover no caminho?", "quero um restaurante barato daqui a uns 50 km", "marca lombada", "resumo da viagem". Responde falando. Avaliar Gemini 2.5 Flash (já ligado no projeto) e outras IAs por custo, tempo de resposta (meta < 2 s) e privacidade; limite por usuário contra abuso; atualizar a Política de Privacidade. Relatado em 2026-10-18. | `functions/ai.js` (ações), `VoiceCommandService`, `MapScreen` (executar ações), `voice_commands.dart` | Pendente (prioridade, versão futura próxima) |
| **[Defeito] Android Auto: tela preta e rota não aparece** | No carro só aparecem velocidade e limite; fundo preto; os botões respondem mas nada muda; com rota traçada no celular, a manobra/chegada não aparece. Fazer o mapa de fundo (`MapRenderer`) e conferir o envio da manobra (`_sendToCar`/`CarState.nav`) e o estado de navegação do `NavigationTemplate`; testar no DHU com celular real. Relatado em 2026-10-19 (testadores). | `UauGoCarAppService.kt`, `CarBridge.kt`, `car_service.dart`, `MapScreen._sendToCar` | Em teste (2.25/1.0.4): mapa do Google no carro; DHU 2.0 (o mais novo do SDK) não recebe imagem do Android Auto 17.8 pelo ADB; testar no carro ou ligar o DHU pelo modo USB (driver WinUSB) |
| **[Defeito] Comandos de voz não funcionam com o Android Auto** | Com o Android Auto conectado, o microfone vai para o carro e o reconhecimento do app não ouve. Avaliar: usar o microfone do carro (áudio do carro / "Hey Google" com ações do app) ou avisar que, no carro, a voz é pelo botão na tela do Android Auto. Relatado em 2026-10-19 (testadores). | `VoiceCommands.kt`, `UauGoCarAppService.kt` | Pendente |
| Telefone da concessionária da rodovia no SOS | No botão de emergência, além de 191 (PRF), 190, 192 e 193, mostrar o **telefone (0800) da concessionária** da rodovia em que o piloto está ou da rota traçada. Os dados da ANTT já dizem a concessionária de cada praça federal; falta a **tabela de telefones oficiais** (federais ANTT e estaduais, ex.: ARTESP), conferida nas fontes oficiais antes de entrar no app (número de emergência não pode estar errado). Relatado em 2026-10-19 (testadores). | `MapScreen._showEmergency`, `functions/tolls.js` (concessionária por trecho), tabela de telefones (nova) | Pendente (montar a tabela verificada) |
| Planejamento: puxar para ver o mapa maior | No roteiro (e na prévia da rota), arrastar para baixo para aumentar o mapa e para cima para ver a lista das paradas. Relatado em 2026-10-20 (testadores). | `PlanScreen` (mapa 34% fixo → área arrastável), `TripPreviewSheet` | ✅ Feito (2.34): alça entre mapa e lista (arrastar ou tocar) |
| Aparência "clean" (escolha do usuário) | Em Configurações: tema **Padrão** (o atual) ou **Clean** (liso, poucas cores: botões neutros, cores só para alerta e SOS). Relatado em 2026-10-20 (testadores). | `main.dart` (tema), `AppSettings`, `MapScreen` (cores dos botões) | ✅ Feito (2.30): escolha de cor, inclusive Clean |
| Alerta de rodízio de veículos | Avisar nas cidades com rodízio (ex.: São Paulo) quando o veículo está no dia/horário de restrição, principalmente se a **rota traçada** passa pela área do rodízio. Precisa do **final da placa** em "Meu veículo" e das regras oficiais de cada cidade (área, dias, horários, quais veículos — conferir se motos estão incluídas), verificadas nas fontes da prefeitura. Relatado em 2026-10-20 (testadores). | `ProfileService`/`BikeProfile` (final da placa), tabela de rodízio (nova), `MapScreen`/`TripPreviewSheet` (aviso) | ✅ Feito (2.34): São Paulo (centro expandido aproximado), placa só no celular, aviso na prévia e por voz |
| Preço de pedágio atualizado por IA (ideia do Eldon) | Rotina **semanal** no servidor que busca na web, com IA, os preços das praças (especialmente as sem preço na base da ANTT e as estaduais) e grava no banco; o app usa no custo da viagem. Cuidar de fontes oficiais (sites das concessionárias/agências) e conferir divergências antes de publicar. Relatado em 2026-10-20 (testadores). | `functions/tolls.js` (nova rotina), `functions/ai.js` | ✅ Feito (2.33): rotina semanal no n8n da VPS (SearXNG + Groq/OpenAI) |
| Posição da polícia na estrada por busca automática | Buscas **diárias (ou de hora em hora)** de pontos de fiscalização (blitz, comandos) para o banco de dados. **Atenção:** avaliar fontes permitidas (dados abertos oficiais, como os trechos de radar da PRF que já usamos) — copiar grupos/redes sociais ou sites de terceiros pode violar termos de uso e direitos; os alertas da comunidade já cobrem polícia na pista. Relatado em 2026-10-20 (testadores). | `functions/` (rotina), `RadarService`/`HazardService` | Pendente (avaliar fontes) |
| Preço do pedágio informado pela comunidade (ideia do Eldon) | Quando uma praça **não tem preço** na base, quem passar perto dela recebe um pedido: "Qual o preço deste pedágio para o seu veículo?" (com o tipo do veículo). Com 3 respostas parecidas de usuários diferentes, o preço passa a valer para todos (como os alertas). Relatado em 2026-10-20 (testadores). | `TollService`, `MapScreen` (pergunta perto da praça), coleção nova no Firestore + regras, `functions/tolls.js` (consolida) | Pendente |
| Controles do Spotify (e outros players) no mapa | Quando houver música tocando (Spotify ou outro app), mostrar no mapa um mini player: capa, nome da música e botões **anterior / tocar-pausar / próxima**, sem sair do UauGo. Caminhos: (1) **controle de mídia do Android** (MediaSession): funciona com Spotify, YouTube Music, Deezer etc., mas o usuário precisa dar a permissão "Acesso a notificações" ao UauGo uma vez; (2) **SDK do Spotify** (App Remote): só Spotify, exige cadastrar o app no Spotify for Developers. No Android Auto o próprio carro já mostra o Spotify na barra de baixo. Relatado em 2026-10-22. | `MapScreen` (mini player), canal nativo novo (MediaSessionManager + NotificationListenerService), Política (permissão) | Pendente (próximas versões) |
| Lembrete na agenda da viagem planejada | Ao salvar uma viagem planejada (com "Saída"), botão "Pôr na agenda": abre o app de agenda do celular já preenchido (título, horário de saída, destino e um alarme antes), via Intent `ACTION_INSERT` / `CalendarContract`. **Sem permissão de agenda** e sem ler a agenda do usuário: o próprio app de agenda salva. Assim não muda a Segurança dos dados do Play nem a Política. Relatado em 2026-10-23. | `TripPreviewSheet` (`_savePlanned`), lista "Viagens planejadas" na Home, canal nativo ou pacote `add_2_calendar` | Pendente (próxima versão) |
| Simulação na velocidade da via | Na simulação **1x**, andar sempre na **velocidade da via** (limite do trecho; sem limite conhecido, a média da rota). Em **5x** e **20x**, andar 5 e 20 vezes mais rápido **e o velocímetro mostrar essa velocidade** (ex.: via de 80 → 400 km/h em 5x). Nos modos acelerados, desligar o aviso de "acima do limite" para não falar o tempo todo. Relatado em 2026-10-22. | `lib/logic/simulation.dart` (velocidade por trecho), `MapScreen` (velocímetro e alerta na simulação), `SpeedService.lookup` | Descartado por enquanto (decisão do responsável, 2026-10-22) |
| **Android Auto (próxima versão — prioridade)** | Muitos usuários serão de carro (centrais multimídia). Criar o "modo carro" com a Car App Library do Google (`androidx.car.app`, categoria **navegação**): mapa desenhado pelo app na tela do carro, faixa da próxima manobra, ETA, alertas (radar, perigo, pedágio) e busca simples ("procurar posto"); voz pelo som do carro. Parte nativa em Kotlin (Flutter não renderiza na tela do carro), conversando com o app pelo mesmo estado da navegação. Exige aprovação da Google para apps de navegação no Android Auto e testes no Desktop Head Unit (DHU). CarPlay fica para depois (exige autorização de navegação da Apple e o app publicado na App Store). | `android/` (CarAppService, Session, NavigationTemplate), ponte com `MapScreen`/`TurnByTurn` | Em andamento (2.22): falta testar no simulador de central (DHU) com o celular |
| Tela própria para o celular deitado (paisagem) | Hoje o app não trava a orientação, mas nenhuma tela foi desenhada para o modo deitado. Criar o layout deitado (mapa ocupando a tela; velocímetro, próxima curva, avisos e botões nas laterais, como Waze/Google Maps) e **manter o layout em pé exatamente como está** (aprovado pelo responsável). Prioridade: tela do mapa/navegação e prévia da rota; depois as demais. Testar no emulador nas duas orientações e com o celular girando no meio da navegação. | `MapScreen` (escolher layout por `MediaQuery.orientation`/`OrientationBuilder`), `TripPreviewSheet`, `Speedometer`, faixa da manobra | ✅ Feito (2.22) |
| Pesquisa de trajeto por voz (opcional) | **Opção nas Configurações, desligada por padrão**, separada dos comandos de voz. "UauGo, ir para …": a palavra de ativação continua offline (Vosk); ao ouvir "ir para", abre por alguns segundos o reconhecimento de voz do Android/Google (frase livre, **precisa de internet**, usa dados), pesquisa o lugar e mostra as opções (ou traça a rota direto se houver uma só). O texto da opção avisa que usa internet. Não interromper a navegação em andamento sem confirmar. Política de privacidade: o áudio dessa frase vai para o Google. | `lib/logic/voice_commands.dart` (gramática "ir para"), `VoiceCommandService`, `AppSettings`, `SettingsScreen` (Acessibilidade), busca do "Para onde?" | ✅ Feito (2.18) |
| Destino por voz com IA (etapa 2) | Depois da publicação. O texto falado vai a uma IA (Claude Haiku, por Cloud Function, com limite por usuário) que transforma pedidos naturais ("o posto mais perto na minha rota", "restaurante bom no caminho", "me leva pra casa", "pousada em Urubici com garagem para moto") em busca precisa (tipo de lugar, perto da rota, endereço salvo). Opcional, precisa de internet, custo estimado < R$ 0,01 por pedido. Política de Privacidade: o texto (não o áudio) vai para a IA. | `functions/` (nova função), `VoiceCommandService`, `HomeScreen._whereTo`, `PlacesService` | ✅ Feito com Gemini (2.22) |

**Transição:** códigos antigos de 6 caracteres continuam aceitos; só os novos
têm 8. Versões antigas do app perdem o voto em alertas e a criação de
expedição até serem atualizadas.

---

## Fase G — Governança da implementação

Antes de publicar qualquer mudança:

1. `flutter analyze` sem erros e `flutter test` passando.
2. Regras: `firebase emulators:exec --only firestore --project demo-comboio "npm --prefix tests/rules test"` passando.
3. Servidor: `npm audit --omit=dev` sem vulnerabilidades.
4. Nenhum segredo no git (`config.env`, `functions/.env`, `config/dart_defines.json` estão no `.gitignore`).
5. Mudança que afete princípios, segurança ou dados → atualizar este documento (Fase H) e, se for decisão, criar um ADR.
6. Publicação no servidor e commits só com a aprovação do responsável.

---

## Fase H — Gestão de mudanças da arquitetura

| Data | Versão | Mudança | Seções afetadas |
|---|---|---|---|
| 2026-10-16 | 2.22 | Melhorias anotadas: placa "110" e velocímetro sem estourar com fonte grande; pílula do radar com distância; pedágio falado pela tabela ANTT (moto sem informação = "não informado"); números romanos por extenso na voz; radares conferidos todo dia (publica só se mudou); limite só da via da rota/direção + troca confirmada em 2 leituras; **locais salvos** (só no celular) e "UauGo, ir para casa"; **refazer rota** pelo histórico; **alertas fixos** (radar fixo, semáforo; 3 confirmações ou Gold; remoção 3/5; `gold/{uid}`, `scripts/gold.js`); **Administração UauGo** (`platformAdmins/{uid}`, funções `admin*`, QR → `/clube`, link `uaugo://clube`); **capitão e ferrolhos** (`captainId`, `sweepers`; desvio do capitão recalcula para todos; rota própria para os outros; grade com ⚠️); **veículo parado no acostamento** (opcional); chuva por consenso de 3 modelos; limites só contra abuso; **layout deitado**; **IA Gemini** (Vertex AI, função `interpret`); **Android Auto** (início: `UauGoCarAppService.kt`, `CarBridge.kt`, `car_service.dart`; manobra, chegada, trajeto desenhado, botões Radar/Perigo/Encerrar; GPS e voz seguem com o celular bloqueado). Política v1.11. | B, C2, C3, D, Segurança |
| 2026-10-17 | 2.23 | Rota normal: **adicionar parada durante a navegação** (botão com busca ou segurar no mapa); entra como a próxima parada e a rota é recalculada a partir da posição atual. A busca por voz ("procurar posto") usa a mesma inclusão. **"Só dirigir"** (ou depois de chegar): botão **"Traçar rota"** (busca) ou segurar no mapa abre a prévia da rota, onde dá para incluir paradas — sem precisar da voz. **Expedição:** o capitão começa sendo o criador (líder); o líder troca o capitão e os ferrolhos, e o **capitão também pode passar a capitania** a outro membro (regra do Firestore: só para quem é membro; o novo capitão sai dos ferrolhos); todos são avisados da troca. Na expedição, o topo mostra **chegada e km que faltam** pela rota do grupo (e o código). **Tocar no piloto** (líder ou capitão) abre o menu: ver no mapa, capitão/ferrolho ou passar a capitania. **Trocou de conta no meio da expedição:** a função `transferExpeditionRoles` leva liderança, capitania, ferrolho e a vaga na lista para a conta nova (prova: token da conta antiga pego antes da troca; `AuthService.onSwitchedFrom`). **Remover alerta** some na 1ª vez (o aparelho guarda os alertas que tirou; antes, com o relógio do celular atrasado, o alerta voltava até a 2ª remoção). | C2 |
| 2026-10-18 | 2.24 | Versão de loja 1.0.2/1.0.3: regras do R8 (`proguard-rules.pro`) para o Firebase App Check e a voz offline (na loja o App Check não iniciava → PERMISSION_DENIED). Assinaturas da Play (SHA-1/SHA-256) no Firebase e na chave do Maps. **Roteiro da expedição:** barra fixa do líder acima dos botões do celular (**Parada / Salvar / Iniciar**); **Iniciar** abre o mapa já navegando (`MapScreen.startNavigation`; pelo mapa, `_openPlan`); gravações do roteiro com limite de tempo e erro tratado (`_guard`), sem travar ao incluir várias paradas. **Minhas expedições** na tela inicial: até 5 expedições que ainda existem (nome · código), tocar entra; encerradas somem; sair tira da lista (`UserService.loadExpeditionHistory` / `removeExpeditionHistory`). **Veículo parado no acostamento automático** (sem opção; alerta sem identificar o usuário; "Não avisar" tira na hora; Política v1.12). **Chuva à frente** a cada 10 km pela rota (até 50 km). Botão **DIRIGIR AGORA** em destaque na tela inicial. **Custos do Google menores:** detalhe do lugar só com endereço e posição (faixa Essentials; o nome vem da sugestão — `functions/maps.js`, publicar a função `places` junto com a versão); **destinos recentes** na busca (`RecentPlacesService`, escolher um recente não consulta o Google e funciona sem internet); sugestões repetidas na mesma tela não reconsultam (espera 500 ms); **rotas repetidas guardadas** no celular por 10 min (com trânsito) ou 30 min (`DirectionsService._cache`). **Estatísticas e erros:** Firebase Analytics + Crashlytics (`AnalyticsService`; eventos `route_start`, `route_simulate`, `just_drive`, `expedition_create`/`expedition_join`/`expedition_start`, `hazard_report`, `voice_command`), sem identificador de anúncios; opção "Compartilhar estatísticas de uso" (ligada por padrão); plugin Crashlytics 3.0.6 + google-services 4.4.2; Política v1.13. **Play Console:** atualizar a "Segurança dos dados" (estatísticas e falhas do app, coletados, não compartilhados, opcionais). | C2, C3, Segurança, Custos |
| 2026-10-19 | 2.25 | Retorno dos testadores: **radar vermelho** no mapa (azul sumia na estrada); aviso de radar padrão **750 m, 1 vez** (opções 300 a 2000 m e 1 a 3 vezes continuam em Configurações); **fila de voz descarta avisos velhos** (6 s; antes "radar a 500 metros" saía em cima do radar quando a voz estava ocupada); frase do **trecho com radar móvel da PRF** clara ("nos próximos N quilômetros", sem "do km 90 ao km 30"); **tempo restante** no topo (chegada · tempo · km). **Android Auto com mapa do Google** na tela do carro (`CarMapView.kt`: tela virtual + Presentation + MapView; segue o piloto girado e inclinado, rota azul, trânsito, seta, velocidade, placa do limite e aviso de radar; se falhar, volta ao desenho simples `MapRenderer`); dependência `play-services-maps` 20.0.0. Simulador do Android Auto (DHU) instalado no SDK para testes. | C2, C3 |
| 2026-10-19 | 2.26 | Depois da 1.0.4: **Minhas expedições aparece na hora** (nomes guardados no celular; conferência no servidor em paralelo, antes uma por vez). **Expedição mostra km, tempo e custo** já antes de iniciar (topo: "85 km · 1h12 · ~R$ 64 · código"); rota normal também mostra o custo. **Tocar no título do mapa abre o Resumo da viagem** (distância, tempo, falta, chegada, combustível, pedágios, custo) — expedição e rota normal. **SOS:** "Enviar minha localização pelo WhatsApp" abre o WhatsApp direto (`wa.me`) + opção "outro app". Termos e Política sem os nomes antigos do app. **Todos os radares em vermelho** (fixo da base, radar móvel e radar fixo da comunidade, trecho da PRF tracejado). **SOS na expedição** avisa os pilotos e também abre os telefones de emergência e o envio da localização. | C2 |
| 2026-10-19 | 2.27 | **Pedidos ao grupo** (só na expedição): botão laranja acima do SOS com ⛽ Preciso abastecer, 🚻 Parada para banheiro, ☕ Preciso descansar, 🔧 Problema no veículo, 🐢 Esperem, fiquei para trás; por voz "UauGo, preciso abastecer" (`GroupRequestCommand`). Os pilotos ouvem "Ricardo precisa abastecer", veem no topo e recebem notificação (função `onRequest`). `expeditions/{code}/requests` (regras: só membros, em nome próprio; TTL `expiresAt` 1 h). **Botão amarelo de alerta menor** (74 px). **Lista do capitão** mais alta e mais acima (60% da tela, logo abaixo da faixa da curva), em **duas colunas** com mais de 8 pilotos, e quem saiu do trajeto primeiro. Configurações sem estouro de largura em tela estreita. | C2, C3, Segurança |
| 2026-10-20 | 2.28 | **OK 👍 do capitão nos pedidos ao grupo:** o capitão ou o líder recebe o pedido com o botão "OK 👍" (ou responde "sim" pela voz); quem pediu ouve "Fulano viu seu pedido"; o grupo vê "👍 Fulano confirmou o pedido de X". Regra: só capitão/líder, só os campos `ackBy`/`ackName`/`ackAt`, uma vez. | C2, C3, Segurança |
| 2026-10-20 | 2.29 | **Velocidade da via:** troca de placa só depois de **3 leituras seguidas** (antes 2; `LimitTracker.confirmations`), contra pontos de saída/marginal colados à pista. **Redução à frente:** só avisa se o limite menor aparece em **dois pontos seguidos** à frente (100 m de distância) **e** em **duas leituras do GPS** (`_checkReducedSpeedAhead`). **Radar sem limite na base:** usa o limite da via no local do radar e, se a base não tiver ponto perto dele, o limite da via em que o piloto está (antes: "velocidade não informada"). | C2 |
| 2026-10-20 | 2.30 | **Aparência** em Configurações: **Padrão** (cores originais) ou **Clean** (tudo claro: fundo branco, letra escura, velocímetro branco) com a **cor dos botões** à escolha (laranja, azul, verde, roxo, rosa, cinza) — `cleanTheme`, `AppAccent`, `schemeFor`; cores de segurança fixas (alertas amarelos, SOS e radar vermelhos, pedidos ao grupo laranja). **Banners de alerta em amarelo** com letra preta (radar/velocidade, polícia e demais alertas). **Topo maior** (84 px, letra maior, 2 linhas: chegada e tempo / falta, custo e código) na rota normal e na expedição. **Avisos somem logo depois de passar** pelo radar ou alerta (ficou para trás e a mais de 30 m; antes até ~950 m depois). | C2 |
| 2026-10-20 | 2.31 | **Android Auto (retorno do testador em vídeo):** o mapa do carro ficava em 0,0 (golfo da Guiné) e os botões não respondiam, porque tudo dependia do mapa aberto no celular. Agora: a tela do carro usa o **GPS direto** quando o celular não manda posição (`NavScreen`, `LocationManager`; `CarState.lastDartUpdate`); conectou no carro com a tela inicial aberta, o app **abre o "Dirigir agora" sozinho** (`HomeScreen._onCar`); **Radar/Perigo funcionam sem o mapa aberto** (`CarService._handleWithoutMap`); o carro mostra **aviso curto** (CarToast) em cada botão ("Alerta enviado", "Abra o UauGo no celular", "Nenhuma navegação em andamento"). Limite do Android Auto: só telas-padrão do Google (mapa, faixa da manobra, chegada, até 4 botões), não o layout livre do celular. | C2, C3 |
| 2026-10-21 | 2.32 | **Rota até ponto sem estrada** (ex.: "Deserto do Atacama"): quando o Google responde "sem rota", o servidor troca cada ponto (exceto a saída) pelo lugar com estrada mais próximo (cidade, posto, hospedagem ou atração, até 50 km; Places searchNearby) e tenta de novo (`functions/maps.js`, `nearestRoadPlace`). **Voz:** "UauGo, parar no posto", "parar na pizzaria", "parada restaurante" e "UauGo, adicionar parada" (pergunta o que procurar). **Simular esta viagem** no Resumo da viagem (rota normal). Nome/e-mail do topo da tela inicial não passa por cima da engrenagem. Botão **Salvar** da parada do roteiro acima da barra do Android. **Versão 1.0.5 (6) publicada no teste interno pela API** (`scripts/publicar-teste-interno.js`). | C2, C3 |
| 2026-10-21 | 2.33 | **Preços de pedágio pela internet, toda semana, no n8n da VPS** (sem custo do Claude): fluxo "UauGo - Preços de pedágio (semanal)" (id `UauGoPedagios001`, segunda 3h; gatilho manual por webhook secreto) → função `tollPrices` (GET lista as praças sem preço não conferidas em 30 dias; POST grava `tollPrices/{lat,lng}` com fonte e data, "estimado", e republica `public/pedagios.json.gz`; senha `TOLL_INGEST_SECRET` no cabeçalho `x-uaugo-key`). Cada praça: nome/rodovia/cidade (Nominatim + Overpass) → busca no **SearXNG** da VPS (container `ricardo-searxng`, só rede interna) → **Groq** (llama-3.3-70b) extrai carro/moto, com **OpenAI** (gpt-4o-mini) de reserva. `updateTolls` (mensal, ANTT) agora mescla esses preços (`applyTollPrices`). **Pedágio no planejamento da expedição** (valor e nº de praças para o seu veículo + custo total com combustível). **"Você" desliza** entre as leituras do GPS (0,9 s, igual à câmera; ~15 quadros/s), sem pulos. | C2, C3, Custos |
| 2026-10-21 | 2.34 | Modo leve automático (`AppSettings.lightMode`, RAM via canal `uaugo/device`); expedição não calcula rota só com a saída; cancelar parada (toque/voz `CancelStopCommand`); sem internet: recálculo com aviso único a cada 20 s e busca explica; planejamento com alça para aumentar o mapa; paradas para abastecer a cada X km (`_suggestFuelStops`); viagem planejada (`PlannedTripsService`, saída na prévia); contato de emergência no SOS; **rodízio de São Paulo** (`lib/logic/rodizio.dart`, placa em `ProfileService.loadPlate`, só no celular). Política 1.14. | C2, C3 |
| 2026-10-22 | 2.35 | **1.0.6 (7) publicada no teste interno** (API). **Android Auto com o visual do celular** (`CarOverlay.kt`: faixa verde da manobra, chegada · tempo · km, faixa amarela de aviso, velocímetro com a placa do limite, contagem do radar; ícone do veículo; zoom e rota como no celular; sem os cartões do Android Auto) — ainda não visto no carro. **Rotina de pedágios** passou a rodar **a cada hora, 15 praças** (~9 min; cada praça ~20 s; o limite de 1 h por tarefa não cabia 150): 1ª rodada 11/15 com preço e fonte. **Lista de paradas no Resumo da viagem** (toque no título: distância e chegada de cada parada; visitadas riscadas) — entra na 1.0.7. | C2, C3 |
| 2026-10-22 | 2.36 | **1.0.7 (8) publicada** (lista de paradas no resumo). **Pedágios:** rotina a cada **20 min** (15 praças), na ordem **SP, MG, RJ, PR, SC, RS e depois os demais** (estado pelos arquivos `public/pois/{UF}`; dentro do estado, mais perto de São Paulo). App confere a tabela de pedágios nova **a cada 30 min** enquanto aberto (`TollService.table`). | C2 |
| 2026-10-22 | 2.37 | **Voz atrasada não fala:** além dos avisos, as **instruções de manobra** que esperarem mais de 6 s na fila (uma fala encavalada na outra) são descartadas; ficam só as faixas na tela. SOS do grupo (urgente) sempre fala. | C2 |
| 2026-10-22 | 2.38 | **Limite da via pelo PERFIL DA ROTA** (`RouteLimitProfile` em `lib/logic/speed.dart`; `MapScreen._routeLimitProfile`): com rota, amostra o limite a cada 50 m (de 1 km atrás a 6 km à frente, sentido da rota ±30°) e ignora trechos com limite diferente menores que 400 m (saídas e alças coladas à pista); o velocímetro e o aviso de "velocidade reduzida" leem o perfil. Sem rota (Só dirigir), continua o ponto mais próximo. | C2 |
| 2026-10-22 | 2.39 | **1.0.8 (9)** gerada (perfil do limite pela rota, voz atrasada não fala, custo estimado também sem pedágio + aviso para informar o consumo, tabela de pedágios conferida a cada 30 min, lista de paradas no resumo). Publicação agendada no Windows para 22/10 às 5h (tarefa "UauGo publicar 1.0.8", `C:\Users\Ricardo\.uaugo\publicar_madrugada.cmd`, log em `publicar_madrugada.log`), que depois desliga o computador. | C2 |
| 2026-10-22 | 2.40 | SOS na expedição: "Ir até lá" agora traça uma **rota temporária dentro do UauGo** até o colega (`_goHelp`, reaproveita a rota própria `_personalTrip`), em vez de abrir outro navegador. A volta automática para a rota do grupo fica desligada até chegar a 80 m do colega; aí avisa por voz e retoma a rota da expedição. 1.0.8 (9) gerada de novo com a correção (ainda não tinha subido). | C2 |
| 2026-10-23 | 2.41 | Manifesto: removidas (`tools:node="remove"`) as permissões `AD_ID` e `ACCESS_ADSERVICES_AD_ID` que o Firebase Analytics adiciona; o app não usa anúncios nem o ID de publicidade (coerente com a Política e com a declaração "ID de publicidade = Não" no Play). Vale a partir da próxima versão gerada. | C2 |
| 2026-10-23 | 2.42 | **Correções achadas ao gravar o vídeo do Play:** (1) "Compartilhar posição em segundo plano" não funcionava no Android 14+: o serviço de localização era ligado ao sair do app ("inactive") e o Android recusava (`SecurityException`, FGS location exige app visível). Agora o GPS já nasce no serviço (notificação "UauGo ativo") com o app na tela, sempre que estiver no comboio com a opção ligada (ou no Android Auto), e não é reiniciado ao sair; muda de modo com o app na tela (`_onPosition`). GPS em segundo plano passa a 1 s (antes 15 s), texto da opção ajustado. (2) Roteiro: criar a parada e reordenar agora vão no mesmo lote (`addToItinerary`); separados, a reordenação podia chegar antes ("No document to update") e aparecia "Não foi possível salvar a parada". | C2 |
| 2026-10-13 | 2.21 | Voz: **"UauGo" + pausa** — o Vosk separa a frase na pausa; agora "uau go" sozinho bipa (`WakeCommand`) e por 6 s o comando vale sem a palavra de ativação (`VoiceContext`; gramática com os comandos com e sem "uau go", 332 frases, todas no vocabulário). Procurar: novas categorias (pizza/pizzaria, churrascaria, hambúrguer, sorvete, açaí, bar, estacionamento, lavagem) e **pedido livre** — "procurar" + algo fora da lista abre "O que você procura?" (reconhecimento livre do Android) e busca o texto (`find` com `category: "text"`). Rota por voz inicia sozinha em 5 s (cancelável). | C3 |
| 2026-10-13 | 2.20 | **"UauGo, procurar posto"** (e restaurante, restaurante barato, lanche, café, padaria, pousada/hotel, oficina, pneu, farmácia, hospital, banco, mercado): ação `find` da função `places` (Text Search do Google; navegando, `searchAlongRouteParameters` com a rota; sem rota, por distância; "barato" = `priceLevels`), limite de **10 por usuário por dia** (`LIMITS.find`). No app: `lib/logic/find_places.dart` (categorias, `rankFound`: só o que está à frente na rota), cartão com até 3 opções, voz "Adicionar como parada? sim/não" — navegando inclui a parada sem perder o destino (`TripService.build` + `_applyTrip`); sem rota, abre a prévia até o lugar; no comboio só informa. | B, C2, C3 |
| 2026-10-13 | 2.19 | Destino por voz sem abrir a janela do Google: `SpeechRecognizer` dentro do app (`VoiceCommands.listenDestination`), no próprio aparelho quando disponível (`createOnDeviceSpeechRecognizer`, sem internet) e, se faltar, o do Google; bipe ao começar, faixa "Ouvindo destino…" com o texto parcial no mapa. | C3, Segurança |
| 2026-10-13 | 2.18 | **"UauGo, ir para"** (opção "Pesquisa de trajeto por voz", desligada, em Acessibilidade): o Vosk reconhece a frase (gramática `uau go ir para [unk]`, `GoToCommand`); o destino é ouvido pela janela de reconhecimento do Google (`RecognizerIntent`, `VoiceCommands.recognize`, internet); a tela inicial pesquisa o texto (`SharedPlaceService`), com um só resultado vai direto à prévia, com vários mostra as opções. Navegando, pergunta "Trocar a rota?" (aceita "sim"/"não" por voz). No comboio, não troca o destino. Política de Privacidade v1.9. | B, C3, Segurança |
| 2026-10-13 | 2.17 | Navegando, o "voltar" pergunta **"Sair da navegação?"** (Continuar navegando / Sair) em vez de encerrar a rota direto (`PopScope` em `MapScreen`, `_askExitNavigation`). | C3 |
| 2026-10-13 | 2.16 | **Bateria:** GPS fora da tela só no comboio com a nova opção **"Compartilhar posição em segundo plano"** (desligada; Configurações → Tela), e então econômico (`LocationService.track(background)`: precisão alta, 15 s, sem wake lock; o serviço começa em `inactive`, ainda visível, por exigência do Android 12+). Navegando sozinho, "Só dirigir" ou opção desligada: GPS para ao sair do app (conferido com `dumpsys location`). Ao sair da tela, `_pauseWork` para relógios (30 s, chuva, trânsito, gravação, bateria) e escutas do Firestore; `_resumeWork` religa. Navegando, a tela fica sempre ligada (`_applyWakelock`). Chuva: opção desligada por padrão e só com rota traçada; chuva e trânsito avisam que aumentam dados e bateria. Política de Privacidade v1.8. | B, C2, C3, Segurança |
| 2026-10-11 | 2.15 | **Pedágio no custo da viagem** (sem custo de API): tabela própria `updateTolls` (OSM + ANTT); prévia da rota mostra o valor para o veículo ou avisa que os órgãos não forneceram os valores e se o veículo paga; moto: isenta/metade conforme a praça (sem regra publicada: metade, avisando); custo total combustível + pedágios. **Meu veículo**: triciclo, camionete, SUV, jeep/4x4, motorhome, ônibus, caminhão, bitrem; eixos (pesados) e reboque (fator ANTT, `BikeProfile.tollFactor`); regras do Firestore aceitam `axles`/`trailerAxles`. **Voz: "No semáforo, vire..."** (semáforos do OSM, `TurnByTurn.signalAt`). **Lombadas e semáforos opcionais** (desligados por padrão; arquivos separados, baixados só se ligar). "Para onde?" usa a posição recente do GPS. | B, C2, C3 |
| 2026-10-10 | 2.14 | **"Abrir com UauGo"**: o app aparece ao lado do Google Maps/Waze ao tocar num endereço ou localização (links `geo:`, `google.navigation:`, links do Google Maps) e em "Compartilhar → UauGo" (texto). Ponte nativa própria `SharedPlace.kt` (canal `uaugo/shared_place`, sem pacote novo); `lib/logic/shared_place.dart` entende os formatos (13 testes); `SharedPlaceService` abre links curtos `maps.app.goo.gl` e dá nome a coordenadas soltas. Com posição → prévia da rota direto; só texto → "Para onde?" já buscando. Navegando, não interrompe (avisa). Deep link do Flutter desligado (`flutter_deeplinking_enabled=false`). | B, C2 |
| 2026-10-10 | 2.13 | Nova identidade visual: ícone D1 (trilha pontilhada laranja + seta do líder sobre azul-marinho), paleta azul-marinho #0F1B2D / laranja #FF7A1A (`appColorScheme` em `main.dart`), mapa-múndi pontilhado atrás da marca na tela inicial (`scripts/gerar-mapa-pontilhado.py`), slogan "Em grupo ou sozinho, qualquer caminho é UauGo." (`lib/brand.dart`), velocímetro azul-marinho, arte e capturas da loja refeitas. | B, C2 |
| 2026-10-08 | 2.12 | App renomeado para **UauGo** (Termos v1.3 com novo aceite, Política v1.7). Comandos de voz ativados por **"UauGo"** (`uau go`), com frases de exclamação ("uau [unk]") na gramática para não disparar com "uau, que paisagem"; ignora `[unk]` antes do comando. Testado com voz sintética + ruído: nenhum disparo falso; não reconhece com ruído igual à voz (0 dB). | B, C2, ADR-11 |
| 2026-10-07 | 2.11 | App renomeado para **Convoyar** (antes RodaJunto e Comboio): nome exibido, textos, Termos v1.2 (novo aceite), Política v1.6, páginas públicas. A palavra de ativação dos comandos de voz continua "roda junto" até a definição do nome da assistente. | B, C2 |
| 2026-10-07 | 2.10 | **Fim da navegação no destino**: ao chegar (regra pela rota), a navegação termina sozinha. Sozinho: salva a viagem, desliga o GPS e mostra "Você chegou" (fecha em 20 s). Expedição: para a narração e continua no comboio. Simulação: a moto para. | B, C2 |
| 2026-10-07 | 2.9 | **Bateria em segundo plano**: GPS (e o serviço com notificação fixa) só continua com o app minimizado em **expedição** ou **navegação até um destino**; em "Só dirigir" e na simulação ele para ao sair do app. Desliga sozinho após 15 min parado em segundo plano. O serviço de localização para ao fechar o app pela lista de recentes (`stopWithTask`). | C2, D |
| 2026-10-07 | 2.8 | Alerta **Lombada** (comunidade + `roda junto lombada`). **Chegada medida pela rota** (`hasArrived`/`distanceToStop` em `logic/navigation.dart`): 80 m de estrada (máx. 400 m em linha reta); fora da rota, 120 m em linha reta. Antes: 300 m em linha reta, que na cidade avisava "você chegou" faltando 1 km. | C2 |
| 2026-10-07 | 2.7 | **Acessibilidade: comandos de voz** (opcional, desligado por padrão, só Android). Reconhecimento **offline** com Vosk (`android/.../VoiceCommands.kt`) restrito a uma lista fechada de frases ("roda junto radar"…, "sim"/"não"); modelo pt (~31 MB) baixado do Storage (`public/voz/`) só ao ligar. Política v1.5 (microfone). ADR-11. | B, C2, D, Segurança |
| 2026-10-07 | 2.6 | **"Ainda está lá?"**: ao passar a menos de 150 m de um alerta de outra pessoa, o app pergunta por voz e na tela (botões grandes, 25 s); a resposta vira voto. Painéis de baixo roláveis e acima da barra do Android (`widgets/safe_sheet.dart`). | B, C2 |
| 2026-10-07 | 2.5 | App renomeado para **RodaJunto** (nome exibido, textos, Termos v1.1 com novo aceite, Política v1.4, páginas públicas); identificadores internos continuam `comboio`. Botão de **radar móvel com um toque** e agradecimento por voz ao reportar. Rotina de radares mantém a última lista boa da PRF se a nova falhar e envia **alerta por e-mail** (Cloud Monitoring, `alerta()`). | B, C2, D, Segurança |
| 2026-10-07 | 2.4 | Clube com **vários administradores** (código de ativação por pessoa; promover/rebaixar no app; `setClubAdmin`). 30 clubes conhecidos **pré-cadastrados** como reservados (`scripts/criar-clubes.js`, lista em `scripts/clubes-iniciais.json`). Política v1.3. | B, C1, C2, Segurança |
| 2026-10-06 | 2.3 | **Clube oficial**: criação só com código de ativação da HelpAITech (presidente), entrada só com convite de uso único, presidente remove membros. "Motoclube" passa a se chamar **"Clube"** (serve para jipeiros, carros antigos etc.). Política v1.2. | B, C1, C2, Segurança, ADR-10 |
| 2026-10-06 | 2.2 | App Check **exigido** nas funções chamáveis (`ENFORCE_APP_CHECK=true`), no Firestore e no Storage, após confirmar tokens VALID do aparelho de teste. | D, Segurança, E/F |
| 2026-10-06 | 2.1 | Site público no Firebase Hosting (`public/`, gerado por `scripts/gerar-paginas.js`): Termos, Política (v1.1: rotas passam pelo servidor sem guardar) e exclusão de dados. Chave de upload da Google Play (fora do git) e assinatura da versão final no Gradle. | C2, D, E/F |
| 2026-10-06 | 2.0 | Documento reorganizado no padrão TOGAF. Correções de segurança: rotas/lugares pelo servidor (S1), App Check ativado (S2), fotos restritas (S3), conta obrigatória para recursos compartilhados (S4), 1 voto por pessoa (S5), SOS protegido (S6), validação de campos (S7), códigos de 8 caracteres (S8), dependências atualizadas (S9). | C1, C2, D, Segurança, E/F |
| 2026-10 | 1.x | Login com conta (Google/Apple/e-mail) vinculado ao anônimo; Termos de Uso e Política com aceite registrado; paradas na prévia da rota; busca de lugares no exterior. | B, C2 |

---

## Gestão de requisitos e decisões de arquitetura (ADRs)

### Requisitos não funcionais

| Id | Requisito |
|---|---|
| RNF-01 | Rodar fluido em celulares de entrada (P1). |
| RNF-02 | Navegação, radares e limites funcionam sem internet (P6). |
| RNF-03 | Conformidade com a LGPD: autorização, exclusão, retenção curta (P4). |
| RNF-04 | Nenhuma chave de API paga dentro do app (P5). |
| RNF-05 | Custo mensal proporcional ao uso, com limites por usuário (P3). |

### ADRs

| Id | Decisão | Motivo | Consequência |
|---|---|---|---|
| ADR-01 | Flutter + Firebase | Um código para Android e iPhone; backend sem servidor próprio. | Dependência do Google/Firebase. |
| ADR-02 | Histórico só no celular | Custo e privacidade (pedido do responsável). | Desinstalar apaga o histórico. |
| ADR-03 | Conta anônima vinculada ao login | Usa o app sem cadastro; ao entrar, mantém o mesmo uid e os dados. | Regras distinguem anônimo (`sign_in_provider`). |
| ADR-04 | Dados abertos processados no servidor e baixados por estado | Leveza e custo (P1, P3). | Rotinas diárias/semanais nas Functions. |
| ADR-05 | Rotas e lugares por proxy no servidor (`maps.js`) | A chave no APK podia ser extraída (S1). | +1 salto de rede (~100–300 ms); limite diário por usuário em `usage/{uid}`. |
| ADR-06 | Conta de verdade para recursos compartilhados | Evita spam com contas descartáveis (S4). | Quem só navega não precisa de conta. |
| ADR-07 | Voto registrado em `hazards/{id}/votes/{uid}` no mesmo lote | Única forma de garantir 1 voto por pessoa só com regras (S5). | TTL também em `votes`. |
| ADR-08 | Códigos de 8 caracteres | Inviabiliza adivinhar convites (S8). | Códigos antigos de 6 continuam válidos. |
| ADR-09 | App Check exigido só após registrar os aparelhos de teste | Exigir antes quebraria as versões de teste. | Período curto com App Check só monitorando. |
| ADR-10 | Clube oficial controlado pelo servidor (ativação + convite de uso único) | Garantir que só administradores autorizados pela HelpAITech gerenciem clubes e só membros oficiais entrem (pedido do responsável). | HelpAITech precisa emitir códigos; clubes antigos (sem código) continuam, sem novos membros por código. |
| ADR-11 | Comandos de voz com Vosk offline + gramática fechada, ativados pela palavra "UauGo" (reconhecida como "uau go"; antes "roda junto") | Mãos livres para quem usa luva, sem enviar áudio, sem internet e sem disparo falso (testado com ruído de 0 dB: comandos certos, conversa e barulho nunca dispararam). O reconhecedor do sistema (speech_to_text) não escuta continuamente e apita; o pacote vosk_flutter estava abandonado, por isso a ponte nativa própria. | +~3 MB no app (bibliotecas) e 31 MB baixados só por quem liga; ouve só com o mapa aberto; iPhone fica para depois. |
