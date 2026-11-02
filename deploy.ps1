# Rolt één app uit naar de NAS.
# Gebruik (in PowerShell, in deze map):
#   .\deploy.ps1 testweb        apps uit deze repo: controleren, pushen, op de NAS ophalen en starten
#   .\deploy.ps1 backlog-app    de backlog-app: image op de pc bouwen, naar de NAS brengen en starten
param(
    [Parameter(Mandatory = $true)]
    [string]$App
)

$ErrorActionPreference = "Stop"

# --- Instellingen: pas aan naar jouw situatie ---
$NasAdres = "192.168.2.4"            # IP-adres van de NAS (zelfde als voor SSH)
$NasGebruiker = "LaurensTK"     # je NAS-account
$NasMap = "/volume1/docker/apps"
# Volledige paden: bij één SSH-commando kent de NAS de zoekpaden van een gewone inlog niet.
$ComposePad = "/usr/local/bin/docker-compose"
$DockerPad = "/usr/local/bin/docker"
# Backlog-app: de code staat naast deze map, de app draait op de NAS in $NasMap/backlog-app.
$BacklogMap = Join-Path (Split-Path $PSScriptRoot -Parent) "Backlog-App"
$BacklogPoort = 8400
# ------------------------------------------------

# Stopt met een duidelijke melding.
function Stop-Met([string]$Melding) {
    Write-Host "Gestopt: $Melding" -ForegroundColor Red
    exit 1
}

# Stopt als het laatste programma een fout gaf.
function Controleer([string]$Melding) {
    if ($LASTEXITCODE -ne 0) { Stop-Met $Melding }
}

# Geeft terug of Docker op de pc antwoordt.
function Docker-Draait {
    $oud = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker info > $null 2>&1
    $draait = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $oud
    return $draait
}

# Kopieert een bestand naar de NAS via SSH. Dat is bewust geen scp: scp heeft op een Synology
# de SFTP-service nodig, en dit werkt met alleen SSH. Het bestand komt eerst onder een tijdelijke
# naam binnen en wordt pas daarna hernoemd, zodat er nooit een half bestand blijft staan.
function Kopieer-Naar-Nas([string]$Bron, [string]$NasPad) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ssh"
    $psi.Arguments = "-o BatchMode=yes $NasGebruiker@$NasAdres ""cat > '$NasPad.deel' && mv '$NasPad.deel' '$NasPad'"""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $proces = [System.Diagnostics.Process]::Start($psi)
    $bestand = [System.IO.File]::OpenRead($Bron)
    try { $bestand.CopyTo($proces.StandardInput.BaseStream) }
    finally { $bestand.Close(); $proces.StandardInput.Close() }
    $proces.WaitForExit()
    if ($proces.ExitCode -ne 0) { Stop-Met "kopiëren naar $NasPad is mislukt." }
}

# Backlog-app: het image wordt op de pc gebouwd (spaart de NAS-processor), naar de NAS gebracht
# en daar geladen. Dit script leest of overschrijft nooit .env op de NAS en wist nooit data/.
function Rol-BacklogAppUit {
    $nas = "$NasGebruiker@$NasAdres"
    $nasApp = "$NasMap/backlog-app"
    $tar = Join-Path $env:TEMP "backlog-app.tar"

    # 1. Controles vooraf
    if (-not (Test-Path (Join-Path $BacklogMap "Dockerfile"))) {
        Stop-Met "de map van de backlog-app is niet gevonden: $BacklogMap"
    }
    if (-not (Docker-Draait)) {
        # Docker Desktop zelf starten en wachten tot het klaar is (maximaal 2 minuten).
        # Docker Desktop staat per gebruiker of voor alle gebruikers geïnstalleerd; probeer beide.
        $dockerDesktop = @(
            "$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe",
            "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $dockerDesktop) { Stop-Met "Docker draait niet en Docker Desktop is niet gevonden. Start Docker Desktop zelf en probeer opnieuw." }
        Write-Host "Docker Desktop starten en wachten tot het klaar is..." -ForegroundColor Cyan
        Start-Process $dockerDesktop
        $wacht = 0
        while (-not (Docker-Draait) -and $wacht -lt 120) { Start-Sleep -Seconds 5; $wacht += 5 }
        if (-not (Docker-Draait)) { Stop-Met "Docker is na 2 minuten nog niet klaar. Wacht tot Docker Desktop opgestart is en probeer opnieuw." }
    }

    $branch = git -C $BacklogMap branch --show-current
    if ($branch -ne "main") {
        Stop-Met "de backlog-app staat op branch '$branch'. Uitrollen kan alleen vanaf 'main'."
    }
    if (git -C $BacklogMap status --porcelain) {
        Stop-Met "de backlog-app heeft wijzigingen die nog niet zijn gecommit. Commit eerst."
    }
    $commit = git -C $BacklogMap rev-parse --short HEAD
    Write-Host "Backlog-app uitrollen, versie $commit." -ForegroundColor Cyan

    # Alleen kijken of de map, .env en data/ er zijn; de inhoud van .env wordt niet gelezen.
    ssh -o BatchMode=yes $nas "test -d '$nasApp' && test -f '$nasApp/.env' && test -d '$nasApp/data'"
    if ($LASTEXITCODE -eq 255) { Stop-Met "inloggen op de NAS met je SSH-sleutel lukt niet." }
    Controleer "op de NAS ontbreekt de map $nasApp, het bestand .env of de map data. Zie stap 1 in docs\NAS-UITROL.md van de backlog-app."
    ssh -o BatchMode=yes $nas "test -x '$DockerPad'"
    Controleer "het programma $DockerPad bestaat niet op de NAS. Zoek het pad met 'which docker' en pas `$DockerPad aan."

    # 2. Image bouwen en inpakken op de pc
    Write-Host "Image bouwen op de pc..." -ForegroundColor Cyan
    docker build --platform linux/amd64 -t backlog-app:latest $BacklogMap
    Controleer "docker build is mislukt."
    docker save backlog-app:latest -o $tar
    Controleer "docker save is mislukt."

    # 3. Alleen het image en het compose-bestand naar de NAS (.env en data/ blijven ongemoeid)
    Write-Host "Naar de NAS kopiëren (dit kan even duren)..." -ForegroundColor Cyan
    Kopieer-Naar-Nas $tar "$nasApp/backlog-app.tar"
    Kopieer-Naar-Nas (Join-Path $BacklogMap "docker-compose.yml") "$nasApp/docker-compose.yml"

    # 4. Laden en starten op de NAS. 'ssh -t' zorgt dat sudo om je wachtwoord kan vragen; typ het zelf in.
    Write-Host "Laden en starten op de NAS (je wordt om je wachtwoord gevraagd)..." -ForegroundColor Cyan
    ssh -t $nas "cd '$nasApp' && sudo $DockerPad load -i backlog-app.tar && sudo $ComposePad up -d --no-build && sudo $ComposePad ps"
    Controleer "het laden of starten op de NAS is mislukt (zie de melding hierboven)."

    # 5. Controleren dat de app antwoordt (de container heeft even nodig om te starten)
    Write-Host "Gezondheidscheck..." -ForegroundColor Cyan
    $adres = "http://${NasAdres}:$BacklogPoort/health"
    for ($poging = 1; $poging -le 10; $poging++) {
        try {
            $antwoord = Invoke-WebRequest -Uri $adres -UseBasicParsing -TimeoutSec 5
            Write-Host "$adres geeft: $($antwoord.Content)" -ForegroundColor Green
            Write-Host "Klaar: 'backlog-app' ($commit) is uitgerold." -ForegroundColor Green
            return
        }
        catch { Start-Sleep -Seconds 3 }
    }
    Write-Host "Let op: $adres antwoordt nog niet. Kijk op de NAS met: sudo $DockerPad logs backlog-app" -ForegroundColor Yellow
    exit 1
}

Set-Location $PSScriptRoot

if ($NasAdres -eq "NAS-IP") {
    Stop-Met "vul eerst het IP-adres van de NAS in bovenaan deploy.ps1."
}

# Alleen kleine letters, cijfers, streepjes en underscores: de naam gaat straks naar de NAS.
if ($App -notmatch '^[a-z0-9][a-z0-9_-]*$') {
    Stop-Met "'$App' is geen geldige app-naam."
}

# De backlog-app heeft een eigen route (image bouwen en kopiëren in plaats van git pull).
if ($App -eq "backlog-app") {
    Rol-BacklogAppUit
    exit 0
}

# 1. Controles vooraf
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
$opdracht = "cd $NasMap && git pull origin main && cd $App && sudo $ComposePad up -d && sudo $ComposePad ps"
ssh -t "$NasGebruiker@$NasAdres" $opdracht
if ($LASTEXITCODE -ne 0) { Stop-Met "het uitrollen op de NAS is mislukt (zie de melding hierboven)." }

Write-Host "Klaar: '$App' is uitgerold." -ForegroundColor Green
