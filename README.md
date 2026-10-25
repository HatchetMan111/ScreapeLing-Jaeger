# ScrapJaeger auf Proxmox LXC – Einzeiler-Installation

> Neues separates Repo nur mit **Scrapling**-Logik. Dein `PreisJaeger`-Repo bleibt unangetastet.

Lokales Scrapling-Dashboard: URL + CSS/XPath rein → Ergebnis-Tabelle + Verlauf + CSV/JSON-Export.
Engine: `Scrapling` (Fetcher/Stealthy/Dynamic), vollständig lokal, keine Cloud nötig.
V1 = Ad-hoc + Verlauf. V2 (Crawl) und V3 (Monitoring) sind als Routen + DB-Tabellen vorbereitet.

| Eigenschaft | Wert |
|---|---|
| App / Hostname | `scrapjaeger` |
| Stack | Python 3.12 + FastAPI + Scrapling + SQLite + Vanilla-JS (kein Build) |
| Web UI | `http://<LXC-IP>:8091` |
| Health | `http://<LXC-IP>:8091/api/health` |
| Standard | 2 vCPU / 3072 MB RAM / 10 GB Disk, **nächste freie CT-ID**, `onboot:1` |
| Template | `debian-12-standard` |

## 1. Installation (Proxmox-Host als root)

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/ScreapeLing-Jaeger/main/install/scrapjaeger.sh)"
```

Anpassen:

```bash
CT_ID=101 CORES=2 RAM=3072 DISK=10 bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/ScreapeLing-Jaeger/main/install/scrapjaeger.sh)"
bash scrapjaeger.sh --ctid 101 --port 8091 --debug
```

Erwartete Schlussausgabe:

```
[OK]    Service laeuft (systemctl is-active scrapjaeger = active).
[OK]    Web UI antwortet (HTTP-Check auf localhost:8091/api/health).

================ INSTALLATION ERFOLGREICH ================
  App          : ScrapJaeger - lokales Scrapling-Dashboard
  Container    : CT 101 (Hostname: scrapjaeger, onboot=1)
  Web UI       : http://192.168.1.101:8091
  Health       : http://192.168.1.101:8091/api/health
```

## 2. Benutzung

1. `http://<LXC-IP>:8091` öffnen.
2. URL eingeben, optional CSS/XPath/Text-Selector (leer = ganze Seite), Fetcher `auto` lassen.
3. Ergebnisse filtern, als JSON/CSV herunterladen.
4. Reiter **Verlauf**: filtern, Detail öffnen, Export.

## 3. Reboot-Test

```bash
CT=101
pct reboot $CT && sleep 30
pct exec $CT -- systemctl is-active scrapjaeger
curl -fs http://$(pct exec $CT -- ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1):8091/api/health
pct config $CT | grep -i onboot
```

## 4. Update (idempotent)

```bash
bash scrapjaeger.sh --ctid 101
```

## 5. Deinstallation

```bash
pct stop 101 && pct destroy 101
```

## 6. Debugging (komplette Fehlermeldungskette)

- Jeder Lauf loggt stdout+stderr nach `/tmp/scrapjaeger-install-*.log`.
- Im Container zusätzlich `/var/log/scrapjaeger-setup.log`.
- Bei Fehlern: Befehl, Exit-Code, Zeile, Stacktrace, `pct config/status`, `journalctl -u scrapjaeger -n 100`.
- Re-Run mit Trace: `bash -x install/scrapjaeger.sh --ctid 101`.

## 7. Dateien

```
ScrapJaeger/
├── install/scrapjaeger.sh          # Proxmox-Installer
├── systemd/scrapjaeger.service     # systemd-Unit
├── app/
│   ├── server.py                   # FastAPI: /api/health, /api/scrape, /api/history
│   ├── scraper.py                  # Scrapling-Wrapper (auto/http/stealthy/dynamic)
│   ├── db.py                       # SQLite (scrapes, crawls, jobs)
│   ├── requirements.txt
│   ├── .env.example
│   └── public/                     # Dashboard (dichte Tabellen, Filter, Export)
├── docs/superpowers/plans/         # Implementierungsplan
└── README.md
```
