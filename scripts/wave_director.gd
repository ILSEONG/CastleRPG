extends RefCounted
## 스폰 스케줄 생성. 씬 의존 없음.
## 몬스터는 spawn_group(설정)마리씩 같은 시각에 나온다.
## 방치: 한 무리가 한 면에(lane 0..lanes−1 = 옆으로 나눈 칸, castle.spawn_position). 스테이지: 한 무리가 이웃한 면들에 한 마리씩 —
## 한 성문에 몰리면 시작 영웅(서쪽 성벽 니나, 공격 12/초)이 무리 둘을 못 버텨 1스테이지 성문이 부서진다(헤드리스 E2E로 확인).

const GameData := preload("res://scripts/game_data.gd")

const MODE_IDLE := 0
const MODE_STAGE := 1


## 반환: [{time: float, kind: String, side: int, (방치만) lane: int, lanes: int}] 시간 오름차순.
## MODE_IDLE은 한 사이클(면마다 한 무리, idle_interval 간격)만. Spawner가 소진되면 다시 build()한다.
## MODE_STAGE: 웨이브마다 wave_size마리를 무리로 나눠(마지막 무리는 남은 수) spawn_spacing_sec 간격, 면은 웨이브 안 순번 % 4(예전과 같다),
## 웨이브 사이 wave_gap_sec, 끝에 보스.
static func build(stage: int, mode: int) -> Array:
	var events: Array = []
	var group := group_size()
	if mode == MODE_IDLE:
		var interval: float = GameData.stage(stage).idle_interval
		for side in 4:
			for i in group:
				events.append({"time": interval * (side + 1), "kind": "grunt", "side": side, "lane": i, "lanes": group})
		return events
	var t := 0.0
	var st := GameData.stage(stage)
	var spacing := GameData.config_num("spawn_spacing_sec")
	for w in int(st.waves):
		var size := int(st.wave_size)
		for i in size:
			events.append({"time": t + (i / group) * spacing, "kind": "grunt", "side": i % 4})
		t += ceili(size / float(group)) * spacing + GameData.config_num("wave_gap_sec")
	var rng := RandomNumberGenerator.new()
	rng.seed = stage
	events.append({"time": t, "kind": "epic_boss", "side": rng.randi_range(0, 3)})
	return events


## 한 무리 마릿수(설정 spawn_group, 1 이상 정수).
static func group_size() -> int:
	return maxi(1, roundi(GameData.config_num("spawn_group")))
