# Portability and host installation

The two build outputs are fully static x86-64 binaries with no ELF interpreter:

- `dist/konica206-native-server` — PAPPL printer application
- `dist/konica-native` — Konica raster vendor filter

They run on glibc **and** musl hosts because they carry their own libc. TLS
(OpenSSL) is linked in; DNS-SD, avahi and GnuTLS are not used.

## Tested

Smoke-tested inside disposable containers (the binaries start and print their
usage text; no printer was attached, so no physical print was attempted):

| Host | libc | Result |
|---|---|---|
| Fedora (glibc) | glibc | server and filter run |
| Alpine 3.24 | musl | server and filter run |
| Kernel note in both binaries | — | minimum Linux 4.9 |

The installer's `--check` mode was exercised on Fedora and Alpine, and full
installs were exercised in throwaway containers to verify the generated systemd
drop-in, OpenRC service and CUPS queue commands.

## Host prerequisites

1. **x86-64 Linux, kernel >= 4.9.**
2. **Ghostscript** in `PATH` when `KONICA_PDF_RENDERER=builtin` (the default).
   The renderer execs `gs` for every PDF job.
   - Debian/Ubuntu: `apt install ghostscript`
   - Alpine: `apk add ghostscript`
   - Fedora/RHEL: `dnf install ghostscript`
   Alternatively set `KONICA_PDF_RENDERER=cups` (and optionally
   `KONICA_RASTER_FILTER=/path/to/pdftoraster`) to use CUPS' raster filter.
3. **USB access.** The udev rule sets group `konica` on VID `132b` / PID
   `232b`; the service user is in that group. On non-udev hosts arrange
   equivalent permissions for `/dev/bus/usb`.
4. **CUPS** with `lpadmin`/`lpstat` if you want a print queue.
5. **Vendor data** (halftone + ICC profiles) from a licensed Konica driver —
   see [vendor-data.md](vendor-data.md). It is never committed here.

## Installing

```sh
sh scripts/install.sh --check   # prerequisites only, no changes
sudo sh scripts/install.sh      # install files, create queue, do not start
sudo env KONICA_START=1 sh scripts/install.sh   # also enable + start
```

Detected host types:

- **systemd** (Fedora/RHEL/bootc, Debian, Ubuntu): installs
  `/etc/systemd/system/konica206.service` plus a port drop-in that sets the
  localhost bind, environment, USB group and `AF_NETLINK` (needed by libusb).
  SELinux users get a `bin_t` fcontext rule; other distros need no label.
- **OpenRC** (Alpine): installs `/etc/conf.d/konica206` and
  `/etc/init.d/konica206`. There is no systemd-style sandboxing, so the USB
  rule and localhost bind are the security boundary.
- **No supported init**: binaries, user, udev rule and PPD are installed, and
  the printed command can be run manually (e.g. from your own supervisor).

Useful environment overrides:

| Variable | Default | Meaning |
|---|---|---|
| `KONICA_PORT` | `8003` | IPP TCP port (8001 is the old service) |
| `KONICA_QUEUE` | `konica206-static` | CUPS queue name |
| `KONICA_PRINTER` | `KONICA206` | PAPPL printer resource name |
| `KONICA_HOME` | `/var/lib/konica206` | state, binaries, PPD and spool |
| `KONICA_PPD` | auto-detected | source PPD copied into the state dir |
| `KONICA_SERIAL` | empty | printer serial, if you want it pinned |
| `KONICA_PDF_RENDERER` | `builtin` | `builtin` (gs) or `cups` (pdftoraster) |
| `KONICA_START` | `0` | enable and start the service |
| `KONICA_SET_DEFAULT` | `0` | make the queue the CUPS default |

The script never stops or removes other printer stacks. On this host the old
8001 systemd service, the 8002 nspawn machine and the 8000 legacy app were left
untouched; the new queue must be selected explicitly unless you set
`KONICA_SET_DEFAULT=1`.

## What does *not* transfer

- The systemd hardening options are distro/version specific; the OpenRC path
  deliberately drops them.
- SELinux fcontext rules are Fedora/RHEL-specific. AppArmor needs its own
  profile if you want Mandatory Access Control on Debian/Ubuntu.
- CUPS queue setup (`-m everywhere`) assumes IPP Everywhere support and the
  printer's real 12 pt imageable margins in the driver; a stale PAPPL state
  file from a full-bleed build must be migrated once (see
  [acceptance.md](acceptance.md#upgrading-from-the-full-bleed-build)).
- The physical print has only been verified on the Fedora host with the
  bizhub 206 attached; other hosts were smoke-tested, not printed on.
