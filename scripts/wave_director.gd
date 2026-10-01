extends RefCounted
## 스폰 스케줄 생성. 씬 의존 없음.

const GameData := preload("res://scripts/game_data.gd")

const MODE_IDLE := 0
const MODE_STAGE := 1


## 반환: [{time: float, kind: String, side: int}] 시간 오름차순.
## MODE_IDLE은 한 사이클(4마리)만. Spawner가 소진되면 다시 build()한다.
static func build(stage: int, mode: int) -> Array:
	var events: Array = []
	if mode == MODE_IDLE:
		var interval: float = GameData.stage(stage).idle_interval
		for side in 4:
			events.append({"time": interval * (side + 1), "kind": "grunt", "side": side})
		return events
	var t := 0.0
	var st := GameData.stage(stage)
	for w in int(st.waves):
		var size := int(st.wave_size)
		for i in size:
			events.append({"time": t + i * GameData.config_num("spawn_spacing_sec"), "kind": "grunt", "side": i % 4})
		t += size * GameData.config_num("spawn_spacing_sec") + GameData.config_num("wave_gap_sec")
	var rng := RandomNumberGenerator.new()
	rng.seed = stage
	events.append({"time": t, "kind": "epic_boss", "side": rng.randi_range(0, 3)})
	return events
