<#
  UauGo - monta o projeto e aplica todas as configurações.

    .\scripts\configurar.ps1            # uso normal
    .\scripts\configurar.ps1 -CI        # usado pelo GitHub Actions
    .\scripts\configurar.ps1 -SemFirebase
#>
param([switch]$CI, [switch]$SemFirebase)
. "$PSScriptRoot\comum.ps1"
Set-Location $Root

if (-not (Test-Path $EnvFile)) {
  Copy-Item (Join-Path $Root 'config.env.example') $EnvFile
  if (-not $CI) {
    Write-Aviso 'Criei o arquivo config.env. Preencha pelo menos ORG e FIREBASE_PROJECT_ID e rode de novo.'
    notepad $EnvFile
    exit 0
  }
}
$cfg = Read-Config
$org = Get-Valor $cfg 'ORG' 'com.seunome'
if ($org -eq 'com.seunome' -and -not $CI) {
  Write-Aviso 'ORG ainda é "com.seunome". Troque em config.env antes de publicar (não poderá mudar depois).'
}

Write-Etapa 'Gerando as pastas nativas (Android e iOS)'
$jaTem = (Test-Path 'android/app/build.gradle') -or (Test-Path 'android/app/build.gradle.kts')
if ($jaTem) { Write-Ok 'Pastas já existem' }
else {
  flutter create --org $org --project-name comboio --platforms=android,ios .
  if ($LASTEXITCODE -ne 0) { throw 'flutter create falhou' }
  Write-Ok "Projeto criado como $org.comboio"
}

Write-Etapa 'Aplicando configurações'
Invoke-AplicarConfig $cfg

Write-Etapa 'Baixando dependências'
flutter pub get
if ($LASTEXITCODE -ne 0) {
  Write-Aviso 'Conflito de versões. Tentando atualizar os pacotes...'
  flutter pub upgrade --major-versions
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou' }
}
Write-Ok 'Dependências'

Write-Etapa 'Ícone do app (assets/branding)'
dart run flutter_launcher_icons | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Ok 'Ícone gerado para Android e iOS' }
else { Write-Aviso 'Não foi possível gerar o ícone (rode: dart run flutter_launcher_icons)' }

$proj = Get-Valor $cfg 'FIREBASE_PROJECT_ID' ''
if (-not $CI -and -not $SemFirebase) {
  if (-not $proj) {
    Write-Aviso 'FIREBASE_PROJECT_ID vazio: pulei a ligação com o Firebase.'
  } else {
    Write-Etapa "Ligando o app ao Firebase ($proj)"
    flutterfire configure --project=$proj --platforms=android,ios `
      --android-package-name="$org.comboio" --ios-bundle-id="$org.comboio" --yes
    if ($LASTEXITCODE -ne 0) { Write-Aviso 'flutterfire configure falhou. Rode "firebase login" e tente de novo.' }
    else { Write-Ok 'lib/firebase_options.dart gerado' }
  }
}

Write-Host "`nPronto! Próximo passo: .\scripts\preparar-nuvem.ps1 (ou .\scripts\rodar.ps1 se a nuvem já estiver pronta)." -ForegroundColor Cyan
