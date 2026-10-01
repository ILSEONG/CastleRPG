-- 개정 10 (스펙 §3.7): 영웅 직업 표(hero_roles)를 영웅 22종 표(heroes)로 바꾼다. 열 = data/heroes.csv, 숫자는 real,
-- 스킬 칸은 비면 null, ord = 파일 순서. 행은 seed가 넣는다. desc는 예약어라 따옴표.
drop table if exists hero_roles;
create table heroes (id text primary key, name text not null, title text not null,
  grade text not null check (grade in ('R', 'SR', 'SSR')), role text not null check (role in ('melee', 'ranged')),
  archetype text not null, model text not null, gear text not null, color text not null,
  hp real not null, atk real not null, range real not null, atk_interval real not null, speed real not null, aggro real not null,
  skill1 text, s1a real, s1b real, s1c real, skill2 text, s2a real, s2b real, s2c real,
  "desc" text not null, ord integer not null default 0);
