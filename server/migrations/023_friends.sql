-- 친구(2026-10-06, 모집권 던전 도우미): 친구 코드(플레이어 id 앞 8자리)로 신청 → 상대가 수락하면 친구. 친구 한 쌍은 한 행(a = 신청한 쪽).
-- friend_hero = 친구에게 빌려주는 대표 영웅(null이면 가장 강한 영웅). 모집권 던전 도우미 후보는 친구들의 대표 영웅이다(없으면 시스템 후보 3).
alter table players add column friend_code text generated always as (upper(substr(replace(id::text, '-', ''), 1, 8))) stored;
create unique index players_friend_code on players (friend_code);
alter table players add column friend_hero text;
create table friend_links (a uuid not null references players(id) on delete cascade, b uuid not null references players(id) on delete cascade,
  accepted boolean not null default false, created_at timestamptz not null default now(), primary key (a, b), check (a <> b));
create unique index friend_links_pair on friend_links (least(a, b), greatest(a, b));
create index friend_links_b on friend_links (b);
