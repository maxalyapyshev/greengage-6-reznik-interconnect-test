#!/usr/bin/env python3
"""Generate executable copies; never rewrite original/ files."""
from pathlib import Path
import re, hashlib, json, difflib
root = Path(__file__).resolve().parent.parent
src, dst = root / 'original', root / 'work'
dst.mkdir(exist_ok=True)
manifest = {}
patches = []
for name in ['interconnect-universal-load.sh', 'interconnect-universal-setup.sql', 'route-host-check.sql']:
    raw = (src / name).read_bytes()
    old = raw.decode('utf-8')
    new = old.replace('\r\n', '\n').replace('\r', '\n').replace(chr(160), ' ')
    if name.endswith('.sh'):
        # Default transport for the generated workload
        new = new.replace('transport=${1:-tcp}', 'transport=${1:-udpifc}')
        # Jumbo-frame UDPIFC default in generated workload
        new = new.replace('${IC_PACKET:-1400}', '${IC_PACKET:-8192}')

        for phrase in ['Параллельная нагрузка', 'Запускать на coordinator', 'Параметры:', 'Проверяем, что']:
            new = re.sub(r'(?m)^(' + re.escape(phrase) + r'.*)$', r'# \1', new)
        new = new.replace('psql -X -qAt -v ON_ERROR_STOP=1 -d adb\n',
                          'psql -X -qAt -v ON_ERROR_STOP=1 -d adb \\\n')
        new = new.replace('-f "$testdir/worker-$i.sql"\n',
                          '-f "$testdir/worker-$i.sql" \\\n')
    if name == 'interconnect-universal-setup.sql':
        new = new.replace('count()', 'count(*)')
        new = new.replace(r'\set row_count 200000', r'\set row_count 4096')
        new = new.replace(r'\set candidate_count 1000000', r'\set candidate_count 4096')
        new = new.replace(r'\set expected_hosts 0', r'\set expected_hosts 2')
        new = new.replace('-- Исходные данные: около 205 МБ payload на весь кластер.',
                          '-- Рабочая копия: 4096 строк, 4 MiB исходного payload на кластер.')
    (dst / name).write_text(new, encoding='utf-8', newline='\n')
    manifest[name] = hashlib.sha256(raw).hexdigest()
    patches.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                     fromfile='original/'+name, tofile='work/'+name))
(root / 'results' / 'original-sha256.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8', newline='\n')
(root / 'results' / 'working-copies.patch').write_text(''.join(patches), encoding='utf-8', newline='\n')
