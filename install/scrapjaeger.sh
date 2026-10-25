#!/usr/bin/env bash
#
# ScrapJaeger auf Proxmox LXC – Einzeiler-Installation (Community-Scripts-Stil)
#
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/ScreapeLing-Jaeger/main/install/scrapjaeger.sh)"
#
# Flags/Env: --ctid/--cores/--memory/--disk/--bridge/--storage/--port/--debug
#
set -Eeuo pipefail

# ---------------- Variablen (oben, anpassbar) ----------------
APP="scrapjaeger"
HOSTNAME="scrapjaeger"
REPO="https://github.com/HatchetMan111/ScreapeLing-Jaeger.git"
BRANCH="main"
PORT="${PORT:-8091}"
CORES="${CORES:-2}"
RAM="${RAM:-3072}"
DISK="${DISK:-10}"
BRIDGE="${BRIDGE:-vmbr0}"
STORAGE="${STORAGE:-}"          # leer = auto (local-lvm, Fallback local)
TEMPLATE_STORE="local"
CT_ID="${CT_ID:-}"             # leer = naechste freie ID
DEBUG="${DEBUG:-0}"

LOG="/tmp/${APP}-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

# ---------------- Fehlerkette (komplett, nie nur letzte Zeile) ----------------
fail() {
  local code=$? cmd="${BASH_COMMAND:-?}"
  echo ""
  echo "[FAIL] Installation abgebrochen."
  echo "  Befehl   : $cmd"
  echo "  Exit-Code: $code"
  echo "  Zeile    : ${BASH_LINENO[0]:-?} in ${FUNCNAME[1]:-main}"
  echo "  Stacktrace:"
  local i=0
  while caller $i 2>/dev/null; do i=$((i + 1)); done | sed 's/^/    /'
  if [[ -n "${CTID:-}" ]]; then
    echo "  --- pct config $CTID ---"
    pct config "$CTID" 2>&1 | sed 's/^/    /' || true
    echo "  --- pct status $CTID ---"
    pct status "$CTID" 2>&1 | sed 's/^/    /' || true
    echo "  --- journalctl -u $APP (letzte 100) ---"
    pct exec "$CTID" -- journalctl -u "$APP" --no-pager -n 100 2>&1 | sed 's/^/    /' || true
    echo "  --- Setup-Log im Container ---"
    pct exec "$CTID" -- tail -n 80 /var/log/scrapjaeger-setup.log 2>&1 | sed 's/^/    /' || true
  fi
  echo "  Voll-Log : $LOG"
  echo "  Re-Run mit Trace: bash -x install/scrapjaeger.sh --ctid ${CTID:-<id>}"
  exit "$code"
}
trap fail ERR

usage() {
  cat <<EOF
Verwendung: scrapjaeger.sh [--ctid ID] [--cores N] [--memory MB] [--disk GB]
  [--bridge vmbr0] [--storage local-lvm] [--port 8091] [--debug] [--help]
Env-Alternativen: CT_ID, CORES, RAM, DISK, BRIDGE, STORAGE, PORT, DEBUG=1
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ctid) CT_ID="$2"; shift 2 ;;
    --cores) CORES="$2"; shift 2 ;;
    --memory) RAM="$2"; shift 2 ;;
    --disk) DISK="$2"; shift 2 ;;
    --bridge) BRIDGE="$2"; shift 2 ;;
    --storage) STORAGE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --debug) DEBUG=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unbekannte Option: $1"; usage; exit 2 ;;
  esac
done
[[ "$DEBUG" == "1" ]] && set -x

ok() { echo "[OK]    $*"; }
step() { echo "==> $*"; }

# ---------------- 1. Host-Pruefung ----------------
step "Pruefe Host und Werkzeuge"
[[ "$(id -u)" -eq 0 ]] || { echo "Bitte als root auf dem Proxmox-Host ausfuehren."; exit 1; }
for bin in pct pvesh pveam wget openssl; do
  command -v "$bin" >/dev/null || { echo "Fehlt auf dem Host: $bin"; exit 1; }
done
ok "Host ok (root, pct/pvesh/pveam/wget/openssl vorhanden)."

# ---------------- 2. CT-ID (immer naechste freie) ----------------
if [[ -z "$CT_ID" ]]; then
  CT_ID="$(pvesh get /cluster/nextid)"
fi
CTID="$CT_ID"
ok "CT-ID: $CTID"

# ---------------- 3. Storage ----------------
if [[ -z "$STORAGE" ]]; then
  if pvesh get /storage/local-lvm --output-format json >/dev/null 2>&1; then
    STORAGE="local-lvm"
  else
    STORAGE="local"
  fi
fi
ok "RootFS-Storage: $STORAGE"

# ---------------- 4. Template ----------------
step "Pruefe debian-12-Standard-Template auf '$TEMPLATE_STORE'"
TPL_HAVE="$(pveam list "$TEMPLATE_STORE" 2>/dev/null | awk '/debian-12-standard/ {print $1}' | sort -V | tail -1 || true)"
if [[ -z "$TPL_HAVE" ]]; then
  step "Lade neuestes debian-12-Standard-Template"
  pveam update
  TPL_AVAIL="$(pveam available --section system 2>/dev/null | awk '/debian-12-standard/ {print $2}' | sort -V | tail -1)"
  [[ -n "$TPL_AVAIL" ]] || { echo "Kein debian-12-Template verfuegbar."; exit 1; }
  pveam download "$TEMPLATE_STORE" "$TPL_AVAIL"
  TPL_HAVE="$(pveam list "$TEMPLATE_STORE" 2>/dev/null | awk '/debian-12-standard/ {print $1}' | sort -V | tail -1)"
fi
[[ -n "$TPL_HAVE" ]] || { echo "Template-Auswahl fehlgeschlagen."; exit 1; }
ok "Template: $TPL_HAVE"

# ---------------- 5. Container erstellen (oder Update-Pfad) ----------------
NEW_CT=0
if pct status "$CTID" >/dev/null 2>&1; then
  step "CT $CTID existiert bereits -> Update-Pfad (idempotent, keine Datenverluste)"
else
  step "Erstelle LXC $CTID ($HOSTNAME, $CORES vCPU / $RAM MB / ${DISK}G)"
  ROOT_PW="$(openssl rand -base64 12)"
  pct create "$CTID" "$TPL_HAVE" \
    --hostname "$HOSTNAME" --cores "$CORES" --memory "$RAM" \
    --rootfs "$STORAGE:$DISK" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=dhcp" \
    --onboot 1 --unprivileged 1 --features nesting=1 \
    --password "$ROOT_PW" --start 1
  NEW_CT=1
  ok "Container erstellt und gestartet."
fi

step "Warte auf Boot + Netzwerk"
LXC_IP=""
for i in $(seq 1 30); do
  sleep 5
  LXC_IP="$(pct exec "$CTID" -- ip -4 -o addr show eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
  if [[ -n "${LXC_IP:-}" ]]; then break; fi
done
[[ -n "${LXC_IP:-}" ]] || { echo "Keine Container-IP erhalten."; exit 1; }
ok "Container-IP: $LXC_IP"

# ---------------- 6. Setup-Dateien in den Container schieben ----------------
step "Uebertrage Setup-Script in den Container"
SETUP_LOCAL="$(mktemp)"
ENV_LOCAL="$(mktemp)"
chmod 600 "$ENV_LOCAL"
cat > "$ENV_LOCAL" <<EOF
PORT=$PORT
DEBUG=$DEBUG
EOF

# bewusst quoted heredoc (keine Expansion auf dem Host)
cat > "$SETUP_LOCAL" <<'SETUP_EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
APP="scrapjaeger"
PORT_IN="${1:?PORT fehlt}"
ENV_FILE="/tmp/scrapjaeger-env"
LOG="/var/log/scrapjaeger-setup.log"
exec > >(tee -a "$LOG") 2>&1
# shellcheck disable=SC1090
source "$ENV_FILE"

echo "==> [CT] Systempakete"
export DEBIAN_FRONTEND=noninteractive
export LANG=C LC_ALL=C
apt-get update
apt-get install -y curl ca-certificates gnupg git python3 python3-venv python3-pip \
  build-essential iproute2 openssl

echo "==> [CT] User $APP"
id "$APP" >/dev/null 2>&1 || useradd -r -m -d "/opt/$APP" -s /bin/bash "$APP"
mkdir -p "/opt/$APP/data"
chown -R "$APP:$APP" "/opt/$APP"

echo "==> [CT] App-Code (Klon oder Update)"
cd "/opt/$APP"
git config --global --add safe.directory "/opt/$APP/repo" 2>/dev/null || true
NEED_BUILD=0
if [[ -d repo/.git ]]; then
  OLD_REV="$(git -C repo rev-parse HEAD)"
  git -C repo fetch origin
  git -C repo reset --hard "origin/main"
  NEW_REV="$(git -C repo rev-parse HEAD)"
  [[ "$OLD_REV" != "$NEW_REV" ]] && NEED_BUILD=1
else
  rm -rf repo app repo-tmp
  git clone --branch main --depth 1 "https://github.com/HatchetMan111/ScreapeLing-Jaeger.git" repo-tmp
  mv repo-tmp repo
  NEED_BUILD=1
fi
ln -sfn "/opt/$APP/repo/app" app
chown -R "$APP:$APP" "/opt/$APP"

echo "==> [CT] venv + Python-Abhaengigkeiten"
[[ -d venv ]] || python3 -m venv venv
venv/bin/pip install --upgrade pip
if [[ "$NEED_BUILD" == "1" || ! -f venv/.built ]]; then
  venv/bin/pip install -r app/requirements.txt
  touch venv/.built
fi
chown -R "$APP:$APP" "/opt/$APP"

echo "==> [CT] Scrapling-Browser (Chromium) passend zur installierten Version"
export PLAYWRIGHT_BROWSERS_PATH="/opt/$APP/ms-playwright"
mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"
if ! (cd app && /opt/$APP/venv/bin/scrapling install); then
  echo "[CT] Fallback: scrapling.cli.install()"
  /opt/$APP/venv/bin/python -c "from scrapling.cli import install; install([], standalone_mode=False)"
fi
chown -R "$APP:$APP" "/opt/$APP"
unset PLAYWRIGHT_BROWSERS_PATH

echo "==> [CT] .env (nur leere Werte fuellen, gesetzte nie ueberschreiben)"
[[ -f /opt/$APP/.env ]] || cp "app/.env.example" "/opt/$APP/.env"
fill_empty() { # key value file
  local key="$1" val="$2" file="$3"
  [[ -z "$val" ]] && return 0
  grep -q "^${key}=$" "$file" 2>/dev/null || return 0
  python3 - "$key" "$val" "$file" <<'PYEOF'
import sys
key, val, path = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().splitlines(keepends=True)
with open(path, "w") as f:
    for line in lines:
        f.write((key + "=" + val + "\n") if line.strip() == key + "=" else line)
PYEOF
}
set +x
fill_empty PORT "$PORT_IN" "/opt/$APP/.env"
fill_empty DB_PATH "/opt/$APP/data/scrapes.db" "/opt/$APP/.env"
[[ "${DEBUG:-0}" == "1" ]] && set -x
chown "$APP:$APP" "/opt/$APP/.env"
chmod 600 "/opt/$APP/.env"

echo "==> [CT] systemd-Unit"
cp "repo/systemd/scrapjaeger.service" /etc/systemd/system/scrapjaeger.service
sed -i "s/--port [0-9]\{1,\}/--port $PORT_IN/" /etc/systemd/system/scrapjaeger.service
systemctl daemon-reload
systemctl enable scrapjaeger >/dev/null
systemctl restart scrapjaeger || systemctl start scrapjaeger

echo "==> [CT] Firewall"
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "$PORT_IN"/tcp
fi

rm -f "$ENV_FILE"
echo "[CT] Setup fertig."
SETUP_EOF

pct push "$CTID" "$SETUP_LOCAL" /tmp/scrapjaeger-setup.sh
pct push "$CTID" "$ENV_LOCAL" /tmp/scrapjaeger-env
shred -u "$ENV_LOCAL" 2>/dev/null || rm -f "$ENV_LOCAL"
rm -f "$SETUP_LOCAL"

step "Fuehre Setup im Container aus"
pct exec "$CTID" -- bash /tmp/scrapjaeger-setup.sh "$PORT"
# Cleanup ist Kosmetik und darf die Installation nie scheitern lassen
pct exec "$CTID" -- rm -f /tmp/scrapjaeger-setup.sh /tmp/scrapjaeger-env 2>/dev/null \
  || echo "[WARN]   Container-Cleanup uebersprungen (harmlos)."
ok "Setup im Container abgeschlossen."

# ---------------- 7. Verifikation ----------------
step "Verifiziere Service + Web UI"
pct exec "$CTID" -- systemctl is-active scrapjaeger
ok "Service laeuft (systemctl is-active scrapjaeger = active)."
for i in $(seq 1 45); do
  if pct exec "$CTID" -- curl -fs "http://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
  [[ "$i" == "45" ]] && {
    echo "Web UI antwortet nicht auf Port $PORT."
    pct exec "$CTID" -- journalctl -u scrapjaeger --no-pager -n 100 2>&1 || true
    exit 1
  }
done
ok "Web UI antwortet (HTTP-Check auf localhost:$PORT/api/health)."

echo ""
echo "================ INSTALLATION ERFOLGREICH ================"
echo "  App          : ScrapJaeger - lokales Scrapling-Dashboard"
echo "  Container    : CT $CTID (Hostname: $HOSTNAME, onboot=1)"
echo "  Ressourcen   : $CORES vCPU / $RAM MB RAM / ${DISK} GB Disk"
echo "  Web UI       : http://$LXC_IP:$PORT"
echo "  Health       : http://$LXC_IP:$PORT/api/health"
if [[ "$NEW_CT" == "1" ]]; then
echo "  Root-Passwort: $ROOT_PW (nur jetzt angezeigt - sicher ablegen!)"
fi
echo "  Service      : systemctl status scrapjaeger  (im Container via: pct enter $CTID)"
echo "  Update       : Skript erneut laufen lassen: bash scrapjaeger.sh --ctid $CTID"
echo "  Deinstall    : pct stop $CTID && pct destroy $CTID"
echo "  Reboot-Test  : pct reboot $CTID && sleep 30 && curl -fs http://$LXC_IP:$PORT/api/health"
echo "  Log          : $LOG"
echo "=========================================================="
