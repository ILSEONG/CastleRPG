-- 슈퍼관리자(사용자 2026-10-07): 이은 Google 계정의 확인된 이메일(로그인할 때마다 적는다, 소문자)이 admin_emails에 있으면 관리자.
-- 관리자는 앱의 기능 잠금이 모두 열린다. 목록은 저장소에 두지 않고 DB에만 넣는다.
alter table player_identities add column if not exists email text;
create table if not exists admin_emails (email text primary key);
