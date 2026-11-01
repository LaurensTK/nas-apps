# nas-apps

Compose-bestanden voor mijn eigen apps op de Synology NAS. De mediastack (Sonarr, Radarr, gluetun enzovoort) staat hier bewust niet in en blijft apart.

## Structuur
Op de NAS: `/volume1/docker/apps/`. Elke app heeft een eigen map, een eigen `docker-compose.yml` en een eigen Docker-netwerk.

```
nas-apps/
├── README.md
├── .gitignore
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

## Bestanden naar de NAS
Bewerken doe je op de pc. Op de NAS haal je alleen binnen:

```bash
cd /volume1/docker/apps
git pull
cd testweb
sudo docker-compose up -d
```

Stoppen: `sudo docker-compose down` in dezelfde map.
