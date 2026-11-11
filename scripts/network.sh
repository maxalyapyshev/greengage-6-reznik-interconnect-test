#!/usr/bin/env bash
# Preserve container paths when running Docker from Git Bash.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'

set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p results
for host in sdw1 sdw2; do
  docker compose exec -T "$host" tc -s -d qdisc show dev eth0 | tee "results/tc-$host.txt" > /dev/null
  docker compose exec -T "$host" tc -j qdisc show dev eth0 > "results/tc-$host.json"
done
printf '\nTCP-тесты: 3 секунды, 1 поток на направление\n\nПоследовательные тесты:\n'
python3 - <<'PY'
import json
from pathlib import Path
for host in ['sdw1','sdw2']:
    data=json.loads(Path('results/tc-'+host+'.json').read_text())
    roots=[q for q in data if q.get('kind')=='tbf' and q.get('root')]
    if len(roots)!=1:
        raise SystemExit('TBF root missing on '+host)
    # iproute2 tc JSON represents rate as bytes per second.
    rate=roots[0].get('options',{}).get('rate')
    if rate != 25000000000:
        raise SystemExit(f'{host}: expected 200 Gbit/s = 25000000000 B/s, got {rate!r}')
# TBF configuration validated.
PY
docker compose exec -T --user gpadmin sdw1 ping -4 -c 2 -M do -s 8972 sdw2 | tee results/mtu-9000.txt > /dev/null
docker compose exec -T --user gpadmin sdw2 ping -4 -c 2 -M do -s 8972 sdw1 | tee results/mtu-9000-reverse.txt > /dev/null
# Separate port; Docker manages background execution, not iperf3 -D.
run_id="reznik-iperf-$$"
pidfile="/tmp/$run_id.pid"
logfile="/tmp/$run_id.log"

cleanup() {
  docker compose exec -T --user gpadmin sdw2 bash -c '
    if [ -f "$1" ]; then
      pid=$(cat "$1")
      kill "$pid" 2>/dev/null || true
      rm -f "$1"
    fi
  ' bash "$pidfile" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker compose exec -T -d --user gpadmin sdw2 bash -c '
  echo $$ > "$1"
  exec iperf3 -s -p 5202 --forceflush > "$2" 2>&1
' bash "$pidfile" "$logfile"

ready=0
for attempt in {1..30}; do
  if docker compose exec -T --user gpadmin sdw2 \
      grep -q 'Server listening on 5202' "$logfile"; then
    ready=1
    break
  fi
  sleep 0.2
done

if [ "$ready" -ne 1 ]; then
  docker compose exec -T --user gpadmin sdw2 cat "$logfile" >&2
  echo "iperf3 server failed to become ready" >&2
  exit 1
fi

for direction in forward reverse; do
  extra=()
  if [ "$direction" = reverse ]; then extra=(-R); fi
  if ! docker compose exec -T --user gpadmin sdw1 \
      iperf3 -c sdw2 -p 5202 -t 3 -P 1 -J "${extra[@]}" \
      > "results/iperf-$direction.json" \
      2> "results/iperf-$direction.stderr"; then
    cat "results/iperf-$direction.stderr" >&2
    docker compose exec -T --user gpadmin sdw2 cat "$logfile" >&2
    exit 1
  fi
done

# Simultaneous bidirectional TCP test.
# Bidirectional test; report is printed below.
if ! docker compose exec -T --user gpadmin sdw1 \
    iperf3 -c sdw2 -p 5202 -t 3 -P 1 --bidir -J \
    > results/iperf-bidir.json \
    2> results/iperf-bidir.stderr; then
  cat results/iperf-bidir.stderr >&2
  cat results/iperf-bidir.json >&2
  docker compose exec -T --user gpadmin sdw2 cat "$logfile" >&2
  exit 1
fi

python -c '
import json
from pathlib import Path

data = json.loads(Path("results/iperf-bidir.json").read_text(encoding="utf-8"))
if data.get("error"):
    raise SystemExit("iperf3 bidir: " + data["error"])
end = data.get("end", {})
if not end:
    raise SystemExit("iperf3 bidir: missing end results")
summary = json.dumps(end, ensure_ascii=False, indent=2)
Path("results/iperf-bidir-summary.json").write_text(summary + "\n", encoding="utf-8")
# Full summary is saved to results/iperf-bidir-summary.json
# No verbose JSON on stdout
'

docker compose exec -T --user gpadmin sdw2 cat "$logfile" \
  > results/iperf-server.log
python3 - <<'PY'
import json
from pathlib import Path
out=[]
for direction in ['forward','reverse']:
    d=json.loads(Path('results/iperf-'+direction+'.json').read_text())
    if d.get('error'): raise SystemExit(d['error'])
    bps=d['end']['sum_received']['bits_per_second']
    if bps<=0: raise SystemExit('No data received')
    out.append(f'{direction}: {bps/1e9:.3f} Gbit/s measured; shaping ceiling 200 Gbit/s')
text='\n'.join(out)+'\n'
Path('results/network-summary.txt').write_text(text)
print(text,end='')
PY

printf '\nОдновременный двунаправленный тест:\n'
# Report simultaneous bidirectional receiver rates.
python -c '
import json
from pathlib import Path

data = json.loads(Path("results/iperf-bidir.json").read_text(encoding="utf-8"))
if data.get("error"):
    raise SystemExit(data["error"])

rates = {True: 0.0, False: 0.0}
seen = set()
for stream in data["end"]["streams"]:
    receiver = stream["receiver"]
    direction = receiver["sender"]
    if not isinstance(direction, bool):
        raise SystemExit("Invalid sender flag in bidir JSON")
    rates[direction] += receiver["bits_per_second"] / 1e9
    seen.add(direction)

if seen != {True, False}:
    raise SystemExit("Missing one direction in bidir JSON")

lines = [
    "bidir forward: %.3f Gbit/s receiver (sdw1 -> sdw2)" % rates[True],
    "bidir reverse: %.3f Gbit/s receiver (sdw2 -> sdw1)" % rates[False],
]
summary = Path("results/network-summary.txt")
previous = summary.read_text(encoding="utf-8") if summary.exists() else ""
previous = "\n".join(
    line for line in previous.splitlines()
    if not line.startswith(("bidir forward:", "bidir reverse:"))
)
summary.write_text(
    (previous.rstrip() + "\n" if previous.strip() else "")
    + "\n".join(lines) + "\n",
    encoding="utf-8",
)
print("\n".join(lines))
'
