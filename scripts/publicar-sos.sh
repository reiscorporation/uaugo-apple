#!/bin/bash
# Rodar uma vez: publica as regras, a função e a página do SOS em tempo real.
set -e
cd "$(dirname "$0")/.."
FUNCTIONS_DISCOVERY_TIMEOUT=120 firebase deploy --only firestore:rules,firestore:indexes,functions:sosLive,hosting --project helpaitechcomboio --force
echo PRONTO
