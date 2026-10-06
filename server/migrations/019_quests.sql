-- 튜토리얼·반복 퀘스트(온라인). quest_defs 열 = data/quests.csv(type = tutorial | repeat, needs = 서버가 볼 수 있는 완료 조건
-- "build:<건물>" | "level:<건물>:<Lv>" | 빈칸, reward·fixed = "키:수|…"), ord = 파일 순서(seed가 넣는다).
create table quest_defs (id text not null, type text not null, needs text, reward text, fixed text, ord integer not null default 0,
  primary key (id));
-- 플레이어 퀘스트 상태. 기존 플레이어는 튜토리얼을 건너뛴 것(skipped)으로 두고 반복 퀘스트부터 받는다. 새 플레이어는 ENSURE_SQL이 active로 만든다.
alter table player_state add column tut_state text not null default 'skipped' check (tut_state in ('active', 'done', 'skipped'));
alter table player_state add column tut_step integer not null default 0 check (tut_step >= 0);
alter table player_state add column rep_n integer not null default 0 check (rep_n >= 0);
alter table player_state add column last_quest_claim timestamptz;
-- 다이아 모집권(튜토리얼 보상): 다이아 모집 1회 = 1장
alter table player_state add column dia_tickets integer not null default 0 check (dia_tickets >= 0);
-- 튜토리얼 공터: 아직 짓지 않은 건물 id(레벨 행은 1 그대로). 짓기 = 일꾼으로 Lv 1 비용·시간, 다 지으면 목록에서 빠진다
alter table player_state add column unbuilt text[] not null default '{}';
-- 튜토리얼 중 병사 1마리 훈련 시간(초)
insert into game_config (key, value) values ('tutorial_train_sec', '5'), ('quest_repeat_min_sec', '30'), ('tutorial_new_players', '1') on conflict (key) do nothing;
