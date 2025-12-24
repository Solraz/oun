extends Camera3D
class_name PlayerCamera

@export var player: Player
@export var head: Node3D
@export var eyes: Node3D

#region Controls
@export_group("Controls")
var RETICLE : Control
var mouse_input : Vector2 = Vector2(0,0)
@export_range(0.001, 1, 0.001) var mouse_sensitivity : float = 0.035
#endregion

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	head.rotation = player.rotation
	pass


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		mouse_input = event.relative


func _process(_delta: float) -> void:
	pass


func _physics_process(_delta: float) -> void:
	head.rotation_degrees.y -= mouse_input.x * mouse_sensitivity
	head.rotation_degrees.x -= mouse_input.y * mouse_sensitivity

	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

	mouse_input = Vector2(0,0)
