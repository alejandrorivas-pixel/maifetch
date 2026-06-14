#!/usr/bin/env bash
set -euo pipefail

mkdir -p build
crystal build src/maifetch.cr -o build/maifetch

output="$(
  ./build/maifetch \
    --profiles-fixture test/fixtures/profile.json \
    --plays-fixture test/fixtures/plays.json \
    --logo-size 0 \
    --score-count 2 \
    --no-color
)"

printf '%s\n' "$output"

grep -q 'MaiTea' <<< "$output"
grep -q 'ID: 42' <<< "$output"
grep -q 'Rating: 123.45 / 130.01' <<< "$output"
grep -q 'Latent Kingdom' <<< "$output"
grep -q 'Citrus City' <<< "$output"
grep -q 'SSS+' <<< "$output"
