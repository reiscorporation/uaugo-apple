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
| `updateRadars` | Segunda e quinta 05:00 | Radares (Pardal) + trechos da PRF → `public/radares.json.gz`. `radars.js`. |
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
| Enviar o AAB ao teste fechado e cadastrar o SHA da chave de assinatura da Play no Firebase e no mapa | Conta Play | Pendente |
| Vincular o projeto do Google Cloud no Play Console (Integridade do app → Play Integrity API), senão o App Check recusa quem baixar da loja | 1º envio do AAB | Pendente |
| ✅ Exigir App Check (funções: `ENFORCE_APP_CHECK=true`; Firestore e Storage no console) | Tokens de depuração dos aparelhos de teste registrados | ✅ Feito |
| Ativar o login com Google no console do Firebase | — | Pendente (responsável) |
| Contas nas lojas (Google Play, Apple Developer) | Definição do nome | Pendente (responsável) |
| Nome do app: UauGo (trocado em 2026-10-07) | — | ✅ Feito |
| Registro da marca UauGo no INPI | Responsável | Pendente |
| Backup no Google Drive da HelpAITech | Google Drive para computador | Pendente (responsável) |

### Próximas versões (anotado para tratar)

| Item | Detalhe | Onde mexer | Situação |
|---|---|---|---|
| Narração lê algarismos romanos letra por letra | "Av. Leão XIII" é falado "Leão X I I I"; o certo é "Leão Treze". Converter números romanos nos nomes de rua (XIII → treze, Pio X → Pio Décimo/Dez, D. Pedro II → Dom Pedro Segundo) antes de falar, sem confundir siglas comuns (ex.: "MG", "BR", "CIC"). | `cleanInstruction` em `lib/logic/navigation.dart` (+ teste em `test/navigation_test.dart`) | Pendente |
| Alertas que não mudam viram fixos após 3 confirmações | Hoje todo alerta da comunidade expira (lombada: 7 dias). Lombada (e outros tipos permanentes que vierem a existir, ex.: semáforo/posto não mapeado) confirmada por **3 pessoas diferentes** (contas distintas) deve ficar **fixa**, sem expirar. Continua a pergunta "ainda está lá?": se 3 pessoas disserem que não está mais, sai. Tipos que mudam (polícia, radar móvel, óleo, animal, acidente, neblina, buraco) continuam expirando. | `HazardType` em `lib/models/hazard.dart` (marcar tipos permanentes), `HazardService` (`expiresAt` ao confirmar), regras do Firestore (permitir sem prazo só com 3 confirmações), TTL de `hazards` | Pendente |

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
