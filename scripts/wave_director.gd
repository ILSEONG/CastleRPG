extends RefCounted
## 스폰 스케줄 생성. 씬 의존 없음.
## 스폰 한 번 = spawn_group(설정)마리가 같은 시각·같은 면에 나란히(lane 0..lanes−1 = 옆으로 나눈 칸, castle.spawn_position).
## 스폰 횟수·면 순서는 예전(한 번에 한 마리) 그대로, 간격만 2배 — 몬스터 수가 3배로 는다.

const GameData := preload("res://scripts/game_data.gd")

const MODE_IDLE := 0
const MODE_STAGE := 1
const SOUTH := 2  # Formation.SIDE_NAMES[2] = "남"


## 반환: [{time: float, kind: String, look: String, side: int, lane: int, lanes: int}] 시간 오름차순(보스는 lane 없이 hp_mult).
## MODE_IDLE은 한 사이클(idle_interval에 네 면이 동시에 한 무리씩)만. Spawner가 소진되면 다시 build()한다.
## MODE_STAGE: 웨이브마다 wave_size번 스폰, spawn_spacing_sec 간격, 면은 웨이브 안 순번 % 4, 웨이브 사이 wave_gap_sec.
## 졸개는 라운드마다 72마리(웨이브 3 × 스폰 8 × 3, stages.csv), 끝에 보스 — 라운드 1~24는 남쪽 하나, 라운드 25는 네 면에 하나씩(HP × boss_round_mult). stage = 전체 라운드 g.
static func build(stage: int, mode: int) -> Array:
	var events: Array = []
	if mode == MODE_IDLE:
		var interval: float = GameData.stage(stage).idle_interval
		for side in 4:  # 네 면 동시: 한 번에 면마다 한 무리
			_add_group(events, interval, side, stage)
		return events
	var t := 0.0
	var st := GameData.stage(stage)
	var spacing := GameData.config_num("spawn_spacing_sec")
	for w in int(st.waves):
		var size := int(st.wave_size)
		for i in size:
			_add_group(events, t + i * spacing, i % 4, stage)
		t += size * spacing + GameData.config_num("wave_gap_sec")
	# 보스(2026-10-12 사용자): 졸개가 다 나온 뒤 매 라운드 남쪽 성문에서 한 마리, 스테이지 마지막 라운드는 네 성문에서 한 마리씩(HP × boss_round_mult).
	var look := GameData.boss_look(stage)
	if not GameData.is_boss_round(stage):
		events.append({"time": t, "kind": "epic_boss", "look": look, "side": SOUTH})
		return events
	for side in 4:
		events.append({"time": t, "kind": "epic_boss", "look": look, "side": side, "hp_mult": GameData.config_num("boss_round_mult")})
	return events


## 스폰 한 번: 한 면에 group_size()마리를 칸을 나눠 넣는다. look = 라운드 g의 생김새(GameData.enemy_look).
static func _add_group(events: Array, time: float, side: int, g: int) -> void:
	var n := group_size()
	var look := GameData.enemy_look(g)
	for lane in n:
		events.append({"time": time, "kind": "grunt", "look": look, "side": side, "lane": lane, "lanes": n})


## 스폰 한 번 마릿수(설정 spawn_group, 1 이상 정수).
static func group_size() -> int:
	return maxi(1, roundi(GameData.config_num("spawn_group")))
