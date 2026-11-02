# Plano: motor de rotas próprio (sair dos serviços pagos do Google)

Decisão do Ricardo (24/10/2026): criar o motor próprio, com cuidado para traçar sempre a melhor rota.

## Por quê
- O mapa exibido no app é grátis; o que custa é **calcular rotas** e **buscar lugares** no Google.
- Motor próprio: **Valhalla** (código aberto) + mapa do **OpenStreetMap**. Tem perfil de **moto**, "evitar área"
  (rodízio), evitar pedágio/rodovias/balsas e manobras em português. Não tem trânsito em tempo real.

## Etapas
| Etapa | O que | Situação |
|---|---|---|
| 1 | Medir o gasto atual com rota/busca | pendente |
| 2 | Montar o Valhalla com o mapa do Brasil (no PC; o servidor só serve) | **feito 25/10** (`E:\UauGo-motor`) |
| 3 | Servidor: Valhalla na VPS (8 GB), app pede ao nosso servidor e cai no Google se falhar | em andamento (02/11): `/opt/helpaitech/motor`, Caddy com chave em `motor.200-141-16-177.sslip.io` |
| 4 | Moto (Marginais) + rodízio (exclude_polygons) no motor próprio | pendente (ver teste) |
| 5 | Busca com Photon, Google como reserva | pendente |
| 6 | Mapa offline (opcional) | pendente |

## Primeiro teste (25/10/2026) — `E:\UauGo-motor\comparacao.txt`
- Distâncias iguais às do Google (±1 km) em Ribeirão→SP, →Campinas, →Pirassununga e Guarulhos→Pinheiros.
- Tempos 10–20% maiores (velocidades padrão, sem trânsito): **calibrar velocidades** antes de usar.
- Moto x carro na Marginal Tietê: inconclusivo; conferir `motorcycle=no` das expressas no OSM.

## Trânsito (decisão 28/10/2026)
- O motor não tem trânsito. Fonte final: **os próprios usuários** (velocidade real de quem está com o app
  aberto em cada trecho, anônima) + **horário típico** aprendido com o tempo (ex.: avenida lenta às 18h).
- **No começo, o Google informa o trânsito** até haver usuários suficientes em cada região: o motor traça o
  caminho e o Google só diz se há lentidão (e, se houver, oferece a rota dele). Menos chamadas que hoje.

## Motor na próxima versão (decisão 02/11/2026)
- O motor traça as rotas e o Google fica com o trânsito: `routeTraffic` a cada 5 min dá cores, tempo real e atraso. Com atraso grande, viagem sozinho pede uma rota ao Google (no máximo a cada 15 min).
- Ainda pelo Google: evitar pedágio, áreas de risco e queda do motor.
- Medição no PC limitado a 2 CPUs (mistura de cidade, estrada e longas, 30% com alternativas): 38 rotas/s com 2 simultâneas, mediana 42 ms, p95 109 ms; com 8 simultâneas, 30 rotas/s e p95 494 ms. Memória 462 MiB depois do teste. Falta repetir na VPS.

## Teste no Galaxy + comparação ampla (28/10/2026) — `E:/UauGo-motor/comparacao-2026-10-28.md`
- Galaxy (versão de teste, Wi-Fi de casa) traçou rotas pelo motor. Limite de distância removido
  (`service_limits.*.max_distance` = 100.000 km no `valhalla.json`; moto vinha com 500 km e recusava a Bahia).
- Comparação automática: `python E:/UauGo-motor/comparar.py` (41 viagens: estrada, longas, cidade, sem pedágio).
  - Estrada: distância +3% e tempo +14% em média; erros a corrigir: RP→São Carlos (+24 km),
    RP→Poços de Caldas (+27 km), RP→Franca (+17 km), RP→BH (+27 km).
  - Cidade de Ribeirão: o motor escolhe caminhos piores (USP→Ribeirão Shopping +6 km).
  - Campinas: tempo 70–100% maior (velocidades urbanas baixas demais).
  - **Evitar pedágio não funciona**: no Brasil o OSM marca a rodovia inteira como pedágio (`toll=yes`, ex.:
    SP-330), mas só se paga na praça. `exclude_tolls` dá 561 km (Google: 418 km sem pedágio) e
    `toll_booth_penalty` usa praças do OSM que não batem com as do Google. Caminho: evitar as **nossas praças**
    (tabela de pedágios do app) com `exclude_locations`, sem penalizar a rodovia.
  - A coluna "caminho igual" desta rodada usou o resumo do traçado do Google (corta curvas); o script já usa o
    traçado detalhado nas próximas rodadas.

## Como montar de novo
- Mapa: `https://download.geofabrik.de/south-america/brazil-latest.osm.pbf` em `E:\UauGo-motor\dados`.
- Docker: `ghcr.io/valhalla/valhalla-scripted:latest`, porta 8002, `server_threads=4`
  (com 16 tarefas estourou a memória de 8 GB do Docker). Leva ~6 h neste PC.
