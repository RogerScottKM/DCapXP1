#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

FILE="apps/api/src/botFarm.ts"

if [ ! -f "$FILE" ]; then
  echo "Missing $FILE"
  exit 1
fi

echo "==> File header"
sed -n '1,120p' "$FILE"

echo
echo "==> RVAI / BTC symbol references"
rg -n 'RVAI-USD|BTC-USD|paper synthesizer|oracle|seed|history|candles|trade|Trade|orderbook|prisma' "$FILE" || true

echo
echo "==> First RVAI-related block"
LINE1="$(rg -n 'RVAI-USD' "$FILE" | head -n 1 | cut -d: -f1 || true)"
if [ -n "${LINE1:-}" ]; then
  START=$(( LINE1 > 40 ? LINE1 - 40 : 1 ))
  END=$(( LINE1 + 120 ))
  sed -n "${START},${END}p" "$FILE"
else
  echo "No RVAI-USD occurrence found."
fi

echo
echo "==> Paper synthesizer blocks"
while IFS=: read -r line _; do
  [ -n "${line:-}" ] || continue
  START=$(( line > 40 ? line - 40 : 1 ))
  END=$(( line + 140 ))
  echo "---- block around line $line ----"
  sed -n "${START},${END}p" "$FILE"
  echo
done < <(rg -n 'paper synthesizer|synthesizer|startBotFarm|oracle watcher|seed.*PAPER|Demo PAPER' "$FILE" || true)

echo
echo "==> Prisma trade insert / createMany / delete blocks"
while IFS=: read -r line _; do
  [ -n "${line:-}" ] || continue
  START=$(( line > 35 ? line - 35 : 1 ))
  END=$(( line + 90 ))
  echo "---- block around line $line ----"
  sed -n "${START},${END}p" "$FILE"
  echo
done < <(rg -n 'prisma\.(trade|order|market)|createMany|deleteMany|INSERT INTO "Trade"|DELETE FROM "Trade"|trade\.create|trade\.createMany' "$FILE" || true)

echo
echo "==> Tail of file"
tail -n 120 "$FILE"
