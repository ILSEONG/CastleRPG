-- 환불 회수·채팅 금지(2026-11-06 사용자 "구글 결제를 환불받아도 지급한 다이아가 회수해야지", "신고가 효과가 없고 채팅 금지 기능을 할 수 있는 관리자 페이지").
-- dia_debt = 환불로 회수하지 못한 다이아(그때 가진 다이아보다 많이 회수해야 할 때). 앞으로 얻는 다이아에서 먼저 갚는다(app.ts commit).
alter table player_state add column if not exists dia_debt bigint not null default 0 check (dia_debt >= 0);
-- 환불된 주문: 회수한 시각과 회수 내용(우편 회수·다이아·모집권 등).
alter table iap_orders add column if not exists refunded_at timestamptz;
alter table iap_orders add column if not exists clawback jsonb;
create index if not exists iap_orders_refunded on iap_orders (refunded_at desc) where refunded_at is not null;
-- 채팅 금지: until이 없으면 영구. 관리자 [운영 관리 → 신고]에서 걸고 푼다.
create table if not exists chat_mutes (player_id uuid primary key references players(id) on delete cascade,
  until timestamptz, reason text not null default '', at timestamptz not null default now());
