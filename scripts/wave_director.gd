extends RefCounted
## 스폰 스케줄 생성. 씬 의존 없음.

const Balance := preload("res://scripts/balance.gd")

const MODE_IDLE := 0
const MODE_STAGE := 1


## 반환: [{time: float, kind: String, side: int}] 시간 오름차순.
## MODE_IDLE은 한 사이클(4마리)만. Spawner가 소진되면 다시 build()한다.
static func build(stage: int, mode: int) -> Array:
	var events: Array = []
	if mode == MODE_IDLE:
		var interval := Balance.idle_interval(stage)
		for side in 4:
			events.append({"time": interval * (side + 1), "kind": "grunt", "side": side})
		return events
	var t := 0.0
	for w in Balance.wave_count(stage):
		var size := Balance.wave_size(stage, w)
		for i in size:
			events.append({"time": t + i * Balance.SPAWN_SPACING_SEC, "kind": "grunt", "side": i % 4})
		t += size * Balance.SPAWN_SPACING_SEC + Balance.WAVE_GAP_SEC
	var rng := RandomNumberGenerator.new()
	rng.seed = stage
	events.append({"time": t, "kind": "epic_boss", "side": rng.randi_range(0, 3)})
	return events
