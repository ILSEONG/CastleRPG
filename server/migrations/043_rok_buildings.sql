-- 2026-10-13 라오킹식 건설 개편.
-- building_defs: 레벨별 L → L+1 시간·비용 "v1|v2|…"(data/buildings.csv lv_* 열, 비면 1→2 값 × 성장 식).
-- player_state: 두 번째 일꾼(build2_id·build2_finish = 짓는 건물·끝나는 시각, builder2_until = 고용 기한)과
--   가속 아이템 보유(speedups = {id: 개수}, server/src/speedups.ts).
alter table building_defs add column if not exists lv_sec text, add column if not exists lv_wood text,
  add column if not exists lv_stone text, add column if not exists lv_food text;
alter table player_state add column if not exists build2_id text, add column if not exists build2_finish timestamptz,
  add column if not exists builder2_until timestamptz, add column if not exists speedups jsonb not null default '{}'::jsonb;
