-- 소셜 로그인 진행 행(2026-10-27 보안 점검): 콜백(브라우저)의 IP. 관리자 계정은 결과를 받는 쪽(/v1/auth/oauth/poll) IP가 같아야 토큰을 준다(app.ts).
alter table oauth_logins add column if not exists callback_ip text;
-- 로그인·연동 시작이 하루 지난 진행 행을 지운다 — 그때 표 전체를 훑지 않게
create index if not exists oauth_logins_created on oauth_logins (created_at);
