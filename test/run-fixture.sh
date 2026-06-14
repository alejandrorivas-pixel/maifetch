#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p build
fpc -Mdelphi -FEbuild -FUbuild src/maifetch.pas >/tmp/maifetch-fpc.log

./build/maifetch \
  --profile-fixture test/fixtures/profile.json \
  --plays-fixture test/fixtures/plays.json \
  --logo-size 0 \
  --score-count 2 > build/fixture-output.txt

perl -pe 's/\e\[[0-9;]*m//g' build/fixture-output.txt > build/fixture-output.plain.txt

grep -q "Test Player" build/fixture-output.plain.txt
grep -q "ID: 123456" build/fixture-output.plain.txt
grep -q "Rating: 123.45 / 130.00" build/fixture-output.plain.txt
grep -q "Recent Scores:" build/fixture-output.plain.txt
grep -q "Amazing Track" build/fixture-output.plain.txt
grep -q "Second Song" build/fixture-output.plain.txt

echo "fixture test passed"
