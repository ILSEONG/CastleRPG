extends Node
## 가이드 화살표 고정 체크(사용자 2026-10-16 "화살표가 고정되지않아" — 가방 [열기]): 미션마다 [바로가기]로 창을 연 뒤, 처치 골드처럼
## Economy.changed가 자주 오는 동안 화살표가 가리키는 버튼이 바뀌거나(창이 줄을 다시 만들었다) 화살표가 튀는지 본다.
## 화살표 위치는 tutorial_card가 그리는 값(Tutorial.point_target의 화면 Rect)을 매 프레임 잰다. 그 미션의 포커스 설명(guide_tours.gd) 대상도
## 같은 방법으로 잰다(성장 창 보유 골드 — 처치마다 글자 폭이 바뀌어 포커스 테두리가 들썩였다).
## 실행: xvfb-run -a godot --path . --resolution 720x1280 res://tests/guide_arrow_check.tscn  (마지막 줄 GUIDE ARROW PASSED, 약 30분)
## -- --only=<미션 id,…> 로 일부만.

const UiWindowScript := preload("res://scripts/ui_window.gd")
const PLACEMENT_PATH := "res://scripts/placement.gd"
const GameData := preload("res://scripts/game_data.gd")
const GuideTour := preload("res://scripts/guide_tour.gd")
const GuideTours := preload("res://scripts/guide_tours.gd")
const TOUR_FRAMES := 40

const SETTLE := 45  # [바로가기] 뒤 창이 펼쳐지는 동안은 재지 않는다
const FRAMES := 150
const CHANGE_EVERY := 5  # 프레임마다 처치 골드(Economy.changed)

var _main
var _fails := 0
var _rows: Array = []


func _ready() -> void:
	Economy.save_path = ""
	Fever.save_path = ""
	Guild.save_path = ""
	GuildWar.save_path = ""
	Party.save_path = ""
	await _frames(2)
	Tutorial.save_path = ""
	Economy.reset(Time.get_unix_time_from_system())
	Tutorial.begin(true)
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(90)
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	for i in Tutorial.MISSIONS.size():
		var id := str(Tutorial.MISSIONS[i].id)
		if not only.is_empty() and not id in only:
			continue
		print("START %s" % id)
		await _mission(i)
	print("")
	for r in _rows:
		print(r)
	print("GUIDE ARROW %s" % ("PASSED" if _fails == 0 else "FAILED %d" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


## 미션 i: 상태를 준비하고 [바로가기] → 창이 자리를 잡은 뒤 FRAMES 동안 잰다.
func _mission(i: int) -> void:
	await _close_all()
	_prep(str(Tutorial.MISSIONS[i].get("kind", "")))
	Tutorial.state = "active"
	Tutorial.step = i
	Tutorial.count = 0
	Tutorial.check()
	Tutorial.changed.emit()
	await _frames(6)
	var m: Dictionary = Tutorial.mission()
	var id := str(m.id)
	if Tutorial.complete():
		_rows.append("%-16s skip (already complete with the test state)" % id)
		return
	var g := Tutorial.goto_of(m)
	if g != "" and g != "stage" and g != "siege_practice":
		Tutorial.goto_current()
	await _frames(SETTLE)
	var open_w: Array = []
	for w in get_tree().get_nodes_in_group(UiWindowScript.GROUP):
		if w.is_open():
			open_w.append(w.name)
	var last_id := 0
	var last_r := Rect2()
	var swaps := 0
	var jumps := 0
	var max_jump := 0.0
	var nulls := 0
	var seen := 0
	var what := ""
	for f in FRAMES:
		if f % CHANGE_EVERY == 0:
			Economy.grant({"gold": 7})  # 처치 골드처럼 자주 바뀐다
		await get_tree().process_frame
		var t: Control = Tutorial.point_target()
		if t == null:
			nulls += 1
			continue
		seen += 1
		if what == "":
			what = "%s %s" % [t.get_class(), t.get("text") if t is Button else t.name]
		var xf := t.get_global_transform_with_canvas()
		var r := Rect2(xf.origin, t.size * xf.get_scale())
		if last_id != 0 and t.get_instance_id() != last_id:
			swaps += 1
		if last_r.size != Vector2.ZERO:
			var d := r.position.distance_to(last_r.position) + absf(r.size.x - last_r.size.x) + absf(r.size.y - last_r.size.y)
			if d > 3.0:
				jumps += 1
				max_jump = maxf(max_jump, d)
		last_id = t.get_instance_id()
		last_r = r
	await _tours(id)
	var ok := swaps == 0 and jumps == 0 and (seen == 0 or nulls == 0)
	var row := "%-16s %s goto=%-18s seen %3d  nulls %3d  swaps %3d  jumps %3d (max %.0f px)  → %s" % [id, "ok  " if ok else "FAIL", g, seen, nulls, swaps, jumps, max_jump, what + " open=" + ",".join(open_w)]
	_rows.append(row)
	print("ROW " + row)
	if not ok:
		_fails += 1


## 이 미션의 포커스 설명(guide_tours.gd) 단계마다: 지금 보이는 대상이면 TOUR_FRAMES 동안 처치 골드를 주며 포커스 자리(GuideTour.resolve)와
## 대상 노드가 바뀌거나 튀는지 본다(설명이 떠 있는 동안 포커스가 대상에서 어긋나면 안 된다). 공성전 체험(전장)은 뺀다.
func _tours(mission_id: String) -> void:
	for tid in GuideTours.MISSION_TOURS.get(mission_id, []):
		var tour: Dictionary = GuideTours.TOURS.get(tid, {})
		for si in tour.get("steps", []).size():
			var at := str(tour.steps[si].get("at", ""))
			if at == "" or at.begins_with("war3d:") or str(tour.get("when", "")).begins_with("war"):
				continue
			var last_ids := []
			var last_r = null
			var swaps := 0
			var jumps := 0
			var seen := 0
			for f in TOUR_FRAMES:
				if f % CHANGE_EVERY == 0:
					Economy.grant({"gold": 7})
				await get_tree().process_frame
				var r = GuideTour.resolve(at, get_tree())
				if not r is Rect2:
					continue
				seen += 1
				var ids := _ids(at)
				if not last_ids.is_empty() and ids != last_ids:
					swaps += 1
				if last_r is Rect2 and (r.position.distance_to(last_r.position) + (r.size - last_r.size).length()) > 3.0:
					jumps += 1
				last_ids = ids
				last_r = r
			if seen == 0:
				continue
			var ok := swaps == 0 and jumps == 0
			var row := "  tour %-14s %-34s %s seen %3d swaps %3d jumps %3d" % [tid, at, "ok  " if ok else "FAIL", seen, swaps, jumps]
			_rows.append(row)
			print("ROW " + row)
			if not ok:
				_fails += 1


## 포커스 대상의 노드 id 목록(배열·사전이면 값들).
func _ids(at: String) -> Array:
	var v = null
	if at.begins_with("ui:"):
		var t = Tutorial.ui_targets.get(at.substr(3))
		v = t.node if t != null else null
	else:
		v = GuideTour._walk(at, get_tree())
	var list: Array = v if v is Array else (v.values() if v is Dictionary else [v])
	return list.map(func(x): return x.get_instance_id() if x is Object and is_instance_valid(x) else 0)


## 시험 상태: 재화·주머니·가속 아이템이 넉넉하다(미션 대상 버튼이 꺼지지 않게). 가이드가 하는 일은 각 미션이 직접.
func _prep(kind: String) -> void:
	if kind == "pouch":  # 이 미션쯤엔 자원 건물이 지어져 있다(자원 주머니도 [열기]가 켜진다 — 사용자 화면 자원 주머니(4시간))
		for k in GameData.building_keys():
			if Economy.res_of(k) != "":
				Economy.unbuilt.erase(k)
	Economy.grant({"gold": 5000000, "diamonds": 50000, "wood": 5000000, "stone": 5000000, "food": 5000000})
	Economy.pouches = {"gold_30": 2, "gold_60": 1, "res_240": 1}
	Economy.speedups = {"build_480": 1, "builder_2880": 1}
	Economy.pouches_changed.emit()
	Economy.speedups_changed.emit()


func _close_all() -> void:
	var placement = _find(_main, PLACEMENT_PATH)
	if placement != null and placement.is_active():
		placement.cancel()
	for w in get_tree().get_nodes_in_group(UiWindowScript.GROUP):
		if w.is_open():
			w.close()
	if Tutorial.tour_node != null and is_instance_valid(Tutorial.tour_node):
		Tutorial.tour_node.finish()
	await _frames(20)


func _find(n: Node, path: String) -> Node:
	if n.get_script() != null and n.get_script().resource_path == path:
		return n
	for c in n.get_children():
		var r = _find(c, path)
		if r != null:
			return r
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
