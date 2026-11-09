# Rotina mensal no PC do Ricardo: ruas do minimapa do 3D do UauGo.
# 1. Baixa o mapa do Brasil atualizado (Geofabrik, ~2 GB) para C:\UauGo-ruas
# 2. Gera os quadrados de ruas (scripts/gerar-ruas-minimapa.py, ~30 min)
# 3. Envia para a VPS (/opt/helpaitech/ruas, servido em /ruas/ do motor)
#
# Agendar (uma vez, PowerShell como o seu usuário):
#   schtasks /Create /SC MONTHLY /D 1 /ST 03:00 /TN "UauGo ruas do minimapa" /TR "powershell -ExecutionPolicy Bypass -File E:\APP\comboio\scripts\gerar-ruas-minimapa.ps1"
# Outros países depois: acrescente a URL do .pbf em $mapas (geofabrik.de).
$ErrorActionPreference = "Stop"
$pasta = "C:\UauGo-ruas"
$saida = "$pasta\saida"
$chave = "$env:USERPROFILE\.ssh\hostinger_vps"
$mapas = @("https://download.geofabrik.de/south-america/brazil-latest.osm.pbf")
New-Item -ItemType Directory -Force $pasta, $saida | Out-Null
Start-Transcript "$pasta\ultima-execucao.log"
foreach ($url in $mapas) {
  $pbf = Join-Path $pasta (Split-Path $url -Leaf)
  Write-Host "Baixando $url"
  Invoke-WebRequest $url -OutFile "$pbf.novo"
  Move-Item -Force "$pbf.novo" $pbf
  python -u "$PSScriptRoot\gerar-ruas-minimapa.py" $pbf $saida
}
Write-Host "Enviando para a VPS"
& scp -i $chave -q -r "$saida\*" root@200.141.16.177:/opt/helpaitech/ruas/
Write-Host "Pronto"
Stop-Transcript
