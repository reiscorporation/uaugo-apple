<#
  Comboio - roda os testes automáticos.
    .\scripts\testar.ps1           # testes do app + regras de segurança
    .\scripts\testar.ps1 -SoApp    # só os testes do app (não precisa de Java)
#>
param([switch]$SoApp)
. "$PSScriptRoot\comum.ps1"
Set-Location $Root

Write-Etapa 'Análise estática'
flutter analyze --no-fatal-infos --no-fatal-warnings

Write-Etapa 'Testes do app'
flutter test
$falhou = $LASTEXITCODE -ne 0

if (-not $SoApp) {
  Write-Etapa 'Testes das regras de segurança (emulador do Firebase, precisa de Java 21)'
  Push-Location tests/rules; npm install --silent; Pop-Location
  firebase emulators:exec --only firestore --project demo-comboio 'npm --prefix tests/rules test'
  if ($LASTEXITCODE -ne 0) { $falhou = $true }
}

if ($falhou) { Write-Aviso 'Há testes falhando. Veja as mensagens acima.'; exit 1 }
Write-Host "`nTodos os testes passaram." -ForegroundColor Green
