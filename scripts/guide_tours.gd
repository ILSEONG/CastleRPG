extends RefCounted
## 가이드 포커스 설명 표(사용자 2026-10-13 "화면의 어떤게 어떤역할인지 포커스를 주면서 설명", 공성전은 "AI 체험으로 한번 하면서 중간중간 멈추면서").
## MISSION_TOURS: 미션 id → 그 미션 동안 차례로 띄울 설명 id. TOURS: 설명 id → {when, steps, pause?}.
## when = 보일 때 띄울 곳(guide_tour.gd resolve 형식) 또는 "war?deploying|fight:<초>|gate_broken|my_dead|done"(공성전 체험 전장 상태).
## steps = [{at, text, title?}] — at 형식은 guide_tour.gd 머리말. 한 번 본 설명은 다시 안 띄운다(Tutorial.tours_seen).

const MISSION_TOURS := {
	"look_keep": ["intro", "building"],
	"hero_level": ["hero", "hero_detail"],
	"growth": ["growth"],
	"gacha": ["recruit"],
	"train": ["train"],
	"dungeon_gold": ["dungeon", "dungeon_form"],
	"research": ["research", "research_detail"],
	"guild": ["guild_join"],
	"guild_attend": ["guild_home"],
	"guild_boss": ["guild_boss"],
	"siege_try": ["war_deploy", "war_fight", "war_respawn", "war_breach", "war_end"],
	"exchange_look": ["exchange"],
}

const TOURS := {
	"intro": {"when": "ui:hud:go", "steps": [
		{"title": "성 화면 둘러보기", "text": "성주님, 환영합니다. 화면의 각 부분이 하는 일을 하나씩 알려 드립니다."},
		{"at": "hud:_chip_row", "text": "가지고 있는 골드·목재·석재·식량·다이아입니다. 건설·레벨업·모집에 씁니다."},
		{"at": "hud:_title_box", "text": "지금 스테이지와 라운드입니다. 한 스테이지는 25라운드이고, 다 막으면 다음 스테이지로 넘어갑니다."},
		{"at": "hud:_castle_bar", "text": "성의 체력입니다. 성문을 부수고 들어온 몬스터가 성을 공격합니다. 0이 되면 그 스테이지 도전에 실패합니다."},
		{"at": "hud:_gate_tiles", "text": "북·동·남·서 네 성문의 체력입니다. 누르면 그 성문으로 화면이 이동합니다."},
		{"at": "ui:hud:go", "text": "[진행]을 누르면 스테이지 전투를 시작합니다. 누르지 않으면 대기하며 영웅들이 몬스터를 잡아 골드를 모읍니다."},
		{"at": "ui:hud:auto", "text": "[연속 진행]을 켜 두면 스테이지를 깬 뒤 다음 스테이지를 저절로 이어 갑니다."},
		{"at": "ui:hud:fever", "text": "FEVER 게이지입니다. 몬스터를 잡으면 차고, 가득 차면 눌러 잠시 몬스터를 몰아서 잡습니다."},
		{"at": "ui:build_button", "text": "[건설]을 누르면 지을 수 있는 건물 목록이 펼쳐집니다. 원하는 자리에 짓고, 지은 건물은 옮길 수 있습니다."},
		{"at": "ui:menu", "text": "[메뉴]에는 이벤트·미션·가방·길드·우편 같은 기능이 모여 있습니다."},
		{"at": "tab_bar:buttons", "text": "아래 탭에서 성장·영웅·병사·던전·모집·상점을 엽니다. 잠긴 탭은 가이드를 진행하면 하나씩 열립니다."},
		{"at": "tutorial_card:panel", "text": "가이드 카드입니다. 지금 할 일과 보상이 나옵니다. [바로가기]를 누르면 할 곳으로 이동하고, 다 하면 [보상 받기]가 켜집니다."},
	]},
	"building": {"when": "building_panel:upgrade_button", "steps": [
		{"at": "building_panel:title_label", "text": "건물 이름과 지금 레벨입니다."},
		{"at": "building_panel:effects", "text": "지금 효과와 다음 레벨 효과(초록)입니다. 성채 레벨은 다른 건물이 오를 수 있는 최대 레벨을 정합니다."},
		{"at": "building_panel:reqs", "text": "레벨업에 필요한 조건입니다. 모두 ✓가 되어야 올릴 수 있습니다."},
		{"at": "building_panel:_cost_row", "text": "레벨업에 드는 자원입니다. 빨간 숫자는 모자란 자원입니다."},
		{"at": "building_panel:upgrade_button", "text": "[레벨업]을 누르면 일꾼이 공사를 시작합니다. 시간이 지나면 끝나고, 가속 아이템으로 줄일 수 있습니다."},
	]},
	"hero": {"when": "hero_panel:_hero_grid", "steps": [
		{"at": "hero_panel:_slot_grid", "text": "출전 자리입니다. 여기 선 영웅이 성문을 지킵니다. 자리를 누른 뒤 아래 영웅을 누르면 그 자리에 섭니다."},
		{"at": "hero_panel:_hero_grid", "text": "가지고 있는 영웅입니다. 카드를 누르면 자세히 보고 레벨업합니다. 초록 ▲는 레벨업, 금색 ⬆는 승급할 수 있다는 표시입니다."},
		{"at": "hero_panel:sort_button", "text": "[정렬]을 누를 때마다 전투력·등급·레벨 순으로 바뀝니다."},
		{"at": "hero_panel:auto_button", "text": "[자동 배치]는 전투력 높은 영웅으로 자리를 채웁니다. [적용]을 눌러야 확정됩니다."},
		{"at": "hero_panel:promote_all_button", "text": "[일괄 승급]은 조각이 모인 영웅을 한 번에 승급합니다."},
	]},
	"hero_detail": {"when": "hero_panel:level_button", "steps": [
		{"at": "hero_panel:stat_values", "text": "능력치입니다. 옆의 초록 숫자는 다음 레벨 값입니다."},
		{"at": "hero_panel:skill_ui", "text": "스킬입니다. 잠긴 스킬은 승급하면 열립니다."},
		{"at": "hero_panel:level_button", "text": "[레벨업]은 골드로 1레벨 올립니다. 옆 [×10]은 여러 번을 한 번에 합니다."},
		{"at": "hero_panel:promote_button", "text": "[승급]은 그 영웅의 조각으로 별을 올립니다. 최대 레벨과 능력치가 함께 오릅니다."},
		{"at": "hero_panel:deploy_button", "text": "[배치]를 누르면 이 영웅을 출전 자리에 세웁니다."},
	]},
	"growth": {"when": "growth_panel:rows.atk.up.button", "steps": [
		{"at": "growth_panel:gold_label", "text": "성장은 골드로 합니다. 지금 가진 골드입니다."},
		{"at": "growth_panel:rows.atk.up.button", "text": "[강화]를 누르면 모든 영웅의 공격력이 오릅니다. 누르고 있으면 계속 강화합니다."},
		{"at": "growth_panel:rows.atk.ten.button", "text": "[×10]은 10번을 한 번에 강화합니다."},
		{"at": "growth_panel:rows.hp.up.button", "text": "체력·공격 속도·치명타 같은 다른 능력치도 같은 방법으로 올립니다. 모든 영웅에게 함께 적용됩니다."},
	]},
	"recruit": {"when": "recruit_panel:one_button", "steps": [
		{"at": "recruit_panel:gold_tab", "text": "골드 모집입니다. 골드로 영웅을 모집합니다."},
		{"at": "recruit_panel:dia_tab", "text": "다이아 모집입니다. SSR 영웅이 더 잘 나오고, 다이아 모집권이 있으면 다이아 대신 씁니다."},
		{"at": "recruit_panel:level_label", "text": "골드 모집 레벨입니다. 모집할수록 오르고, 레벨이 높을수록 좋은 영웅이 잘 나옵니다."},
		{"at": "recruit_panel:ten_button", "text": "[10회]는 10명을 한 번에 모집합니다. 다이아 모집은 10회마다 SR 이상 1명을 보장합니다."},
		{"at": "recruit_panel:odds_button", "text": "[확률 정보]에서 영웅마다 나올 확률을 볼 수 있습니다."},
	]},
	"train": {"when": "building_panel:train_button", "steps": [
		{"at": "building_panel:unit_label", "text": "이 건물에서 훈련하는 병사와 1마리 훈련 시간입니다."},
		{"at": "building_panel:_train_cost_row", "text": "훈련 비용입니다."},
		{"at": "building_panel:train_button", "text": "[훈련]을 누르면 시작합니다. 다 되면 [받기]로 병사를 데려오고, [병사] 탭에서 성문에 배치합니다."},
	]},
	"dungeon": {"when": "dungeon_panel:cards.gold.go", "steps": [
		{"at": "dungeon_panel:section_buttons", "text": "던전과 PVP를 고릅니다."},
		{"at": "dungeon_panel:bands.gold", "text": "골드 던전입니다. 깨면 골드를 받습니다. 장비 던전과 모집권 던전은 가이드를 진행하면 열립니다."},
		{"at": "dungeon_panel:cards.gold.keys", "text": "남은 입장권입니다. 도전할 때 1장씩 씁니다."},
		{"at": "dungeon_panel:cards.gold.level", "text": "단계입니다. 높은 단계일수록 어렵고 보상이 큽니다."},
		{"at": "dungeon_panel:cards.gold.go", "text": "[도전]을 누르면 출전 영웅을 고르는 화면으로 갑니다."},
	]},
	"dungeon_form": {"when": "dungeon_panel:go_button", "steps": [
		{"at": "dungeon_panel:_slot_grid", "text": "던전에 들어갈 영웅 자리입니다."},
		{"at": "dungeon_panel:_hero_grid", "text": "영웅을 누르면 자리에 넣고, 다시 누르면 뺍니다."},
		{"at": "dungeon_panel:auto_button", "text": "전투력 높은 영웅으로 자리를 한 번에 채웁니다."},
		{"at": "dungeon_panel:go_button", "text": "준비가 되면 눌러 던전에 들어갑니다."},
	]},
	"research": {"when": "research_panel:tree", "steps": [
		{"at": "research_panel:branch_buttons", "text": "연구 분야입니다. 분야마다 다른 능력을 올립니다."},
		{"at": "research_panel:tree", "text": "연구 카드입니다. 위 단 연구를 올리면 아래 단이 열립니다. 카드를 누르면 자세히 봅니다."},
		{"at": "research_panel:cur_panel", "text": "지금 진행 중인 연구와 남은 시간입니다. 연구는 한 번에 하나씩 합니다."},
	]},
	"research_detail": {"when": "research_panel:start_button", "steps": [
		{"at": "research_panel:detail_effect", "text": "이 연구의 효과입니다."},
		{"at": "research_panel:_cost_grid", "text": "필요한 자원입니다(가진 양 / 필요한 양)."},
		{"at": "research_panel:start_button", "text": "[연구]를 누르면 시작합니다."},
	]},
	"guild_join": {"when": "guild_panel:buttons.join:0", "steps": [
		{"at": "guild_panel:buttons.join:0", "text": "추천 길드입니다. [가입]을 누르면 바로 들어갑니다."},
		{"at": "guild_panel:buttons.create", "text": "길드를 직접 만들 수도 있습니다."},
	]},
	"guild_home": {"when": "guild_panel:buttons.attend", "steps": [
		{"at": "guild_panel:buttons.attend", "text": "[출석]은 하루 한 번 합니다. 길드 경험치와 보상을 받습니다."},
		{"at": "guild_panel:buttons.box:0", "text": "오늘 출석한 길드원 수가 늘면 상자를 차례로 열 수 있습니다."},
		{"at": "guild_panel:buttons.donate:gold", "text": "기부하면 길드 경험치가 오릅니다. 길드 레벨이 오르면 모든 영웅의 공격력·체력이 오릅니다."},
		{"at": "guild_panel:buttons.tab:boss", "text": "[보스]에서는 길드원과 함께 드래곤과 싸웁니다."},
		{"at": "guild_panel:buttons.tab:war", "text": "[길드전]에서는 일주일에 한 번 다른 길드의 성을 공격합니다."},
		{"at": "guild_panel:buttons.tab:shop", "text": "[상점]에서 길드 코인으로 물건을 삽니다."},
	]},
	"guild_boss": {"when": "guild_panel:buttons.boss", "steps": [
		{"at": "guild_panel:buttons.boss", "text": "[도전]은 하루 2번 할 수 있습니다. 제한 시간 동안 드래곤에게 준 피해로 등급(S~D)과 길드 코인이 정해집니다."},
	]},
	"war_deploy": {"when": "war?deploying", "pause": true, "steps": [
		{"title": "공성전 체험", "text": "공성전은 길드끼리 상대 성을 공격하는 전투입니다. 이번 체험은 연습이라 기록이 남지 않습니다. 화면을 누를 때마다 하나씩 설명하고, 그동안 전투는 멈춰 있습니다."},
		{"at": "war_hud:time_label", "text": "남은 시간입니다. 실제 공성전은 10분, 체험은 4분입니다."},
		{"at": "war_hud:gate_bars", "text": "상대 성의 네 성문(북·동·남·서) 체력입니다."},
		{"at": "war_hud:keep_bar", "text": "가운데 성채의 체력입니다."},
		{"at": "war3d:keep", "text": "이것이 상대의 성채입니다. 성문을 부수고 들어가 성채를 치면 큰 점수를 얻습니다."},
		{"at": "war3d:def:2", "text": "성문 앞과 성벽 위에는 상대 길드원이 정해 둔 수비 영웅이 섭니다. 근접 영웅은 성문 앞, 원거리 영웅은 성벽 위에서 막습니다."},
		{"at": "war3d:mine", "text": "내 영웅 4명입니다. 성 밖 진영에서 시작합니다. 나머지 길드원의 영웅은 AI가 움직입니다."},
		{"at": "war_hud:strip", "text": "아래 띠에서 내 영웅을 고를 수도 있습니다. 쓰러진 영웅은 흐리게 보입니다."},
		{"at": "war_hud:deploy_panel", "text": "지금은 배치 단계입니다. 내 영웅을 누르고 붉은 선 바깥 바닥을 누르면 그 자리로 옮깁니다. 자리 잡은 쪽 성문을 공격합니다."},
		{"at": "war_hud:start_button", "text": "자리를 다 잡았으면 [전투 시작]을 누르세요. 실제 공성전은 길드장이 누르거나 배치 시간이 끝나면 시작합니다."},
	]},
	"war_fight": {"when": "war?fight:4", "pause": true, "steps": [
		{"at": "war3d:gate:2", "text": "전투가 시작되었습니다. 영웅들이 성문으로 가서 수비 영웅과 싸우고 성문을 공격합니다."},
		{"at": "war_hud:score_label", "text": "이번 전투 점수입니다. 수비 영웅 처치 1점, 성문 파괴 10점(성문 점수는 2개까지), 성채는 최대 체력의 3%를 깎을 때마다 1점입니다."},
		{"at": "war_hud:gate_bars", "text": "성문 체력이 0이 되면 그 면으로 성 안에 들어갈 수 있습니다. 한 성문에 힘을 모으면 빨리 부서집니다."},
		{"at": "war_hud:auto_button", "text": "[자동 진격]을 누르면 내 영웅도 AI가 알아서 움직입니다. 직접 움직이려면 내 영웅을 누르고 갈 곳을 누르세요."},
	]},
	"war_respawn": {"when": "war?my_dead", "pause": true, "steps": [
		{"at": "war_hud:strip", "text": "영웅이 쓰러졌습니다. 공격 영웅은 30초 뒤 진영에서 한 번 다시 일어납니다. 두 번째로 쓰러지면 그 전투에서는 더 싸우지 못합니다. 수비 영웅은 다시 일어나지 않습니다."},
	]},
	"war_breach": {"when": "war?gate_broken", "pause": true, "steps": [
		{"at": "war3d:keep", "text": "성문이 부서졌습니다! 이제 그 면으로 들어가 성채를 칠 수 있습니다. 성채를 무너뜨리면 전투가 바로 끝납니다."},
	]},
	"war_end": {"when": "war?done", "steps": [
		{"at": "war_hud:result_layer", "text": "체험이 끝났습니다. 실제 공성전은 일주일에 한 번 길드장이 정한 시각에 열리고, 점수가 더 높은 길드가 이깁니다. [나가기]를 누르면 성으로 돌아갑니다."},
	]},
	"exchange": {"when": "exchange_panel:buttons.tab:buy", "steps": [
		{"at": "exchange_panel:buttons.tab:buy", "text": "[구매]에서는 다른 성주가 올린 장비를 봅니다. 통화·부위·등급으로 거르고 가격순으로 정렬합니다."},
		{"at": "exchange_panel:buttons.tab:sell", "text": "[판매 등록]에서는 내 장비를 골라 값을 정해 올립니다. 48시간 동안 걸리고, 동시에 10개까지 올릴 수 있습니다."},
		{"at": "exchange_panel:buttons.tab:mine", "text": "[내 판매]에서는 올린 장비를 봅니다. 팔리면 수수료 10%를 뺀 대금을 [대금 받기]로 받습니다."},
		{"at": "exchange_panel:wallet_label", "text": "가지고 있는 골드와 다이아입니다."},
	]},
}
