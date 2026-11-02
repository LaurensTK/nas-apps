# nas-apps

Compose-bestanden voor mijn eigen apps op de Synology NAS. De mediastack (Sonarr, Radarr, gluetun enzovoort) staat hier bewust niet in en blijft apart.

## Structuur
Op de NAS: `/volume1/docker/apps/`. Elke app heeft een eigen map, een eigen `docker-compose.yml` en een eigen Docker-netwerk.

```
nas-apps/
├── README.md
├── .gitignore
├── deploy.ps1            uitrollen naar de NAS met één commando
├── .vscode/tasks.json    VS Code-taak "Deploy app naar NAS"
├── caddy/                reverse proxy (Caddy, poort 8300)
│   ├── docker-compose.yml
│   └── conf/Caddyfile
└── testweb/              testcontainer (nginx, poort 8200)
    ├── docker-compose.yml
    └── html/index.html
```

## Bereikbaar via Tailscale
Apps zijn bereikbaar op `http://system-nas:8300/<appnaam>/`, via de reverse proxy in `caddy/`. Zie `caddy/README.md`.

### HTTPS voor een app (PWA)
Een app die als PWA op de telefoon moet, heeft HTTPS nodig. Dat regelt Tailscale zelf, zonder Caddy: de app staat dan op de root van een eigen HTTPS-poort, alleen binnen het tailnet (niet op internet). Eenmalig: *Enable HTTPS* op de DNS-pagina van de Tailscale-console. Let op: de machinenaam komt daarna in een openbaar certificaatregister (Certificate Transparency), dus hernoem de NAS eerst als de naam persoonlijk is.

Op de NAS, via SSH:

```bash
sudo tailscale serve --bg --https=8443 localhost:8400
```

Dit is voor de backlog-app (poort 8400); kies per app een eigen HTTPS-poort. Het adres wordt `https://system-nas.<tailnet>.ts.net:8443/`. Controleren: `tailscale serve status`. Uitzetten: `sudo tailscale serve --https=8443 off`. De instelling blijft na een herstart staan.

### Bekend probleem op de telefoon
Android staat één VPN tegelijk toe. Beheert je werk de Defender-app met webbeveiliging, dan schopt die Tailscale eruit. Thuis kan het dan nog via het IP-adres met poort (bijvoorbeeld `http://<NAS-IP>:8300/testweb/`).


## Afspraken
- Geheimen alleen in `.env` naast het compose-bestand; `.env` staat in `.gitignore`. Zet een voorbeeld zonder echte waarden in `.env.example`.
- Elke app: eigen map, eigen netwerk en `mem_limit`.
- `cpus` werkt niet op deze NAS: Docker geeft de fout "NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler". Gebruik het niet.
- Geen app via gluetun en geen app publiek bereikbaar.
- Op de NAS heet het commando `docker-compose` (met streepje) en is `sudo` nodig.
- Poorten die al bezet zijn: 6881, 6246, 7878, 8080, 8090, 8099, 8191, 8200 (testweb), 8300 (caddy), 8400 (backlog-app), 8989. Kies een andere, bijvoorbeeld 82xx.

## Uitrollen met één commando
Na het committen rol je een app uit vanaf je pc (PowerShell, in deze map):

```powershell
.\deploy.ps1 testweb
```

Het script controleert eerst dat je op `main` staat, dat alles gecommit is en dat de app-map bestaat. Daarna pusht het, haalt het op de NAS de wijzigingen op (`git pull`) en start het de app (`sudo docker-compose up -d`). Tot slot toont het de status. Het draait alleen als jij het start: er is geen automatisch ophalen of Watchtower.

### De backlog-app
De backlog-app staat in een eigen repo (`..\Backlog-App`) en wordt anders uitgerold: het image wordt op de pc gebouwd (spaart de NAS-processor) en naar de NAS gebracht.

```powershell
.\deploy.ps1 backlog-app
```

Het script controleert eerst dat Docker Desktop draait, dat de backlog-app op `main` staat zonder ongecommitte wijzigingen, en dat op de NAS de map `backlog-app` met `.env` en `data/` bestaat (stap 1 in `docs\NAS-UITROL.md` van de backlog-app, die maak je zelf). Daarna bouwt het het image, zet het in een tar-bestand, kopieert dat samen met `docker-compose.yml` naar `/volume1/docker/apps/backlog-app/`, laadt het op de NAS en start de container (`up -d --no-build`, poort 8400). Je typt alleen het `sudo`-wachtwoord. Tot slot controleert het `http://<nas-ip>:8400/health`.

Het script leest of overschrijft `.env` op de NAS nooit en wist `data/` (de database) nooit; het kopieert alleen `backlog-app.tar` en `docker-compose.yml`. Het oude tar-bestand blijft op de NAS staan en wordt de volgende keer overschreven. Het kopiëren gaat via SSH (niet via `scp`), zodat de SFTP-service van de Synology niet nodig is.

Controleer eenmalig dat het pad `$DockerPad` bovenaan het script klopt: log in op de NAS en draai `which docker`.

In VS Code kan het ook met een taak: Ctrl+Shift+P, kies *Taken: taak uitvoeren* en dan *Deploy app naar NAS*. Vul de naam van de app in (standaard `testweb`; voor de backlog-app typ je `backlog-app`). Het wachtwoord voor `sudo` typ je in de terminal die opent. De taak start PowerShell met `-ExecutionPolicy Bypass` alleen voor dit script, zodat Windows het niet blokkeert.

Eenmalig instellen:
1. Vul bovenaan `deploy.ps1` het IP-adres van de NAS in (`$NasAdres`).
2. Zet de SSH-sleutel van je pc op de NAS, zodat SSH geen wachtwoord meer vraagt (zie hieronder). Het wachtwoord voor `sudo` blijft gevraagd worden: dat is de veilige standaard.

### SSH-sleutel van je pc op de NAS zetten
Doe dit zelf, in PowerShell op je pc. De geheime sleutel blijft op je pc; alleen de publieke helft (`.pub`) gaat naar de NAS.

```powershell
ssh-keygen -t ed25519 -C "pc naar nas"
```

Druk bij de vraag naar de bestandsnaam op Enter (standaard `id_ed25519`). Een passphrase is veiliger, omdat iemand met toegang tot je pc anders ook op de NAS kan; je kunt hem leeg laten of later toevoegen met `ssh-keygen -p -f "$env:USERPROFILE\.ssh\id_ed25519"`. Bestaat er al een sleutel met die naam, overschrijf hem dan niet maar kies een andere naam. Zet daarna de publieke sleutel op de NAS (je typt eenmalig je NAS-wachtwoord):

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | ssh LaurensTK@NAS-IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Test: `ssh LaurensTK@NAS-IP` moet nu zonder NAS-wachtwoord inloggen. SSH gebruikt de standaardsleutel vanzelf, dus een configbestand is niet nodig. Vraagt het toch om een wachtwoord, dan is op Synology vaak je thuismap te ruim ingesteld; draai op de NAS `chmod 755 ~` en probeer opnieuw.

### Zonder wachtwoord voor sudo (optioneel)
Staat het wachtwoord voor `sudo` je in de weg? Je kunt op de NAS toestaan dat alleen `docker-compose` zonder wachtwoord draait. Dat is minder veilig: wie de sleutel van je pc heeft, kan dan Docker op de NAS besturen. Kies daar bewust voor.

## Handmatig naar de NAS
Bewerken doe je op de pc. Zonder het script haal je op de NAS zelf binnen:

```bash
cd /volume1/docker/apps
git pull
cd testweb
sudo docker-compose up -d
```

Stoppen: `sudo docker-compose down` in dezelfde map.
