-- 가이드 「닉네임 바꾸기」(2026-11-07, 사용자 "가이드 중에 이름 바꾸기 없으면 추가해줘"): 25번(0부터 24)에 끼어 가이드가 138개 → 139개.
-- 진행 중인 성주는 하던 그 퀘스트 번호로 옮긴다(앱 Tutorial.map_v12와 같다): 24번(0부터) 이상은 +1, 끝낸 138은 139.
-- 그 퀘스트가 시작된 때 기록(missions.c.gq.step)도 같은 번호로 옮겨 처치·모집 수가 이어진다.
update player_state set missions = jsonb_set(missions, '{c,gq,step}', to_jsonb((missions->'c'->'gq'->>'step')::int + 1))
  where missions->'c'->'gq'->>'step' is not null and (missions->'c'->'gq'->>'step')::int >= 24;
update player_state set tut_step = tut_step + 1 where tut_step >= 24;
