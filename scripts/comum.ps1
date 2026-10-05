# Funções compartilhadas pelos scripts do Comboio (Windows, Mac e Linux com PowerShell 7).
# 'Continue' porque ferramentas como gcloud escrevem progresso no stderr;
# as falhas são verificadas por $LASTEXITCODE e 'throw'.
$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root 'config.env'
$Utf8 = New-Object System.Text.UTF8Encoding $false

function Write-Etapa([string]$Texto) { Write-Host "`n==> $Texto" -ForegroundColor Yellow }
function Write-Ok([string]$Texto) { Write-Host "    OK  $Texto" -ForegroundColor Green }
function Write-Aviso([string]$Texto) { Write-Host "    !!  $Texto" -ForegroundColor Magenta }

function Test-Comando([string]$Nome) { return [bool](Get-Command $Nome -ErrorAction SilentlyContinue) }

function Read-Config {
  $cfg = @{}
  if (Test-Path $EnvFile) {
    foreach ($line in [IO.File]::ReadAllLines($EnvFile)) {
      if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
      $parts = $line -split '=', 2
      $cfg[$parts[0].Trim()] = $parts[1].Trim()
    }
  }
  return $cfg
}

function Set-ConfigValue([string]$Key, [string]$Value) {
  $lines = @()
  if (Test-Path $EnvFile) { $lines = @([IO.File]::ReadAllLines($EnvFile)) }
  $found = $false
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($l in $lines) {
    if ($l -match "^\s*$([regex]::Escape($Key))\s*=") { $out.Add("$Key=$Value"); $found = $true }
    else { $out.Add($l) }
  }
  if (-not $found) { $out.Add("$Key=$Value") }
  [IO.File]::WriteAllLines($EnvFile, $out, $Utf8)
}

function Update-Arquivo([string]$Path, [scriptblock]$Transform) {
  if (-not (Test-Path $Path)) { Write-Aviso "Arquivo não encontrado: $Path"; return }
  $text = [IO.File]::ReadAllText($Path)
  $new = & $Transform $text
  if ($new -ne $text) { [IO.File]::WriteAllText($Path, $new, $Utf8) }
}

function Get-Valor($cfg, [string]$Key, [string]$Padrao) {
  if ($cfg.ContainsKey($Key) -and $cfg[$Key]) { return $cfg[$Key] }
  return $Padrao
}

# Aplica chaves e ajustes de plataforma. Pode rodar quantas vezes quiser.
function Invoke-AplicarConfig($cfg) {
  $androidKey = Get-Valor $cfg 'ANDROID_MAPS_KEY' 'SUA_CHAVE_ANDROID_AQUI'
  $iosKey     = Get-Valor $cfg 'IOS_MAPS_KEY' 'SUA_CHAVE_IOS_AQUI'
  $dirKey     = Get-Valor $cfg 'DIRECTIONS_API_KEY' ''

  # --- Android: permissões, chave do Maps e apps externos (WhatsApp, telefone)
  $manifest = Join-Path $Root 'android/app/src/main/AndroidManifest.xml'
  Update-Arquivo $manifest {
    param($t)
    if ($t -notmatch 'ACCESS_FINE_LOCATION') {
      $perms = @(
        'INTERNET', 'ACCESS_FINE_LOCATION', 'ACCESS_COARSE_LOCATION',
        'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_LOCATION', 'WAKE_LOCK',
        'POST_NOTIFICATIONS'
      ) | ForEach-Object { "    <uses-permission android:name=`"android.permission.$_`"/>" }
      $t = ([regex]'(<manifest[^>]*>)').Replace($t, ('${1}' + "`n" + ($perms -join "`n")), 1)
    }
    if ($t -notmatch 'com\.google\.android\.geo\.API_KEY') {
      $meta = "        <meta-data android:name=`"com.google.android.geo.API_KEY`" android:value=`"$androidKey`"/>`n    </application>"
      $t = ([regex]'\s*</application>').Replace($t, "`n" + $meta, 1)
    }
    if ($t -notmatch 'TTS_SERVICE') {
      # Android 11+: sem isto o app não enxerga o sintetizador de voz.
      $q = "        <intent><action android:name=`"android.intent.action.TTS_SERVICE`"/></intent>`n    </queries>"
      $t = ([regex]'\s*</queries>').Replace($t, "`n" + $q, 1)
    }
    if ($t -notmatch 'android:scheme="tel"') {
      $q = "        <intent><action android:name=`"android.intent.action.VIEW`"/><data android:scheme=`"https`"/></intent>`n" +
           "        <intent><action android:name=`"android.intent.action.DIAL`"/><data android:scheme=`"tel`"/></intent>`n    </queries>"
      $t = ([regex]'\s*</queries>').Replace($t, "`n" + $q, 1)
    }
    $t = $t -replace 'android:label="comboio"', 'android:label="Comboio"'
    $t -replace '(android:name="com\.google\.android\.geo\.API_KEY"\s*android:value=")[^"]*(")', ('${1}' + $androidKey + '${2}')
  }
  Write-Ok 'Permissões e chave do Maps no AndroidManifest'

  # --- Android: versão mínima 23
  foreach ($g in @('android/app/build.gradle.kts', 'android/app/build.gradle')) {
    $p = Join-Path $Root $g
    if (Test-Path $p) {
      Update-Arquivo $p { param($t) $t -replace 'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 23' }
      Write-Ok "minSdk = 23 em $g"
    }
  }

  # --- Android: o Kotlin incremental quebra quando o cache do pub e o projeto
  # estão em discos diferentes (ex.: C: e E:). Sem ele o build só fica um pouco mais lento.
  $gprops = Join-Path $Root 'android/gradle.properties'
  Update-Arquivo $gprops {
    param($t)
    if ($t -match 'kotlin\.incremental=') { return $t }
    return $t.TrimEnd() + "`nkotlin.incremental=false`n"
  }
  Write-Ok 'kotlin.incremental=false em android/gradle.properties'

  # --- iOS: permissões no Info.plist
  $plist = Join-Path $Root 'ios/Runner/Info.plist'
  Update-Arquivo $plist {
    param($t)
    # Salvar a imagem da viagem na galeria ("Minhas viagens" > Compartilhar).
    if ($t -notmatch 'NSPhotoLibraryAddUsageDescription') {
      $i = $t.LastIndexOf('</dict>')
      $t = $t.Substring(0, $i) +
        "`t<key>NSPhotoLibraryAddUsageDescription</key>`n`t<string>Para salvar a imagem da sua viagem na galeria.</string>`n" +
        $t.Substring($i)
    }
    if ($t -match 'NSLocationWhenInUseUsageDescription') { return $t }
    $bloco = @"
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Sua localização é compartilhada com os pilotos da expedição.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Para o comboio saber onde você está mesmo com o app minimizado.</string>
	<key>NSCameraUsageDescription</key>
	<string>Para tirar uma foto da sua moto.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Para escolher uma foto da sua moto.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
		<string>remote-notification</string>
	</array>

"@
    $i = $t.LastIndexOf('</dict>')
    return $t.Substring(0, $i) + $bloco + $t.Substring($i)
  }
  Write-Ok 'Permissões no Info.plist'

  # --- iOS: versão mínima 15.0 (exigida pelo Google Maps SDK atual)
  $pbx = Join-Path $Root 'ios/Runner.xcodeproj/project.pbxproj'
  Update-Arquivo $pbx { param($t) $t -replace 'IPHONEOS_DEPLOYMENT_TARGET = \d+\.\d+;', 'IPHONEOS_DEPLOYMENT_TARGET = 15.0;' }
  $podfile = Join-Path $Root 'ios/Podfile'
  if (-not (Test-Path $podfile)) {
    Copy-Item (Join-Path $Root 'config/Podfile') $podfile
    Write-Ok 'Podfile criado (iOS 15.0)'
  } else {
    Update-Arquivo $podfile { param($t) $t -replace "(?m)^#?\s*platform :ios, '[^']*'", "platform :ios, '15.0'" }
    Write-Ok 'Podfile ajustado (iOS 15.0)'
  }

  # --- iOS: chave do Maps no AppDelegate
  $delegate = Join-Path $Root 'ios/Runner/AppDelegate.swift'
  Update-Arquivo $delegate {
    param($t)
    if ($t -match 'GMSServices\.provideAPIKey') {
      return $t -replace 'GMSServices\.provideAPIKey\("[^"]*"\)', ('GMSServices.provideAPIKey("' + $iosKey + '")')
    }
    if ($t -notmatch 'GeneratedPluginRegistrant\.register') {
      Write-Aviso 'AppDelegate com formato inesperado: adicione GMSServices.provideAPIKey manualmente.'
      return $t
    }
    $t = $t -replace 'import Flutter', "import Flutter`nimport GoogleMaps"
    $re = [regex]'(?m)^(\s*)GeneratedPluginRegistrant\.register'
    return $re.Replace($t, ('${1}GMSServices.provideAPIKey("' + $iosKey + '")' + "`n" + '${1}GeneratedPluginRegistrant.register'), 1)
  }
  Write-Ok 'Chave do Maps no AppDelegate'

  # --- Chave de rotas para o flutter run/build
  $defs = Join-Path $Root 'config/dart_defines.json'
  [IO.File]::WriteAllText($defs, "{ `"DIRECTIONS_API_KEY`": `"$dirKey`" }", $Utf8)
  Write-Ok 'config/dart_defines.json'
}
