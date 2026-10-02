#!/bin/bash
# Import Slurm accounting that mgmtnode appends to /xdmod/data.csv
# (scaleout/dump_xdmod.sh, hourly). Shredder skips duplicate jobs, so
# overlapping exports are safe.
set -euo pipefail

SRC=/xdmod/data.csv
DONE=/xdmod/imported
WORK=/var/lib/xdmod-lab/incoming

[ -f /var/lib/xdmod-lab/configured ] || exit 0
exec 9>/run/xdmod-ingest.lock
flock -n 9 || exit 0
[ -s "$SRC" ] || exit 0

mkdir -p "$DONE" "$WORK"
ts=$(date -u +%Y%m%dT%H%M%SZ)
mv "$SRC" "$DONE/data-$ts.csv"
install -o xdmod -g xdmod -m 0640 "$DONE/data-$ts.csv" "$WORK/data.csv"

runuser -u xdmod -- xdmod-shredder --quiet -r scaleout -f slurm -i "$WORK/data.csv"
runuser -u xdmod -- xdmod-ingestor --quiet
rm -f "$WORK/data.csv"
echo "xdmod-ingest: imported $DONE/data-$ts.csv"
