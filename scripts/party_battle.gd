extends Node3D
## 파티 퀘스트 전투 장면(Party.battle_started → main._enter_dungeon(run, 이 스크립트), 나가기 → main.leave_dungeon). 던전·PVP와 같은 자리에 붙는다.
## run = 서버 live 상태 {match_id, run_id, quest, diff, seed, elapsed, time_limit, boss {hp, atk}, seats [{name, bot, me, hero? | soldiers?}], me, online}.
## 리치(lich): 성주 4명이 영웅 1명씩 — 내 영웅만 내가 조종(unit_picker: 영웅 탭 → 바닥 이동·적 공격), 나머지는 AI(보스 범위 예고를 비킨다).
##   쓰러진 영웅은 REVIVE_SEC초 뒤 제자리에서 일어난다. 네 영웅이 한꺼번에 쓰러져 있으면 패배.
## 거미 여왕(spider): 성주 3명이 병사 4마리씩(조종 없음 — AI). 거미 부하가 둥지 가장자리에서 쉬지 않고 기어 나온다(WAVE_*). 병사가 모두 쓰러지면 패배.
## 승리 = 보스 처치, 제한 시간이 지나면 패배. 결과는 Party.finish(서버가 반지·목걸이를 준다).
## 실시간(party_net.gd): 방장 기기 한 대가 판단(role "host")하고 SNAP_SEC마다 상태 한 장 — 나머지는 꼭두각시(role "puppet")로 따라 그린다.
## 보스 스킬 연출은 event(…)로 스냅샷에 실려 꼭두각시 기기에서도 똑같이 보인다. 방장이 나가면 다른 성주가 이어받는다.
## 화면 배속은 늘 1배(여럿이 함께 — main이 배속 버튼을 붙이지 않는다).

const Lang := preload("res://scripts/lang.gd")
const GameData := preload("res://scripts/game_data.gd")
const ArenaKit := preload("res://scripts/arena_kit.gd")
const PartyArena := preload("res://scripts/party_arena.gd")
const PartyRules := preload("res://scripts/party_rules.gd")
const HeroScript := preload("res://scripts/party_hero.gd")
const SoldierScript := preload("res://scripts/party_soldier.gd")
const LichScript := preload("res://scripts/lich.gd")
const QueenScript := preload("res://scripts/spider_queen.gd")
const MinionScript := preload("res://scripts/party_minion.gd")
const NetScript := preload("res://scripts/party_net.gd")
const HudScript := preload("res://scripts/party_hud.gd")
const CameraRigScript := preload("res://scripts/camera_rig.gd")
const HpBarsScript := preload("res://scripts/hp_bars.gd")
const DamageNumbersScript := preload("res://scripts/damage_numbers.gd")
const PortraitsScript := preload("res://scripts/portraits.gd")
const PickerScript := preload("res://scripts/unit_picker.gd")
const CrowdScript := preload("res://scripts/crowd.gd")
const Formation := preload("res://scripts/formation.gd")
const Fx := preload("res://scripts/fx.gd")

signal command_sent(uid, pos)
signal ended(result)

enum Phase { INTRO, FIGHT, RESULT }

const INTRO_SEC := 2.2
const SNAP_SEC := 0.2  # 초당 5장(공성전과 같은 간격)
const REVIVE_SEC := 15.0
const KO_SEC := 0.8
const FIELD_R := PartyArena.FIGHT_R
const CAMERA_SIZE := 30.0
const FOLLOW_MIN := 20.0
const BOSS_ROW := {"lich": {"speed": 2.4, "range": 2.6, "atk_interval": 1.6, "aggro": 40.0, "scale": 2.2},
	"spider": {"speed": 2.8, "range": 2.8, "atk_interval": 1.5, "aggro": 40.0, "scale": 1.0}}
const WAVE_SEC := 3.5  # 거미 부하: 이 간격마다
const WAVE_N := 3  # 이만큼씩
const SPIDERLING_CAP := 45  # 살아 있는 새끼 거미 상한(부화 포함)
const SOLDIER_GAP := 1.3
const GOOD := Color(0.55, 1.0, 0.55)
const BAD := Color(1.0, 0.5, 0.45)

var run := {}
var main
var quest := "lich"
var diff := 1
var me := 0
var role := "host"  # host | puppet
var phase := Phase.INTRO
var clock := 0.0
var duration := 180.0
var done := false
var result := {}
var rng := RandomNumberGenerator.new()
var heroes: Array = []  # 리치: 자리 순서 영웅
var soldiers: Array = []  # 거미 여왕: 자리마다 4마리씩 차례로
var boss
var monsters := {}  # uid → 졸개·보스(살아 있는 것)
var units_by_uid := {}  # uid → 영웅·병사
var seats: Array = []
var rig
var camera: Camera3D
var picker
var hud
var net

var _uid := 100  # 보스 = 100, 졸개 = 101부터(영웅·병사는 1부터)
var _events: Array = []
var _zones: Array = []  # [중심, 반경, 끝나는 clock]
var _snap_cd := 0.0
var _revive: Array = []  # [영웅, 남은 초]
var _wave_cd := 2.0
var _ko_left := -1.0
var _ko_win := false
var _leaving := false
var _reported := false
var _sent_home := {}
var _end_wait := -1.0  # 방장: end를 보낸 뒤 방이 돌려주길 기다리는 초
var _seat_spots: Array = []


func _ready() -> void:
	quest = str(run.get("quest", "lich"))
	diff = clampi(int(run.get("diff", 1)), 1, PartyRules.DIFFS)
	me = int(run.get("me", 0))
	seats = run.get("seats", [])
	duration = float(run.get("time_limit", PartyRules.TIME_LIMIT.get(quest, 180.0)))
	rng.seed = int(run.get("seed", 1))
	var stage: Dictionary = PartyArena.crypt() if quest == "lich" else PartyArena.nest()
	_seat_spots = stage.seats
	add_child(ArenaKit.lighting(stage.light))
	add_child(stage.root)
	var crowd = CrowdScript.new()
	crowd.arena_r = FIELD_R
	add_child(crowd)
	add_child(PortraitsScript.new())
	rig = CameraRigScript.new()
	add_child(rig)
	camera = rig.camera
	camera.size = CAMERA_SIZE
	rig.zoom_by(1.0)
	camera.make_current()
	var bars = HpBarsScript.new()
	bars.camera = camera
	add_child(bars)
	var numbers = DamageNumbersScript.new()
	numbers.camera = camera
	add_child(numbers)
	if quest == "lich":
		_spawn_heroes()
	else:
		_spawn_soldiers()
	_spawn_boss(stage.boss)
	if quest == "lich":
		picker = PickerScript.new()
		picker.camera = camera
		picker.arena_r = FIELD_R - 1.0
		add_child(picker)
	_freeze(true)
	rig.follow(self, FOLLOW_MIN, CAMERA_SIZE)
	hud = HudScript.new()
	hud.battle = self
	add_child(hud)
	hud.flash(Lang.t("party_battle.ready") % PartyRules.BOSS_NAMES.get(quest, ""), INTRO_SEC)
	Party.result_ready.connect(_on_result_ready)
	if run.get("online", false) and Economy.net != null:
		role = "puppet"  # 방이 방장을 정해 줄 때까지(hello) — 연결이 안 되면 혼자(host)
		net = NetScript.new()
		net.battle = self
		net.url = NetScript.live_url(Economy.net.api_base, str(run.get("match_id", "")), Economy.net.token)
		add_child(net)
	set_role(role)
	print("[party] %s diff %d seats %d me %d role %s" % [quest, diff, seats.size(), me, role])


func _seat_name(i: int) -> String:
	return str(seats[i].get("name", "")) if i < seats.size() else ""


func _spawn_heroes() -> void:
	for i in seats.size():
		var e = seats[i].get("hero")
		if not (e is Dictionary):
			continue
		var def := GameData.hero(str(e.get("hero", "")))
		if def.is_empty():
			continue
		var u = HeroScript.new()
		u.setup_war(i + 1, def, 0, int(e.get("level", 1)), int(e.get("promotion", 0)), {"hp": float(e.get("hp", 500.0)), "atk": float(e.get("atk", 40.0))})
		u.party = self
		u.seat = i
		u.mine = i == me
		u.squad = i
		u.idle_dir = -ArenaKit.DOWN
		var p: Vector3 = _seat_spots[mini(i, _seat_spots.size() - 1)]
		u.post_pos = p
		u.free_pos = p
		u.hold = false
		add_child(u)
		u.global_position = p
		u.puppet_hold(p)
		u.fell.connect(_on_hero_fell)
		heroes.append(u)
		units_by_uid[u.uid] = u


func _spawn_soldiers() -> void:
	var n := 0
	for i in seats.size():
		var list = seats[i].get("soldiers")
		if not (list is Array):
			continue
		var base: Vector3 = _seat_spots[mini(i, _seat_spots.size() - 1)]
		for k in list.size():
			var x: Dictionary = list[k]
			if GameData.soldier(str(x.get("type", ""))).is_empty():
				continue
			n += 1
			var s = SoldierScript.new()
			s.setup(str(x.type), int(x.get("tier", 1)), 0, n)
			var home: Vector3 = base + ArenaKit.RIGHT * ((k % 2) - 0.5) * SOLDIER_GAP + ArenaKit.DOWN * (k / 2) * SOLDIER_GAP
			s.setup_party({"hp": float(x.get("hp", 0.0)), "atk": float(x.get("atk", 0.0))}, i, home)
			s.party = self
			s.march_dir = -ArenaKit.DOWN
			add_child(s)
			s.global_position = home
			soldiers.append(s)
			units_by_uid[s.uid] = s


func _boss_row() -> Dictionary:
	var row: Dictionary = BOSS_ROW[quest].duplicate()
	var st: Dictionary = run.get("boss", PartyRules.boss_stats(quest, diff))
	row.kind = "lich" if quest == "lich" else "spider_queen"
	row.hp = float(st.get("hp", 10000.0))
	row.atk = float(st.get("atk", 50.0))
	return row


func _spawn_boss(at: Vector3) -> void:
	boss = (LichScript if quest == "lich" else QueenScript).new()
	boss.setup_arena(_boss_row())
	boss.uid = 100
	boss.battle = self
	add_child(boss)
	boss.global_position = at
	boss._model.face(ArenaKit.DOWN)
	boss.died.connect(_on_boss_died)
	monsters[100] = boss


## 졸개 하나(방장만). hp > 0이면 그 체력(영혼 수정 — 리치 최대 체력의 비율).
func spawn_minion(kind: String, at: Vector3, hp := 0.0):
	if role != "host" or phase == Phase.RESULT:
		return null
	var row := PartyRules.minion_row(kind, diff)
	if hp > 0.0:
		row.hp = hp
	return _add_minion(kind, row, at, -1)


func _add_minion(kind: String, row: Dictionary, at: Vector3, uid: int):
	var m = MinionScript.new()
	m.setup_arena(row)
	if uid < 0:
		_uid += 1
		uid = _uid
	m.uid = uid
	m.battle = self
	m.puppet = role == "puppet"
	add_child(m)
	m.global_position = Vector3(at.x, 0.0, at.z)
	monsters[uid] = m
	m.died.connect(_on_monster_died)
	return m


func _on_monster_died(m) -> void:
	monsters.erase(m.uid)


## 알이 깨어난다: 그 자리에 새끼 거미 n마리(상한 안), 알은 터져 사라진다.
func hatch(egg, n: int) -> void:
	var at: Vector3 = egg.global_position
	egg.take_damage(egg.hp, DamageNumbersScript.Kind.HIT)
	var room := SPIDERLING_CAP - _count("spiderling")
	for i in mini(n, room):
		var a := TAU * i / n
		spawn_minion("spiderling", clamp_field(at + Vector3(cos(a), 0, sin(a)) * 0.8))
	event(0, ["line", "hatch"])
	boss_line("hatch")


func _count(kind: String) -> int:
	var n := 0
	for m in monsters.values():
		if is_instance_valid(m) and m.kind == kind and m.is_alive():
			n += 1
	return n


## 거미 부하 무리: 둥지 위쪽 가장자리(여왕 뒤 반원)에서 기어 나온다.
func _spider_wave() -> void:
	var room := SPIDERLING_CAP - _count("spiderling")
	for i in mini(WAVE_N, room):
		var a := rng.randf_range(-1.3, 1.3)
		var dir := (-ArenaKit.DOWN).rotated(Vector3.UP, a)
		spawn_minion("spiderling", dir * (FIELD_R - 0.5))


# --- 보스·영웅이 묻는 것 ---

func field_center() -> Vector3:
	return Vector3.ZERO


func clamp_field(p: Vector3) -> Vector3:
	var v := Vector2(p.x, p.z).limit_length(FIELD_R - 1.0)
	return Vector3(v.x, 0.0, v.y)


## 성주 쪽(화면 아래).
func toward_seats() -> Vector3:
	return ArenaKit.DOWN


## 살아 있는 성주 유닛(리치 = 영웅, 거미 여왕 = 병사).
func player_units() -> Array:
	return (heroes if quest == "lich" else soldiers).filter(func(u): return is_instance_valid(u) and u.is_alive())


func my_units() -> Array:
	return heroes.filter(func(u): return u.mine) if quest == "lich" else soldiers.filter(func(s): return s.owner_seat == me)


func unit_by_uid(uid: int):
	var u = units_by_uid.get(uid)
	if u == null:
		u = monsters.get(uid)
	return u if u != null and is_instance_valid(u) else null


## 보스 범위 예고(방장): AI 영웅·병사가 비킨다.
func danger(pos: Vector3, r: float, sec: float) -> void:
	_zones.append([Vector3(pos.x, 0, pos.z), r, clock + sec])


## p(반지름 rad)가 예고 범위 안이면 가장 가까운 바깥 지점, 아니면 Vector3.INF.
func escape_from(p: Vector3, rad: float) -> Vector3:
	var flat := Vector3(p.x, 0, p.z)
	for z in _zones:
		if float(z[2]) < clock:
			continue
		var c: Vector3 = z[0]
		var r: float = float(z[1]) + rad + 0.5
		var d := Formation.flat_distance(flat, c)
		if d >= r:
			continue
		var dir := (flat - c).normalized() if d > 0.05 else ArenaKit.DOWN
		for turn in [0.0, 0.6, -0.6, 1.2, -1.2, PI]:
			var out := clamp_field(c + dir.rotated(Vector3.UP, turn) * (r + 0.4))
			if not _in_zone(out, rad):
				return out
		return clamp_field(c + dir * (r + 0.4))
	return Vector3.INF


func _in_zone(p: Vector3, rad: float) -> bool:
	for z in _zones:
		if float(z[2]) >= clock and Formation.flat_distance(p, z[0]) < float(z[1]) + rad + 0.3:
			return true
	return false


## AI가 먼저 깰 것: 영혼 수정·거미 알(가장 가까운 것).
func priority_target(from: Vector3):
	var best = null
	var best_d := INF
	for m in monsters.values():
		if not is_instance_valid(m) or not m.is_alive() or not (m.kind == "soul_crystal" or m.kind == "spider_egg"):
			continue
		var d := Formation.flat_distance(from, m.global_position)
		if d < best_d:
			best_d = d
			best = m
	return best


## 보스 스킬 연출(방장이 남긴다 — 다음 스냅샷에 실어 꼭두각시가 그린다).
func event(src_uid: int, ev: Array) -> void:
	if role == "host":
		_events.append([src_uid, ev])


func boss_line(key: String) -> void:
	if hud == null:
		return
	match key:
		"harvest":
			hud.flash(Lang.t("party_battle.boss_line"), 3.0, Color(0.55, 1.0, 0.9))
		"harvest_broken":
			hud.flash(Lang.t("party_battle.boss_line_2"), 2.5, GOOD)
		"hatch":
			hud.flash(Lang.t("party_battle.boss_line_3"), 1.6, BAD)


# --- 진행 ---

func _freeze(on: bool) -> void:
	for u in heroes + soldiers + monsters.values():
		if is_instance_valid(u):
			u.set_process(not on)


func _process(delta: float) -> void:
	if role == "puppet":
		if phase != Phase.RESULT:
			_relay_my_commands()
		if phase == Phase.INTRO and clock > 0.0:
			_begin_fight()
		return
	if _end_wait >= 0.0:
		_end_wait -= delta
		if _end_wait < 0.0:
			report_result()  # 방이 end를 돌려주지 않는다: 바로 보낸다
	match phase:
		Phase.INTRO:
			clock = minf(clock, 0.0)
			clock -= delta
			if clock <= -INTRO_SEC:
				clock = 0.0
				_begin_fight()
		Phase.FIGHT:
			_snap_cd -= delta
			if _ko_left >= 0.0:
				_ko_left -= delta
				if _ko_left < 0.0:
					_end(_ko_win, "ko" if _ko_win else "wipe")
				return
			clock += delta
			_zones = _zones.filter(func(z): return float(z[2]) >= clock)
			for r in _revive.duplicate():
				r[1] -= delta
				var u = r[0]
				if is_instance_valid(u) and u.is_alive():
					_revive.erase(r)  # 꼭두각시였다가 이어받은 사이에 이미 일어났다
				elif r[1] <= 0.0:
					_revive.erase(r)
					if is_instance_valid(u):
						u.respawn(_seat_spots[mini(u.seat, _seat_spots.size() - 1)])
						u.commanded = false
						Fx.revive(u)
			if quest == "spider":
				_wave_cd -= delta
				if _wave_cd <= 0.0:
					_wave_cd = WAVE_SEC
					_spider_wave()
			if player_units().is_empty():
				_ko_win = false
				_ko_left = KO_SEC
				hud.flash(Lang.t("party_battle.process"), 2.0, BAD)
			elif clock >= duration:
				_end(false, "time")


func _begin_fight() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.FIGHT
	_freeze(false)


func _on_boss_died(_b) -> void:
	monsters.erase(100)
	if role == "host" and phase == Phase.FIGHT and _ko_left < 0.0:
		_ko_win = true
		_ko_left = KO_SEC
		hud.flash(Lang.t("party_battle.on_boss_died") % PartyRules.BOSS_NAMES.get(quest, ""), 2.2, GOOD)


func _on_hero_fell(u) -> void:
	if hud != null:
		hud.refresh()
	if role != "host" or phase != Phase.FIGHT:
		return
	_revive.append([u, REVIVE_SEC])
	if u.mine:
		hud.flash(Lang.t("party_battle.on_hero_fell") % int(REVIVE_SEC), 2.0, BAD)


## 내 영웅 부활까지 남은 초(없으면 -1).
func revive_left(u) -> float:
	for r in _revive:
		if r[0] == u:
			return float(r[1])
	if role == "puppet" and is_instance_valid(u) and not u.is_alive():
		return float(u.get_meta("revive_at", clock + REVIVE_SEC)) - clock
	return -1.0


func time_left() -> float:
	return maxf(0.0, duration - maxf(0.0, clock))


func boss_hp_ratio() -> float:
	return boss.hp_ratio() if is_instance_valid(boss) else 0.0


func set_auto() -> void:
	for u in my_units():
		u.commanded = false


# --- 끝 ---

func _end(win: bool, reason: String) -> void:
	if done:
		return
	done = true
	phase = Phase.RESULT
	_freeze(true)
	result = {"win": win, "reason": reason, "pending": true}
	print("[party] end %s win %s clock %.1f role %s" % [quest, win, clock, role])
	if hud != null:
		hud.show_result(result)
	if role == "host" and net != null and net.send_end(win, clock):
		_end_wait = 6.0  # 방이 모두에게 end를 돌리면(end_from_room) 그때 결과를 보낸다
	else:
		report_result()
	ended.emit(result)


## 방(서버)이 판 끝을 알렸다: 방장의 결과로 끝내고 결과를 보낸다.
func end_from_room(win: bool, _elapsed: float) -> void:
	if not done:
		_end(win, "ko" if win else "wipe")
	_end_wait = -1.0
	report_result()


func report_result() -> void:
	if _reported:
		return
	_reported = true
	Party.finish(str(run.get("run_id", "")), bool(result.get("win", false)), maxf(0.0, clock))


func _on_result_ready(r: Dictionary) -> void:
	if not done:
		return
	result.merge(r, true)
	result.erase("pending")
	if hud != null:
		hud.show_result(result)


## [나가기]: 싸우는 중이면 이 성주만 포기(패배로 결과를 보낸다 — 다른 성주들의 판은 계속된다).
func forfeit() -> void:
	if not done:
		if _ko_left >= 0.0:
			_end(_ko_win, "ko")
		else:
			done = true
			phase = Phase.RESULT
			result = {"win": false, "reason": "forfeit"}
			_reported = true
			Party.finish(str(run.get("run_id", "")), false, maxf(0.0, clock))
	leave()


func leave() -> void:
	if _leaving:
		return
	_leaving = true
	if main != null:
		main.leave_dungeon.call_deferred()
	else:
		queue_free()


# --- 실시간 ---

func set_role(r: String) -> void:
	var was := role
	role = r
	var pup := role == "puppet"
	for u in heroes + soldiers:
		if is_instance_valid(u):
			u.puppet = pup
	for m in monsters.values():
		if is_instance_valid(m):
			m.puppet = pup
	if was == "puppet" and role == "host" and phase == Phase.INTRO and clock > 0.0:
		_begin_fight()


func snapshot_due() -> bool:
	if _snap_cd > 0.0:
		return false
	_snap_cd = SNAP_SEC
	return true


func snapshot() -> Dictionary:
	var u := {}
	for x in heroes + soldiers:
		if is_instance_valid(x):
			u[str(x.uid)] = x.puppet_row()
	var rv := {}
	for r in _revive:
		if is_instance_valid(r[0]):
			rv[str(r[0].uid)] = snappedf(float(r[1]), 0.1)
	var m := {}
	for id in monsters:
		var x = monsters[id]
		if is_instance_valid(x) and x.is_alive():
			var row: Array = [x.kind]
			row.append_array(x.puppet_row())
			m[str(id)] = row
	var out := {"c": snappedf(clock, 0.01), "ph": phase, "u": u, "m": m, "rv": rv}
	if not _events.is_empty():
		out.e = _events
		_events = []
	return out


## 꼭두각시: 방장 스냅샷을 따른다(새 졸개는 만들고, 빠진 것은 쓰러뜨린다).
func apply_snapshot(s: Dictionary) -> void:
	if role != "puppet" or done:
		return
	clock = float(s.get("c", clock))
	if int(s.get("ph", 0)) >= Phase.FIGHT and phase == Phase.INTRO:
		_begin_fight()
	var rows = s.get("u", {})
	if rows is Dictionary:
		for k in rows:
			var x = units_by_uid.get(int(k))
			if x != null and is_instance_valid(x) and rows[k] is Array:
				x.puppet_apply(rows[k])
	var rv = s.get("rv", {})
	if rv is Dictionary:
		for k in rv:
			var x = units_by_uid.get(int(k))
			if x != null:
				x.set_meta("revive_at", clock + float(rv[k]))
	var ms = s.get("m", {})
	if ms is Dictionary:
		for k in ms:
			var id := int(k)
			var row = ms[k]
			if not (row is Array) or row.size() < 7:
				continue
			var x = monsters.get(id)
			if x == null or not is_instance_valid(x):
				var kind := str(row[0])
				if not PartyRules.MINION.has(kind):
					continue
				x = _add_minion(kind, PartyRules.minion_row(kind, diff), Vector3(float(row[1]), 0, float(row[2])), id)
			x.puppet_apply(row.slice(1))
		for id in monsters.keys():
			if not ms.has(str(id)):
				var x = monsters[id]
				monsters.erase(id)
				if is_instance_valid(x) and x.is_alive():
					x.take_damage(x.hp, DamageNumbersScript.Kind.HIT)
	var evs = s.get("e", [])
	if evs is Array:
		for e in evs:
			if not (e is Array) or e.size() < 2 or not (e[1] is Array):
				continue
			var ev: Array = e[1]
			if int(e[0]) == 0:
				if ev.size() >= 2 and str(ev[0]) == "line":
					boss_line(str(ev[1]))
				continue
			var src = monsters.get(int(e[0]))
			if src != null and is_instance_valid(src) and src.has_method("play_event"):
				src.play_event(ev)
	if hud != null:
		hud.refresh()


## 방장: 다른 성주가 보낸 명령(자기 자리 영웅만).
func apply_command(seat: int, uid: int, pos) -> void:
	var u = units_by_uid.get(uid)
	if u == null or not is_instance_valid(u) or quest != "lich" or int(u.seat) != seat or not u.is_alive():
		return
	if pos == null:
		u.commanded = false
		return
	u.move_to_point(clamp_field(Vector3(float(pos[0]), 0.0, float(pos[1]))))
	var foe = monsters.get(int(pos[2])) if pos.size() >= 3 else null
	if foe != null and is_instance_valid(foe) and foe.is_alive():
		u.attack_unit(foe)


## 꼭두각시: 내 영웅 명령을 방장에게(바뀔 때만). [자동]이면 null.
func _relay_my_commands() -> void:
	for u in my_units():
		if quest != "lich":
			return
		var order := [u.free_pos, u.focus_uid, u.commanded]
		if _sent_home.get(u.uid) == order:
			continue
		_sent_home[u.uid] = order
		if u.commanded:
			var pos := [snappedf(u.free_pos.x, 0.01), snappedf(u.free_pos.z, 0.01)]
			if u.focus_uid >= 0:
				pos.append(u.focus_uid)
			command_sent.emit(u.uid, pos)
		else:
			command_sent.emit(u.uid, null)
