-- 개정 10: 골드를 0.1 단위 정수(tenths)로. 이름 변경 + 기존 값 × 10.
alter table player_state rename column gold to gold_tenths;
update player_state set gold_tenths = gold_tenths * 10;
