#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

[[ -f .env ]] || cp .env.example .env
set -a
source .env
set +a

ref=${GG_REF:-6.30.1}
src=".cache/greengage"

mkdir -p .cache results

if [[ ! -d "$src/.git" ]]; then
  git clone --branch "$ref" --recurse-submodules \
    https://github.com/GreengageDB/greengage.git "$src"
fi

git -C "$src" checkout --detach "$ref"
git -C "$src" submodule update --init --recursive
git -C "$src" rev-parse HEAD > results/greengage-commit.txt

# Контекст передаётся Docker как tar, без распаковки на Windows.
context=$(mktemp -d "$PWD/.cache/build-context.XXXXXX")
trap 'rm -rf -- "$context"' EXIT

echo "Exporting build context as tar..."
git -C "$src" archive --format=tar HEAD > "$context/context.tar"

git -C "$src" submodule foreach --quiet --recursive \
  'printf "%s\0" "$displaypath"' > "$context/modules.list"

while IFS= read -r -d '' module; do
  git -C "$src/$module" archive \
    --format=tar \
    --prefix="$module/" \
    HEAD > "$context/submodule.tar"

  tar --concatenate \
    --file="$context/context.tar" \
    "$context/submodule.tar"
done < "$context/modules.list"

MSYS_NO_PATHCONV=1 docker build --platform linux/amd64 \
  -t "gg6-reznik-build:$ref" \
  -f ci/Dockerfile.ubuntu \
  - < "$context/context.tar"

docker build --platform linux/amd64 \
  --build-arg "BASE_IMAGE=gg6-reznik-build:$ref" \
  -t "${GG_IMAGE:-gg6-reznik:$ref}" \
  -f docker/Dockerfile .
