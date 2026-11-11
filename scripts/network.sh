#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p results
for host in sdw1 sdw2; do
  docker compose exec -T "$host" tc -s -d qdisc show dev eth0 | tee "results/tc-$host.txt"
  docker compose exec -T "$host" tc -j qdisc show dev eth0 > "results/tc-$host.json"
done
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
    if rate != 12500000000:
        raise SystemExit(f'{host}: expected 100 Gbit/s = 12500000000 B/s, got {rate!r}')
print('TC_CONFIG_OK: 100 Gbit/s egress on each segment host')
PY
docker compose exec -T --user gpadmin sdw1 ping -c 2 -M do -s 1472 sdw2 | tee results/mtu-1500.txt
docker compose exec -T --user gpadmin sdw2 iperf3 -s -D --pidfile /tmp/reznik-iperf.pid
cleanup() {
  docker compose exec -T --user gpadmin sdw2 bash -c \
    'test ! -f /tmp/reznik-iperf.pid || kill "$(cat /tmp/reznik-iperf.pid)"' >/dev/null 2>&1 || true
}
trap cleanup EXIT
sleep 1
docker compose exec -T --user gpadmin sdw1 iperf3 -c sdw2 -t 3 -P 1 -J > results/iperf-forward.json
docker compose exec -T --user gpadmin sdw1 iperf3 -c sdw2 -t 3 -P 1 -R -J > results/iperf-reverse.json
python3 - <<'PY'
import json
from pathlib import Path
out=[]
for direction in ['forward','reverse']:
    d=json.loads(Path('results/iperf-'+direction+'.json').read_text())
    if d.get('error'): raise SystemExit(d['error'])
    bps=d['end']['sum_received']['bits_per_second']
    if bps<=0: raise SystemExit('No data received')
    out.append(f'{direction}: {bps/1e9:.3f} Gbit/s measured; shaping ceiling 100 Gbit/s')
text='\n'.join(out)+'\n'
Path('results/network-summary.txt').write_text(text)
print(text,end='')
PY
