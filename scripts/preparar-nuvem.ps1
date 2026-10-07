<#
  Comboio - configura o Google Cloud e o Firebase pela linha de comando:
  ativa APIs, cria o banco, cria as chaves do Maps restritas, liga o TTL
  dos alertas e publica regras e funções.

  Antes, faça no console do Firebase (só você pode):
    - plano Blaze (Uso e faturamento)
    - Authentication > Sign-in method > Anônimo
    - Storage > Começar (região southamerica-east1)
#>
. "$PSScriptRoot\comum.ps1"
Set-Location $Root
$cfg = Read-Config
$proj = Get-Valor $cfg 'FIREBASE_PROJECT_ID' ''
$org  = Get-Valor $cfg 'ORG' 'com.seunome'
$pkg  = "$org.comboio"
if (-not $proj) { throw 'Preencha FIREBASE_PROJECT_ID em config.env' }
foreach ($c in 'gcloud', 'firebase') { if (-not (Test-Comando $c)) { throw "$c não encontrado. Rode o instalar.ps1." } }

$r = Read-Host 'Você já ativou no console: plano Blaze, login Anônimo e Storage? (s/n)'
if ($r -notmatch '^[sS]') {
  Start-Process "https://console.firebase.google.com/project/$proj/overview"
  Write-Aviso 'Abri o console. Faça esses três itens e rode o script de novo.'; exit 0
}

gcloud config set project $proj | Out-Null

Write-Etapa 'Ativando APIs (pode levar alguns minutos)'
gcloud services enable firestore.googleapis.com apikeys.googleapis.com `
  maps-android-backend.googleapis.com maps-ios-backend.googleapis.com `
  directions-backend.googleapis.com cloudscheduler.googleapis.com
Write-Ok 'APIs ativas'

Write-Etapa 'Banco Firestore em São Paulo'
gcloud firestore databases describe --database='(default)' 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Ok 'Banco já existe' }
else {
  gcloud firestore databases create --location=southamerica-east1
  Write-Ok 'Banco criado'
}

Write-Etapa 'Impressão digital (SHA-1) de depuração do Android'
$keytool = Join-Path ${env:ProgramFiles} 'Android\Android Studio\jbr\bin\keytool.exe'
if (-not (Test-Path $keytool)) { $keytool = 'keytool' }
# Em inglês: o keytool do Java 25 quebra ao imprimir as mensagens em português.
$ktLang = @('-J-Duser.language=en', '-J-Duser.country=US')
$ks = Join-Path $env:USERPROFILE '.android\debug.keystore'
if (-not (Test-Path $ks)) {
  New-Item -ItemType Directory -Force -Path (Split-Path $ks) | Out-Null
  & $keytool @ktLang -genkeypair -v -keystore $ks -storepass android -alias androiddebugkey -keypass android `
    -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US' | Out-Null
}
$m = & $keytool @ktLang -list -v -keystore $ks -alias androiddebugkey -storepass android -keypass android |
  Select-String 'SHA1:\s*([0-9A-F:]+)'
if (-not $m) { throw 'Não consegui ler o SHA-1. Confira se o Android Studio está instalado.' }
$sha1 = $m.Matches[0].Groups[1].Value
Write-Ok "SHA-1: $sha1"

function New-ChaveMaps([string]$Nome, [string[]]$Extra) {
  $existe = gcloud services api-keys list --filter="displayName='$Nome'" --format='value(name)'
  if (-not $existe) {
    gcloud services api-keys create --display-name=$Nome @Extra | Out-Null
    $existe = gcloud services api-keys list --filter="displayName='$Nome'" --format='value(name)'
  }
  $id = ($existe -split "`n")[0].Trim()
  return (gcloud services api-keys get-key-string $id --format='value(keyString)').Trim()
}

Write-Etapa 'Criando as chaves do Google Maps (restritas)'
$kAndroid = New-ChaveMaps 'Comboio Android' @('--api-target=service=maps-android-backend.googleapis.com', "--allowed-application=sha1_fingerprint=$sha1,package_name=$pkg")
$kIos     = New-ChaveMaps 'Comboio iOS'     @('--api-target=service=maps-ios-backend.googleapis.com', "--allowed-bundle-ids=$pkg")
# Rotas e busca de lugares: chave SÓ do servidor (nunca entra no app).
$kSrv     = New-ChaveMaps 'Comboio Servidor (rotas e lugares)' @('--api-target=service=directions-backend.googleapis.com', '--api-target=service=places.googleapis.com')
Set-ConfigValue 'ANDROID_MAPS_KEY' $kAndroid
Set-ConfigValue 'IOS_MAPS_KEY' $kIos
Write-Ok 'Chaves do mapa salvas em config.env'
$envFile = Join-Path $Root 'functions/.env'
$linhas = if (Test-Path $envFile) { @(Get-Content $envFile | Where-Object { $_ -notmatch '^MAPS_SERVER_KEY=' }) } else { @() }
[IO.File]::WriteAllLines($envFile, $linhas + "MAPS_SERVER_KEY=$kSrv", $Utf8)
Write-Ok 'Chave do servidor salva em functions/.env'
Invoke-AplicarConfig (Read-Config)

Write-Etapa 'Expiração automática dos alertas (TTL)'
gcloud firestore fields ttls update expiresAt --collection-group=hazards --enable-ttl --async | Out-Null
Write-Ok 'TTL solicitado (ativa em alguns minutos)'

Write-Etapa 'Publicando regras, índices e funções'
Push-Location functions; npm install; Pop-Location
firebase deploy --only firestore,storage,functions --project $proj
if ($LASTEXITCODE -ne 0) { Write-Aviso 'O deploy falhou. Confira a mensagem acima (plano Blaze ativo?).' }
else { Write-Ok 'Backend publicado' }

Write-Host "`nNuvem pronta! Conecte o celular e rode: .\scripts\rodar.ps1" -ForegroundColor Cyan
Write-Host "Quando gerar a versão de loja, adicione o SHA-1 de release à chave 'Comboio Android'." -ForegroundColor Cyan
