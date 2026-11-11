#!/usr/bin/env python3
# WINDOWS_GIT_BASH_FIX
import os
import sys

from pathlib import Path
import subprocess, hashlib, json, ast
root=Path(__file__).resolve().parent.parent
subprocess.run([sys.executable,str(root/'scripts/prepare.py')],check=True)
manifest=json.loads((root/'original/SHA256.json').read_text())
for name,expected in manifest.items():
    assert hashlib.sha256((root/'original'/name).read_bytes()).hexdigest()==expected,name
for folder in ['scripts','docker','work']:
    for p in (root/folder).glob('*.sh'):
        subprocess.run([os.environ["BASH_EXE"], "-n", p.as_posix()],check=True)
for p in (root/'scripts').glob('*.py'):
    ast.parse(p.read_text())
assert 'count()' not in (root/'work/interconnect-universal-setup.sql').read_text()
assert '\u00a0' not in (root/'work/interconnect-universal-load.sh').read_text()
print('STATIC_CHECKS_OK: checksums, shell syntax, Python syntax, generated fixes')
print('This does not execute Docker, SQL, interconnect, standby or failover tests.')
