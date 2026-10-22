#!/bin/sh
# Installs the vpn helper for sing-box system-wide. Needs the sing-box package.
set -e
cd "$(dirname "$0")"
command -v sing-box >/dev/null || { echo "install sing-box first" >&2; exit 1; }
sudo visudo -cqf sudoers
sudo install -Dm755 vpn /usr/local/bin/vpn
sudo install -Dm644 vpn-update.service /etc/systemd/system/vpn-update.service
sudo install -Dm644 vpn-update.timer /etc/systemd/system/vpn-update.timer
sudo install -Dm644 50-sing-box.rules /etc/polkit-1/rules.d/50-sing-box.rules
sudo install -Dm440 sudoers /etc/sudoers.d/vpn
sudo install -d -o sing-box -g sing-box /var/lib/sing-box
sudo systemctl daemon-reload
sudo systemctl enable --now vpn-update.timer
echo "done, now add a subscription: vpn sub add URL"
