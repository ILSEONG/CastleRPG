-- 가이드 기능이 열리는 간격을 메이플스토리 키우기처럼(2026-10-29 오후, 사용자 "지금은 너무 급박하게 컨텐츠를 너무 빨리 푸는거같아 메이플 키우기 좀
-- 참고하라고"): 기능이 처음 열리는 미션을 메이플 가이드 퀘스트 번호 근처에 두고(성장 8, 건설 25, 주점 58, 골드 던전 79, 길드 140, PVP 247) 그 사이를
-- 스테이지 돌파·몬스터 처치·영웅 레벨·능력치 레벨·던전 단계 퀘스트가 채운다(82개 → 265개). 성장·스테이지·처치 미션은 자리가 바뀌었다.
-- 진행 중인 플레이어의 단계(tut_step = 옛 표 번호)를 옛 표에서 이미 한 기능·행동 미션(영웅 레벨·능력치·스테이지·처치가 아닌 것과 첫 1-1) 중
-- 새 표에서 가장 뒤에 있는 미션의 다음 번호로 옮긴다(이미 연 기능은 그대로 열려 있고, 그 앞으로 옮겨진 안 한 미션은 건너뛴다). 다 끝낸(82 이상) 플레이어는 새 표 크기로. 앱 Tutorial.map_v7(V7_IDS)과 같은 표.
-- 새 사이 퀘스트 행은 quests.csv(neon:seed)가 넣는다.
update player_state set tut_step = case tut_step
    when 0 then 0
    when 1 then 1
    when 2 then 3
    when 3 then 3
    when 4 then 3
    when 5 then 8
    when 6 then 8
    when 7 then 13
    when 8 then 13
    when 9 then 18
    when 10 then 25
    when 11 then 28
    when 12 then 31
    when 13 then 34
    when 14 then 34
    when 15 then 40
    when 16 then 45
    when 17 then 50
    when 18 then 54
    when 19 then 54
    when 20 then 54
    when 21 then 54
    when 22 then 58
    when 23 then 59
    when 24 then 61
    when 25 then 64
    when 26 then 64
    when 27 then 64
    when 28 then 64
    when 29 then 64
    when 30 then 67
    when 31 then 68
    when 32 then 68
    when 33 then 75
    when 34 then 75
    when 35 then 75
    when 36 then 75
    when 37 then 79
    when 38 then 79
    when 39 then 79
    when 40 then 89
    when 41 then 89
    when 42 then 89
    when 43 then 96
    when 44 then 98
    when 45 then 98
    when 46 then 98
    when 47 then 105
    when 48 then 105
    when 49 then 105
    when 50 then 105
    when 51 then 115
    when 52 then 117
    when 53 then 117
    when 54 then 117
    when 55 then 117
    when 56 then 124
    when 57 then 124
    when 58 then 124
    when 59 then 131
    when 60 then 133
    when 61 then 133
    when 62 then 135
    when 63 then 137
    when 64 then 138
    when 65 then 138
    when 66 then 138
    when 67 then 138
    when 68 then 140
    when 69 then 143
    when 70 then 143
    when 71 then 143
    when 72 then 160
    when 73 then 175
    when 74 then 175
    when 75 then 200
    when 76 then 247
    when 77 then 253
    when 78 then 253
    when 79 then 253
    when 80 then 253
    when 81 then 259
    else 265
  end
  where tut_step > 0;
