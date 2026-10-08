<#
  Convoyar - testa o app no emulador do Android usando o Firebase Emulator
  Suite (banco, login, funções e arquivos rodando no seu computador).
  Não usa a nuvem e não gera custo. O mapa fica vazio sem a chave do Maps
  e os pushes aparecem só no log dos emuladores ("[push simulado]").

    .\scripts\testar-local.ps1
    .\scripts\testar-local.ps1 -d ID_DO_APARELHO   (veja os IDs com: flutter devices)

  Funciona no emulador do Android (o celular de verdade não enxerga o PC).
  Ao alternar entre este modo e a nuvem (rodar.ps1), limpe os dados do app
  (adb shell pm clear helpaitech.comboio): o login de um não vale no outro.
  Painel dos emuladores (dados, usuários, logs): http://localhost:4000
#>
. "$PSScriptRoot\comum.ps1"
Set-Location $Root
$cfg = Read-Config
$proj = Get-Valor $cfg 'FIREBASE_PROJECT_ID' ''
if (-not $proj) { throw 'Preencha FIREBASE_PROJECT_ID em config.env' }

Write-Etapa 'Java para os emuladores'
$jbr = Join-Path ${env:ProgramFiles} 'Android\Android Studio\jbr'
if (Test-Path (Join-Path $jbr 'bin\java.exe')) {
  $env:JAVA_HOME = $jbr
  $env:Path = (Join-Path $jbr 'bin') + ';' + $env:Path
  Write-Ok 'Usando o Java do Android Studio'
} else {
  Write-Aviso 'Java do Android Studio não encontrado; os emuladores precisam de Java 21 ou mais novo.'
}

Write-Etapa 'Dependências das funções'
if (-not (Test-Path 'functions/node_modules')) {
  Push-Location functions; npm install; Pop-Location
}
Write-Ok 'functions/node_modules'

# Os emuladores usam http (sem TLS): libera só na versão de depuração do app.
$debugManifest = Join-Path $Root 'android/app/src/debug/AndroidManifest.xml'
Update-Arquivo $debugManifest {
  param($t)
  if ($t -match 'usesCleartextTraffic') { return $t }
  return $t -replace '</manifest>', "    <application android:usesCleartextTraffic=`"true`"/>`n</manifest>"
}

function Test-Porta([int]$Porta) {
  $c = New-Object Net.Sockets.TcpClient
  try { $c.Connect('127.0.0.1', $Porta); return $true } catch { return $false } finally { $c.Close() }
}

Write-Etapa 'Emuladores do Firebase'
$portas = 9099, 5001, 8080, 9199
if (-not ($portas | Where-Object { -not (Test-Porta $_) })) { Write-Ok 'Já estavam rodando' }
else {
  Start-Process powershell -ArgumentList '-NoExit', '-Command', "Set-Location '$Root'; firebase emulators:start --project $proj"
  Write-Host '    Aguardando os emuladores (abrem numa janela separada; deixe-a aberta)...'
  $limite = (Get-Date).AddMinutes(3)
  while (($portas | Where-Object { -not (Test-Porta $_) }) -and (Get-Date) -lt $limite) { Start-Sleep 2 }
  if ($portas | Where-Object { -not (Test-Porta $_) }) { throw 'Os emuladores não subiram. Veja a mensagem na outra janela.' }
  Write-Ok 'Emuladores no ar. Painel: http://localhost:4000'
}

Write-Etapa 'Emulador do Android'
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$emu = Join-Path $sdk 'emulator\emulator.exe'
if (($args -contains '-d') -or ((& $adb devices) -match '^emulator-\d+\s+device')) { Write-Ok 'Aparelho já conectado' }
else {
  $avd = & $emu -list-avds | Where-Object { $_ -and $_ -notmatch '^(INFO|WARNING)' } | Select-Object -First 1
  if (-not $avd) { throw 'Nenhum emulador criado. Crie um no Android Studio (Device Manager).' }
  # 'auto': usa a placa de vídeo quando o driver é compatível (NVIDIA 553+)
  # e cai para gráficos por software quando não é.
  Start-Process $emu -ArgumentList '-avd', $avd, '-gpu', 'auto'
  Write-Host "    Ligando $avd (pode levar alguns minutos)..."
  & $adb wait-for-device
  while ((& $adb shell getprop sys.boot_completed) -notmatch '1') { Start-Sleep 2 }
  Write-Ok "$avd pronto"
}

Write-Etapa 'Abrindo o app em modo de teste local'
if (-not (Test-Path 'config/dart_defines.json')) { Invoke-AplicarConfig $cfg }
flutter run --dart-define-from-file=config/dart_defines.json --dart-define=USE_EMULATOR=true @args
