extends Node3D
## 원거리 투사체(개정 12-2 §3): 발사 순간 쏜 자리에서 대상 몸통을 따라(유도) 일정 속도로 날아가, 도착하는 순간 on_hit(대상)을 부른다.
## 대상이 도착 전에 죽거나 사라지면 피해 없이 사라진다. 모양(kind: Fx.dress_projectile)은 이펙트 상한 안에서만 붙는다 —
## 상한이면 모양 없이 날지만 피해는 그대로 들어간다. 쏜 쪽이 사라지면(on_hit 무효) 피해도 없다.

const Fx := preload("res://scripts/fx.gd")

const AIM := Vector3(0, 0.8, 0)  # 대상 몸통 높이(hero.HIT_HEIGHT)
const AXE_SPIN := TAU * 6.0      # 도끼 초당 회전

var target
var speed := 30.0
var kind := "arrow"
var color := Color.WHITE
var tail := false  # multishot: 고유 색 꼬리(개정 17)
var on_hit: Callable

var _look: Node3D


func _ready() -> void:
	_look = Fx.dress_projectile(self, kind, color, tail)


func _process(delta: float) -> void:
	if not is_instance_valid(target) or not target.is_alive():
		queue_free()
		return
	var dest: Vector3 = target.global_position + AIM
	var to := dest - global_position
	if to.length() <= speed * delta:
		global_position = dest
		queue_free()
		if on_hit.is_valid():
			on_hit.call(target)
		return
	global_position += to.normalized() * speed * delta
	var left := dest - global_position
	if left.length() > 0.01:
		look_at(dest, Vector3.UP if absf(left.normalized().y) < 0.99 else Vector3.FORWARD)
	if kind == "axe" and _look != null:
		_look.rotation.x -= AXE_SPIN * delta
