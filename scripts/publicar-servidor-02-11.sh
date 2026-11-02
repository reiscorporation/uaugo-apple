#!/bin/bash
# Rodar uma vez: libera a Routes API na chave do servidor e publica regras,
# funções e o complemento de limites. Não mostra a chave.
set -e
cd "$(dirname "$0")/.."
K=$(grep '^MAPS_SERVER_KEY=' functions/.env | cut -d= -f2- | tr -d '"\r')
N=$(gcloud services api-keys lookup "$K" --format='value(name)')
SV=$(gcloud services api-keys describe "$N" --format=json | python -c "import json,sys;print(' '.join(t['service'] for t in json.load(sys.stdin).get('restrictions',{}).get('apiTargets',[])))")
echo "APIs na chave: $SV"
if [ -n "$SV" ] && [[ " $SV " != *" routes.googleapis.com "* ]]; then
  A=""
  for s in $SV routes.googleapis.com; do A="$A --api-target=service=$s"; done
  gcloud services api-keys update "$N" $A --quiet >/dev/null
  echo "Routes API incluída na chave"
fi
firebase deploy --only firestore:rules,functions:routeTraffic,functions:onRequest,functions:updateSpeedLimits --project helpaitechcomboio --force
BUCKET=$(python -c "import json;print(json.load(open('firebase.json')).get('storage',{}).get('bucket','') or 'helpaitechcomboio.firebasestorage.app')")
gcloud storage cp /e/UauGo-motor/limites-osm/*.json.gz "gs://$BUCKET/public/limites-osm/"
gcloud scheduler jobs run firebase-schedule-updateSpeedLimits-southamerica-east1 --location=southamerica-east1 --project helpaitechcomboio
echo PRONTO
