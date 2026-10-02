extends RefCounted
## 스폰 스케줄 생성. 씬 의존 없음.
## 몬스터는 spawn_group(설정)마리씩 한 무리로 같은 시각·같은 면에 나온다. 무리 안 lane(0..lanes−1)은 옆으로 나눈 칸(castle.spawn_position).

const GameData := preload("res://scripts/game_data.gd")

const MODE_IDLE := 0
const MODE_STAGE := 1


## 반환: [{time: float, kind: String, side: int, lane: int, lanes: int}] 시간 오름차순(보스는 lane 없음).
## MODE_IDLE은 한 사이클(면마다 한 무리, idle_interval 간격)만. Spawner가 소진되면 다시 build()한다.
## MODE_STAGE: 웨이브마다 wave_size마리를 무리로 나눠(마지막 무리는 남은 수) spawn_spacing_sec 간격(무리마다 면 순환),
## 웨이브 사이 wave_gap_sec, 끝에 보스.
static func build(stage: int, mode: int) -> Array:
	var events: Array = []
	var group := group_size()
	if mode == MODE_IDLE:
		var interval: float = GameData.stage(stage).idle_interval
		for side in 4:
			_add_group(events, interval * (side + 1), side, group)
		return events
	var t := 0.0
	var st := GameData.stage(stage)
	var spacing := GameData.config_num("spawn_spacing_sec")
	var k := 0  # 스테이지 전체 무리 순번 — 면은 웨이브를 넘어 이어서 돈다(무리가 웨이브에 3개면 한 면이 빠지지 않게)
	for w in int(st.waves):
		var size := int(st.wave_size)
		var groups := ceili(size / float(group))
		for g in groups:
			_add_group(events, t + g * spacing, k % 4, mini(group, size - g * group))
			k += 1
		t += groups * spacing + GameData.config_num("wave_gap_sec")
	var rng := RandomNumberGenerator.new()
	rng.seed = stage
	events.append({"time": t, "kind": "epic_boss", "side": rng.randi_range(0, 3)})
	return events


## 한 무리 마릿수(설정 spawn_group, 1 이상 정수).
static func group_size() -> int:
	return maxi(1, roundi(GameData.config_num("spawn_group")))


static func _add_group(events: Array, time: float, side: int, n: int) -> void:
	for i in n:
		events.append({"time": time, "kind": "grunt", "side": side, "lane": i, "lanes": n})
