#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4010}"
USERS="${USERS:-1000}"
PARALLEL="${PARALLEL:-12}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "Missing $1"; exit 1; }; }
need curl

# Always give quote USD as well
USD_AMT="${USD_AMT:-250000}"

# Base asset starter balances (tweak freely)
RVAI_AMT="${RVAI_AMT:-250000}"   # price ~1.09-1.13; generous for liquidity
XAU_AMT="${XAU_AMT:-200}"        # synthetic "oz" units; tune later
EUR_AMT="${EUR_AMT:-250000}"
AAPL_AMT="${AAPL_AMT:-2000}"     # synthetic "shares"; tune later

fund_one() {
  local uid="$1" asset="$2" amt="$3"
  curl -sS --fail-with-body -X POST "$API/v1/faucet" \
    -H "content-type: application/json" \
    -d "{\"userId\":${uid},\"asset\":\"${asset}\",\"amount\":\"${amt}\"}" >/dev/null
}

export -f fund_one
export API USD_AMT RVAI_AMT XAU_AMT EUR_AMT AAPL_AMT

echo "Funding ${USERS} users on USD + RVAI + XAU + EUR + AAPL via $API/v1/faucet ..."

seq 1 "$USERS" | xargs -P "$PARALLEL" -I{} bash -lc '
  uid="{}"
  fund_one "$uid" "USD"  "$USD_AMT"
  fund_one "$uid" "RVAI" "$RVAI_AMT"
  fund_one "$uid" "XAU"  "$XAU_AMT"
  fund_one "$uid" "EUR"  "$EUR_AMT"
  fund_one "$uid" "AAPL" "$AAPL_AMT"
'

echo "✅ Funding complete"
