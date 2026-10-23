-- 이탈 기록(2026-10-23): 플레이어가 접속한 날(KST 날짜 = floor((유닉스 초 + 9시간) / 86400)). 하루에 한 행, 인증된 첫 요청이 넣는다(retention.ts).
-- 하루 뒤(D1)·일주일 뒤(D7) 복귀율과 오늘·7일 접속 수를 여기서 센다. 가이드 이탈 단계는 player_state.tut_step으로 본다.
create table if not exists player_days (player_id uuid not null references players(id) on delete cascade, day integer not null,
  primary key (player_id, day));
create index if not exists player_days_day on player_days (day);
-- 지금까지 남은 흔적(가입일·마지막 접속일)으로 채운다 — 그 사이 날은 모른다.
insert into player_days (player_id, day) select id, floor((extract(epoch from created_at) + 32400) / 86400)::int from players on conflict do nothing;
insert into player_days (player_id, day) select id, floor((extract(epoch from last_seen) + 32400) / 86400)::int from players on conflict do nothing;
