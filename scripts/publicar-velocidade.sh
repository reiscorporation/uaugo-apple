#!/bin/bash
# Publica a correção de velocidade (regras speedReports/speedFixes e a função
# onSpeedReport). Rodar no Git Bash: bash scripts/publicar-velocidade.sh
cd "$(dirname "$0")/.."
FUNCTIONS_DISCOVERY_TIMEOUT=120 firebase deploy --only firestore:rules,functions:onSpeedReport --project helpaitechcomboio --force
echo PRONTO
