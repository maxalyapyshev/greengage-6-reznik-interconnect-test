#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .env ]] || cp .env.example .env
set -a; source .env; set +a
ref=${GG_REF:-6.30.1}
mkdir -p .cache
if [[ ! -d .cache/greengage/.git ]]; then
  git clone --branch "$ref" --recurse-submodules https://github.com/GreengageDB/greengage.git .cache/greengage
fi
git -C .cache/greengage checkout --detach "$ref"
git -C .cache/greengage submodule update --init --recursive
mkdir -p results
git -C .cache/greengage rev-parse HEAD > results/greengage-commit.txt
docker build --platform linux/amd64 -t "gg6-reznik-build:$ref" -f .cache/greengage/ci/Dockerfile.ubuntu .cache/greengage
docker build --platform linux/amd64 --build-arg "BASE_IMAGE=gg6-reznik-build:$ref" -t "${GG_IMAGE:-gg6-reznik:$ref}" -f docker/Dockerfile .
