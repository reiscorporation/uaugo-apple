<#
  RodaJunto - simula uma viagem no emulador Android, enviando posições de GPS.
  Use para testar movimento no mapa, alertas por proximidade e aviso de
  passagem do motoclube sem sair de casa.

  Exemplos:
    .\scripts\simular-viagem.ps1
    .\scripts\simular-viagem.ps1 -DeLat -23.5505 -DeLng -46.6333 -ParaLat -23.40 -ParaLng -46.40 -VelocidadeKmh 100
    .\scripts\simular-viagem.ps1 -Serial emulator-5556      (com dois emuladores abertos)

  Padrão: trecho aproximado da Serra do Rio do Rastro (SC), a 60 km/h.
  Dica: abra o app no emulador e entre numa expedição antes de começar.
#>
param(
  [double]$DeLat = -28.3870, [double]$DeLng = -49.5440,
  [double]$ParaLat = -28.4000, [double]$ParaLng = -49.4600,
  [double]$VelocidadeKmh = 60,
  [double]$IntervaloSeg = 2,
  [string]$Serial = ''
)
. "$PSScriptRoot\comum.ps1"

$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path $adb)) { $adb = 'adb' }
$inv = [Globalization.CultureInfo]::InvariantCulture
$sel = @(); if ($Serial) { $sel = @('-s', $Serial) }

function Get-DistM($a1, $o1, $a2, $o2) {
  $r = 6371000; $rad = [Math]::PI / 180
  $dA = ($a2 - $a1) * $rad; $dO = ($o2 - $o1) * $rad
  $h = [Math]::Sin($dA / 2) * [Math]::Sin($dA / 2) +
       [Math]::Cos($a1 * $rad) * [Math]::Cos($a2 * $rad) * [Math]::Sin($dO / 2) * [Math]::Sin($dO / 2)
  return 2 * $r * [Math]::Asin([Math]::Sqrt($h))
}

$dist = Get-DistM $DeLat $DeLng $ParaLat $ParaLng
$passo = ($VelocidadeKmh / 3.6) * $IntervaloSeg
$n = [Math]::Max(1, [Math]::Ceiling($dist / $passo))
Write-Etapa ("Viagem de {0:N1} km a {1} km/h ({2} pontos, ~{3:N0} min)" -f ($dist / 1000), $VelocidadeKmh, $n, ($n * $IntervaloSeg / 60))
Write-Host '    Ctrl+C para parar.'

for ($i = 0; $i -le $n; $i++) {
  $f = $i / $n
  $lat = $DeLat + ($ParaLat - $DeLat) * $f
  $lng = $DeLng + ($ParaLng - $DeLng) * $f
  # Atenção: o "geo fix" recebe LONGITUDE primeiro.
  & $adb @sel emu geo fix $lng.ToString('F6', $inv) $lat.ToString('F6', $inv) | Out-Null
  Write-Progress -Activity 'Simulando viagem' -Status ("{0:F5}, {1:F5}" -f $lat, $lng) -PercentComplete ([int]($f * 100))
  Start-Sleep -Seconds $IntervaloSeg
}
Write-Ok 'Chegou ao destino'
