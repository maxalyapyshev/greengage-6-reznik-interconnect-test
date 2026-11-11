#!/usr/bin/env bash
set -euo pipefail
source /opt/lab/scripts/env.sh
psql -X -v ON_ERROR_STOP=1 -d adb -c 'SELECT version();'
psql -X -v ON_ERROR_STOP=1 -d adb -c 'SELECT dbid,content,role,preferred_role,mode,status,hostname,port,datadir FROM gp_segment_configuration ORDER BY content,role;'
psql -X -v ON_ERROR_STOP=1 -d adb -f /opt/lab/scripts/topology.sql
# Verify exactly one master and one standby, 8 primaries, 8 remote mirrors.
gpstate -s
gpstate -m
gpstate -f
