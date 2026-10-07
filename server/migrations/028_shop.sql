-- 상점(2026-10-07, server/src/shop.ts): 산 기록 {day, week, d: {상품 id: 오늘 산 수}, w: {상품 id: 이번 주 산 수}}. 날·주가 바뀌면 서버가 읽을 때 비운다.
alter table player_state add column if not exists shop jsonb not null default '{}'::jsonb;
