#!/bin/sh
# Install the static Konica 206 PAPPL app on the target host.
#
# Works on systemd hosts (Fedora/RHEL/bootc, Debian, Ubuntu) and on OpenRC
# hosts (Alpine). The binaries are portable; everything around them (user
# creation, service manager, CUPS queue, SELinux) is not, so this script
# detects the host and generates the right files.
#
# Nothing is started by default: set KONICA_START=1 to enable/start the
# service, and KONICA_SET_DEFAULT=1 to make the new CUPS queue the default.
set -eu

here="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Configuration (all overridable from the environment)
# ---------------------------------------------------------------------------
HOME_DIR=${KONICA_HOME:-/var/lib/konica206}
BIN_DIR="$HOME_DIR/bin"
PPD_DIR="$HOME_DIR/ppd"
SPOOL_DIR="$HOME_DIR/spool"
PORT=${KONICA_PORT:-8003}
QUEUE=${KONICA_QUEUE:-konica206-static}
PRINTER=${KONICA_PRINTER:-KONICA206}
RENDERER=${KONICA_PDF_RENDERER:-builtin}
SERIAL=${KONICA_SERIAL:-}
START=${KONICA_START:-0}
SET_DEFAULT=${KONICA_SET_DEFAULT:-0}

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "==> $*"; }

case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  --help|-h)
    sed -n '2,18p' "$0"
    exit 0 ;;
  "") CHECK_ONLY=0 ;;
  *) fail "unknown argument: $1 (try --help)" ;;
esac

# ---------------------------------------------------------------------------
# Host detection and prerequisite checks
# ---------------------------------------------------------------------------
distro_id=unknown
[ -r /etc/os-release ] && . /etc/os-release && distro_id=${ID:-unknown}

arch=$(uname -m)
[ "$arch" = x86_64 ] || fail "this is an x86-64 build; host is $arch"
[ "$(id -u)" -eq 0 ] || fail "run as root"

kver=$(uname -r)
kmaj=${kver%%.*}; krest=${kver#*.}; kmin=${krest%%.*}
case "$kmaj$kmin" in
  *[!0-9]*) warn "cannot parse kernel version '$kver'; assuming >= 4.9" ;;
  *)
    if [ "$kmaj" -lt 4 ] || { [ "$kmaj" -eq 4 ] && [ "$kmin" -lt 9 ]; }; then
      fail "kernel $kver is older than the binary's 4.9 minimum"
    fi ;;
esac

if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  init=systemd
elif command -v rc-service >/dev/null 2>&1 || command -v openrc >/dev/null 2>&1; then
  init=openrc
else
  init=none
fi

info "host: $distro_id, kernel $kver, init $init"

for f in konica206-native-server konica-native; do
  [ -x "$here/dist/$f" ] || fail "missing dist/$f; run scripts/build-static.sh in the Wolfi container first"
done
if command -v readelf >/dev/null 2>&1; then
  if readelf -l "$here/dist/konica206-native-server" | grep -qi interp; then
    fail "dist/konica206-native-server is not statically linked"
  fi
fi

case "$RENDERER" in
  builtin)
    if ! command -v gs >/dev/null 2>&1; then
      case "$distro_id" in
        debian|ubuntu|linuxmint|pop) pkg="apt install ghostscript" ;;
        alpine) pkg="apk add ghostscript" ;;
        *) pkg="dnf install ghostscript" ;;
      esac
      fail "Ghostscript is required by the builtin renderer ($pkg)"
    fi ;;
  cups)
    rf=${KONICA_RASTER_FILTER:-/usr/lib/cups/filter/pdftoraster}
    [ -x "$rf" ] || fail "KONICA_PDF_RENDERER=cups needs an executable pdftoraster at $rf"
    ;;
  *) fail "unknown KONICA_PDF_RENDERER: $RENDERER" ;;
esac

if command -v lpadmin >/dev/null 2>&1; then
  cups=yes
else
  cups=no
  warn "lpadmin not found; the CUPS queue will be skipped (install cups first)"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  info "checks passed; no changes made"
  exit 0
fi

# ---------------------------------------------------------------------------
# User, group and directories
# ---------------------------------------------------------------------------
info "creating user and directories under $HOME_DIR"
if [ "$init" = systemd ] && command -v systemd-sysusers >/dev/null 2>&1; then
  install -D -m 0644 "$here/config/sysusers/konica206.conf" /etc/sysusers.d/konica206.conf
  systemd-sysusers
elif command -v useradd >/dev/null 2>&1; then
  groupadd -f konica 2>/dev/null || true
  id -u konica >/dev/null 2>&1 || useradd -r -g konica -d "$HOME_DIR" -s /usr/sbin/nologin konica
elif command -v adduser >/dev/null 2>&1; then
  addgroup -S konica 2>/dev/null || true
  id -u konica >/dev/null 2>&1 || adduser -S -D -H -G konica -h "$HOME_DIR" -s /sbin/nologin konica
else
  fail "no supported user manager (need systemd-sysusers, useradd or adduser)"
fi

install -d -o konica -g konica -m 0755 "$BIN_DIR" "$PPD_DIR" "$SPOOL_DIR"
install -o konica -g konica -m 0755 "$here/dist/konica206-native-server" "$BIN_DIR/"
install -o konica -g konica -m 0755 "$here/dist/konica-native" "$BIN_DIR/"

# PPD: take KONICA_PPD, a copy shipped in dist/, or the known host path.
ppd=${KONICA_PPD:-}
if [ -z "$ppd" ]; then
  for candidate in "$here/dist/konica206-native.ppd" \
                   /usr/share/konica206/ppd/KonicaMinolta-206-fullbleed-rotated.ppd; do
    [ -f "$candidate" ] && { ppd=$candidate; break; }
  done
fi
if [ -n "$ppd" ] && [ -f "$ppd" ]; then
  install -o konica -g konica -m 0644 "$ppd" "$PPD_DIR/konica206.ppd"
  PPD_FILE="$PPD_DIR/konica206.ppd"
else
  PPD_FILE="$PPD_DIR/konica206.ppd"
  warn "no PPD found; set KONICA_PPD and re-run, or copy a PPD to $PPD_FILE"
fi

install -D -m 0644 "$here/config/udev/70-konica206.rules" /etc/udev/rules.d/70-konica206.rules
udevadm control --reload >/dev/null 2>&1 || true
udevadm trigger >/dev/null 2>&1 || true

# SELinux only exists on Fedora/RHEL; AppArmor/distros without it need no label.
if command -v semanage >/dev/null 2>&1 && command -v restorecon >/dev/null 2>&1; then
  semanage fcontext -a -t bin_t "$BIN_DIR(/.*)?" 2>/dev/null || true
  restorecon -R "$BIN_DIR" >/dev/null 2>&1 || true
fi

env_lines="Environment=KONICA_VENDOR_FILTER=$BIN_DIR/konica-native
Environment=KONICA_PPD=$PPD_FILE
Environment=KONICA_PDF_RENDERER=$RENDERER
Environment=KONICA_LISTEN=localhost
Environment=KONICA_SPOOLDIR=$SPOOL_DIR"
if [ -n "$SERIAL" ]; then
  env_lines="$env_lines
Environment=KONICA_SERIAL=$SERIAL"
fi
if [ -n "${KONICA_RASTER_FILTER:-}" ]; then
  env_lines="$env_lines
Environment=KONICA_RASTER_FILTER=$KONICA_RASTER_FILTER"
fi

# ---------------------------------------------------------------------------
# Service definition
# ---------------------------------------------------------------------------
case "$init" in
  systemd)
    info "installing systemd unit (port $PORT)"
    install -D -m 0644 "$here/config/systemd/konica206.service" /etc/systemd/system/konica206.service
    mkdir -p /etc/systemd/system/konica206.service.d
    cat > /etc/systemd/system/konica206.service.d/10-port.conf <<EOF
[Service]
ExecStart=
ExecStart=$BIN_DIR/konica206-native-server server -o server-port=$PORT -o listen=localhost
User=konica
Group=konica
SupplementaryGroups=lp
StateDirectory=
WorkingDirectory=$HOME_DIR
ReadWritePaths=
ReadWritePaths=$HOME_DIR
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
$env_lines
EOF
    systemctl daemon-reload
    ;;
  openrc)
    info "installing OpenRC init script (port $PORT)"
    install -d -m 0755 /etc/conf.d /etc/init.d
    cat > /etc/conf.d/konica206 <<EOF
# Generated by scripts/install.sh
KONICA_VENDOR_FILTER=$BIN_DIR/konica-native
KONICA_PPD=$PPD_FILE
KONICA_PDF_RENDERER=$RENDERER
KONICA_LISTEN=localhost
KONICA_SPOOLDIR=$SPOOL_DIR
EOF
    if [ -n "$SERIAL" ]; then echo "KONICA_SERIAL=$SERIAL" >> /etc/conf.d/konica206; fi
    if [ -n "${KONICA_RASTER_FILTER:-}" ]; then
      echo "KONICA_RASTER_FILTER=$KONICA_RASTER_FILTER" >> /etc/conf.d/konica206
    fi
    cat > /etc/init.d/konica206 <<EOF
#!/sbin/openrc-run
# Generated by scripts/install.sh. No namespace hardening on OpenRC.
name="Konica bizhub 206 printer application"
command="$BIN_DIR/konica206-native-server"
command_args="server -o server-port=$PORT -o listen=localhost"
command_user="konica:konica"
command_background="yes"
pidfile="/run/konica206.pid"
depend() {
  need localmount
  use net
}
EOF
    chmod 0755 /etc/init.d/konica206
    warn "OpenRC has no systemd-style sandboxing; keep the USB udev rule and localhost bind"
    ;;
  none)
    warn "no supported init system; start manually:"
    echo "  $BIN_DIR/konica206-native-server server -o server-port=$PORT -o listen=localhost"
    ;;
esac

# ---------------------------------------------------------------------------
# CUPS queue
# ---------------------------------------------------------------------------
uri="ipp://127.0.0.1:$PORT/ipp/print/$PRINTER"
if [ "$cups" = yes ]; then
  info "configuring CUPS queue $QUEUE -> $uri"
  if lpstat -p "$QUEUE" >/dev/null 2>&1; then
    lpadmin -p "$QUEUE" -v "$uri" -m everywhere -E
  else
    lpadmin -p "$QUEUE" -E -v "$uri" -m everywhere
  fi
  if [ "$SET_DEFAULT" -eq 1 ]; then lpadmin -d "$QUEUE"; fi
else
  warn "after installing CUPS, create the queue with:"
  echo "  lpadmin -p $QUEUE -E -v $uri -m everywhere"
fi

# ---------------------------------------------------------------------------
# Optional start
# ---------------------------------------------------------------------------
if [ "$START" -eq 1 ]; then
  info "enabling and starting the service"
  case "$init" in
    systemd) systemctl enable --now konica206 ;;
    openrc) rc-update add konica206 default && rc-service konica206 start ;;
    none) warn "cannot start without an init system" ;;
  esac
else
  info "not starting automatically; set KONICA_START=1 to enable/start"
fi

info "done. Add vendor data (docs/vendor-data.md), then send a print from $QUEUE."
