-- 2026-10-13 새 건물(창고·금광·대장간·길드 회관·망루)과 자원 건물 n번째 채.
-- building_defs.unlock_keep = 그 건물을 처음 지을 수 있는 성채 레벨(비면 0 = 처음부터). 자원 건물 몇 채인지는 config res_copy_tiers.
-- 플레이어 건물 키는 종류 또는 "종류#n"(lumber#2) — player_buildings.building은 text라 열 변경은 없다.
alter table building_defs add column if not exists unlock_keep integer;
