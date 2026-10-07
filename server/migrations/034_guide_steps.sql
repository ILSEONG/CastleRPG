-- 가이드(2026-10-07, 튜토리얼 → 가이드): 새 메뉴·기능을 여는 미션 사이에 성장 미션 34개가 끼어 미션이 33개 → 67개가 됐다.
-- 진행 중인 플레이어의 단계(tut_step = 옛 표 번호)를 같은 미션 id의 새 번호로 옮긴다(하던 미션 그대로 — 앞에 새로 낀 미션은 건너뛴다).
-- 다 끝낸(33 이상) 플레이어는 새 표 크기로. 앱 Tutorial.v2_step과 같은 표.
update player_state set tut_step = case tut_step
    when 0 then 0
    when 1 then 1
    when 2 then 2
    when 3 then 3
    when 4 then 4
    when 5 then 5
    when 6 then 6
    when 7 then 7
    when 8 then 8
    when 9 then 11
    when 10 then 15
    when 11 then 16
    when 12 then 17
    when 13 then 19
    when 14 then 22
    when 15 then 23
    when 16 then 24
    when 17 then 27
    when 18 then 28
    when 19 then 31
    when 20 then 34
    when 21 then 35
    when 22 then 38
    when 23 then 39
    when 24 then 42
    when 25 then 43
    when 26 then 47
    when 27 then 50
    when 28 then 51
    when 29 then 54
    when 30 then 55
    when 31 then 58
    when 32 then 59
    else 67
  end
  where tut_step > 0;
