-- 개정 17 (스펙 §2): 영웅 스킬 3번째 칸(★5에서 해금, SSR·SR만). 열 = data/heroes.csv의 skill3·s3a·s3b·s3c, 비면 null.
-- 기존 행은 null로 두고 시드가 채운다(등급별 스킬 수 검증은 시드가 한다)
alter table heroes add column skill3 text, add column s3a real, add column s3b real, add column s3c real;
-- 시드 전 DB에서도 앱이 받도록 해금 설정 기본값만 넣는다(이미 있으면 그대로)
insert into game_config (key, value) values ('skill2_unlock_star', '3'), ('skill3_unlock_star', '5') on conflict (key) do nothing;
