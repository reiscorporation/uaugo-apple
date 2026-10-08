<#
  Convoyar - instala as ferramentas de desenvolvimento no Windows 10/11.

  Como rodar (PowerShell, na pasta do projeto):
    Set-ExecutionPolicy -Scope Process Bypass
    .\scripts\instalar.ps1

  O Windows pode pedir confirmação de administrador em algumas instalações.
#>
. "$PSScriptRoot\comum.ps1"

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq 'Core') {
  Write-Aviso 'Este script é para Windows. No Mac/Linux, siga o README.'; exit 1
}
if (-not (Test-Comando 'winget')) {
  Write-Aviso 'winget não encontrado. Atualize o "Instalador de Aplicativo" pela Microsoft Store e rode de novo.'; exit 1
}

function Update-PathSessao {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Add-PathUsuario([string]$Dir) {
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $user) { $user = '' }
  if (($user -split ';') -notcontains $Dir) {
    [Environment]::SetEnvironmentVariable('Path', ($user.TrimEnd(';') + ';' + $Dir), 'User')
  }
  Update-PathSessao
}
function Install-Winget([string]$Id, [string]$Nome) {
  Write-Etapa "Instalando $Nome"
  winget install --id $Id -e --silent --accept-source-agreements --accept-package-agreements
  if ($LASTEXITCODE -ne 0) { Write-Aviso "${Nome}: o winget retornou código $LASTEXITCODE (pode já estar instalado)." }
  else { Write-Ok $Nome }
  Update-PathSessao
}

Install-Winget 'Git.Git' 'Git'
Install-Winget 'OpenJS.NodeJS.LTS' 'Node.js (LTS)'
Install-Winget 'Google.AndroidStudio' 'Android Studio'
Install-Winget 'Google.CloudSDK' 'Google Cloud CLI'

# --- Flutter (canal estável) em C:\src\flutter
$flutterDir = 'C:\src\flutter'
Write-Etapa 'Instalando o Flutter'
if (Test-Path (Join-Path $flutterDir 'bin\flutter.bat')) {
  Write-Ok 'Flutter já instalado'
} else {
  New-Item -ItemType Directory -Force -Path 'C:\src' | Out-Null
  git clone https://github.com/flutter/flutter.git -b stable $flutterDir
  Write-Ok 'Flutter baixado'
}
Add-PathUsuario (Join-Path $flutterDir 'bin')
Add-PathUsuario (Join-Path $env:LOCALAPPDATA 'Pub\Cache\bin')
Add-PathUsuario (Join-Path $env:APPDATA 'npm')
Add-PathUsuario (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools')
flutter --version

Write-Etapa 'Instalando Firebase CLI e FlutterFire CLI'
npm install -g firebase-tools
dart pub global activate flutterfire_cli
Write-Ok 'firebase e flutterfire'

Write-Etapa 'Modo de desenvolvedor do Windows'
Write-Host '    O Flutter precisa do "Modo de desenvolvedor" ativado para compilar plugins.'
Write-Host '    Vou abrir a tela de configurações: ative a opção e volte aqui.'
Start-Process 'ms-settings:developers'
Read-Host '    Pressione Enter depois de ativar'

Write-Etapa 'Verificando a instalação'
flutter doctor

Write-Host @"

============================================================
 PRÓXIMOS PASSOS (manuais, uma única vez)
============================================================
 1. Abra o Android Studio e conclua o assistente inicial
    (ele baixa o SDK do Android). Depois, em Settings >
    Languages & Frameworks > Android SDK > SDK Tools, marque
    "Android SDK Command-line Tools" e aplique.
 2. Feche e abra o PowerShell e rode:
      flutter doctor --android-licenses     (responda y)
      firebase login
      gcloud auth login
 3. Continue com:  .\scripts\configurar.ps1
============================================================
"@ -ForegroundColor Cyan
