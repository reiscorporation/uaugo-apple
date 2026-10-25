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
| 3 | Servidor: Valhalla na VPS (8 GB), app pede ao nosso servidor e cai no Google se falhar | pendente |
| 4 | Moto (Marginais) + rodízio (exclude_polygons) no motor próprio | pendente (ver teste) |
| 5 | Busca com Photon, Google como reserva | pendente |
| 6 | Mapa offline (opcional) | pendente |

## Primeiro teste (25/10/2026) — `E:\UauGo-motor\comparacao.txt`
- Distâncias iguais às do Google (±1 km) em Ribeirão→SP, →Campinas, →Pirassununga e Guarulhos→Pinheiros.
- Tempos 10–20% maiores (velocidades padrão, sem trânsito): **calibrar velocidades** antes de usar.
- Moto x carro na Marginal Tietê: inconclusivo; conferir `motorcycle=no` das expressas no OSM.

## Como montar de novo
- Mapa: `https://download.geofabrik.de/south-america/brazil-latest.osm.pbf` em `E:\UauGo-motor\dados`.
- Docker: `ghcr.io/valhalla/valhalla-scripted:latest`, porta 8002, `server_threads=4`
  (com 16 tarefas estourou a memória de 8 GB do Docker). Leva ~6 h neste PC.
