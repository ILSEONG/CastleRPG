-- 앱 없이 계정 삭제 요청(2026-10-14, /legal/account-deletion 양식 → inquiry.ts): 문의 표에 category 'delete'로 쌓는다.
-- 친구 코드·Google 이메일로 계정을 찾지 못한 요청도 남겨야 해서(관리자가 확인) player_id를 비울 수 있게 한다.
-- 관리자가 [계정 삭제]로 지우면 그 요청 행은 player_id를 비우고 종료로 남는다(삭제 처리 기록).
alter table inquiries alter column player_id drop not null;
