extends Node3D
## 쿼터뷰 직교 카메라 리그. 리그 위치 = 화면 중앙이 바라보는 바닥 지점.
## 드래그 이동·줌 입력은 Task 4에서 추가.

const Balance := preload("res://scripts/balance.gd")

const PITCH_DEG := -35.0
const YAW_DEG := 45.0
const DISTANCE := 100.0

var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = Balance.CAMERA_SIZE_DEFAULT
	camera.near = 1.0
	camera.far = 300.0
	camera.rotation_degrees = Vector3(PITCH_DEG, YAW_DEG, 0)
	camera.position = camera.basis.z * DISTANCE
	add_child(camera)
