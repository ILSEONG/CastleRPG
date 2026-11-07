-- 파티 던전 탈주 기록(2026-11-07 사용자 "상습적으로 파티던전에서 나가버리면 그 사람은 패널티를 줘"): 다른 성주(사람)가 남아 싸우는 판을
-- 결과 없이 나간 때마다 한 줄. 24시간 안에 LEAVE_FREE번을 넘으면 매칭 제한(party.ts LEAVE_BAN_MIN).
create table if not exists party_leaves (
  player_id uuid not null references players (id) on delete cascade,
  at timestamptz not null
);
create index if not exists party_leaves_player_at on party_leaves (player_id, at);
