-- 2026-10-07 장비 개편: 장비 레벨을 없애고(열은 남기고 기본 1, 읽지 않는다) 장비마다 굴림을 둔다.
-- rolls = 기본 능력치마다 굴림 %(85~115, 없는 키 = 100 = 기준값), subs = 특수 능력치 [{id, r}](SR·SSR 1줄, UR 2줄, LR 3줄. rules.ts SUB_*).
-- 이미 있는 장비: 기본 능력치는 기준값(rolls {}), SR 이상은 특수 능력치를 지금 굴려 준다(서로 다른 종류, 굴림 85~115).
alter table player_items add column if not exists rolls jsonb not null default '{}'::jsonb;
alter table player_items add column if not exists subs jsonb not null default '[]'::jsonb;
alter table player_items alter column level set default 1;
update player_items i set subs = coalesce((
    select jsonb_agg(jsonb_build_object('id', x.s, 'r', 85 + floor(random() * 31)::int))
    from (select s from unnest(array['lifesteal', 'crit_rate', 'crit_dmg', 'aspd', 'dmg_reduce', 'skill_dmg']) as s
      where i.id is not null order by random() limit (case i.grade when 'SR' then 1 when 'SSR' then 1 when 'UR' then 2 when 'LR' then 3 else 0 end)) x
  ), '[]'::jsonb)
  where i.grade in ('SR', 'SSR', 'UR', 'LR') and i.subs = '[]'::jsonb;
