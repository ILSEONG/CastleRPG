extends Node
## 던전 전투장 여유 재기(개발용, 사용자 2026-10-19 "맵 규모가 좁아서 영웅 컨트롤이 안되는 곳은 맵 크기를 좀 키워줘").
## 던전(골드·장비·모집권)과 파티(리치·거미 여왕)를 오프라인으로 열어 SEC초 동안 매 프레임 잰다:
##  - 도망 여유: 내 유닛마다 가장 가까운 적의 반대쪽으로 걸어서 무대 끝(반경·옆 폭)까지 몇 m인가 — 작으면 끌고 다니거나 피할 자리가 없다.
##  - 끝 붙음: 무대 끝 1.5 m 안에 선 내 유닛 비율.
##  - 유닛당 넓이: 무대 넓이 ÷ (내 유닛 + 살아 있는 적) 평균.
## 화면도 찍는다(--out=경로 접두, 창이 있어야 한다). 실행:
##   xvfb-run -a godot --path . --resolution 720x1280 res://tests/arena_room.tscn -- --out=/tmp/arena

const GameData := preload("res://scripts/game_data.gd")
const DungeonScript := preload("res://scripts/dungeon.gd")
const BattleScript := preload("res://scripts/party_battle.gd")
const SIDE := Vector2(0.70710678, -0.70710678)
const SEC := 14.0

var _main
var _out := ""
var _rows := []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	Tutorial.save_path = ""
	Party.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.state = "skipped"
	Party.auto_accept = true
	Party.view = {"quests": Party._local_quests(), "queue": {"state": "idle"}}
	for h in GameData.heroes():
		Economy.heroes[str(h.id)] = 1
		Economy.hero_levels[str(h.id)] = 20
	Economy.soldiers = {"infantry:1": 8, "archer:1": 8}
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(30)
	var party: Array = GameData.heroes().slice(0, 6).map(func(h): return str(h.id))
	for t in ["ticket", "gold", "equip"]:
		var before: int = _main._dungeon.get_instance_id() if _main._dungeon != null else 0
		for c in get_children():  # 던전을 나오면 main이 새로 만들어질 수 있다
			if c.get_script() == _main.get_script() and not c.is_queued_for_deletion():
				_main = c
		party = GameData.heroes().slice(0, GameData.party_size(t)).map(func(h): return str(h.id))
		print("ROOM start %s: %s" % [t, Economy.dungeon_block(t, 1, party, "" if t == "ticket" else null)])
		var helper := ""
		if t == "ticket":
			for hc in Economy.helper_candidates():
				if not party.has(hc.hero_id):
					helper = str(hc.key)
					break
		Economy.start_dungeon(t, 1, party, helper)
		await _wait_until(func(): return _main._dungeon != null and _main._dungeon.get_instance_id() != before and _main._dungeon.is_inside_tree(), 8.0)
		var d = _main._dungeon
		if d == null:
			print("ROOM %s: no dungeon (children %s)" % [t, get_children().map(func(c): return c.name)])
			continue
		await _measure(t, d, DungeonScript.arena_r(t), DungeonScript.arena_side(t), func(): return d.heroes)
		d.leave()
		await get_tree().create_timer(3.0).timeout
	for q in ["lich", "spider"]:
		Party.start_queue(q, 1, Party.pick_hero(), Party.pick_soldiers())
		await _wait_until(func(): return _battle() != null, 10.0)
		var b = _battle()
		if b == null:
			print("ROOM %s: battle did not open" % q)
			continue
		await _measure(q, b, BattleScript.FIELD_R, INF, func(): return b.player_units())
		b.hud._on_leave()
		await get_tree().create_timer(0.5).timeout
		b.hud._on_leave()
		await _frames(30)
	print("ROOM table (kite = m to the arena edge walking away from the nearest enemy, edge = share of own units within 1.5 m of the edge)")
	for r in _rows:
		print("ROOM %-7s R %.1f side %s  area %4.0f m2  own %2d  foes avg %4.1f max %2d  kite avg %4.1f m p10 %4.1f m  edge %3.0f%%  m2/unit %5.1f  sidestep p10 %4.1f m" % r)
	get_tree().quit(0)


func _measure(name_s: String, scene, r: float, side: float, own: Callable) -> void:
	var kites := []
	var sides := []
	var edge := 0
	var samples := 0
	var foes_sum := 0.0
	var foes_max := 0
	var frames := 0
	var area := _area(r, side)
	var t0 := Time.get_ticks_msec()
	var shot := false
	while Time.get_ticks_msec() - t0 < SEC * 1000.0 and is_instance_valid(scene) and scene.is_inside_tree():
		await get_tree().process_frame
		var mine: Array = own.call().filter(func(u): return is_instance_valid(u) and u.is_alive())
		var foes: Array = get_tree().get_nodes_in_group("monsters").filter(func(m): return is_instance_valid(m) and m.is_alive() and m.is_inside_tree())
		if mine.is_empty() or foes.is_empty():
			continue
		frames += 1
		foes_sum += foes.size()
		foes_max = maxi(foes_max, foes.size())
		for u in mine:
			var p := Vector2(u.global_position.x, u.global_position.z)
			var near: Vector2 = Vector2.INF
			for m in foes:
				var q := Vector2(m.global_position.x, m.global_position.z)
				if near == Vector2.INF or p.distance_to(q) < p.distance_to(near):
					near = q
			var dir := (p - near).normalized() if p.distance_to(near) > 0.01 else Vector2.DOWN
			var k := 0.0
			while k < 30.0 and _inside(p + dir * (k + 0.25), r, side):
				k += 0.25
			kites.append(k)
			var perp := Vector2(-dir.y, dir.x)
			var sr := 0.0
			for sgn in [1.0, -1.0]:
				var j := 0.0
				while j < 30.0 and _inside(p + perp * sgn * (j + 0.25), r, side):
					j += 0.25
				sr = maxf(sr, j)
			sides.append(sr)
			if not _inside(p, r - 1.5, side - 1.5):
				edge += 1
			samples += 1
		if not shot and Time.get_ticks_msec() - t0 > 6000 and _out != "":
			shot = true
			get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, name_s])
	kites.sort()
	var avg := 0.0
	for k in kites:
		avg += k
	avg /= maxf(1.0, kites.size())
	var p10: float = kites[int(kites.size() * 0.1)] if not kites.is_empty() else 0.0
	sides.sort()
	var sp10: float = sides[int(sides.size() * 0.1)] if not sides.is_empty() else 0.0
	var foes_avg := foes_sum / maxf(1.0, frames)
	var own_n: int = own.call().size()
	_rows.append([name_s, r, "%.1f" % side if side < INF else "-", area, own_n, foes_avg, foes_max, avg, p10, 100.0 * edge / maxf(1.0, samples), area / maxf(1.0, own_n + foes_avg), sp10])


static func _inside(p: Vector2, r: float, side: float) -> bool:
	return p.length() <= r and absf(p.dot(SIDE)) <= side


static func _area(r: float, side: float) -> float:
	if side >= r:
		return PI * r * r
	# 원 ∩ 띠 |v| ≤ side
	var a := 0.0
	var n := 400
	for i in n:
		var v := -side + (i + 0.5) * 2.0 * side / n
		a += 2.0 * sqrt(maxf(0.0, r * r - v * v)) * 2.0 * side / n
	return a


func _battle():
	for c in get_children():
		if c.get_script() == BattleScript and not c.is_queued_for_deletion():
			return c
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait_until(cond: Callable, timeout_sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while not cond.call():
		if Time.get_ticks_msec() > end:
			return false
		await get_tree().process_frame
	return true
