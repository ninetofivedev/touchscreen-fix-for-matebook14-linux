#!/usr/bin/env bash
# Installer for ninetofivedev/touchscreen-fix-for-matebook14-linux
# Targets systemd-based Linux distributions. Run: sudo bash install-touchscreen-fix.sh
set -Eeuo pipefail

readonly SCRIPT_PATH='/usr/local/bin/ftsc1000-touch-init.sh'
readonly SERVICE_PATH='/etc/systemd/system/ftsc1000-touch.service'
readonly SERVICE_NAME='ftsc1000-touch.service'
readonly MARKER='# Managed by ftsc1000-touchscreen-fix-installer'

info()  { printf '[INFO] %s\n' "$*"; }
ok()    { printf '[ OK ] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
die()   { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

on_error() {
  local code="$1" line="$2"
  warn "Abbruch in Zeile $line (Exit-Code $code). Bitte Status prüfen und ggf. Option 2 wählen."
}
trap 'on_error "$?" "$LINENO"' ERR

check_platform() {
  [[ "$(uname -s)" == Linux ]] || die 'Dieses Script ist nur für Linux vorgesehen.'
  command -v systemctl >/dev/null 2>&1 || die 'systemctl fehlt. Benötigt wird systemd.'
  [[ -d /run/systemd/system ]] || die 'systemd ist auf diesem System nicht aktiv.'
  command -v modprobe >/dev/null 2>&1 || die 'modprobe fehlt (Paket kmod benötigt).'
}

is_managed() {
  [[ -f "$1" ]] && grep -Fxq -- "$MARKER" "$1"
}

check_conflicts() {
  local f
  for f in "$SCRIPT_PATH" "$SERVICE_PATH"; do
    if [[ -e "$f" || -L "$f" ]]; then
      [[ ! -L "$f" ]] || die "Symlink gefunden: $f. Kein automatisches Überschreiben."
      is_managed "$f" || die "Nicht verwaltete Datei vorhanden: $f. Keine Änderung vorgenommen."
    fi
  done
}

write_init_script() {
  local tmp
  tmp=$(mktemp "${SCRIPT_PATH}.tmp.XXXXXXXX")
  cat > "$tmp" <<'INNER'
#!/usr/bin/env bash
# Managed by ftsc1000-touchscreen-fix-installer
set -e
modprobe -r i2c_hid_acpi
sleep 2
modprobe i2c_hid_acpi
sleep 2
INNER
  chmod 0755 "$tmp"
  mv -f -- "$tmp" "$SCRIPT_PATH"
  [[ -x "$SCRIPT_PATH" ]] || die 'Init-Script ist nicht ausführbar.'
  bash -n "$SCRIPT_PATH" || die 'Syntaxprüfung des Init-Scripts fehlgeschlagen.'
}

write_service() {
  local tmp
  tmp=$(mktemp "${SERVICE_PATH}.tmp.XXXXXXXX")
  cat > "$tmp" <<'UNIT'
# Managed by ftsc1000-touchscreen-fix-installer
[Unit]
Description=FTSC1000 Touchscreen Init Delay Fix
After=systemd-modules-load.service
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ftsc1000-touch-init.sh
TimeoutStartSec=10

[Install]
WantedBy=multi-user.target
UNIT
  chmod 0644 "$tmp"
  mv -f -- "$tmp" "$SERVICE_PATH"
  [[ -s "$SERVICE_PATH" ]] || die 'Service-Datei ist leer.'
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$SERVICE_PATH" || die 'systemd-Service-Verifikation fehlgeschlagen.'
  fi
}

install_fix() {
  info 'Prüfe Systemvoraussetzungen ...'
  check_platform
  check_conflicts
  ok 'Keine fremden Dateien werden überschrieben.'

  if modinfo i2c_hid_acpi >/dev/null 2>&1; then
    ok 'Kernelmodul i2c_hid_acpi gefunden.'
  else
    warn 'Kernelmodul derzeit nicht über modinfo auffindbar. Bitte Kernel/Hardware prüfen.'
  fi

  info 'Erstelle Touchscreen-Initialisierungsscript ...'
  write_init_script
  ok "$SCRIPT_PATH erstellt und geprüft."

  info 'Erstelle systemd-Service ...'
  write_service
  ok "$SERVICE_PATH erstellt und geprüft."

  info 'Lade systemd-Konfiguration neu ...'
  systemctl daemon-reload
  ok 'systemd-Konfiguration aktualisiert.'

  info 'Aktiviere Service für künftige Systemstarts ...'
  systemctl enable "$SERVICE_NAME"
  systemctl is-enabled --quiet "$SERVICE_NAME" || die 'Service wurde nicht aktiviert.'
  ok "$SERVICE_NAME ist aktiviert."
  printf '\n'
  ok 'Installation abgeschlossen. Bitte Linux neu starten und Touchscreen testen.'
  info 'Der Service wurde absichtlich nicht sofort gestartet.'
}

uninstall_fix() {
  info 'Prüfe vorhandene Installation ...'
  check_platform
  local f found=0
  for f in "$SCRIPT_PATH" "$SERVICE_PATH"; do
    if [[ -e "$f" || -L "$f" ]]; then
      [[ ! -L "$f" ]] || die "Symlink vorhanden: $f. Entfernung aus Sicherheitsgründen verweigert."
      is_managed "$f" || die "Fremde oder veränderte Datei: $f. Keine Entfernung vorgenommen."
      found=1
    fi
  done

  if (( found == 0 )); then
    info 'Keine durch diesen Installer verwalteten Dateien gefunden.'
    return 0
  fi

  info 'Deaktiviere systemd-Service ...'
  systemctl disable "$SERVICE_NAME" || die 'Service konnte nicht deaktiviert werden.'
  ok 'Service deaktiviert.'

  info 'Entferne verwaltete Dateien ...'
  for f in "$SERVICE_PATH" "$SCRIPT_PATH"; do
    if [[ -f "$f" ]]; then
      rm -- "$f"
      ok "$f entfernt."
    fi
  done

  info 'Lade systemd-Konfiguration neu ...'
  systemctl daemon-reload
  [[ ! -e "$SCRIPT_PATH" && ! -e "$SERVICE_PATH" ]] || die 'Eine Datei wurde nicht entfernt.'
  ok 'Deinstallation abgeschlossen. Beim nächsten Neustart wird der Fix nicht mehr ausgeführt.'
}

confirm() {
  local answer
  printf '\nWirklich %s? [Y/n]: ' "$1"
  IFS= read -r answer || die 'Keine Bestätigung erhalten.'
  case "$answer" in
    Y|y|J|j|YES|yes|JA|ja|'') return 0 ;;
    *) info 'Abgebrochen. Keine Änderungen vorgenommen.'; return 1 ;;
  esac
}

main() {
  [[ "$EUID" -eq 0 ]] || die 'Bitte mit sudo starten: sudo bash install-touchscreen-fix.sh'
  printf '\n=============================================\n'
  printf ' FTSC1000 Touchscreen Fix – MateBook 14 2025\n'
  printf '=============================================\n\n'
  printf '1) Fix installieren / erneut installieren\n'
  printf '2) Fix vollständig deinstallieren\n'
  printf '3) Beenden\n\n'
  local choice
  printf 'Auswahl [1-3]: '
  IFS= read -r choice || die 'Keine Auswahl erhalten.'
  case "$choice" in
    1) confirm 'installieren' || return 0; install_fix ;;
    2) confirm 'deinstallieren' || return 0; uninstall_fix ;;
    3) info 'Beendet.' ;;
    *) die 'Ungültige Auswahl.' ;;
  esac
}

main "$@"
