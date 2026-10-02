-- 개정 17 (스펙 §2): 영웅 스킬 3번째 칸(★5에서 해금, SSR·SR만). 열 = data/heroes.csv의 skill3·s3a·s3b·s3c, 비면 null.
-- 기존 행은 null로 두고 시드가 채운다(등급별 스킬 수 검증은 시드가 한다)
alter table heroes add column skill3 text, add column s3a real, add column s3b real, add column s3c real;
