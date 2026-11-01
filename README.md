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
└── testweb/              testcontainer (nginx, poort 8200)
    ├── docker-compose.yml
    └── html/index.html
```

## Afspraken
- Geheimen alleen in `.env` naast het compose-bestand; `.env` staat in `.gitignore`. Zet een voorbeeld zonder echte waarden in `.env.example`.
- Elke app: eigen map, eigen netwerk en `mem_limit`.
- `cpus` werkt niet op deze NAS: Docker geeft de fout "NanoCPUs can not be set, as your kernel does not support CPU CFS scheduler". Gebruik het niet.
- Geen app via gluetun en geen app publiek bereikbaar.
- Op de NAS heet het commando `docker-compose` (met streepje) en is `sudo` nodig.
- Poorten die al bezet zijn: 6881, 6246, 7878, 8080, 8090, 8099, 8191, 8989. Kies een andere, bijvoorbeeld 82xx.

## Uitrollen met één commando
Na het committen rol je een app uit vanaf je pc (PowerShell, in deze map):

```powershell
.\deploy.ps1 testweb
```

Het script controleert eerst dat je op `main` staat, dat alles gecommit is en dat de app-map bestaat. Daarna pusht het, haalt het op de NAS de wijzigingen op (`git pull`) en start het de app (`sudo docker-compose up -d`). Tot slot toont het de status. Het draait alleen als jij het start: er is geen automatisch ophalen of Watchtower.

In VS Code kan het ook met een taak: Ctrl+Shift+P, kies *Taken: taak uitvoeren* en dan *Deploy app naar NAS*. Vul de naam van de app in (standaard `testweb`). Het wachtwoord voor `sudo` typ je in de terminal die opent. De taak start PowerShell met `-ExecutionPolicy Bypass` alleen voor dit script, zodat Windows het niet blokkeert.

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
