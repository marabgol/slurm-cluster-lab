#!/bin/bash
# Runs xdmod-setup non-interactively the first time the container starts,
# using expect scripts adapted from XDMoD's own CI (tests/ci/scripts).
set -euo pipefail
. /etc/sysconfig/xdmod-lab

STATE=/var/lib/xdmod-lab
[ -f "$STATE/configured" ] && exit 0
mkdir -p "$STATE"

for i in $(seq 60); do
	mysqladmin ping >/dev/null 2>&1 && break
	sleep 2
done

cd /usr/local/share/xdmod-lab
echo "xdmod-firstboot: general settings and databases ($XDMOD_SITE_ADDRESS)"
expect setup-start.tcl "$XDMOD_SITE_ADDRESS"
echo "xdmod-firstboot: resource 'scaleout'"
expect setup-jobs.tcl
echo "xdmod-firstboot: admin user, hierarchy, export settings"
expect setup-finish.tcl

touch "$STATE/configured"
echo "xdmod-firstboot: done, importing any waiting Slurm data"
/usr/local/sbin/xdmod-ingest.sh || true
