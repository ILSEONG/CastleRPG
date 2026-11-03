extends RefCounted
## 전투 통계(사용자 2026-11-02 "스테이지를 밀때, 각 던전, PVP 등 방치할때 제외하고 왼쪽 하단에 통계버튼 — 가한 피해량, 받은 피해량, 치유량").
## 영웅마다 세 값을 모은다(창은 stats_button.gd). 참고: AFK 아레나 전투 통계(영웅별 막대 + 탭), 세븐나이츠 키우기 전투 정보, 로스트아크 피해 미터.
##  - 가한 피해: 맞은 쪽(몬스터·적 영웅·적 병사)이 실제로 잃은 HP(넘친 피해는 빼고). 때린 영웅 = 지금 행동 중인 영웅(src).
##  - 받은 피해: 영웅이 실제로 잃은 HP(회피·보호막·피해 감소로 막은 양은 빼고).
##  - 치유량: 실제로 오른 HP(넘친 회복은 빼고). 준 영웅 = src(없으면 회복받은 영웅 자신 — 재생·흡혈).
## 누가 때렸나(src): hero.gd·war_hero.gd의 한 프레임(_process) 동안 src = 그 영웅. 나중에 터지는 것(투사체·지연 타격·독/지속 피해·소환수)은
## 만들 때의 src를 들고 있다가 터질 때 되돌린다(capture / run). 병사·망루·몬스터의 행동은 src가 비어 있어 아무에게도 안 쌓인다.
## 범위(scope): 성 화면 영웅(castle != null) = "castle"(스테이지가 시작될 때마다 비운다), 던전·PVP·드래곤 등 전투 장면 = "arena"(장면마다 비운다).

static var src = null  # 지금 행동 중인 영웅(hero.gd 계열) — 없으면 null
static var rows := {}  # scope → {instance_id: 행}
static var version := 0  # 값이 바뀔 때마다 오른다(창이 다시 그릴지 본다)


static func is_hero(h) -> bool:
	return h != null and is_instance_valid(h) and h is Node3D and h.get("def") is Dictionary and h.has_method("revive")


static func scope_of(h) -> String:
	return "castle" if h.get("castle") != null else "arena"


static func team_of(n) -> int:
	var t = n.get("team") if n != null and is_instance_valid(n) else null
	return int(t) if t != null else 0


## 영웅의 행(없으면 만든다).
static func row(h) -> Dictionary:
	var sc := scope_of(h)
	if not rows.has(sc):
		rows[sc] = {}
	var bucket: Dictionary = rows[sc]
	var id: int = h.get_instance_id()
	if not bucket.has(id):
		bucket[id] = {"hero_id": str(h.def.get("id", "")), "name": str(h.def.get("name", "")), "team": team_of(h),
			"order": bucket.size(), "dealt": 0.0, "taken": 0.0, "healed": 0.0, "node": weakref(h)}
	return bucket[id]


## 전투 화면이 지금 있는 영웅을 0으로라도 보이게(아직 아무 것도 안 한 영웅).
static func enroll(h) -> void:
	if is_hero(h):
		row(h)


## 맞은 쪽(victim)이 amount만큼 HP를 잃었다 — 지금 영웅(src)이 가한 피해. 자기 자신·같은 편은 세지 않는다.
static func dealt(victim, amount: float) -> void:
	if amount <= 0.0 or not is_hero(src) or src == victim:
		return
	if victim != null and is_instance_valid(victim) and victim.get("team") != null and team_of(victim) == team_of(src):
		return
	row(src).dealt += amount
	version += 1


## 영웅 h가 amount만큼 HP를 잃었다.
static func taken(h, amount: float) -> void:
	if amount <= 0.0 or not is_hero(h):
		return
	row(h).taken += amount
	version += 1


## target의 HP가 amount만큼 올랐다 — 준 영웅 = src(없으면 target 자신).
static func healed(target, amount: float) -> void:
	if amount <= 0.0:
		return
	var s = src if is_hero(src) and team_of(src) == team_of(target) else target
	if not is_hero(s):
		return
	row(s).healed += amount
	version += 1


## 나중에 터질 일(투사체·지연 타격·지속 피해)에 지금 영웅을 실어 둔다.
static func capture():
	return weakref(src) if is_hero(src) else null


## capture()로 실어 둔 영웅을 src로 두고 f를 부른다(끝나면 되돌린다).
static func run(cap, f: Callable) -> void:
	var prev = src
	src = cap.get_ref() if cap is WeakRef else null
	f.call()
	src = prev


static func reset(scope: String) -> void:
	rows.erase(scope)
	version += 1


## 표시용 행들(team 편만, 들어온 순서).
static func list(scope: String, team := 0) -> Array:
	var out := []
	for r in rows.get(scope, {}).values():
		if int(r.team) == team:
			out.append(r)
	out.sort_custom(func(a, b): return int(a.order) < int(b.order))
	return out


## 상대 편 행이 하나라도 있나(PVP·길드전 — 창에 [상대 팀] 탭을 보인다).
static func has_team(scope: String, team: int) -> bool:
	for r in rows.get(scope, {}).values():
		if int(r.team) == team:
			return true
	return false
