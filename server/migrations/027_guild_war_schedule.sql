-- 길드전 주 1회(2026-10-06): 그 주 공성 시각을 길드원이 정한다. battle_at = 정한 시각(null = 기본 토요일 21:00), battle_by = 정한 길드원 이름.
alter table guild_wars add column battle_at timestamptz, add column battle_by text;
