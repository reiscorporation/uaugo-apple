<#
  Convoyar - instala e abre o app no celular conectado (ou emulador).
    .\scripts\rodar.ps1
    .\scripts\rodar.ps1 -d ID_DO_APARELHO     (veja os IDs com: flutter devices)
#>
. "$PSScriptRoot\comum.ps1"
Set-Location $Root
if (-not (Test-Path 'config/dart_defines.json')) { Invoke-AplicarConfig (Read-Config) }
flutter run --dart-define-from-file=config/dart_defines.json @args
