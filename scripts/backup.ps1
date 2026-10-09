# ============================================================================
# backup.ps1 — Backup do código-fonte no Google Drive
#
# O que faz:
#   1. Registra as mudanças no histórico do Git ("foto" do código com data).
#   2. Copia para a pasta do Drive:
#        - comboio-historico.bundle : TODO o histórico (todas as versões).
#          Para restaurar: git clone comboio-historico.bundle comboio
#        - comboio-AAAA-MM-DD_HHMM.zip : o código atual, pronto para abrir.
#   3. Mantém só os 15 zips mais recentes (o bundle sempre tem tudo).
#
# Uso (na pasta do projeto):
#   .\scripts\backup.ps1                         # usa a pasta salva/encontrada
#   .\scripts\backup.ps1 -Destino 'G:\Meu Drive\HelpAITech\UauGo'
#   .\scripts\backup.ps1 -Mensagem 'Antes de publicar na loja'
#   .\scripts\backup.ps1 -IncluirChaves          # também as chaves (ver abaixo)
#
# Chaves (config.env, config/dart_defines.json, functions/.env) NÃO entram no
# histórico. Com -IncluirChaves, vão num zip separado (comboio-chaves.zip) na
# mesma pasta: só use se a pasta do Drive for restrita a quem pode vê-las.
# ============================================================================

param(
  [string]$Destino = '',
  [string]$Mensagem = '',
  [switch]$IncluirChaves
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
  [Environment]::GetEnvironmentVariable('Path', 'User')

function Escrever($t, $cor = 'Gray') { Write-Host $t -ForegroundColor $cor }

# --- 1. Pasta de destino: parâmetro > salva em config.env > Drive encontrado
$cfg = Join-Path $Root 'config.env'
if (-not $Destino -and (Test-Path $cfg)) {
  $linha = Get-Content $cfg | Where-Object { $_ -match '^BACKUP_DIR=' } | Select-Object -First 1
  if ($linha) { $Destino = $linha.Split('=', 2)[1].Trim() }
}
if (-not $Destino) {
  # Google Drive para computador: aparece como uma unidade (ex.: G:) com
  # "Meu Drive" ou "My Drive".
  foreach ($d in Get-PSDrive -PSProvider FileSystem) {
    foreach ($nome in 'Meu Drive', 'My Drive') {
      $p = Join-Path $d.Root $nome
      if (Test-Path $p) { $Destino = Join-Path $p 'HelpAITech\UauGo\backup'; break }
    }
    if ($Destino) { break }
  }
}
if (-not $Destino) {
  Escrever 'Pasta do Google Drive não encontrada.' Yellow
  Escrever 'Instale o "Google Drive para computador", entre com a conta da HelpAITech'
  Escrever 'e rode de novo, ou informe a pasta: .\scripts\backup.ps1 -Destino "G:\Meu Drive\..."'
  exit 1
}
New-Item -ItemType Directory -Force $Destino | Out-Null
# Lembra a pasta para os próximos backups.
if (Test-Path $cfg) {
  $t = Get-Content $cfg | Where-Object { $_ -notmatch '^BACKUP_DIR=' }
  [IO.File]::WriteAllLines($cfg, [string[]]($t + "BACKUP_DIR=$Destino"),
    (New-Object Text.UTF8Encoding($false)))
}
Escrever "Destino: $Destino" Cyan

# --- 2. Registra as mudanças no histórico
git add -A
$mudou = (git status --porcelain).Length -gt 0
if ($mudou) {
  $msg = if ($Mensagem) { $Mensagem } else { 'Backup ' + (Get-Date -Format 'dd/MM/yyyy HH:mm') }
  git commit -q -m $msg
  Escrever "Nova versão registrada: $msg" Green
} else {
  Escrever 'Sem mudanças desde o último backup (histórico já atualizado).'
}

# --- 3. Copia para o Drive
$data = Get-Date -Format 'yyyy-MM-dd_HHmm'
$bundle = Join-Path $Destino 'comboio-historico.bundle'
git bundle create "$bundle.tmp" --all 2>$null
Move-Item "$bundle.tmp" $bundle -Force
$zip = Join-Path $Destino "comboio-$data.zip"
git archive --format=zip -o $zip HEAD
Escrever ("Histórico: {0:N1} MB  |  Código atual: {1:N1} MB" -f `
  ((Get-Item $bundle).Length / 1MB), ((Get-Item $zip).Length / 1MB)) Green

if ($IncluirChaves) {
  $chaves = @('config.env', 'config\dart_defines.json', 'functions\.env') |
    Where-Object { Test-Path (Join-Path $Root $_) } |
    ForEach-Object { Join-Path $Root $_ }
  if ($chaves) {
    Compress-Archive -Path $chaves -DestinationPath (Join-Path $Destino 'comboio-chaves.zip') -Force
    Escrever 'Chaves salvas em comboio-chaves.zip (guarde com cuidado).' Yellow
  }
}

# --- 4. Mantém os 15 zips mais recentes
Get-ChildItem $Destino -Filter 'comboio-20*.zip' | Sort-Object Name -Descending |
  Select-Object -Skip 15 | Remove-Item -Force

Escrever 'Backup concluído.' Green
