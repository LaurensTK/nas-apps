# Rolt één app uit naar de NAS: controleren, pushen, op de NAS ophalen en starten.
# Gebruik (in PowerShell, in deze map):  .\deploy.ps1 testweb
param(
    [Parameter(Mandatory = $true)]
    [string]$App
)

$ErrorActionPreference = "Stop"

# --- Instellingen: pas aan naar jouw situatie ---
$NasAdres = "192.168.2.4"            # IP-adres van de NAS (zelfde als voor SSH)
$NasGebruiker = "LaurensTK"     # je NAS-account
$NasMap = "/volume1/docker/apps"
# ------------------------------------------------

# Stopt met een duidelijke melding.
function Stop-Met([string]$Melding) {
    Write-Host "Gestopt: $Melding" -ForegroundColor Red
    exit 1
}

Set-Location $PSScriptRoot

if ($NasAdres -eq "NAS-IP") {
    Stop-Met "vul eerst het IP-adres van de NAS in bovenaan deploy.ps1."
}

# 1. Controles vooraf
# Alleen kleine letters, cijfers, streepjes en underscores: de naam gaat straks naar de NAS.
if ($App -notmatch '^[a-z0-9][a-z0-9_-]*$') {
    Stop-Met "'$App' is geen geldige app-naam."
}
if (-not (Test-Path (Join-Path $PSScriptRoot "$App\docker-compose.yml"))) {
    Stop-Met "er is geen map '$App' met een docker-compose.yml."
}
$branch = git branch --show-current
if ($branch -ne "main") {
    Stop-Met "je staat op branch '$branch'. Uitrollen kan alleen vanaf 'main'."
}
if (git status --porcelain) {
    Stop-Met "er zijn wijzigingen die nog niet zijn gecommit. Commit eerst (git status laat zien welke)."
}

# 2. Pushen naar GitHub
Write-Host "Pushen naar GitHub..." -ForegroundColor Cyan
git push
if ($LASTEXITCODE -ne 0) { Stop-Met "git push is mislukt." }

# 3 en 4. Op de NAS ophalen, starten en de status tonen.
# 'ssh -t' zorgt dat sudo om je wachtwoord kan vragen; typ het zelf in.
Write-Host "Uitrollen op de NAS (je wordt om je wachtwoord gevraagd)..." -ForegroundColor Cyan
$opdracht = "cd $NasMap && git pull origin main && cd $App && sudo docker-compose up -d && sudo docker-compose ps"
ssh -t "$NasGebruiker@$NasAdres" $opdracht
if ($LASTEXITCODE -ne 0) { Stop-Met "het uitrollen op de NAS is mislukt (zie de melding hierboven)." }

Write-Host "Klaar: '$App' is uitgerold." -ForegroundColor Green
