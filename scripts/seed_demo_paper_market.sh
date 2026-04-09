#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose exec -T pg psql -U dcapx -d dcapx <<'SQL'
DO $$
DECLARE
  uid text;
  btc_buy bigint;
  btc_sell bigint;
  rvai_buy bigint;
  rvai_sell bigint;
  t_buy bigint;
  t_sell bigint;
BEGIN
  SELECT id INTO uid
  FROM "User"
  WHERE email = 'pedro.vx.km@gmail.com';

  IF uid IS NULL THEN
    RAISE EXCEPTION 'User pedro.vx.km@gmail.com not found';
  END IF;

  -- clean recent demo paper rows for these symbols
  DELETE FROM "Trade"
  WHERE symbol IN ('BTC-USD', 'RVAI-USD')
    AND mode = 'PAPER'::"TradeMode"
    AND "createdAt" > now() - interval '7 days';

  DELETE FROM "Order"
  WHERE symbol IN ('BTC-USD', 'RVAI-USD')
    AND mode = 'PAPER'::"TradeMode"
    AND "createdAt" > now() - interval '7 days';

  -- balances for Pedro so positions panel has something to show
  INSERT INTO "Balance" ("userId","asset","amount","mode")
  VALUES
    (uid, 'USD',  '250000', 'PAPER'::"TradeMode"),
    (uid, 'BTC',  '1.2500', 'PAPER'::"TradeMode"),
    (uid, 'RVAI', '50000',  'PAPER'::"TradeMode")
  ON CONFLICT ("userId","mode","asset")
  DO UPDATE SET amount = EXCLUDED.amount;

  -- open orders for BTC-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','BUY'::"OrderSide",70850.00,0.20000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '3 minutes');

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','SELL'::"OrderSide",70950.00,0.18000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '2 minutes');

  -- open orders for RVAI-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','BUY'::"OrderSide",1.12000000,8000.00000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '3 minutes');

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','SELL'::"OrderSide",1.18000000,7500.00000000,'OPEN'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '2 minutes');

  -- trade 1: BTC-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','BUY'::"OrderSide",70910.00,0.05000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '15 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','SELL'::"OrderSide",70910.00,0.05000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '15 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('BTC-USD',70910.00,0.05000000,now() - interval '15 minutes','PAPER'::"TradeMode",t_buy,t_sell);

  -- trade 2: BTC-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','BUY'::"OrderSide",70883.19,0.04000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '6 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('BTC-USD','SELL'::"OrderSide",70883.19,0.04000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '6 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('BTC-USD',70883.19,0.04000000,now() - interval '6 minutes','PAPER'::"TradeMode",t_buy,t_sell);

  -- trade 1: RVAI-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','BUY'::"OrderSide",1.14000000,1200.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '12 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','SELL'::"OrderSide",1.14000000,1200.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '12 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('RVAI-USD',1.14000000,1200.00000000,now() - interval '12 minutes','PAPER'::"TradeMode",t_buy,t_sell);

  -- trade 2: RVAI-USD
  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','BUY'::"OrderSide",1.16000000,900.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '4 minutes')
  RETURNING id INTO t_buy;

  INSERT INTO "Order" ("symbol","side","price","qty","status","mode","userId","createdAt")
  VALUES ('RVAI-USD','SELL'::"OrderSide",1.16000000,900.00000000,'FILLED'::"OrderStatus",'PAPER'::"TradeMode",uid, now() - interval '4 minutes')
  RETURNING id INTO t_sell;

  INSERT INTO "Trade" ("symbol","price","qty","createdAt","mode","buyOrderId","sellOrderId")
  VALUES ('RVAI-USD',1.16000000,900.00000000,now() - interval '4 minutes','PAPER'::"TradeMode",t_buy,t_sell);

END $$;
SQL

echo "✅ Demo PAPER market seeded for BTC-USD and RVAI-USD"
