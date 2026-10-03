-- 오프라인 처치 골드: 마지막 활동 시각(플레이어 상태를 바꾼 마지막 요청의 서버 시각 — commit이 늘 쓴다). null = 아직 없음(첫 정산은 0).
-- POST /v1/offline이 지난 활동부터 지금까지(accum_cap_min 상한)를 방치 처치로 쳐 골드 × offline_gold_mult를 준다.
alter table player_state add column last_active timestamptz;
insert into game_config (key, value) values ('offline_gold_mult', '0.4') on conflict (key) do nothing;
