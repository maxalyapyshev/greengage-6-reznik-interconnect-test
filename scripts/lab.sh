#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p results work
as_admin() { docker compose exec -T --user gpadmin master bash -lc "$1"; }
case "${1:-}" in
  up)
    [[ -f .env ]] || cp .env.example .env
    mkdir -p .secrets
    [[ -f .secrets/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -f .secrets/id_ed25519
    chmod 700 .secrets; chmod 600 .secrets/id_ed25519
    python3 scripts/prepare.py
    docker compose up -d --wait
    ;;
  init) as_admin 'bash /opt/lab/scripts/init.sh' 2>&1 | tee results/init.log ;;
  start) as_admin 'source /opt/lab/scripts/env.sh; gpstart -a' ;;
  stop) as_admin 'source /opt/lab/scripts/env.sh; gpstop -a' ;;
  check) as_admin 'bash /opt/lab/scripts/check.sh' 2>&1 | tee results/check.log ;;
  test)
    python3 scripts/prepare.py
    as_admin 'bash /opt/lab/scripts/test.sh' 2>&1 | tee results/reznik-test.log
    ;;
  shell) docker compose exec --user gpadmin master bash -l ;;
  down) docker compose down ;;
  *) echo 'Usage: scripts/lab.sh up|init|start|stop|check|test|shell|down' >&2; exit 2 ;;
esac
