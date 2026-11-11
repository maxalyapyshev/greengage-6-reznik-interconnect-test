#!/usr/bin/env bash
# Параллельная нагрузка Greenplum Interconnect широкими строками.
# Запускать на coordinator от gpadmin после interconnect-universal-setup.sql.
# Параметры: transport clients repeats payload_repeat queue_depth
set -euo pipefail

transport=${1:-tcp}
clients=${2:-1}
repeats=${3:-2}
payload_repeat=${4:-32}
queue_depth=${5:-128}

case "$transport" in
  tcp) packet=${IC_PACKET:-65507} ;;
  udpifc) packet=${IC_PACKET:-1400} ;;
  *) echo "transport must be tcp or udpifc" >&2; exit 2 ;;
esac

[[ "$clients" =~ ^[1-9][0-9]*$ ]] && (( clients <= 64 )) || { echo "clients must be 1..64" >&2; exit 2; }
[[ "$repeats" =~ ^[1-9][0-9]*$ ]] && (( repeats <= 100 )) || { echo "repeats must be 1..100" >&2; exit 2; }
[[ "$payload_repeat" =~ ^[1-9][0-9]*$ ]] && (( payload_repeat <= 128 )) || { echo "payload_repeat must be 1..128" >&2; exit 2; }
[[ "$queue_depth" =~ ^[1-9][0-9]*$ ]] && (( queue_depth <= 1024 )) || { echo "queue_depth must be 1..1024" >&2; exit 2; }

command -v psql >/dev/null || { echo 'psql is not available in PATH' >&2; exit 2; }

# Проверяем, что маршруты существуют и все они межхостовые.
route_check=$(psql -XqAt -v ON_ERROR_STOP=1 -d adb -c "
SELECT count(*) || '|' ||
       sum(CASE WHEN s.hostname <> t.hostname THEN 1 ELSE 0 END) || '|' ||
       count(DISTINCT r.source_seg)
FROM public.interconnect_universal_routes r
JOIN gp_segment_configuration s
  ON s.content = r.source_seg AND s.role = 'p'
JOIN gp_segment_configuration t
  ON t.content = r.target_seg AND t.role = 'p';")
IFS='|' read -r route_count inter_host_count source_count <<< "$route_check"
if [[ -z "$route_count" || "$route_count" = "0" || "$route_count" != "$inter_host_count" || "$route_count" != "$source_count" ]]; then
  echo "Invalid route map: routes=$route_count inter_host=$inter_host_count sources=$source_count" >&2
  echo 'Run interconnect-universal-setup.sql and inspect the topology first.' >&2
  exit 2
fi

run_id="$(date +%Y%m%d%H%M%S)-$$"
testdir=$(mktemp -d "/tmp/adb-interconnect-universal.${run_id}.XXXXXX")
cleanup() { rm -rf "$testdir"; }
trap cleanup EXIT

export PGOPTIONS="-c gp_interconnect_type=$transport -c gp_max_packet_size=$packet"

for ((i=1; i<=clients; i++)); do
  cat > "$testdir/worker-$i.sql" <<SQL
SET application_name = 'ic_universal_${run_id}_${i}';
SET statement_timeout = '60s';
SET memory_spill_ratio = 0;
SET statement_mem = '128MB';
SET optimizer = off;
SET enable_mergejoin = off;
SET gp_interconnect_queue_depth = ${queue_depth};
SET gp_interconnect_snd_queue_depth = ${queue_depth};
\\timing on
SQL
  for ((j=1; j<=repeats; j++)); do
    cat >> "$testdir/worker-$i.sql" <<SQL
SELECT sum(octet_length(w.payload || coalesce(k.route_key::text, ''))) AS processed_bytes
FROM
(
    SELECT r.route_key,
           repeat(s.payload, ${payload_repeat}) AS payload
    FROM public.interconnect_universal_seed s
    JOIN public.interconnect_universal_routes r
      ON r.source_seg = s.gp_segment_id
    OFFSET 0
) w
FULL JOIN public.interconnect_universal_routes k
  ON k.route_key = w.route_key;
SQL
  done
done

echo "transport=$transport packet=$packet clients=$clients repeats=$repeats payload_repeat=$payload_repeat queue_depth=$queue_depth"
echo "routes=$route_count inter_host_routes=$inter_host_count"

pids=()
for ((i=1; i<=clients; i++)); do
  psql -X -qAt -v ON_ERROR_STOP=1 -d adb \
    -f "$testdir/worker-$i.sql" \
    > "$testdir/worker-$i.log" 2>&1 &
  pids+=("$!")
done

failed=0
for ((i=1; i<=clients; i++)); do
  if ! wait "${pids[$((i-1))]}"; then
    failed=1
  fi
done

for ((i=1; i<=clients; i++)); do
  echo "--- worker $i ---"
  cat "$testdir/worker-$i.log"
done

if (( failed != 0 )); then
  echo 'One or more workers failed.' >&2
  exit 1
fi

echo 'All workers completed successfully.'
