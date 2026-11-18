# Acceptance checklist

The static build is verified in a clean Wolfi container. The service and
physical print tests are not. Tick every item before relying on this
deployment.

## Static link

- [ ] `file dist/konica206-native-server` reports "statically linked"
- [ ] `readelf -l dist/konica206-native-server | grep -i interp` prints nothing
- [ ] `strings dist/konica206-native-server | grep -Ei 'gnutls_|avahi_'` prints nothing (no GnuTLS or avahi symbols; OpenSSL strings are expected because PAPPL requires TLS)
- [ ] Static NSS warnings (`getpwnam_r`, `getpwuid_r`, `getservbyname`) seen at link time are understood and accepted
- [ ] The same binary runs on a non-Wolfi host (e.g. Fedora)

## Service

- [ ] Any existing service on `127.0.0.1:8001` is stopped before installing `konica206.service`
- [ ] `systemctl enable --now konica206` succeeds
- [ ] `systemctl status konica206` shows active (running)
- [ ] `journalctl -u konica206 -b` shows no errors
- [ ] USB device is visible to the `konica` user; VID/PID confirmed with `lsusb`
- [ ] `ipptool -tv ipp://127.0.0.1:8001/ipp/print get-printer-attributes.test` succeeds (adjust the printer path to match your PAPPL printer name)
- [ ] `systemd-analyze security konica206` reviewed
- [ ] Port 8001 is NOT reachable from the LAN — plain HTTP on `127.0.0.1` only

## Physical print tests

- [ ] single page
- [ ] duplex
- [ ] multiple copies
- [ ] large job

A green build is not a printed page.

## Upgrading from the full-bleed build

PAPPL validates saved `media-ready` entries against the margins the driver
advertises. A state file written while the app reported zero margins makes the
new build log `Unsupported media-ready.media-*-margin` at startup and drop all
media support. With the service stopped:

1. Back up `/var/lib/konica206/.config/konica206-native-server.state`.
2. Delete its `media-col-default` and `media-col-ready[0-9]*` lines.
3. Keep the file owned by `konica:konica` (`restorecon` it if you copy it).
4. Start the service; the driver supplies its own ready media again.

The CUPS queue's driverless PPD must also be refreshed (`lpadmin -p QUEUE -m
everywhere`) so it stops advertising `A4.Borderless`.
