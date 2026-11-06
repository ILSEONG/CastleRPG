-- 길드 문양 편집(2026-11-05, 사용자 "길드 문양은 길드장이 만들 수 있게해, 배경 모양 + 가운데 문양 + 배경 색 + 가운데 문양 색 조합으로"):
-- emblem 값이 0..7(예전 문장)에서 0..19207(8 + 모양 8 × 문양 20 × 배경색 12 × 문양색 10)로 넓어진다. 이미 있는 값은 그대로 예전 모양으로 보인다.
alter table guilds drop constraint if exists guilds_emblem_check;
alter table guilds add constraint guilds_emblem_check check (emblem between 0 and 19207);
