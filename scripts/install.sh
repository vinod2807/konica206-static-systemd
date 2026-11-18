#!/bin/sh
# Run on the target host; on bootc this touches only /etc and /var.
set -eu
here="$(cd "$(dirname "$0")/.." && pwd)"

install -D -m 0644 "$here/config/sysusers/konica206.conf" /etc/sysusers.d/konica206.conf
systemd-sysusers

install -D -m 0644 "$here/config/udev/70-konica206.rules" /etc/udev/rules.d/70-konica206.rules
udevadm control --reload && udevadm trigger

install -d -o konica -g konica -m 0755 /var/lib/konica206/bin
install -o konica -g konica -m 0755 "$here/dist/konica206-native-server" /var/lib/konica206/bin/

install -D -m 0644 "$here/config/systemd/konica206.service" /etc/systemd/system/konica206.service
systemctl daemon-reload
echo "Installed. Add vendor data (see docs/vendor-data.md), then: systemctl enable --now konica206"
