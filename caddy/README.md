# caddy

Reverse proxy voor de apps op de NAS. Eén adres, een pad per app:

- `http://system-nas:8300/ping` laat zien dat Caddy draait
- `http://system-nas:8300/testweb/` is de testcontainer

`system-nas` is de MagicDNS-naam uit Tailscale; je telefoon en pc moeten dus in Tailscale zitten. Het is alleen HTTP: Tailscale versleutelt het verkeer al, en zo komen je machinenamen niet in openbare certificaatregisters. De poort is niet open naar internet.

## Een app toevoegen
1. Zorg dat de app in zijn eigen compose-bestand draait en dat de proxy hem kan bereiken: voeg in `docker-compose.yml` het netwerk van de app toe (als `external: true`, zoals bij `testweb-net`).
2. Zet een blok in `conf/Caddyfile`, naar het voorbeeld van `testweb`.
3. Start de app eerst, daarna de proxy opnieuw: `sudo docker-compose up -d` in deze map. Alleen de Caddyfile gewijzigd? Dan volstaat `sudo docker exec -w /etc/caddy caddy caddy reload`.

Let op: de app moet met een pad (`/naam/`) kunnen werken. Een statische pagina doet dat vanzelf; bij een app met eigen links of een API (zoals FastAPI) moet je dat in de app instellen.

## Volgorde
`testweb-net` bestaat pas als `testweb` ooit gestart is. Start `testweb` dus eerst, anders weigert Caddy te starten.

## Waarom de hele map `conf/` en niet het bestand
Een los bestand koppelen kan ertoe leiden dat wijzigingen pas zichtbaar worden na opnieuw aanmaken van de container. De map doet dat niet.
