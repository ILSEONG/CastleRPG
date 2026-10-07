-- 거래소(2026-10-07, server/src/market.ts): 플레이어가 자기 장비를 골드·다이아로 올리고 다른 플레이어가 산다. 정산 수수료 10%.
-- 올린 장비는 player_items 행 그대로 판매자에게 남고(능력치·형식이 장비 표와 늘 같다), 판매 중(status active, 기한 전)인 동안은
-- 플레이어 읽기에서 빠진다(보관함·장착·판매 대상 아님). 기한이 지나면 저절로 보관함에 다시 보인다. 팔리면 행의 player_id가 구매자로 바뀐다.
-- status: active(판매 중) → sold(팔림, 판매자가 대금 수령 전) → collected, 또는 cancelled(판매자가 내림), expired(기한 지남, 다음 거래소 요청이 표시).
-- item = 올릴 때의 장비 사본(지난 기록 표시용 — 판매 중 장비는 player_items에서 읽는다). item_id는 외래 키가 아니다(산 사람이 그 장비를 팔아도 기록은 남는다).
create table if not exists market_listings (id bigserial primary key, seller_id uuid not null references players(id) on delete cascade,
  item_id bigint not null, item jsonb not null, currency text not null check (currency in ('gold', 'diamonds')),
  price bigint not null check (price > 0), proceeds bigint not null check (proceeds >= 0 and proceeds <= price),
  status text not null default 'active' check (status in ('active', 'sold', 'collected', 'cancelled', 'expired')),
  buyer_id uuid references players(id) on delete set null, created_at timestamptz not null, expires_at timestamptz not null, sold_at timestamptz);
create unique index if not exists market_listings_active_item on market_listings (item_id) where status = 'active';
create index if not exists market_listings_browse on market_listings (currency, price) where status = 'active';
create index if not exists market_listings_seller on market_listings (seller_id, status);
create index if not exists market_listings_expiry on market_listings (expires_at) where status = 'active'
