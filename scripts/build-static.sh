#!/bin/sh
# Static-link build on Wolfi (glibc). Run inside a Wolfi container.
# Produces dist/konica206-native-server and dist/konica-native.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/config/pins.env"

apk add --no-cache \
  build-base git pkgconf linux-headers coreutils file \
  libusb-dev \
  zlib-dev zlib-static \
  libpng-dev libpng-static \
  libjpeg-turbo-dev libjpeg-turbo-static \
  cups-dev openssl-dev brotli-static

mkdir -p "$repo/build" "$repo/dist"
cd "$repo/build"
cups_prefix="$repo/cups-static"
pappl_prefix="$repo/pappl-static"

# CUPS: Wolfi ships no static libcups, so build it from source.
git clone --branch "$CUPS_VERSION" --depth 1 https://github.com/OpenPrinting/cups.git cups
(
  cd cups
  # Upstream 2.4.20 typo: _cups_getdata_t lacks two fields that dest.c uses
  # (they exist in _cups_dnssd_data_t). Add them before compiling.
  awk '
    /^typedef struct _cups_getdata_s/ { in_getdata = 1 }
    in_getdata && /cups_dest_t[[:space:]]*\*dests;/ {
      print
      print "  int\t\tnum_local;\t\t/* Number of local cupsd queues */"
      print "  cups_dest_t\t*local_dests;\t\t/* Local cupsd queues */"
      in_getdata = 0
      next
    }
    { print }
  ' cups/dest.c > dest.c.new && mv dest.c.new cups/dest.c

  ./configure --prefix="$cups_prefix" \
    --disable-shared --enable-static \
    --with-tls=openssl --with-dnssd=no
  make -j"$(nproc)"
  make install
)

# PAPPL: DNS-SD disabled. TLS is mandatory in PAPPL 1.3.1, so it is linked
# statically from Wolfi's OpenSSL .a. Never install avahi-dev here.
git clone --branch "$PAPPL_VERSION" --depth 1 https://github.com/michaelrsweet/pappl.git pappl
(
  cd pappl
  PKG_CONFIG_PATH="$cups_prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
    ./configure --prefix="$pappl_prefix" \
      --disable-shared --enable-static \
      --with-tls=openssl --with-dnssd=no
  # Static archive order: -lm must come after -lcups in PAPPL's own test links.
  sed -i "/^LIBS[[:space:]]*=/ s/$/ -lm/" Makedefs
  make -j"$(nproc)"
  make install
)

# Renderer (pure libc; -ffp-contract=off keeps output bit-exact).
git clone "$RENDERER_REPO" renderer
git -C renderer checkout "$RENDERER_REV"
make -C renderer CFLAGS="-O2 -std=c11 -ffp-contract=off -D_POSIX_C_SOURCE=200809L -static"

# App: its Makefile ignores LDFLAGS, so pass a complete static library list.
# Static archives are order-sensitive: libpappl before libcups.
git clone "$APP_REPO" app
git -C app checkout "$APP_REV"
make -C app \
  CC="gcc -static" \
  PAPPL_CFLAGS="-I$pappl_prefix/include -D_REENTRANT" \
  PAPPL_LIBS="-L$pappl_prefix/lib -lpappl -L$cups_prefix/lib64 -lcups -lusb-1.0 -lpng16 -ljpeg -lssl -lcrypto -l:libbrotlienc-static.a -l:libbrotlidec-static.a -l:libbrotlicommon-static.a -lz -lm -lpthread -ldl" \
  USB_CFLAGS="-I/usr/include/libusb-1.0" \
  USB_LIBS="-lusb-1.0" \
  -j"$(nproc)" konica206-native

cp app/konica206-native "$repo/dist/konica206-native-server"
cp renderer/konica-native "$repo/dist/konica-native"

file "$repo/dist/konica206-native-server" "$repo/dist/konica-native"
readelf -l "$repo/dist/konica206-native-server" | grep -qi interp && {
  echo "ERROR: server is not statically linked" >&2; exit 1
} || echo "server: no INTERP, statically linked"
strings "$repo/dist/konica206-native-server" | grep -Ei 'gnutls_|avahi_' || echo "no gnutls/avahi symbols (good)"
strings "$repo/dist/konica206-native-server" | grep -qi openssl && echo "OpenSSL statically linked (expected; PAPPL requires TLS)"
echo "getpwuid/getservbyname static NSS warnings during link are expected on glibc"
