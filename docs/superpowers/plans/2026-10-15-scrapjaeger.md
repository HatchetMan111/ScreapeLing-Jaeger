# ScrapJaeger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Neues lokales Scrapling-Dashboard als Proxmox-LXC-Einzeiler bauen.

**Architecture:** FastAPI + Scrapling (auto http→stealthy→dynamic) + SQLite, Vanilla-JS-Dashboard ohne Build, ein systemd-Service, Installer wie PreisJaeger.

**Tech Stack:** Python 3.12, FastAPI, Uvicorn, Scrapling[fetchers,all], SQLite, Vanilla JS.

**Spec:** Brainstorming-Chat (Ansatz A, V1 Ad-hoc + Verlauf, V2/V3 reserviert, funktionales Dashboard, neues Repo, PreisJaeger unangetastet).

## Global Constraints

- Lokal ohne Cloud-Zwang, Port 8091, bind 0.0.0.0.
- Installer: set -Eeuo pipefail, idempotent, naechste freie CT-ID, onboot 1, Debian 12, 2 vCPU / 3072 MB / 10 GB.
- Service: Restart=always, After=network-online.target, systemctl enable.
- Verifikation: systemctl is-active + curl localhost:8091/api/health, finale URL ausgeben.
- Debugging: volle Fehlerkette + bash -x, Log unter /tmp/scrapjaeger-install-*.log.

## Review Focus

- Leere Selector-Eingabe darf nicht 500 werfen, sondern ganze Seite liefern.
- Nicht-http-URL muss 400 mit klarer Meldung geben.
- Selector-Fehler duerfen Scrape nicht crashen, sondern in errors landen.
- History-Limit muss auf 1..500 geclampt sein.
- Export-CSV muss auch bei 0 Zeilen gueltiges Header-CSV liefern.

---

### Task 1: Backend-Scrape

**Files:**
- Create: `app/scraper.py`
- Create: `app/db.py`
- Create: `app/server.py`

**Interfaces:**
- Consumes: Scrapling Fetcher/StealthyFetcher/DynamicFetcher
- Produces: `scraper.scrape(url, selector, selector_type, fetcher, timeout_ms) -> {items, fetcher, errors, duration_ms}`; `db.insert_scrape/get_history/get_by_id`; `POST /api/scrape`, `GET /api/health|history|history/export`

- [x] **Step 1: scraper.py schreiben** (auto-Fallback, max 500 Items, Fehler sammeln)
- [x] **Step 2: db.py schreiben** (scrapes/crawls/jobs-Tabellen, clamped limit)
- [x] **Step 3: server.py schreiben** (Validierung http(s), 400/404-Pfade, StaticFiles)
- [x] **Step 4: py_compile** — `python3 -m py_compile app/*.py` — exit 0
- [ ] **Step 5: Commit**

### Task 2: Dashboard-UI

**Files:**
- Create: `app/public/index.html`, `app/public/app.js`, `app/public/styles.css`

- [x] **Step 1: index.html** (Form URL/Selector/Typ/Fetcher, Tabellen)
- [x] **Step 2: app.js** (fetch-POST, renderRows max 300, Verlauf-Detail, Export)
- [x] **Step 3: styles.css** (dunkel, dicht, sticky header)
- [ ] **Step 4: Commit**

### Task 3: Installer + Service + Docs

**Files:**
- Create: `install/scrapjaeger.sh`, `systemd/scrapjaeger.service`, `README.md`

- [x] **Step 1: Installer** (nextid, Storage-Auto, Template, nesting=1, venv+pip, scrapling install, .env, Unit, Verifikation)
- [x] **Step 2: bash -n** — exit 0
- [x] **Step 3: systemd-Unit** (Restart=always, PLAYWRIGHT_BROWSERS_PATH, Port per sed)
- [x] **Step 4: README**
- [ ] **Step 5: Commit**
