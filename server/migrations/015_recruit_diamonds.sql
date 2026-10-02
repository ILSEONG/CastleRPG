-- 개정 23 (스펙 §3): 다이아(서버 권위 현금 재화)와 모집 상태 — 골드 모집 레벨·그 레벨 안 누적, 다이아 천장 카운터(SSR 없이 뽑은 수).
alter table player_state add column diamonds bigint not null default 0 check (diamonds >= 0);
alter table player_state add column gacha_gold_level integer not null default 1 check (gacha_gold_level >= 1);
alter table player_state add column gacha_gold_pulls integer not null default 0 check (gacha_gold_pulls >= 0);
alter table player_state add column gacha_dia_pity integer not null default 0 check (gacha_dia_pity >= 0);
-- 골드 고정 비용·확률이 골드 레벨·다이아 설정으로 바뀐다(시드 전 DB도 돌도록 기본값만 넣는다)
insert into game_config (key, value) values ('gacha_gold_cost_base', '3000'), ('gacha_gold_cost_growth', '1.15'), ('gacha_gold_level_max', '10'),
  ('gacha_gold_level_pulls', '30'), ('gacha_gold_ssr_base', '0.03'), ('gacha_gold_ssr_step', '0.004'), ('gacha_gold_sr_base', '0.17'),
  ('gacha_gold_sr_step', '0.01'), ('gacha_dia_cost_1', '300'), ('gacha_dia_cost_10', '2700'), ('gacha_dia_ssr', '0.08'), ('gacha_dia_sr', '0.30'),
  ('gacha_dia_pity', '50')
  on conflict (key) do nothing;
delete from game_config where key in ('gacha_cost_1', 'gacha_cost_10', 'gacha_rate_ssr', 'gacha_rate_sr');
