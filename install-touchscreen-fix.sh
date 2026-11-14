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
  warn "Failed at line $line (exit code $code). Check the status and use option 2 if necessary."
}
trap 'on_error "$?" "$LINENO"' ERR

check_platform() {
  [[ "$(uname -s)" == Linux ]] || die 'This script only supports Linux.'
  command -v systemctl >/dev/null 2>&1 || die 'systemctl not found. systemd is required.'
  [[ -d /run/systemd/system ]] || die 'systemd is not running on this system.'
  command -v modprobe >/dev/null 2>&1 || die 'modprobe not found (the kmod package is required).'
}

is_managed() {
  [[ -f "$1" ]] && grep -Fxq -- "$MARKER" "$1"
}

check_conflicts() {
  local f
  for f in "$SCRIPT_PATH" "$SERVICE_PATH"; do
    if [[ -e "$f" || -L "$f" ]]; then
      [[ ! -L "$f" ]] || die "Symbolic link found: $f. Refusing to overwrite it."
      is_managed "$f" || die "Unmanaged file already exists: $f. No changes made."
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
  [[ -x "$SCRIPT_PATH" ]] || die 'Initialization script is not executable.'
  bash -n "$SCRIPT_PATH" || die 'Initialization script syntax check failed.'
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
  [[ -s "$SERVICE_PATH" ]] || die 'Service file is empty.'
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$SERVICE_PATH" || die 'systemd service verification failed.'
  fi
}

install_fix() {
  info 'Checking system requirements ...'
  check_platform
  check_conflicts
  ok 'No unmanaged files will be overwritten.'

  if modinfo i2c_hid_acpi >/dev/null 2>&1; then
    ok 'Kernel module i2c_hid_acpi found.'
  else
    warn 'Kernel module not found using modinfo. Please check your kernel and hardware.'
  fi

  info 'Creating touchscreen initialization script ...'
  write_init_script
  ok "$SCRIPT_PATH created and verified."

  info 'Creating systemd service ...'
  write_service
  ok "$SERVICE_PATH created and verified."

  info 'Reloading systemd configuration ...'
  systemctl daemon-reload
  ok 'systemd configuration reloaded.'

  info 'Enabling service for future boots ...'
  systemctl enable "$SERVICE_NAME"
  systemctl is-enabled --quiet "$SERVICE_NAME" || die 'Service could not be enabled.'
  ok "$SERVICE_NAME is enabled."
  printf '\n'
  ok 'Installation complete. Please reboot Linux and test the touchscreen.'
  info 'The service was intentionally not started immediately.'
}

uninstall_fix() {
  info 'Checking existing installation ...'
  check_platform
  local f found=0
  for f in "$SCRIPT_PATH" "$SERVICE_PATH"; do
    if [[ -e "$f" || -L "$f" ]]; then
      [[ ! -L "$f" ]] || die "Symbolic link found: $f. Refusing to remove it for safety reasons."
      is_managed "$f" || die "Unmanaged or modified file: $f. No files removed."
      found=1
    fi
  done

  if (( found == 0 )); then
    info 'No files managed by this installer were found.'
    return 0
  fi

  info 'Disabling systemd service ...'
  systemctl disable "$SERVICE_NAME" || die 'Service could not be disabled.'
  ok 'Service disabled.'

  info 'Removing managed files ...'
  for f in "$SERVICE_PATH" "$SCRIPT_PATH"; do
    if [[ -f "$f" ]]; then
      rm -- "$f"
      ok "$f removed."
    fi
  done

  info 'Reloading systemd configuration ...'
  systemctl daemon-reload
  [[ ! -e "$SCRIPT_PATH" && ! -e "$SERVICE_PATH" ]] || die 'A file could not be removed.'
  ok 'Uninstallation complete. The fix will no longer run after the next reboot.'
}

confirm() {
  local answer
  printf '\nAre you sure you want to %s? [Y/n]: ' "$1"
  IFS= read -r answer || die 'No confirmation received.'
  case "$answer" in
    Y|y|YES|yes|'') return 0 ;;
    *) info 'Cancelled. No changes made.'; return 1 ;;
  esac
}

main() {
  [[ "$EUID" -eq 0 ]] || die 'Please run with sudo: sudo bash install-touchscreen-fix.sh'
  printf '\n=============================================\n'
  printf ' FTSC1000 Touchscreen Fix – MateBook 14 2025\n'
  printf '=============================================\n\n'
  printf '1) Install / reinstall touchscreen fix\n'
  printf '2) Uninstall touchscreen fix\n'
  printf '3) Exit\n\n'
  local choice
  printf 'Select an option [1-3]: '
  IFS= read -r choice || die 'No selection received.'
  case "$choice" in
    1) confirm 'install the fix' || return 0; install_fix ;;
    2) confirm 'uninstall the fix' || return 0; uninstall_fix ;;
    3) info 'Exiting.' ;;
    *) die 'Invalid selection.' ;;
  esac
}

main "$@"
