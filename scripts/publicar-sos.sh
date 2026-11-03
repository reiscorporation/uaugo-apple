#!/bin/bash
# Rodar uma vez: publica as regras, o TTL e a página do SOS em tempo real.
set -e
cd "$(dirname "$0")/.."
firebase deploy --only firestore:rules,firestore:indexes,hosting --project helpaitechcomboio
echo PRONTO
