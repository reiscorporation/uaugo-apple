#!/bin/sh
# Ruas do minimapa do 3D, geradas NA VPS (17/11; antes no PC, mas o envio de
# ~730 mil arquivos pela internet de casa não era viável).
#
# Lê o mapa do Brasil que o atualizador dos lugares já baixa toda semana
# (/opt/helpaitech/pois/osm/brazil-latest.osm.pbf), gera os quadrados com
# gerar-ruas-minimapa.py e troca a pasta servida de uma vez:
#   /opt/helpaitech/mapa/publico/ruas  ->  https://motor.../ruas/<ilat>_<ilng>.json.gz
# (contêiner uaugo-mapa; bloco "handle /ruas/*" em proxy/sites/motor.caddy).
#
# Instalar (uma vez), no PC:
#   scp -i ~/.ssh/hostinger_vps scripts/gerar-ruas-minimapa.py scripts/vps-ruas-atualizar.sh root@200.141.16.177:/opt/helpaitech/ruas-minimapa/
# Cron mensal (dia 2, 04:40, depois do domingo dos lugares): crontab do root.
set -e
cd /opt/helpaitech/ruas-minimapa
PBF=/opt/helpaitech/pois/osm/brazil-latest.osm.pbf
DEST=/opt/helpaitech/mapa/publico
rm -rf "$DEST/ruas.novo"
python3 -I gerar-ruas-minimapa.py "$PBF" "$DEST/ruas.novo"
# Troca: a pasta antiga sai e a nova entra (o app só vê um dos dois).
if [ -d "$DEST/ruas" ]; then mv "$DEST/ruas" "$DEST/ruas.velho"; fi
mv "$DEST/ruas.novo" "$DEST/ruas"
rm -rf "$DEST/ruas.velho"
echo "ruas atualizadas $(date)"
