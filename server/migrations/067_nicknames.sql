-- 닉네임 변경(사용자 2026-11-05 "설정에서 닉네임 변경, 무료 1번, 이후 다이아 소모"). 비어 있으면 id에서 정해지는 별명(guild.ts playerName).
-- 같은 닉네임은 하나만(대소문자 무시). nickname_changes = 지금까지 바꾼 횟수(0이면 다음 변경은 무료).
alter table players add column if not exists nickname text;
alter table players add column if not exists nickname_changes integer not null default 0;
create unique index if not exists players_nickname_lower on players (lower(nickname)) where nickname is not null;
