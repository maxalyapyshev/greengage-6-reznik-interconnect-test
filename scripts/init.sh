#!/usr/bin/env bash
set -euo pipefail
source /opt/lab/scripts/env.sh
if [[ -f "$MASTER_DATA_DIRECTORY/PG_VERSION" ]]; then
  echo 'Cluster exists. Use make start; initialization refused.' >&2
  exit 2
fi
for host in master standby sdw1 sdw2; do
  for attempt in {1..30}; do
    if ssh "$host" true; then break; fi
    sleep 2
  done
  ssh "$host" true
  ssh "$host" 'mkdir -p /data/master /data/primary /data/mirror'
done
printf 'sdw1\nsdw2\n' > /tmp/segment-hosts
cat > /tmp/gpinitsystem.conf <<'EOF'
ARRAY_NAME="Greengage 6 Reznik local lab"
SEG_PREFIX=gg
PORT_BASE=6000
declare -a DATA_DIRECTORY=(/data/primary /data/primary /data/primary /data/primary)
MASTER_HOSTNAME=master
MASTER_DIRECTORY=/data/master
MASTER_PORT=5432
TRUSTED_SHELL=ssh
CHECK_POINT_SEGMENTS=8
ENCODING=UNICODE
DATABASE_NAME=adb
MIRROR_PORT_BASE=7000
declare -a MIRROR_DATA_DIRECTORY=(/data/mirror /data/mirror /data/mirror /data/mirror)
EOF
gpinitsystem -a -c /tmp/gpinitsystem.conf -h /tmp/segment-hosts -s standby
# Low-memory lab settings; preserve statement_mem=128MB in supplied workload.
gpconfig -c shared_buffers -v 32MB -m 64MB
gpconfig -c max_connections -v 30 -m 20
gpconfig -c gp_vmem_protect_limit -v 384
gpconfig -c statement_mem -v 32MB
gpconfig -c gp_interconnect_type -v udpifc
gpconfig -c gp_max_packet_size -v 1400
gpstop -a -r
bash /opt/lab/scripts/check.sh
