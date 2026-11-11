#!/usr/bin/env bash
set -euo pipefail
source /opt/lab/scripts/env.sh
# One lock covers preparation, plan capture, and load; prevents overlapping make tests.
exec 9>/tmp/reznik-test.lock
flock -n 9 || { echo 'Another test is running' >&2; exit 2; }
cd /opt/lab/work
psql -X -v ON_ERROR_STOP=1 -d adb -f /opt/lab/scripts/topology.sql
PGOPTIONS='-c gp_interconnect_type=udpifc -c gp_max_packet_size=8192' \
  psql -X -v ON_ERROR_STOP=1 -d adb -f interconnect-universal-setup.sql
psql -X -v ON_ERROR_STOP=1 -d adb -f route-host-check.sql
psql -X -v ON_ERROR_STOP=1 -d adb -f /opt/lab/scripts/assert-routes.sql
PGOPTIONS='-c gp_interconnect_type=udpifc -c gp_max_packet_size=8192' \
  psql -X -v ON_ERROR_STOP=1 -d adb -f /opt/lab/scripts/plan.sql
IC_PACKET=8192 bash interconnect-universal-load.sh udpifc 1 1 8 32
IC_PACKET=8192 bash interconnect-universal-load.sh udpifc 2 2 16 32
printf 'REZNIK_FUNCTIONAL_TEST_OK\n'
