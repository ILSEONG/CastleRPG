-- 방치 주머니(2026-10-06, server/src/pouches.ts): 보유한 주머니 id("gold_60"·"res_240" …) → 개수. 열면 지금의 방치 수입 × 주머니 시간을 준다.
alter table player_state add column if not exists pouches jsonb not null default '{}'::jsonb;
