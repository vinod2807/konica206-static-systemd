# Proprietary vendor data (never commit this)

The renderer needs Konica's 600 dpi halftone and two ICC profiles. They are
proprietary: keep them out of this repository. `.gitignore` already excludes
`*.hft`, `*.icm`, `*.icc` and `vendor-data/`.

Obtain the files from a legally licensed Konica driver. For reference, the
upstream app repo contains a `vendor/KonicaMinolta/245igdi/` tree with these
names; do not copy them from a source you are not licensed to use.

Required files:

- `Halftones/COPA.DEFAULT.600x600.hft`
- `Profiles/sRGB.icm`
- `Profiles/sGrayInv.icm`

Install them under the state directory, owned by `konica:konica`, for example:

```sh
install -d -o konica -g konica -m 0755 /var/lib/konica206/vendor-data/Halftones
install -d -o konica -g konica -m 0755 /var/lib/konica206/vendor-data/Profiles
install -o konica -g konica -m 0644 COPA.DEFAULT.600x600.hft \
  /var/lib/konica206/vendor-data/Halftones/
install -o konica -g konica -m 0644 sRGB.icm sGrayInv.icm \
  /var/lib/konica206/vendor-data/Profiles/
chown -R konica:konica /var/lib/konica206
```

Confirm the exact paths against the upstream app's documentation before
printing. The renderer filter built by `scripts/build-static.sh` is a separate
static helper; place it where the app expects its filter, also owned by
`konica:konica`.
