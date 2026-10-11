-- 공성 성문 체력 = 성 주인 길드 레벨 × 10,000(2026-10-11, server/src/guild_war.ts castleMax). 그 주를 열 때 우리 길드 레벨을 남긴다
-- (가상 상대 길드는 우리 레벨을 따른다). 비어 있으면(이전에 연 주) 예전 식(그 면 수비 체력 합 × 3)을 쓴다.
alter table guild_wars add column if not exists level integer;
