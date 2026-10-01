-- 개정 9 리뷰 수정(스펙 §3): 처치 보고 멱등 번호, 스테이지 클리어 최소 간격용 시각, 처치 버킷 길이 기본값.
alter table player_state add column kill_seq integer not null default 0;
alter table player_state add column last_stage_clear timestamptz not null default now();
-- 시드 전 DB에서도 /v1/kills가 돌도록 기본값만 넣는다(이미 있으면 그대로).
insert into game_config (key, value) values ('kill_burst_sec', '60') on conflict (key) do nothing;
