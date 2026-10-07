-- 결제 상품(2026-10-07, server/src/iap.ts): 다이아 충전·월정액·패키지·성장 패스. player_state.iap = 첫 구매·한도·월정액 기간·패스·성장 패스 받은 단계.
-- iap_orders = 쓴 주문 번호(같은 영수증으로 두 번 받지 않게).
alter table player_state add column if not exists iap jsonb not null default '{}'::jsonb;
create table if not exists iap_orders (order_id text primary key, player_id uuid not null references players(id) on delete cascade,
  product text not null, provider text not null, at timestamptz not null default now());
