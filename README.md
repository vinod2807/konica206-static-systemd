# konica206-static-systemd

Run the Konica bizhub 206 PAPPL printer application as **one static binary under a hardened systemd unit** — no rootfs, no container, no nspawn/Podman at runtime.

The build runs in a **Wolfi** container with `apk`, but Wolfi is only the build environment: the output is a statically linked binary copied to the target host.

## 1. What this is and why

This repository trades a whole Alpine guest (rootfs / container / nspawn) for a single static server binary and a restrictive systemd unit. The build happens in a throwaway container; nothing is installed on the target by the build.

Inputs are pinned, not forked or vendored:

- [`vinod2807/konica206-native-alpine`](https://github.com/vinod2807/konica206-native-alpine) — the PAPPL app
- [`vinod2807/konica-native-musl`](https://github.com/vinod2807/konica-native-musl) — the renderer
- Konica proprietary data (halftone + ICC profiles) is **never committed** — see [docs/vendor-data.md](docs/vendor-data.md)

### Wolfi-specific changes from the original Alpine plan

- **glibc, not musl.** Wolfi has no musl packages, so the result is a static **glibc** executable. The original "static musl" wording no longer applies.
- **TLS is included.** PAPPL 1.3.1 hard-requires TLS (`configure` errors out if none is found), so `--with-tls=no` is not possible. OpenSSL is linked statically from Wolfi's `.a`. DNS-SD/avahi is still disabled with `--with-dnssd=no`, and the service remains bound to `127.0.0.1` only. Do not expose port 8001 to the LAN.
- **CUPS is built from source.** Wolfi's `cups-dev` has no static `libcups.a`. The build script builds CUPS 2.4.20 with `--enable-static --disable-shared --with-dnssd=no` and applies a two-field struct fix for an upstream 2.4.20 typo in `cups/dest.c`.
- **Static NSS warnings are expected** for `getpwnam_r`/`getpwuid_r`/`getservbyname` on glibc; they are harmless for localhost-only use.

## 2. Status

The static build is verified in a clean Wolfi container: both `dist/konica206-native-server` and `dist/konica-native` are reported as statically linked with no ELF interpreter. Service and physical-print acceptance are tracked in [docs/acceptance.md](docs/acceptance.md); those boxes describe the default port-8001 install.

The live 8003 deployment has since printed A4 simplex and duplex pages through the static binary. The app now advertises the bizhub 206's real 12 pt imageable area instead of full-bleed media, so `-m everywhere` yields plain `A4`/`Letter` names and PDF content is inset before it reaches the engine. If you upgrade an older install, see the state-migration note in [docs/acceptance.md](docs/acceptance.md).

On a Fedora bootc host, `/etc` and `/var` are persistent and writable, so a live install survives `bootc upgrade`. Baking into the bootc image is optional and is a separate decision.

## 3. Build, install, vendor data

1. **Build** (in a Wolfi container):

   ```sh
   podman run --rm -v "$PWD":/work -w /work \
     cgr.dev/chainguard/wolfi-base:latest \
     sh -c 'sh scripts/build-static.sh'
   file dist/konica206-native-server     # "statically linked"
   readelf -l dist/konica206-native-server | grep -i interp  # no output
   ```

   Also copy the binary to a non-Wolfi host (e.g. Fedora) and run it there before going further.

2. **Add vendor data** — follow [docs/vendor-data.md](docs/vendor-data.md). The data is proprietary and gitignored.

3. **Install** (on the target host; on bootc this touches only `/etc` and `/var`):

   ```sh
   sudo sh scripts/install.sh
   sudo systemctl enable --now konica206
   sudo systemctl status konica206
   ```

   Warning: stop and disable any existing printer service already listening on `127.0.0.1:8001` first, otherwise `konica206.service` cannot bind.

4. **Verify** with `journalctl -u konica206 -b`, `ipptool`, `systemd-analyze security konica206`, and the physical print tests in [docs/acceptance.md](docs/acceptance.md).

To remove everything again: `sudo sh scripts/uninstall.sh`.

Configure the print queue explicitly by URI — there is no DNS-SD advertising:

```sh
lpadmin -p KONICA206 -E -v ipp://127.0.0.1:8001/ipp/print/konica206 -m everywhere
```

Confirm the actual printer path with `ipptool` before using that command.

## 4. Troubleshooting

- **USB permissions** — confirm VID/PID with `lsusb`, check `config/udev/70-konica206.rules`, then `udevadm control --reload && udevadm trigger`.
- **`/sys` access** — libusb enumerates through `/sys`. `ProtectSystem=strict` leaves it readable; if enumeration fails, check `journalctl -u konica206`.
- **seccomp** — if `SystemCallFilter=@system-service` blocks something libusb needs, loosen it in `config/systemd/konica206.service` and record why.
- **Port conflicts** — the server binds `127.0.0.1:8001` (`IPP_PORT` in `config/pins.env`). Only one printer service can own that port.
- **TLS / avahi checks** — `strings dist/konica206-native-server | grep -Ei 'gnutls_|avahi_'` must print nothing. OpenSSL strings are expected.
- **Static link errors** — archive order matters: `libpappl` before `libcups`, and `-lm` after `-lcups`. The build script handles both.
- **getaddrinfo / NSS warnings** — expected with static glibc and harmless for localhost-only use.

## 5. Relationship to other repos

- `konica206-alpine-nspawn` — the rootfs/nspawn approach this repo is an alternative to.
- `konica206-native-alpine` — the upstream PAPPL app; pinned in `config/pins.env`, never forked here.
- `konica-native-musl` — the upstream renderer; likewise pinned.
- `fedora-bootc-konica206` — the current Fedora bootc image with a working dynamic-binary printer stack; baking this static build into that image is a separate decision.

## Optional later

- Bake the binary, unit, udev rule and sysusers file into the bootc image's `Containerfile` instead of running `install.sh` on a live host.
- Make the experimental static-build workflow non-manual once the service and print tests pass.
