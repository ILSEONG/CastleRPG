extends RefCounted
## 장비 능력치 글자·색(2026-10-07 장비 개편): 기본 능력치와 특수 능력치(SR 1줄 … LR 3줄)를 [[글자, 색]]으로. 굴림이 기준값(100)보다
## 높으면 초록, 낮으면 빨강, 같으면 검정. 보관함·장비 고르기·던전 결과(bag_panel.gd)가 쓴다. 오토로드를 부르지 않는다(단위 테스트).

const GameData := preload("res://scripts/game_data.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

const UP_COLOR := Color(0.12, 0.56, 0.2)  # 기준값보다 높은 능력치
const DOWN_COLOR := Color(0.84, 0.17, 0.15)  # 기준값보다 낮은 능력치
const INK := Color(0.16, 0.18, 0.24)  # hud.gd INK와 같다(기준값 그대로)


## 기본 능력치 [[글자, 색]]: 기준값(굴림 100)보다 높으면 초록, 낮으면 빨강, 같으면 검정.
static func stat_parts(it: Dictionary) -> Array:
	var s := GameData.item_stats(it)
	var b := GameData.item_stats(it, true)
	var out := []
	if b.hp > 0:
		out.append(["HP +%s" % UiKit.commas(s.hp), cmp_color(s.hp, b.hp)])
	if b.atk > 0:
		out.append(["공격 +%s" % UiKit.commas(s.atk), cmp_color(s.atk, b.atk)])
	if b.speed_pct > 0.0:
		out.append(["이동 +%s%%" % pct_text(s.speed_pct), cmp_color(s.speed_pct, b.speed_pct)])
	return out


## 특수 능력치 줄 [[글자, 색]](SR 1줄 … LR 3줄): "흡혈 +2.1%". 색은 그 줄의 기준값과 비교.
static func sub_parts(it: Dictionary) -> Array:
	var out := []
	for sub in it.get("subs", []):
		var one := {"slot": it.get("slot"), "grade": it.get("grade"), "subs": [sub]}
		var v: float = GameData.item_stats(one)[sub.id]
		var b: float = GameData.item_stats(one, true)[sub.id]
		out.append(["%s +%s%%" % [GameData.SUB_NAMES.get(sub.id, sub.id), pct_text(v)], cmp_color(v, b)])
	return out


static func cmp_color(v: float, base: float) -> Color:
	return UP_COLOR if v > base + 0.0001 else (DOWN_COLOR if v < base - 0.0001 else INK)


## 2.5 → "2.5", 3.0 → "3", 2.91 → "2.91"
static func pct_text(v: float) -> String:
	var t := "%.2f" % v
	return t.rstrip("0").rstrip(".")
