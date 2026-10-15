-- 게임 문구 다국어 표(2026-10-14 사용자 "모든 메시지 라벨을 다국어로 관리해줘, DB에 다국어 테이블을 만들고 일단 한국어만 값 채워줘").
-- key = 문구 키(앱 Lang.t·서버 txt), 언어별 칸(ko 필수, 나머지는 비면 ko로 보인다), note = 쓰는 곳.
-- 시드(neon:seed)가 data/texts.csv + 기획 표 이름(data.<표>.<id>.<칸>)으로 채운다 — 다른 기획 표처럼 CSV에 없는 키는 지운다.
-- 앱은 GET /v1/texts?lang=ko 로 받는다(server/src/texts.ts, docs/TEXTS.md).
create table if not exists texts (key text primary key, ko text not null, en text, ja text, zh text, note text);
